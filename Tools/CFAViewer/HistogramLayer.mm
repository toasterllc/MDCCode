#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <mutex>
//#import "HistogramLayer.h"
//#import "HistogramLayerTypes.h"
#import "Assert.h"
#import "Util.h"
using namespace CFAViewer;
using namespace MetalUtil;
using namespace HistogramLayerTypes;

@implementation HistogramLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    
    struct {
        // Protects this struct
        std::mutex lock;
        
        id<MTLTexture> depthTexture;
        MTLRenderPassDepthAttachmentDescriptor* depthAttachment;
         
        RenderContext ctx;
        Histogram histogram __attribute__((aligned(4096)));
        HistogramFloat histogramFloat __attribute__((aligned(4096)));
        id<MTLBuffer> histogramBuf;
        float maxVal;
    } _state;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setActions:LayerNullActions()];
    [self setNeedsDisplayOnBoundsChange:true];
    
    _device = MTLCreateSystemDefaultDevice();
    Assert(_device, return nil);
    [self setDevice:_device];
    [self setPixelFormat:MTLPixelFormatBGRA8Unorm];
    
    _commandQueue = [_device newCommandQueue];
    
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:
        [NSBundle bundleForClass:[self class]] error:nil];
    Assert(library, return nil);
    
    id<MTLFunction> vertexShader = [library newFunctionWithName:@"HistogramLayer_VertexShader"];
    Assert(vertexShader, return nil);
    
    id<MTLFunction> fragmentShader = [library newFunctionWithName:@"HistogramLayer_FragmentShader"];
    Assert(fragmentShader, return nil);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    Assert(_pipelineState, return nil);
    
    MTLDepthStencilDescriptor* depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDescriptor.depthWriteEnabled = true;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
    
    auto lock = std::lock_guard(_state.lock);
        _state.depthAttachment = [MTLRenderPassDepthAttachmentDescriptor new];
        [_state.depthAttachment setLoadAction:MTLLoadActionClear];
        [_state.depthAttachment setStoreAction:MTLStoreActionDontCare];
        [_state.depthAttachment setClearDepth:1];
        
        _state.histogramBuf = [_device newBufferWithBytesNoCopy:&_state.histogramFloat
            length:sizeof(_state.histogramFloat) options:MTLResourceStorageModeShared
            deallocator:nil];
    
    return self;
}

- (void)setHistogram:(const MetalUtil::Histogram&)histogram {
    auto lock = std::unique_lock(_state.lock);
    _state.histogram = histogram;
//    _state.histogram.r[0] = 5000000;
//    float val = sampleRange(0, 1./400, _state.histogram.r);
//    _state.histogram.r[4095] = 5000000;
//    float val = sampleRange(1-1./400, 1, _state.histogram.r);
    lock.unlock();
    
    [self setNeedsDisplay];
}

- (CGPoint)valueFromPoint:(CGPoint)p {
    auto lock = std::unique_lock(_state.lock);
    auto& ctx = _state.ctx;
    CGSize size = [self bounds].size;
    CGPoint r = {p.x/size.width, p.y/size.height};
    r.x *= Histogram::Count;
    r.y = powf(ctx.maxVal, r.y);
    return r;
}

// _state.lock must be held
- (MTLRenderPassDepthAttachmentDescriptor*)_depthAttachmentForDrawableTexture:(id<MTLTexture>)drawableTexture {
    NSParameterAssert(drawableTexture);
    
    const NSUInteger width = [drawableTexture width];
    const NSUInteger height = [drawableTexture height];
    if (!_state.depthTexture || width!=[_state.depthTexture width] || height!=[_state.depthTexture height]) {
        // The _depthTexture doesn't exist or our size changed, so re-create the depth texture
        MTLTextureDescriptor* desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
            width:width height:height mipmapped:false];
        [desc setTextureType:MTLTextureType2D];
        [desc setSampleCount:1];
        [desc setUsage:MTLTextureUsageUnknown];
        [desc setStorageMode:MTLStorageModePrivate];
        
        _state.depthTexture = [_device newTextureWithDescriptor:desc];
        [_state.depthAttachment setTexture:_state.depthTexture];
    }
    
    return _state.depthAttachment;
}

template <size_t N>
float sampleRange(float unitRange0, float unitRange1, const uint32_t(& bins)[N]) {
    unitRange0 = std::max(0.f, unitRange0);
    unitRange1 = std::min(1.f, unitRange1);
    
    const float range0 = unitRange0*N;
    const float range1 = unitRange1*N;
    const uint32_t rangeIdx0 = range0;
    const uint32_t rangeIdx1 = range1;
    const float leftAmount = 1-(range0-floor(range0));
    const float rightAmount = range1-floor(range1);
    
    float sample = 0;
    // Limit `i` to N-1 here to prevent reading beyond `bins`.
    // We don't limit `i` via `rangeIdx`, because our alg works with
    // closed-open intervals, where the open interval has rightAmount==0.
    // If we limited our iteration with `rangeIdx`, we'd need a special
    // case to set rightAmount=1, otherwise the last bin would get dropped.
    for (uint i=rangeIdx0; i<=std::min((uint32_t)N-1, rangeIdx1); i++) {
        if (i == rangeIdx0)         sample += leftAmount*bins[i];
        else if (i == rangeIdx1)    sample += rightAmount*bins[i];
        else                        sample += bins[i];
    }
    return sample;
}

- (void)display {
    auto lock = std::unique_lock(_state.lock);
    auto& ctx = _state.ctx;
    
    // Update our drawable size using our view size (in pixels)
    const CGFloat scale = [self contentsScale];
    CGSize viewSizePx = [self bounds].size;
    viewSizePx.width *= scale;
    viewSizePx.height *= scale;
    [self setDrawableSize:viewSizePx];
    
    ctx.viewWidth = (uint32_t)lround(viewSizePx.width);
    ctx.viewHeight = (uint32_t)lround(viewSizePx.height);
    
    // Update _state.histogramFloat
    // We do this in CPU-land so that we can determine the max Y values,
    // to scale the histogram appropriately.
    ctx.maxVal = 0;
    for (uint32_t i=0; i<ctx.viewWidth; i++) {
        assert(i < Histogram::Count);   // TODO: Our float histogram is capped at Histogram::Count points,
                                        // so if our view is wider than that, then we need to implement a
                                        // way for multiple pixels to refer to the same bin in
                                        // _state.histogramFloat.r/g/b
        const float start = (float)i/ctx.viewWidth;
        const float end = ((float)i+1)/ctx.viewWidth;
        const float r = sampleRange(start, end, _state.histogram.r);
        const float g = sampleRange(start, end, _state.histogram.g);
        const float b = sampleRange(start, end, _state.histogram.b);        
        _state.histogramFloat.r[i] = r;
        _state.histogramFloat.g[i] = g;
        _state.histogramFloat.b[i] = b;
        ctx.maxVal = std::max(ctx.maxVal, r);
        ctx.maxVal = std::max(ctx.maxVal, g);
        ctx.maxVal = std::max(ctx.maxVal, b);
    }
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    id<MTLTexture> drawableTexture = [drawable texture];
    Assert(drawableTexture, return);
    
    MTLRenderPassDepthAttachmentDescriptor* depthAttachment = [self _depthAttachmentForDrawableTexture:drawableTexture];
    Assert(depthAttachment, return);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [renderPassDescriptor setDepthAttachment:depthAttachment];
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{0, 0, 0, 1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    [renderEncoder setDepthStencilState:_depthStencilState];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeNone];
    
    [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
    [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
    [renderEncoder setFragmentBuffer:_state.histogramBuf offset:0 atIndex:1];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
        vertexCount:MetalUtil::SquareVertIdxCount];
    
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [commandBuffer waitUntilCompleted];
    
    lock.unlock();
}

- (void)layoutSublayers {
    [super layoutSublayers];
}

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

- (void)setNeedsDisplay {
    if ([NSThread isMainThread]) {
        [super setNeedsDisplay];
    
    } else {
        // Call -setNeedsDisplay on the main thread, so that drawing is
        // sync'd with drawing triggered by the main thread.
        // Don't use dispatch_async here, because dispatch_async's don't get drained
        // while the runloop is run recursively, eg during mouse tracking.
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [self setNeedsDisplay];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

@end

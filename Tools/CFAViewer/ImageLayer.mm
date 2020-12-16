#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <mutex>
#import <os/log.h>
#import "ImageLayer.h"
#import "ImageLayerTypes.h"
#import "Assert.h"
#import "MyTime.h"
using namespace MetalTypes;
using namespace ImageLayerTypes;

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    ImageLayerHistogramChangedHandler _histogramChangedHandler;
    
    struct {
        // Protects this struct
        std::mutex lock;
        
        id<MTLTexture> depthTexture;
        MTLRenderPassDepthAttachmentDescriptor* depthAttachment;
        
        RenderContext ctx;
        id<MTLBuffer> pixelData;
        
        Histogram inputHistogram __attribute__((aligned(4096)));
        id<MTLBuffer> inputHistogramBuf;
        Histogram outputHistogram __attribute__((aligned(4096)));
        id<MTLBuffer> outputHistogramBuf;
    } _state;
}

static NSDictionary* layerNullActions() {
    static NSDictionary* r = @{
        kCAOnOrderIn: [NSNull null],
        kCAOnOrderOut: [NSNull null],
        @"bounds": [NSNull null],
        @"frame": [NSNull null],
        @"position": [NSNull null],
        @"sublayers": [NSNull null],
        @"transform": [NSNull null],
        @"contents": [NSNull null],
        @"contentsScale": [NSNull null],
        @"hidden": [NSNull null],
        @"fillColor": [NSNull null],
        @"fontSize": [NSNull null],
    };
    return r;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setActions:layerNullActions()];
    [self setNeedsDisplayOnBoundsChange:true];
    
    _device = MTLCreateSystemDefaultDevice();
    Assert(_device, return nil);
    [self setDevice:_device];
    [self setPixelFormat:MTLPixelFormatBGRA8Unorm];
    
    _commandQueue = [_device newCommandQueue];
    
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:
        [NSBundle bundleForClass:[self class]] error:nil];
    Assert(library, return nil);
    
    id<MTLFunction> vertexShader = [library newFunctionWithName:@"ImageLayer_VertexShader"];
    Assert(vertexShader, return nil);
    
    id<MTLFunction> fragmentShader = [library newFunctionWithName:@"ImageLayer_FragmentShader"];
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
        
        _state.inputHistogramBuf = [_device newBufferWithBytesNoCopy:&_state.inputHistogram
            length:sizeof(_state.inputHistogram) options:MTLResourceStorageModeShared deallocator:nil];
        
        _state.outputHistogramBuf = [_device newBufferWithBytesNoCopy:&_state.outputHistogram
            length:sizeof(_state.outputHistogram) options:MTLResourceStorageModeShared deallocator:nil];
    
    return self;
}

- (void)updateImage:(const Image&)image {
    // If we don't have pixel data, ensure that our image has 0 pixels
    NSParameterAssert(image.pixels || (image.width*image.height)==0);
    const size_t pixelCount = image.width*image.height;
    
    auto lock = std::unique_lock(_state.lock);
        // Reset image size in case something fails
        _state.ctx.imageWidth = 0;
        _state.ctx.imageHeight = 0;
        
        const size_t len = pixelCount*sizeof(ImagePixel);
        if (len) {
            if (!_state.pixelData || [_state.pixelData length]<len) {
                _state.pixelData = [_device newBufferWithLength:len
                    options:MTLResourceCPUCacheModeDefaultCache];
                Assert(_state.pixelData, return);
            }
            
            // Copy the pixel data into the Metal buffer
            memcpy([_state.pixelData contents], image.pixels, len);
            
            // Set the image size now that we have image data
            _state.ctx.imageWidth = image.width;
            _state.ctx.imageHeight = image.height;
        
        } else {
            _state.pixelData = nil;
        }
    lock.unlock();
    
    [self setNeedsDisplay];
}

- (void)updateColorMatrix:(const ColorMatrix&)colorMatrix {
    auto lock = std::unique_lock(_state.lock);
        _state.ctx.colorMatrix = colorMatrix;
    lock.unlock();
    [self setNeedsDisplay];
}

- (void)setHistogramChangedHandler:(ImageLayerHistogramChangedHandler)histogramChangedHandler {
    _histogramChangedHandler = histogramChangedHandler;
}

- (MetalTypes::Histogram)inputHistogram {
    auto lock = std::unique_lock(_state.lock);
    return _state.inputHistogram;
}

- (MetalTypes::Histogram)outputHistogram {
    auto lock = std::unique_lock(_state.lock);
    return _state.outputHistogram;
}

// _state.lock lock must be held
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

- (void)display {
    auto lock = std::unique_lock(_state.lock);
    auto& ctx = _state.ctx;
    
    _state.inputHistogram = Histogram();
    _state.outputHistogram = Histogram();
    
    // Update our drawable size using our view size (in pixels)
    const CGFloat scale = [self contentsScale];
    CGSize viewSizePx = [self bounds].size;
    viewSizePx.width *= scale;
    viewSizePx.height *= scale;
    [self setDrawableSize:viewSizePx];
    
    ctx.viewWidth = (uint32_t)lround(viewSizePx.width);
    ctx.viewHeight = (uint32_t)lround(viewSizePx.height);
    
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
    
    // Only try to render if we have a _state.pixelData
    if (_state.pixelData) {
        [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
        
        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setFragmentBuffer:_state.pixelData offset:0 atIndex:1];
        [renderEncoder setFragmentBuffer:_state.inputHistogramBuf offset:0 atIndex:2];
        [renderEncoder setFragmentBuffer:_state.outputHistogramBuf offset:0 atIndex:3];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
            vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    }
    
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
//    auto startTime = MyTime::Now();
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [commandBuffer waitUntilCompleted];
    
    lock.unlock();
    
    // Notify that our histogram changed
    if (_histogramChangedHandler) _histogramChangedHandler(self);
    
//    size_t i = 0;
//    for (const auto& count : _state.inputHistogram.r) {
//        printf("[%ju] %ju\n", (uintmax_t)i, (uintmax_t)count);
//        i++;
//    }
    
//    printf("Duration: %ju\n", (uintmax_t)MyTime::DurationNs(startTime));
//    printf("%ju\n", (uintmax_t)_state.histogram.counts[0].load());
    
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

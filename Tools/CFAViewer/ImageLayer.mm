#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <mutex>
#import <os/log.h>
#import "ImageLayer.h"
#import "ImageLayerTypes.h"
#import "Assert.h"
#import "MyTime.h"
#import "Util.h"
using namespace CFAViewer;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    ImageLayerHistogramChangedHandler _histogramChangedHandler;
    
    id<MTLTexture> _depthTexture;
    MTLRenderPassDepthAttachmentDescriptor* _depthAttachment;
    
    RenderContext _ctx;
    id<MTLBuffer> _pixelData;
    
    Histogram _inputHistogram __attribute__((aligned(4096)));
    id<MTLBuffer> _inputHistogramBuf;
    Histogram _outputHistogram __attribute__((aligned(4096)));
    id<MTLBuffer> _outputHistogramBuf;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setActions:LayerNullActions()];
    
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
    
    _depthAttachment = [MTLRenderPassDepthAttachmentDescriptor new];
    [_depthAttachment setLoadAction:MTLLoadActionClear];
    [_depthAttachment setStoreAction:MTLStoreActionDontCare];
    [_depthAttachment setClearDepth:1];
    
    _inputHistogramBuf = [_device newBufferWithBytesNoCopy:&_inputHistogram
        length:sizeof(_inputHistogram) options:MTLResourceStorageModeShared deallocator:nil];
    
    _outputHistogramBuf = [_device newBufferWithBytesNoCopy:&_outputHistogram
        length:sizeof(_outputHistogram) options:MTLResourceStorageModeShared deallocator:nil];
    
    return self;
}

- (void)updateImage:(const Image&)image {
    // If we don't have pixel data, ensure that our image has 0 pixels
    NSParameterAssert(image.pixels || (image.width*image.height)==0);
    const size_t pixelCount = image.width*image.height;
    
    // Reset image size in case something fails
    _ctx.imageWidth = 0;
    _ctx.imageHeight = 0;
    
    const size_t len = pixelCount*sizeof(ImagePixel);
    if (len) {
        if (!_pixelData || [_pixelData length]<len) {
            _pixelData = [_device newBufferWithLength:len
                options:MTLResourceCPUCacheModeDefaultCache];
            Assert(_pixelData, return);
        }
        
        // Copy the pixel data into the Metal buffer
        memcpy([_pixelData contents], image.pixels, len);
        
        // Set the image size now that we have image data
        _ctx.imageWidth = image.width;
        _ctx.imageHeight = image.height;
    
    } else {
        _pixelData = nil;
    }
    
    const CGFloat scale = [self contentsScale];
    [self setBounds:{0, 0, _ctx.imageWidth/scale, _ctx.imageHeight/scale}];
    
    [self setNeedsDisplay];
}

- (void)updateColorMatrix:(const ColorMatrix&)colorMatrix {
    _ctx.colorMatrix = colorMatrix;
    [self setNeedsDisplay];
}

- (void)setHistogramChangedHandler:(ImageLayerHistogramChangedHandler)histogramChangedHandler {
    _histogramChangedHandler = histogramChangedHandler;
}

- (MetalTypes::Histogram)inputHistogram {
    return _inputHistogram;
}

- (MetalTypes::Histogram)outputHistogram {
    return _outputHistogram;
}

- (MTLRenderPassDepthAttachmentDescriptor*)_depthAttachmentForDrawableTexture:(id<MTLTexture>)drawableTexture {
    NSParameterAssert(drawableTexture);
    
    const NSUInteger width = [drawableTexture width];
    const NSUInteger height = [drawableTexture height];
    if (!_depthTexture || width!=[_depthTexture width] || height!=[_depthTexture height]) {
        // The _depthTexture doesn't exist or our size changed, so re-create the depth texture
        MTLTextureDescriptor* desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
            width:width height:height mipmapped:false];
        [desc setTextureType:MTLTextureType2D];
        [desc setSampleCount:1];
        [desc setUsage:MTLTextureUsageUnknown];
        [desc setStorageMode:MTLStorageModePrivate];
        
        _depthTexture = [_device newTextureWithDescriptor:desc];
        [_depthAttachment setTexture:_depthTexture];
    }
    
    return _depthAttachment;
}

- (void)display {
    
    // Short-circuit if we don't have any image data
    if (!_pixelData) return;
    
    _inputHistogram = Histogram();
    _outputHistogram = Histogram();
    
    // Update our drawable size using our view size (in pixels)
    const CGFloat scale = [self contentsScale];
    CGSize viewSizePx = [self bounds].size;
    viewSizePx.width *= scale;
    viewSizePx.height *= scale;
    [self setDrawableSize:viewSizePx];
    
    _ctx.viewWidth = (uint32_t)lround(viewSizePx.width);
    _ctx.viewHeight = (uint32_t)lround(viewSizePx.height);
    
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
    
    // Only try to render if we have a _pixelData
    [renderEncoder setVertexBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    
    [renderEncoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentBuffer:_pixelData offset:0 atIndex:1];
    [renderEncoder setFragmentBuffer:_inputHistogramBuf offset:0 atIndex:2];
    [renderEncoder setFragmentBuffer:_outputHistogramBuf offset:0 atIndex:3];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
//    auto startTime = MyTime::Now();
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [commandBuffer waitUntilCompleted];
    
    // Notify that our histogram changed
    if (_histogramChangedHandler) _histogramChangedHandler(self);
    
//    size_t i = 0;
//    for (const auto& count : _inputHistogram.r) {
//        printf("[%ju] %ju\n", (uintmax_t)i, (uintmax_t)count);
//        i++;
//    }
    
//    printf("Duration: %ju\n", (uintmax_t)MyTime::DurationNs(startTime));
//    printf("%ju\n", (uintmax_t)_histogram.counts[0].load());
    
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

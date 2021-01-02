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
    id<MTLLibrary> _library;
    id<MTLRenderPipelineState> _debayerPipelineState;
    id<MTLRenderPipelineState> _colorAdjustPipelineState;
    id<MTLRenderPipelineState> _srgbGammaPipelineState;
    ImageLayerHistogramChangedHandler _histogramChangedHandler;
    
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
    
    _library = [_device newDefaultLibraryWithBundle:[NSBundle bundleForClass:[self class]] error:nil];
    Assert(_library, return nil);
    
    _inputHistogramBuf = [_device newBufferWithBytesNoCopy:&_inputHistogram
        length:sizeof(_inputHistogram) options:MTLResourceStorageModeShared deallocator:nil];
    
    _outputHistogramBuf = [_device newBufferWithBytesNoCopy:&_outputHistogram
        length:sizeof(_outputHistogram) options:MTLResourceStorageModeShared deallocator:nil];
    
    // We have multiple render passes
    // -> so a fragment shader's input is the previous shader's output
    // -> so the drawable's texture needs to support sampling
    // -> so framebufferOnly=false to allow sampling
    [self setFramebufferOnly:false];
    
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

- (void)updateColorMatrix:(const simd::float3x3&)colorMatrix {
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




- (id<MTLRenderPipelineState>)_debayerPipelineState {
    if (_debayerPipelineState) return _debayerPipelineState;
    
    id<MTLFunction> vertexShader = [_library newFunctionWithName:@"ImageLayer_VertexShader"];
    Assert(vertexShader, return nil);
    
    id<MTLFunction> fragmentShader = [_library newFunctionWithName:@"ImageLayer_Debayer"];
    Assert(fragmentShader, return nil);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    
    [pipelineDescriptor colorAttachments][0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _debayerPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    Assert(_debayerPipelineState, return nil);
    return _debayerPipelineState;
}

- (void)_debayerRenderPass:(id<MTLCommandBuffer>)cmdBuf texture:(id<MTLTexture>)texture {
    NSParameterAssert(cmdBuf);
    NSParameterAssert(texture);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [[renderPassDescriptor colorAttachments][0] setTexture:texture];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    id<MTLRenderCommandEncoder> renderEncoder = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [renderEncoder setRenderPipelineState:[self _debayerPipelineState]];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeNone];
    
    [renderEncoder setVertexBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentBuffer:_pixelData offset:0 atIndex:1];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [renderEncoder endEncoding];
}







- (id<MTLRenderPipelineState>)_colorAdjustPipelineState {
    if (_colorAdjustPipelineState) return _colorAdjustPipelineState;
    
    id<MTLFunction> vertexShader = [_library newFunctionWithName:@"ImageLayer_VertexShader"];
    Assert(vertexShader, return nil);
    
    id<MTLFunction> fragmentShader = [_library newFunctionWithName:@"ImageLayer_ColorAdjust"];
    Assert(fragmentShader, return nil);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    
    [pipelineDescriptor colorAttachments][0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _colorAdjustPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    Assert(_colorAdjustPipelineState, return nil);
    return _colorAdjustPipelineState;
}

- (void)_colorAdjustRenderPass:(id<MTLCommandBuffer>)cmdBuf texture:(id<MTLTexture>)texture {
    NSParameterAssert(cmdBuf);
    NSParameterAssert(texture);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [[renderPassDescriptor colorAttachments][0] setTexture:texture];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    id<MTLRenderCommandEncoder> renderEncoder = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [renderEncoder setRenderPipelineState:[self _colorAdjustPipelineState]];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeNone];
    
    [renderEncoder setVertexBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentTexture:texture atIndex:0];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [renderEncoder endEncoding];
}









- (id<MTLRenderPipelineState>)_srgbGammaPipelineState {
    if (_srgbGammaPipelineState) return _srgbGammaPipelineState;
    
    id<MTLFunction> vertexShader = [_library newFunctionWithName:@"ImageLayer_VertexShader"];
    Assert(vertexShader, return nil);
    
    id<MTLFunction> fragmentShader = [_library newFunctionWithName:@"ImageLayer_SRGBGamma"];
    Assert(fragmentShader, return nil);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    
    [pipelineDescriptor colorAttachments][0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _srgbGammaPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    Assert(_srgbGammaPipelineState, return nil);
    return _srgbGammaPipelineState;
}

- (void)_srgbGammaRenderPass:(id<MTLCommandBuffer>)cmdBuf texture:(id<MTLTexture>)texture {
    NSParameterAssert(cmdBuf);
    NSParameterAssert(texture);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [[renderPassDescriptor colorAttachments][0] setTexture:texture];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    id<MTLRenderCommandEncoder> renderEncoder = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [renderEncoder setRenderPipelineState:[self _srgbGammaPipelineState]];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeNone];
    
    [renderEncoder setVertexBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    [renderEncoder setFragmentTexture:texture atIndex:0];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [renderEncoder endEncoding];
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
    
    id<MTLTexture> texture = [drawable texture];
    Assert(texture, return);
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
    // De-bayer render pass
    [self _debayerRenderPass:cmdBuf texture:texture];
    
    // Color-adjust render pass
    [self _colorAdjustRenderPass:cmdBuf texture:texture];
    
    // Apply SRGB gamma
    [self _srgbGammaRenderPass:cmdBuf texture:texture];
    
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
//    auto startTime = MyTime::Now();
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [cmdBuf waitUntilCompleted];
    
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

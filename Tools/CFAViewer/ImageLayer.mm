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
    NSMutableDictionary* _pipelineStates;
//    id<MTLRenderPipelineState> _debayerPipelineState;
//    id<MTLRenderPipelineState> _colorAdjustPipelineState;
//    id<MTLRenderPipelineState> _findHighlightsPipelineState;
//    id<MTLRenderPipelineState> _srgbGammaPipelineState;
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
    
//    _highlightsBuf = [_device newBufferWithBytesNoCopy:&_highlights
//        length:sizeof(_highlights) options:MTLResourceStorageModeShared deallocator:nil];
    
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
            _pixelData = [_device newBufferWithLength:len options:MTLResourceCPUCacheModeDefaultCache];
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

- (id<MTLRenderPipelineState>)_pipelineState:(NSString*)name {
    return [self _pipelineState:name format:MTLPixelFormatRGBA32Float];
}

- (id<MTLRenderPipelineState>)_pipelineState:(NSString*)name format:(MTLPixelFormat)format {
    NSParameterAssert(name);
    id<MTLRenderPipelineState> ps = _pipelineStates[name];
    if (!ps) {
        id<MTLFunction> vertexShader = [_library newFunctionWithName:@"ImageLayer_VertexShader"];
        Assert(vertexShader, return nil);
        id<MTLFunction> fragmentShader = [_library newFunctionWithName:name];
        Assert(fragmentShader, return nil);
        
        MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
        [pipelineDescriptor setVertexFunction:vertexShader];
        [pipelineDescriptor setFragmentFunction:fragmentShader];
        [[pipelineDescriptor colorAttachments][0] setPixelFormat:format];
        ps = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
        Assert(ps, return nil);
        _pipelineStates[name] = ps;
    }
    return ps;
}

using RenderPassBlock = void(^)(id<MTLRenderCommandEncoder>);
- (void)_renderPass:(id<MTLCommandBuffer>)cmdBuf texture:(id<MTLTexture>)texture
    name:(NSString*)name block:(NS_NOESCAPE RenderPassBlock)block {
    
    NSParameterAssert(cmdBuf);
    NSParameterAssert(texture);
    NSParameterAssert(name);
    NSParameterAssert(block);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [[renderPassDescriptor colorAttachments][0] setTexture:texture];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    id<MTLRenderCommandEncoder> encoder = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [encoder setRenderPipelineState:[self _pipelineState:name format:[texture pixelFormat]]];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBytes:&_ctx length:sizeof(_ctx) atIndex:0];
    
    block(encoder);
    
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [encoder endEncoding];
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
    
    MTLTextureDescriptor* textureDesc = [MTLTextureDescriptor new];
    [textureDesc setTextureType:MTLTextureType2D];
    [textureDesc setWidth:_ctx.viewWidth];
    [textureDesc setHeight:_ctx.viewHeight];
    [textureDesc setPixelFormat:MTLPixelFormatRGBA32Float];
    [textureDesc setUsage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDesc];
    Assert(texture, return);
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    id<MTLTexture> drawableTexture = [drawable texture];
    Assert(drawableTexture, return);
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
    // De-bayer render pass
    {
        // ImageLayer_DebayerLMMSE
        // ImageLayer_DebayerBilinear
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_DebayerLMMSE"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentBuffer:_pixelData offset:0 atIndex:1];
            }
        ];
    }
    
    // Camera raw -> XYY.D50
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_XYYD50FromCameraRaw"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
//    // Find the max values for {x,y,Y}, so that we can normalize Y (luminance) to 1
//    id<MTLBuffer> maxValsBuf = [_device newBufferWithLength:sizeof(Vals3) options:MTLResourceStorageModeShared];
//    {
//        // Zero the max vals buffer
//        memset([maxValsBuf contents], 0, sizeof(Vals3));
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_FindMaxVals"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:maxValsBuf offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
//    
//    // Normalize XYY luminance
//    {
////        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_NormalizeXYYLuminance"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:maxValsBuf offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
    // XYY.D50 -> LSRGB.D65
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_LSRGBD65FromXYYD50"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
//    // Correct highlights
//    {
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_FixHighlights"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:_pixelData offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
//    // Find the max rgb values
//    id<MTLBuffer> maxValsBuf = [_device newBufferWithLength:sizeof(Vals3) options:MTLResourceStorageModeShared];
//    {
//        // Zero the max vals buffer
//        memset([maxValsBuf contents], 0, sizeof(Vals3));
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_FindMaxVals"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:maxValsBuf offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
//    // Normalize RGB
//    {
////        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_NormalizeRGB"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:maxValsBuf offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
//    // Clip RGB
//    {
////        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_ClipRGB"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:maxValsBuf offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
//    // Find the max values
//    id<MTLBuffer> maxValsBuf2 = [_device newBufferWithLength:sizeof(Vals3) options:MTLResourceStorageModeShared];
//    {
//        // Zero the max vals buffer
//        memset([maxValsBuf2 contents], 0, sizeof(Vals3));
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_FindMaxVals"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBuffer:maxValsBuf2 offset:0 atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
    // Apply SRGB gamma
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_SRGBGamma"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
//    // XYZ.D50 from camera raw pass
//    {
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_XYZD50FromXYYD50"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
//    // XYY.D50 from camera raw pass
//    {
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_XYYD50FromCameraRaw"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
    
//    // De-bayer render pass
//    [self _xyzd50FromCameraRawRenderPass:cmdBuf texture:texture];
//    
////    // Color-adjust render pass
////    [self _colorAdjustRenderPass:cmdBuf texture:texture];
    
//    
//    // Apply SRGB gamma
//    [self _srgbGammaRenderPass:cmdBuf texture:texture];
    
    // Run the final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
    {
        [self _renderPass:cmdBuf texture:[drawable texture] name:@"ImageLayer_Display"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
//    auto startTime = MyTime::Now();
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [cmdBuf waitUntilCompleted];
    
//    Vals3 maxVals;
//    memcpy(&maxVals, [maxValsBuf contents], sizeof(maxVals));
//    printf("Max channel values 1: %f %f %f\n",
//        (float)maxVals.x/UINT16_MAX,
//        (float)maxVals.y/UINT16_MAX,
//        (float)maxVals.z/UINT16_MAX
//    );
//    
//    memcpy(&maxVals, [maxValsBuf2 contents], sizeof(maxVals));
//    printf("Max channel values 2: %f %f %f\n",
//        (float)maxVals.x/UINT16_MAX,
//        (float)maxVals.y/UINT16_MAX,
//        (float)maxVals.z/UINT16_MAX
//    );
    
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

- (simd::float3)sampleCameraRaw:(CGRect)rect {
    return {};
}

- (simd::float3)sampleXYZD50:(CGRect)rect {
    return {};
}

- (simd::float3)sampleSRGBD65:(CGRect)rect {
    return {};
}

@end

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <mutex>
#import <vector>
#import <os/log.h>
#import "ImageLayer.h"
#import "ImageLayerTypes.h"
#import "Assert.h"
#import "MyTime.h"
#import "Util.h"
#import "ColorUtil.h"
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
    
    id<MTLBuffer> _sampleBuf_cameraRaw;
    id<MTLBuffer> _sampleBuf_XYZD50;
    id<MTLBuffer> _sampleBuf_SRGBD65;
    
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
    
    _sampleBuf_cameraRaw = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
    _sampleBuf_XYZD50 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
    _sampleBuf_SRGBD65 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
    
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

static simd::float3x3 simdFromMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m[0], (float)m[3], (float)m[6]},
        simd::float3{(float)m[1], (float)m[4], (float)m[7]},
        simd::float3{(float)m[2], (float)m[5], (float)m[8]},
    };
}

static simd::float3 simdFromMat(const Mat<double,3,1>& m) {
    return {(float)m[0], (float)m[1], (float)m[2]};
}

- (void)setColorMatrix:(const Mat<double,3,3>&)cm {
    using namespace ColorUtil;
    
    _ctx.colorMatrix = simdFromMat(cm);
    
    // From "How the CIE 1931 Color-Matching Functions Were
    // Derived from Wright–Guild Data", page 19
    const Mat<double,3,3> XYZ_E_From_CIERGB_E(
        0.49000, 0.31000, 0.20000,
        0.17697, 0.81240, 0.01063,
        0.00000, 0.01000, 0.99000
    );
    
    // Bradform chromatic adaptation: XYZ.E -> XYZ.D50
    const Mat<double,3,3> XYZ_D50_From_XYZ_E(
         0.9977545, -0.0041632, -0.0293713,
        -0.0097677,  1.0183168, -0.0085490,
        -0.0074169,  0.0134416,  0.8191853
    );
    
    const Mat<double,3,3> XYZ_D50_From_CIERGB_E = XYZ_D50_From_XYZ_E * XYZ_E_From_CIERGB_E;
    const Mat<double,3,3> CameraRaw_D50_From_XYZ_D50 = cm.inv();
    
    // maxY = maximum luminance possible, given the color matrix `cm`
//    const double maxY = std::max(0.,cm[3]) + std::max(0.,cm[4]) + std::max(0.,cm[5]);
    
    // Luminance to apply to the primaries
    const double maxY = 6.5;
    
    // Enumerate the primaries in the CIE RGB colorspace, and convert them to XYY
    Color_XYY_D50 redPoint_XYY_D50          = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(1.,0.,0.));
    Color_XYY_D50 greenPoint_XYY_D50        = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(0.,1.,0.));
    Color_XYY_D50 bluePoint_XYY_D50         = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(0.,0.,1.));
    Color_XYY_D50 redGreenPoint_XYY_D50     = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(1.,1.,0.));
    Color_XYY_D50 redBluePoint_XYY_D50      = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(1.,0.,1.));
    Color_XYY_D50 greenBluePoint_XYY_D50    = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(0.,1.,1.));
    Color_XYY_D50 whitePoint_XYY_D50        = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(1.,1.,1.));
    
    // Set the luminance of every color to the maximum luminance possible
    redPoint_XYY_D50[2]         = maxY;
    greenPoint_XYY_D50[2]       = maxY;
    bluePoint_XYY_D50[2]        = maxY;
    redGreenPoint_XYY_D50[2]    = maxY;
    redBluePoint_XYY_D50[2]     = maxY;
    greenBluePoint_XYY_D50[2]   = maxY;
    whitePoint_XYY_D50[2]       = maxY;
    
    _ctx.redPoint_CamRaw_D50        = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(redPoint_XYY_D50));
    _ctx.greenPoint_CamRaw_D50      = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(greenPoint_XYY_D50));
    _ctx.bluePoint_CamRaw_D50       = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(bluePoint_XYY_D50));
    _ctx.redGreenPoint_CamRaw_D50   = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(redGreenPoint_XYY_D50));
    _ctx.redBluePoint_CamRaw_D50    = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(redBluePoint_XYY_D50));
    _ctx.greenBluePoint_CamRaw_D50  = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(greenBluePoint_XYY_D50));
    _ctx.whitePoint_CamRaw_D50      = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(whitePoint_XYY_D50));
    
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
    [self setDrawableSize:{(CGFloat)_ctx.imageWidth, (CGFloat)_ctx.imageHeight}];
    
    id<MTLTexture> rawTexture = nil;
    {
        MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
        [desc setTextureType:MTLTextureType2D];
        [desc setWidth:_ctx.imageWidth];
        [desc setHeight:_ctx.imageHeight];
        [desc setPixelFormat:MTLPixelFormatRGBA32Float];
        [desc setUsage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
        rawTexture = [_device newTextureWithDescriptor:desc];
        Assert(rawTexture, return);
    }
    
    id<MTLTexture> texture = nil;
    {
        MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
        [desc setTextureType:MTLTextureType2D];
        [desc setWidth:_ctx.imageWidth];
        [desc setHeight:_ctx.imageHeight];
        [desc setPixelFormat:MTLPixelFormatRGBA32Float];
        [desc setUsage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
        texture = [_device newTextureWithDescriptor:desc];
        Assert(texture, return);
    }
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    id<MTLTexture> drawableTexture = [drawable texture];
    Assert(drawableTexture, return);
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
    // De-bayer render pass
    {
        // ImageLayer_DebayerLMMSE
        // ImageLayer_DebayerBilinear
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_DebayerBilinear"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentBuffer:_pixelData offset:0 atIndex:1];
                [encoder setFragmentBuffer:_sampleBuf_cameraRaw offset:0 atIndex:2];
            }
        ];
    }
    
    // Fix highlights
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_FixHighlights"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
//    // Down-sample raw de-bayered image
//    {
//        [self _renderPass:cmdBuf texture:smallRawTexture name:@"ImageLayer_Downsample"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentBytes:&SmallRawTextureDownsampleFactor
//                    length:sizeof(SmallRawTextureDownsampleFactor) atIndex:1];
//                [encoder setFragmentTexture:texture atIndex:0];
//            }
//        ];
//    }
//    
//    // Fix highlights
//    {
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_FixHighlightsPropagation"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentTexture:texture atIndex:0];
//                [encoder setFragmentTexture:smallRawTexture atIndex:1];
//            }
//        ];
//    }
    
    // Camera raw -> XYY.D50
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_XYYD50FromCameraRaw"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
    // Decrease luminance
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_DecreaseLuminance"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
    // XYY.D50 -> XYZ.D50
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_XYZD50FromXYYD50"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentBuffer:_sampleBuf_XYZD50 offset:0 atIndex:1];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
//    // Decrease luminance
//    {
//        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_DecreaseLuminanceXYZD50"
//            block:^(id<MTLRenderCommandEncoder> encoder) {
//                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
//                [encoder setFragmentTexture:texture atIndex:0];
//                [encoder setFragmentTexture:rawTexture atIndex:1];
//            }
//        ];
//    }
    
    // XYZ.D50 -> LSRGB.D65
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_LSRGBD65FromXYZD50"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentBuffer:_sampleBuf_XYZD50 offset:0 atIndex:1];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
    
    // Apply SRGB gamma
    {
        [self _renderPass:cmdBuf texture:texture name:@"ImageLayer_SRGBGamma"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_ctx length:sizeof(_ctx) atIndex:0];
                [encoder setFragmentBuffer:_sampleBuf_SRGBD65 offset:0 atIndex:1];
                [encoder setFragmentTexture:texture atIndex:0];
            }
        ];
    }
    
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

//- (float)_sampleX:(int32_t)x y:(int32_t)y {
//    NSParameterAssert(x>=0 && x<_ctx.imageWidth);
//    NSParameterAssert(y>=0 && y<_ctx.imageHeight);
//    const ImagePixel* pixels = (const ImagePixel*)[_pixelData contents];
//    return (float)pixels[y*_ctx.imageWidth+x] / ImagePixelMax;
//}
//
//- (simd::float3)sampleCameraRaw:(CGRect)rect {
//    //  Row0    G1  R
//    //  Row1    B   G2
//    int32_t left = std::clamp((int32_t)round(rect.origin.x), 0, (int32_t)_ctx.imageWidth);
//    int32_t right = std::clamp((int32_t)round(rect.origin.x+rect.size.width), 0, (int32_t)_ctx.imageWidth);
//    int32_t top = std::clamp((int32_t)round(rect.origin.y), 0, (int32_t)_ctx.imageHeight);
//    int32_t bottom = std::clamp((int32_t)round(rect.origin.y+rect.size.height), 0, (int32_t)_ctx.imageHeight);
//    simd::float3 color = {0,0,0};
//    int32_t i = 0;
//    for (int32_t y=top; y<bottom; y++) {
//        for (int32_t x=left; x<right; x++, i++) {
//            const bool r = (!(y%2) && (x%2));
//            const bool g = ((!(y%2) && !(x%2)) || ((y%2) && (x%2)));
//            const bool b = ((y%2) && !(x%2));
//            const float val = [self _sampleX:x y:y];
//            if (r)      color[0] += val;
//            else if (g) color[1] += val;
//            else if (b) color[2] += val;
//        }
//    }
//    color /= i;
//    return color;
//}

- (void)setSampleRect:(CGRect)rect {
    rect.origin.x *= _ctx.imageWidth;
    rect.origin.y *= _ctx.imageHeight;
    rect.size.width *= _ctx.imageWidth;
    rect.size.height *= _ctx.imageHeight;
    _ctx.sampleRect = {
        .left = (uint32_t)std::clamp((int32_t)round(CGRectGetMinX(rect)), 0, (int32_t)_ctx.imageWidth),
        .right = (uint32_t)std::clamp((int32_t)round(CGRectGetMaxX(rect)), 0, (int32_t)_ctx.imageWidth),
        .top = (uint32_t)std::clamp((int32_t)round(CGRectGetMinY(rect)), 0, (int32_t)_ctx.imageHeight),
        .bottom = (uint32_t)std::clamp((int32_t)round(CGRectGetMaxY(rect)), 0, (int32_t)_ctx.imageHeight),
    };
    
    if (_ctx.sampleRect.left == _ctx.sampleRect.right) _ctx.sampleRect.right++;
    if (_ctx.sampleRect.top == _ctx.sampleRect.bottom) _ctx.sampleRect.bottom++;
    
    _sampleBuf_cameraRaw = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, _ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    _sampleBuf_XYZD50 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, _ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    _sampleBuf_SRGBD65 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, _ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    [self display];
}

- (simd::float3)sampleCameraRaw {
    assert(_sampleBuf_cameraRaw);
    const simd::float3* vals = (simd::float3*)[_sampleBuf_cameraRaw contents];
    size_t i = 0;
    simd::double3 c = {};
    simd::uint3 count = {};
    for (size_t y=_ctx.sampleRect.top; y<_ctx.sampleRect.bottom; y++) {
        for (size_t x=_ctx.sampleRect.left; x<_ctx.sampleRect.right; x++, i++) {
            const bool r = (!(y%2) && (x%2));
            const bool g = ((!(y%2) && !(x%2)) || ((y%2) && (x%2)));
            const bool b = ((y%2) && !(x%2));
            const simd::float3& val = vals[i];
            if (r) count[0]++;
            if (g) count[1]++;
            if (b) count[2]++;
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (count[0]) c[0] /= count[0];
    if (count[1]) c[1] /= count[1];
    if (count[2]) c[2] /= count[2];
    return {(float)c[0], (float)c[1], (float)c[2]};
}

//- (simd::float3)sampleCameraRaw {
//    assert(_sampleBuf_cameraRaw);
//    const float* vals = (float*)[_sampleBuf_cameraRaw contents];
//    size_t i = 0;
//    simd::float3 c = {0,0,0};
//    for (size_t y=_ctx.sampleRect.top; y<_ctx.sampleRect.bottom; y++) {
//        for (size_t x=_ctx.sampleRect.left; x<_ctx.sampleRect.right; x++, i++) {
//            const bool r = (!(y%2) && (x%2));
//            const bool g = ((!(y%2) && !(x%2)) || ((y%2) && (x%2)));
//            const bool b = ((y%2) && !(x%2));
//            const float val = vals[i];
//            if (r)      c[0] += val;
//            else if (g) c[1] += val;
//            else if (b) c[2] += val;
//        }
//    }
//    c /= i;
//    return c;
//}

- (simd::float3)sampleXYZD50 {
    assert(_sampleBuf_XYZD50);
    const simd::float3* vals = (simd::float3*)[_sampleBuf_XYZD50 contents];
    size_t i = 0;
    simd::double3 c = {0,0,0};
    for (size_t y=_ctx.sampleRect.top; y<_ctx.sampleRect.bottom; y++) {
        for (size_t x=_ctx.sampleRect.left; x<_ctx.sampleRect.right; x++, i++) {
            const simd::float3& val = vals[i];
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    c /= i;
    return {(float)c[0], (float)c[1], (float)c[2]};
}

- (simd::float3)sampleSRGBD65 {
    assert(_sampleBuf_SRGBD65);
    const simd::float3* vals = (simd::float3*)[_sampleBuf_SRGBD65 contents];
    size_t i = 0;
    simd::double3 c = {0,0,0};
    for (size_t y=_ctx.sampleRect.top; y<_ctx.sampleRect.bottom; y++) {
        for (size_t x=_ctx.sampleRect.left; x<_ctx.sampleRect.right; x++, i++) {
            const simd::float3& val = vals[i];
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    c /= i;
    return {(float)c[0], (float)c[1], (float)c[2]};
}

@end

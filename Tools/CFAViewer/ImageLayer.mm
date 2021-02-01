#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <mutex>
#import "ImageLayer.h"
#import "ImageLayerTypes.h"
#import "Assert.h"
#import "Util.h"
#import "ColorUtil.h"
using namespace CFAViewer;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;
using namespace ColorUtil;

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _library;
    NSMutableDictionary* _pipelineStates;
//    id<MTLRenderPipelineState> _debayerPipelineState;
//    id<MTLRenderPipelineState> _colorAdjustPipelineState;
//    id<MTLRenderPipelineState> _findHighlightsPipelineState;
//    id<MTLRenderPipelineState> _srgbGammaPipelineState;
    
    struct {
        std::mutex lock; // Protects this struct
        RenderContext ctx;
        bool debayerLMMSEGammaEnabled = false;
        ImageAdjustments imageAdjustments;
        id<MTLBuffer> pixelData = nil;
        
        id<MTLBuffer> sampleBuf_CamRaw_D50 = nil;
        id<MTLBuffer> sampleBuf_XYZ_D50 = nil;
        id<MTLBuffer> sampleBuf_SRGB_D65 = nil;
        
        ImageLayerDataChangedHandler dataChangedHandler = nil;
    } _state;
    
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
    
    _pipelineStates = [NSMutableDictionary new];
    
    auto lock = std::lock_guard(_state.lock);
        _state.sampleBuf_CamRaw_D50 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
        _state.sampleBuf_XYZ_D50 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
        _state.sampleBuf_SRGB_D65 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
    
    return self;
}

- (void)setImage:(const Image&)image {
    // If we don't have pixel data, ensure that our image has 0 pixels
    NSParameterAssert(image.pixels || (image.width*image.height)==0);
    
    auto lock = std::lock_guard(_state.lock);
    
    const size_t pixelCount = image.width*image.height;
    
    // Reset image size in case something fails
    _state.ctx.imageWidth = 0;
    _state.ctx.imageHeight = 0;
    
    const size_t len = pixelCount*sizeof(ImagePixel);
    if (len) {
        if (!_state.pixelData || [_state.pixelData length]<len) {
            _state.pixelData = [_device newBufferWithLength:len options:MTLResourceCPUCacheModeDefaultCache];
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
    
    const CGFloat scale = [self contentsScale];
    [self setBounds:{0, 0, _state.ctx.imageWidth/scale, _state.ctx.imageHeight/scale}];
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
    auto lock = std::lock_guard(_state.lock);
    _state.ctx.colorMatrix = simdFromMat(cm);
    
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
    Color_XYY_D50 whitePoint_XYY_D50 = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(1.,1.,1.));
    
    // Set the luminance of every color to the maximum luminance possible
    whitePoint_XYY_D50[2] = maxY;
    
    _state.ctx.whitePoint_XYY_D50 = simdFromMat(whitePoint_XYY_D50);
    _state.ctx.whitePoint_CamRaw_D50 = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(whitePoint_XYY_D50));
    
    [self setNeedsDisplay];
}

- (void)setDebayerLMMSEGammaEnabled:(bool)en {
    auto lock = std::lock_guard(_state.lock);
    _state.debayerLMMSEGammaEnabled = en;
    [self setNeedsDisplay];
}

- (void)setImageAdjustments:(const CFAViewer::ImageLayerTypes::ImageAdjustments&)adj {
    auto lock = std::lock_guard(_state.lock);
    _state.imageAdjustments = adj;
    [self setNeedsDisplay];
}

- (void)setHighlightFactor:(const Mat<double,3,3>&)hf {
    auto lock = std::lock_guard(_state.lock);
    _state.ctx.highlightFactorR = {(float)hf[0], (float)hf[1], (float)hf[2]};
    _state.ctx.highlightFactorG = {(float)hf[3], (float)hf[4], (float)hf[5]};
    _state.ctx.highlightFactorB = {(float)hf[6], (float)hf[7], (float)hf[8]};
    [self setNeedsDisplay];
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
// _state.lock must be held
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
    [encoder setVertexBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
    
    block(encoder);
    
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [encoder endEncoding];
}

// _state.lock must be held
- (id<MTLTexture>)_newTexture:(MTLPixelFormat)fmt {
    MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
    [desc setTextureType:MTLTextureType2D];
    [desc setWidth:_state.ctx.imageWidth];
    [desc setHeight:_state.ctx.imageHeight];
    [desc setPixelFormat:fmt];
    // TODO: most textures don't need `MTLTextureUsageShaderWrite`, add usage argument in case that speeds us up?
    [desc setUsage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
    id<MTLTexture> txt = [_device newTextureWithDescriptor:desc];
    Assert(txt, return nil);
    return txt;
}

- (void)display {
    auto lock = std::lock_guard(_state.lock);
    
    // Short-circuit if we don't have any image data
    if (!_state.pixelData) return;
    
    _inputHistogram = Histogram();
    _outputHistogram = Histogram();
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)_state.ctx.imageWidth, (CGFloat)_state.ctx.imageHeight}];
    
    id<MTLTexture> rawOriginalTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> blueTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> scaledBlueTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> redTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> scaledRedTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> rawTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> filteredHTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> filteredVTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> diffHTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> diffVTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> diffGRTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> diffGBTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> lTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> blurredLTxt = [self _newTexture:MTLPixelFormatR32Float];
    id<MTLTexture> txt = [self _newTexture:MTLPixelFormatRGBA32Float];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
//    // Pass-through (bilinear debayer only)
//    {
//        // Load the pixels into a texture
//        {
//            [self _renderPass:cmdBuf texture:rawOriginalTxt name:@"ImageLayer_LoadRaw"
//                block:^(id<MTLRenderCommandEncoder> encoder) {
//                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
//                    [encoder setFragmentBuffer:_state.pixelData offset:0 atIndex:1];
//                    [encoder setFragmentBuffer:_state.sampleBuf_CamRaw_D50 offset:0 atIndex:2];
//                }
//            ];
//        }
//        
//        // De-bayer render pass
//        {
//            // ImageLayer_DebayerBilinear
//            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_DebayerBilinear"
//                block:^(id<MTLRenderCommandEncoder> encoder) {
//                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
//                    [encoder setFragmentTexture:rawOriginalTxt atIndex:0];
//                }
//            ];
//        }
//        
//        // Run the final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
//        {
//            [self _renderPass:cmdBuf texture:[drawable texture] name:@"ImageLayer_Display"
//                block:^(id<MTLRenderCommandEncoder> encoder) {
//                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
//                    [encoder setFragmentTexture:txt atIndex:0];
//                }
//            ];
//        }
//    }
    
    {
        // Load the pixels into a texture
        {
            [self _renderPass:cmdBuf texture:rawOriginalTxt name:@"ImageLayer_LoadRaw"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentBuffer:_state.pixelData offset:0 atIndex:1];
                    [encoder setFragmentBuffer:_state.sampleBuf_CamRaw_D50 offset:0 atIndex:2];
                }
            ];
        }
        
        // Scale blue channel
        {
            // Interpolate blue channel
            {
                [self _renderPass:cmdBuf texture:blueTxt name:@"ImageLayer_InterpolateBlue"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawOriginalTxt atIndex:0];
                    }
                ];
            }
            
            // Scale blue channel
            {
                [self _renderPass:cmdBuf texture:scaledBlueTxt name:@"ImageLayer_ScaleBlue"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:blueTxt atIndex:0];
                    }
                ];
            }
            
            // Resample blue channel into raw
            {
                [self _renderPass:cmdBuf texture:rawOriginalTxt name:@"ImageLayer_ResampleBlue"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawOriginalTxt atIndex:0];
                        [encoder setFragmentTexture:scaledBlueTxt atIndex:1];
                    }
                ];
            }
        }
        
        // Scale red channel
        {
            // Interpolate red channel
            {
                [self _renderPass:cmdBuf texture:redTxt name:@"ImageLayer_InterpolateRed"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawOriginalTxt atIndex:0];
                    }
                ];
            }
            
            // Scale red channel
            {
                [self _renderPass:cmdBuf texture:scaledRedTxt name:@"ImageLayer_ScaleRed"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:redTxt atIndex:0];
                    }
                ];
            }
            
            // Resample red channel into raw
            {
                [self _renderPass:cmdBuf texture:rawOriginalTxt name:@"ImageLayer_ResampleRed"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawOriginalTxt atIndex:0];
                        [encoder setFragmentTexture:scaledRedTxt atIndex:1];
                    }
                ];
            }
        }
        
        // Fix highlights
        {
            [self _renderPass:cmdBuf texture:rawTxt name:@"ImageLayer_FixHighlightsRaw"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:rawOriginalTxt atIndex:0];
                }
            ];
        }
        
        // LMMSE Debayer
        {
            // Gamma before (improves quality of edges)
            if (_state.debayerLMMSEGammaEnabled) {
                [self _renderPass:cmdBuf texture:rawTxt name:@"ImageLayer_DebayerLMMSE_Gamma"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                    }
                ];
            }
            
            // Horizontal interpolation
            {
                const bool h = true;
                [self _renderPass:cmdBuf texture:filteredHTxt name:@"ImageLayer_DebayerLMMSE_Interp5"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                    }
                ];
            }
            
            // Vertical interpolation
            {
                const bool h = false;
                [self _renderPass:cmdBuf texture:filteredVTxt name:@"ImageLayer_DebayerLMMSE_Interp5"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                    }
                ];
            }
            
            // Calculate DiffH
            {
                [self _renderPass:cmdBuf texture:diffHTxt name:@"ImageLayer_DebayerLMMSE_NoiseEst"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:filteredHTxt atIndex:1];
                    }
                ];
            }
            
            // Calculate DiffV
            {
                [self _renderPass:cmdBuf texture:diffVTxt name:@"ImageLayer_DebayerLMMSE_NoiseEst"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:filteredVTxt atIndex:1];
                    }
                ];
            }
            
            // Smooth DiffH
            {
                const bool h = true;
                [self _renderPass:cmdBuf texture:filteredHTxt name:@"ImageLayer_DebayerLMMSE_Smooth9"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:diffHTxt atIndex:0];
                    }
                ];
            }
            
            // Smooth DiffV
            {
                const bool h = false;
                [self _renderPass:cmdBuf texture:filteredVTxt name:@"ImageLayer_DebayerLMMSE_Smooth9"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:diffVTxt atIndex:0];
                    }
                ];
            }
            
            // Calculate txt.g
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_DebayerLMMSE_CalcG"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:filteredHTxt atIndex:1];
                        [encoder setFragmentTexture:diffHTxt atIndex:2];
                        [encoder setFragmentTexture:filteredVTxt atIndex:3];
                        [encoder setFragmentTexture:diffVTxt atIndex:4];
                    }
                ];
            }
            
            // Calculate diffGRTxt.r
            {
                const bool modeGR = true;
                [self _renderPass:cmdBuf texture:diffGRTxt name:@"ImageLayer_DebayerLMMSE_CalcDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGRTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGBTxt.b
            {
                const bool modeGR = false;
                [self _renderPass:cmdBuf texture:diffGBTxt name:@"ImageLayer_DebayerLMMSE_CalcDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGRTxt.b
            {
                const bool modeGR = true;
                [self _renderPass:cmdBuf texture:diffGRTxt name:@"ImageLayer_DebayerLMMSE_CalcDiagAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGRTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGBTxt.r
            {
                const bool modeGR = false;
                [self _renderPass:cmdBuf texture:diffGBTxt name:@"ImageLayer_DebayerLMMSE_CalcDiagAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGRTxt.g
            {
                [self _renderPass:cmdBuf texture:diffGRTxt name:@"ImageLayer_DebayerLMMSE_CalcAxialAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGRTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGBTxt.g
            {
                [self _renderPass:cmdBuf texture:diffGBTxt name:@"ImageLayer_DebayerLMMSE_CalcAxialAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate txt.rb
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_DebayerLMMSE_CalcRB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:0];
                        [encoder setFragmentTexture:diffGRTxt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Gamma after (improves quality of edges)
            if (_state.debayerLMMSEGammaEnabled) {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_DebayerLMMSE_Degamma"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
        }
        
        // Camera raw -> XYY.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_XYYD50FromCameraRaw"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Exposure
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_Exposure"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    const float exposure = pow(2, _state.imageAdjustments.exposure);
                    [encoder setFragmentBytes:&exposure length:sizeof(exposure) atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
//        // Decrease luminance
//        {
//            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_DecreaseLuminance"
//                block:^(id<MTLRenderCommandEncoder> encoder) {
//                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
//                    [encoder setFragmentTexture:txt atIndex:0];
//                }
//            ];
//        }
        
        // XYY.D50 -> XYZ.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_XYZD50FromXYYD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // XYZ.D50 -> Lab.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_LabD50FromXYZD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Brightness
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_Brightness"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    auto brightness = _state.imageAdjustments.brightness;
                    [encoder setFragmentBytes:&brightness length:sizeof(brightness) atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Contrast
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_Contrast"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    const float contrast = _state.imageAdjustments.contrast;
                    [encoder setFragmentBytes:&contrast length:sizeof(contrast) atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        if (_state.imageAdjustments.localContrast.enable) {
            // Extract L
            {
                [self _renderPass:cmdBuf texture:lTxt name:@"ImageLayer_ExtractL"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Blur L channel
            {
                MPSImageGaussianBlur* blur = [[MPSImageGaussianBlur alloc] initWithDevice:_device
                    sigma:_state.imageAdjustments.localContrast.radius];
                [blur setEdgeMode:MPSImageEdgeModeClamp];
                [blur encodeToCommandBuffer:cmdBuf sourceTexture:lTxt destinationTexture:blurredLTxt];
            }
            
            // Local contrast
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_LocalContrast"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        auto& amount = _state.imageAdjustments.localContrast.amount;
                        [encoder setFragmentBytes:&amount length:sizeof(amount) atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                        [encoder setFragmentTexture:blurredLTxt atIndex:1];
                    }
                ];
            }
        }
        
        // Lab.D50 -> XYZ.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_XYZD50FromLabD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Saturation
        {
            // XYZ.D50 -> Luv.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_LuvD50FromXYZD50"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Luv.D50 -> LCHuv.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_LCHuvFromLuv"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Saturation
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_Saturation"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        const float sat = pow(2, 2*_state.imageAdjustments.saturation);
                        [encoder setFragmentBytes:&sat length:sizeof(sat) atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // LCHuv.D50 -> Luv.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_LuvFromLCHuv"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Luv.D50 -> XYZ.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_XYZD50FromLuvD50"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
        }
        
        // XYZ.D50 -> LSRGB.D65
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_LSRGBD65FromXYZD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Apply SRGB gamma
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer_SRGBGamma"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentBuffer:_state.sampleBuf_SRGB_D65 offset:0 atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Run the final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
        {
            [self _renderPass:cmdBuf texture:[drawable texture] name:@"ImageLayer_Display"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
    }
    
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [cmdBuf waitUntilCompleted];
    
    // Notify that our histogram changed
    auto dataChangedHandler = _state.dataChangedHandler;
    if (dataChangedHandler) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            dataChangedHandler(self);
        });
    }
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
    auto lock = std::lock_guard(_state.lock);
    auto& ctx = _state.ctx;
    
    rect.origin.x *= ctx.imageWidth;
    rect.origin.y *= ctx.imageHeight;
    rect.size.width *= ctx.imageWidth;
    rect.size.height *= ctx.imageHeight;
    ctx.sampleRect = {
        .left = (uint32_t)std::clamp((int32_t)round(CGRectGetMinX(rect)), 0, (int32_t)ctx.imageWidth),
        .right = (uint32_t)std::clamp((int32_t)round(CGRectGetMaxX(rect)), 0, (int32_t)ctx.imageWidth),
        .top = (uint32_t)std::clamp((int32_t)round(CGRectGetMinY(rect)), 0, (int32_t)ctx.imageHeight),
        .bottom = (uint32_t)std::clamp((int32_t)round(CGRectGetMaxY(rect)), 0, (int32_t)ctx.imageHeight),
    };
    
    if (ctx.sampleRect.left == ctx.sampleRect.right) ctx.sampleRect.right++;
    if (ctx.sampleRect.top == ctx.sampleRect.bottom) ctx.sampleRect.bottom++;
    
    _state.sampleBuf_CamRaw_D50 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    _state.sampleBuf_XYZ_D50 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    _state.sampleBuf_SRGB_D65 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    [self setNeedsDisplay];
}

- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler {
    auto lock = std::lock_guard(_state.lock);
    _state.dataChangedHandler = handler;
}

template <typename T>
std::unique_ptr<T[]> copyMTLBuffer(id<MTLBuffer> buf) {
    std::unique_ptr<T[]> p(new T[[buf length]/sizeof(T)]);
    memcpy(p.get(), [buf contents], [buf length]);
    return p;
}

- (Color_CamRaw_D50)sample_CamRaw_D50 {
    // Copy _state.sampleBuf_CamRaw_D50 locally
    auto lock = std::unique_lock(_state.lock);
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleBuf_CamRaw_D50);
        auto rect = _state.ctx.sampleRect;
    lock.unlock();
    
    size_t i = 0;
    simd::double3 c = {};
    simd::uint3 count = {};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
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

- (Color_XYZ_D50)sample_XYZ_D50 {
    // Copy _state.sampleBuf_XYZ_D50 locally
    auto lock = std::unique_lock(_state.lock);
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleBuf_XYZ_D50);
        auto rect = _state.ctx.sampleRect;
    lock.unlock();
    
    size_t i = 0;
    simd::double3 c = {0,0,0};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const simd::float3& val = vals[i];
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (i) c /= i;
    return {(float)c[0], (float)c[1], (float)c[2]};
}

- (Color_SRGB_D65)sample_SRGB_D65 {
    // Copy _state.sampleBuf_SRGB_D65 locally
    auto lock = std::unique_lock(_state.lock);
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleBuf_SRGB_D65);
        auto rect = _state.ctx.sampleRect;
    lock.unlock();
    
    size_t i = 0;
    simd::double3 c = {0,0,0};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const simd::float3& val = vals[i];
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (i) c /= i;
    return {(float)c[0], (float)c[1], (float)c[2]};
}

@end

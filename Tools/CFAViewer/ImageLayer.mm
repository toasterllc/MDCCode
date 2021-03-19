#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <mutex>
#import <vector>
#import "ImageLayer.h"
#import "ImageLayerTypes.h"
#import "Assert.h"
#import "Util.h"
#import "ColorUtil.h"
#import "TimeInstant.h"
#import "Poly2D.h"
#import "Defringe.h"
#import "DebayerLMMSE.h"
#import "Saturation.h"
#import "LocalContrast.h"
using namespace CFAViewer;
using namespace CFAViewer::MetalUtil;
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
        bool rawMode = false;
        
        Renderer renderer;
        
        struct {
            bool en = false;
            Defringe::Options options;
        } defringe;
        
        DebayerLMMSE::Options debayerLMMSEOptions;
        
        Saturation saturationFilter;
        
        bool reconstructHighlights = false;
        
        RenderContext ctx;
        ImageAdjustments imageAdjustments;
        id<MTLBuffer> pixelData = nil;
        
        Renderer::Buf sampleBuf_CamRaw_D50;
        Renderer::Buf sampleBuf_XYZ_D50;
        Renderer::Buf sampleBuf_SRGB_D65;
        
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
    
//    MTLHeapDescriptor* desc = [MTLHeapDescriptor new];
//    [desc setSize:128*1024*1024];
////    [desc setStorageMode:MTLStorageModeManaged];
//    _heap = [_device newHeapWithDescriptor:desc];
    
    _library = [_device newDefaultLibraryWithBundle:[NSBundle bundleForClass:[self class]] error:nil];
    Assert(_library, return nil);
    
    _pipelineStates = [NSMutableDictionary new];
    
    auto lock = std::lock_guard(_state.lock);
        _state.renderer = Renderer(_device, _library, _commandQueue);
        
        _state.sampleBuf_CamRaw_D50 = _state.renderer.createBuffer(sizeof(simd::float3));
        _state.sampleBuf_XYZ_D50 = _state.renderer.createBuffer(sizeof(simd::float3));
        _state.sampleBuf_SRGB_D65 = _state.renderer.createBuffer(sizeof(simd::float3));
    
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
    _state.ctx.cfaDesc = image.cfaDesc;
    
    const size_t len = pixelCount*sizeof(ImagePixel);
    if (len) {
        if (!_state.pixelData || [_state.pixelData length]<len) {
            _state.pixelData = _state.renderer.createBuffer(len);
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

- (void)setRawMode:(bool)rawMode {
    auto lock = std::lock_guard(_state.lock);
    _state.rawMode = rawMode;
    [self setNeedsDisplay];
}

static simd::float3x3 simdFromMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
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

- (void)setDefringe:(bool)en {
    auto lock = std::lock_guard(_state.lock);
    _state.defringe.en = en;
    [self setNeedsDisplay];
}

- (void)setDefringeOptions:(const Defringe::Options&)opts {
    auto lock = std::lock_guard(_state.lock);
    _state.defringe.options = opts;
    [self setNeedsDisplay];
}

- (void)setReconstructHighlights:(bool)en {
    auto lock = std::lock_guard(_state.lock);
    _state.reconstructHighlights = en;
    [self setNeedsDisplay];
}

- (void)setDebayerLMMSEApplyGamma:(bool)en {
    auto lock = std::lock_guard(_state.lock);
    _state.debayerLMMSEOptions.applyGamma = en;
    [self setNeedsDisplay];
}

- (void)setImageAdjustments:(const ImageAdjustments&)adj {
    auto lock = std::lock_guard(_state.lock);
    _state.imageAdjustments = adj;
    [self setNeedsDisplay];
}

- (void)setHighlightFactor:(const Mat<double,3,3>&)hf {
    auto lock = std::lock_guard(_state.lock);
    _state.ctx.highlightFactorR = {(float)hf.at(0,0), (float)hf.at(0,1), (float)hf.at(0,2)};
    _state.ctx.highlightFactorG = {(float)hf.at(1,0), (float)hf.at(1,1), (float)hf.at(1,2)};
    _state.ctx.highlightFactorB = {(float)hf.at(2,0), (float)hf.at(2,1), (float)hf.at(2,2)};
    [self setNeedsDisplay];
}

- (MetalUtil::Histogram)inputHistogram {
    return _inputHistogram;
}

- (MetalUtil::Histogram)outputHistogram {
    return _outputHistogram;
}

- (id<MTLRenderPipelineState>)_pipelineState:(NSString*)name {
    return [self _pipelineState:name format:MTLPixelFormatRGBA32Float];
}

- (id<MTLRenderPipelineState>)_pipelineState:(NSString*)name format:(MTLPixelFormat)format {
    NSParameterAssert(name);
    id<MTLRenderPipelineState> ps = _pipelineStates[name];
    if (!ps) {
        id<MTLFunction> vertexShader = [_library newFunctionWithName:@"ImageLayer::VertexShader"];
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

// Lock must be held
- (void)_displayToTexture:(id<MTLTexture>)outTxt drawable:(id<CAMetalDrawable>)drawable {
    NSParameterAssert(outTxt);
    
    // Short-circuit if we don't have any image data
    if (!_state.pixelData) return;
    
    _inputHistogram = Histogram();
    _outputHistogram = Histogram();
    
    Renderer::Txt raw = _state.renderer.createTexture(MTLPixelFormatR32Float,
        _state.ctx.imageWidth, _state.ctx.imageHeight);
    
    _state.renderer.render("ImageLayer::LoadRaw", raw,
        // Buffer args
        _state.ctx,
        _state.pixelData,
        _state.sampleBuf_CamRaw_D50
        // Texture args
    );
    
    Renderer::Txt rgb = _state.renderer.createTexture(MTLPixelFormatRGBA32Float,
        _state.ctx.imageWidth, _state.ctx.imageHeight);
    
    // Raw mode (bilinear debayer only)
    if (_state.rawMode) {
        // De-bayer
        _state.renderer.render("CFAViewer::Shader::DebayerBilinear::Debayer", rgb,
            // Buffer args
            _state.ctx.cfaDesc,
            // Texture args
            raw
        );
    
    } else {
        if (_state.defringe.en) {
            _state.defringe.options.cfaDesc = _state.ctx.cfaDesc;
            Defringe::Run(_state.renderer, _state.defringe.options, raw);
        }
        
        // Reconstruct highlights
        if (_state.reconstructHighlights) {
            Renderer::Txt tmp = _state.renderer.createTexture(MTLPixelFormatR32Float,
                _state.ctx.imageWidth, _state.ctx.imageHeight);
            
            _state.renderer.render("ImageLayer::ReconstructHighlights", tmp,
                // Buffer args
                _state.ctx,
                // Texture args
                raw
            );
            raw = std::move(tmp);
        }
        
        // LMMSE Debayer
        {
            _state.debayerLMMSEOptions.cfaDesc = _state.ctx.cfaDesc;
            DebayerLMMSE::Run(_state.renderer, _state.debayerLMMSEOptions, raw, rgb);
        }
        
        // Camera raw -> XYY.D50
        {
            _state.renderer.render("ImageLayer::XYYD50FromCameraRaw", rgb,
                _state.ctx,
                rgb
            );
        }
        
        // Exposure
        {
            const float exposure = pow(2, _state.imageAdjustments.exposure);
            _state.renderer.render("ImageLayer::Exposure", rgb,
                _state.ctx,
                exposure,
                rgb
            );
        }
        
//        // Decrease luminance
//        {
//            _state.renderer.render("ImageLayer::DecreaseLuminance", txt,
//                _state.ctx,
//                txt
//            );
//        }
        
        // XYY.D50 -> XYZ.D50
        {
            _state.renderer.render("ImageLayer::XYZD50FromXYYD50", rgb,
                _state.ctx,
                rgb
            );
        }
        
        // XYZ.D50 -> Lab.D50
        {
            _state.renderer.render("ImageLayer::LabD50FromXYZD50", rgb,
                _state.ctx,
                rgb
            );
        }
        
        // Brightness
        {
            auto brightness = _state.imageAdjustments.brightness;
            _state.renderer.render("ImageLayer::Brightness", rgb,
                _state.ctx,
                brightness,
                rgb
            );
        }
        
        // Contrast
        {
            const float contrast = _state.imageAdjustments.contrast;
            _state.renderer.render("ImageLayer::Contrast", rgb,
                _state.ctx,
                contrast,
                rgb
            );
        }
        
        // Local contrast
        if (_state.imageAdjustments.localContrast.enable) {
            LocalContrast::Run(_state.renderer, _state.imageAdjustments.localContrast.amount,
                _state.imageAdjustments.localContrast.radius, rgb);
        }
        
        // Lab.D50 -> XYZ.D50
        {
            _state.renderer.render("ImageLayer::XYZD50FromLabD50", rgb,
                _state.ctx,
                rgb
            );
        }
        
        // Saturation
        Saturation::Run(_state.renderer, _state.imageAdjustments.saturation, rgb);
        
        // XYZ.D50 -> LSRGB.D65
        {
            _state.renderer.render("ImageLayer::LSRGBD65FromXYZD50", rgb,
                _state.ctx,
                _state.sampleBuf_XYZ_D50,
                rgb
            );
        }
        
        // Apply SRGB gamma
        {
            _state.renderer.render("ImageLayer::SRGBGamma", rgb,
                _state.ctx,
                _state.sampleBuf_SRGB_D65,
                rgb
            );
        }
    }
    
    // Final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
    _state.renderer.render("ImageLayer::Display", outTxt,
        // Buffer args
        _state.ctx,
        // Texture args
        rgb
    );
    
    // If outTxt isn't framebuffer-only, then do a blit-sync, which is
    // apparently required for [outTxt getBytes:] to work, which
    // -CGImage uses.
    if (![outTxt isFramebufferOnly]) {
        _state.renderer.sync(outTxt);
    }
    
    if (drawable) _state.renderer.present(drawable);
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    _state.renderer.commitAndWait();
    
    // Notify that our histogram changed
    auto dataChangedHandler = _state.dataChangedHandler;
    if (dataChangedHandler) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            dataChangedHandler(self);
        });
    }
}

- (void)display {
    auto lock = std::lock_guard(_state.lock);
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)_state.ctx.imageWidth, (CGFloat)_state.ctx.imageHeight}];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    id<MTLTexture> txt = [drawable texture];
    Assert(txt, return);
    
    TimeInstant start;
    [self _displayToTexture:txt drawable:drawable];
    printf("Display took %f\n", start.durationMs()/1000.);
}

- (id)CGImage {
    auto lock = std::lock_guard(_state.lock);
    Renderer::Txt txt = _state.renderer.createTexture(MTLPixelFormatBGRA8Unorm,
        _state.ctx.imageWidth, _state.ctx.imageHeight,
        MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    [self _displayToTexture:txt drawable:nil];
    const NSUInteger w = [txt width];
    const NSUInteger h = [txt height];
    
    uint32_t opts = kCGImageAlphaNoneSkipFirst;
    id ctx = CFBridgingRelease(CGBitmapContextCreate(nullptr, w, h, 8, 4*w, SRGBColorSpace(), opts));
    Assert(ctx, return nil);
    
    uint8_t* data = (uint8_t*)CGBitmapContextGetData((CGContextRef)ctx);
    [txt getBytes:data bytesPerRow:4*w fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    
    // BGRA -> ARGB
    for (size_t i=0; i<4*w*h; i+=4) {
        std::swap(data[i], data[i+3]);
        std::swap(data[i+1], data[i+2]);
    }
    
    return CFBridgingRelease(CGBitmapContextCreateImage((CGContextRef)ctx));
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
    
    _state.sampleBuf_CamRaw_D50 =
        _state.renderer.createBuffer(sizeof(simd::float3)*std::max((uint32_t)1,
        ctx.sampleRect.count()));
    
    _state.sampleBuf_XYZ_D50 =
        _state.renderer.createBuffer(sizeof(simd::float3)*std::max((uint32_t)1,
        ctx.sampleRect.count()));
    
    _state.sampleBuf_SRGB_D65 =
        _state.renderer.createBuffer(sizeof(simd::float3)*std::max((uint32_t)1,
        ctx.sampleRect.count()));
    
    [self setNeedsDisplay];
}

- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler {
    auto lock = std::lock_guard(_state.lock);
    _state.dataChangedHandler = handler;
}

template <typename T>
std::unique_ptr<T[]> copyMTLBuffer(id<MTLBuffer> buf) {
    auto p = std::make_unique<T[]>([buf length]/sizeof(T));
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

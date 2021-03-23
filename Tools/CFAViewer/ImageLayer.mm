#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <mutex>
#import <vector>
#import "ImageLayer.h"
#import "Assert.h"
#import "Util.h"
#import "ColorUtil.h"
#import "TimeInstant.h"
#import "ImagePipeline.h"
using namespace CFAViewer;
using namespace MetalUtil;
using namespace ColorUtil;
using namespace ImagePipeline;

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _library;
//    id<MTLRenderPipelineState> _debayerPipelineState;
//    id<MTLRenderPipelineState> _colorAdjustPipelineState;
//    id<MTLRenderPipelineState> _findHighlightsPipelineState;
//    id<MTLRenderPipelineState> _srgbGammaPipelineState;
    
    struct {
        std::mutex lock; // Protects this struct
        Renderer renderer;
        struct {
            CFADesc cfaDesc;
            uint32_t width = 0;
            uint32_t height = 0;
            Renderer::Buf pixels;
        } img;
        Pipeline::Options opts;
        Pipeline::SampleOptions sampleOpts;
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
    
    auto lock = std::lock_guard(_state.lock);
        _state.renderer = Renderer(_device, _library, _commandQueue);
        _state.sampleOpts.camRaw_D50 = _state.renderer.createBuffer(sizeof(simd::float3));
        _state.sampleOpts.xyz_D50 = _state.renderer.createBuffer(sizeof(simd::float3));
        _state.sampleOpts.srgb_D65 = _state.renderer.createBuffer(sizeof(simd::float3));
    
    return self;
}


- (void)setImage:(const CFAViewer::ImageLayerTypes::Image&)img {
    // If we don't have pixel data, ensure that our image has 0 pixels
    NSParameterAssert(img.pixels || (img.width*img.height)==0);
    
    auto lock = std::lock_guard(_state.lock);
    
    const size_t pixelCount = img.width*img.height;
    
    // Reset image size in case something fails
    _state.img.width = 0;
    _state.img.height = 0;
    _state.img.cfaDesc = img.cfaDesc;
    
    const size_t len = pixelCount*sizeof(ImagePixel);
    if (len) {
        if (!_state.img.pixels || [_state.img.pixels length]<len) {
            _state.img.pixels = _state.renderer.createBuffer(len);
            Assert(_state.img.pixels, return);
        }
        
        // Copy the pixel data into the Metal buffer
        memcpy([_state.img.pixels contents], img.pixels, len);
        
        // Set the image size now that we have image data
        _state.img.width = img.width;
        _state.img.height = img.height;
    
    } else {
        _state.img.pixels = Renderer::Buf();
    }
    
    const CGFloat scale = [self contentsScale];
    [self setBounds:{0, 0, _state.img.width/scale, _state.img.height/scale}];
    [self setNeedsDisplay];
}


- (void)setOptions:(const CFAViewer::ImageLayerTypes::Options&)opts {
    auto lock = std::lock_guard(_state.lock);
    _state.opts = opts;
    [self setNeedsDisplay];
}

//static simd::float3x3 simdFromMat(const Mat<double,3,3>& m) {
//    return {
//        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
//        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
//        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
//    };
//}

//- (void)setHighlightFactor:(const Mat<double,3,3>&)hf {
//    auto lock = std::lock_guard(_state.lock);
//    _state.ctx.highlightFactorR = {(float)hf.at(0,0), (float)hf.at(0,1), (float)hf.at(0,2)};
//    _state.ctx.highlightFactorG = {(float)hf.at(1,0), (float)hf.at(1,1), (float)hf.at(1,2)};
//    _state.ctx.highlightFactorB = {(float)hf.at(2,0), (float)hf.at(2,1), (float)hf.at(2,2)};
//    [self setNeedsDisplay];
//}

- (MetalUtil::Histogram)inputHistogram {
    return _inputHistogram;
}

- (MetalUtil::Histogram)outputHistogram {
    return _outputHistogram;
}

// Lock must be held
- (void)_displayToTexture:(id<MTLTexture>)outTxt drawable:(id<CAMetalDrawable>)drawable {
    const ImagePipeline::Pipeline::Image img = {
        .cfaDesc = _state.img.cfaDesc,
        .width = _state.img.width,
        .height = _state.img.height,
        .pixels = _state.img.pixels,
    };
    
    ImagePipeline::Pipeline::Run(_state.renderer, img,
        _state.opts, _state.sampleOpts, outTxt);
    
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
    [self setDrawableSize:{(CGFloat)_state.img.width, (CGFloat)_state.img.height}];
    
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
        _state.img.width, _state.img.height,
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
    auto& img = _state.img;
    auto& sampleOpts = _state.sampleOpts;
    auto& sampleRect = sampleOpts.rect;
    
    rect.origin.x *= img.width;
    rect.origin.y *= img.height;
    rect.size.width *= img.width;
    rect.size.height *= img.height;
    sampleRect = {
        .left = std::clamp((int32_t)round(CGRectGetMinX(rect)), 0, (int32_t)img.width),
        .right = std::clamp((int32_t)round(CGRectGetMaxX(rect)), 0, (int32_t)img.width),
        .top = std::clamp((int32_t)round(CGRectGetMinY(rect)), 0, (int32_t)img.height),
        .bottom = std::clamp((int32_t)round(CGRectGetMaxY(rect)), 0, (int32_t)img.height),
    };
    
    if (sampleRect.left == sampleRect.right) sampleRect.right++;
    if (sampleRect.top == sampleRect.bottom) sampleRect.bottom++;
    
    sampleOpts.camRaw_D50 =
        _state.renderer.createBuffer(sizeof(simd::float3)*std::max(1, sampleRect.count()));
    
    sampleOpts.xyz_D50 =
        _state.renderer.createBuffer(sizeof(simd::float3)*std::max(1, sampleRect.count()));
    
    sampleOpts.srgb_D65 =
        _state.renderer.createBuffer(sizeof(simd::float3)*std::max(1, sampleRect.count()));
    
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
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleOpts.camRaw_D50);
        auto rect = _state.sampleOpts.rect;
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
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleOpts.xyz_D50);
        auto rect = _state.sampleOpts.rect;
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
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleOpts.srgb_D65);
        auto rect = _state.sampleOpts.rect;
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

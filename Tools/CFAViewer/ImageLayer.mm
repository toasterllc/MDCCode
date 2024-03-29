#import "ImageLayer.h"
#import <Metal/Metal.h>
#import "Assert.h"
#import "Util.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"
using namespace CFAViewer;

// _PixelFormat: Our pixels are in the linear RGB space (LSRGB), and need conversion to the display color space.
// To do so, we declare that our pixels are LSRGB (ie we _don't_ use the _sRGB MTLPixelFormat variant!),
// and we opt-in to color matching by setting the colorspace on our CAMetalLayer via -setColorspace:.
// (Without calling -setColorspace:, CAMetalLayers don't perform color matching!)
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm;

static CGColorSpaceRef _LSRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    return cs;
}

@implementation ImageLayer {
    Toastbox::Renderer _renderer;
    id<MTLTexture> _txt;
    
//    ImagePipelineManager* _ipm;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _renderer = Toastbox::Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    [self setActions:LayerNullActions()];
    [self setPixelFormat:_PixelFormat];
    [self setColorspace:_LSRGBColorSpace()]; // See comment for _PixelFormat
    [self setDevice:device];
    return self;
}

//- (void)setImagePipelineManager:(ImagePipelineManager*)ipm {
//    _ipm = ipm;
//    [self setDevice:_ipm->renderer.dev];
//}

- (void)setTexture:(id<MTLTexture>)txt {
    const CGFloat scale = [self contentsScale];
    assert([NSThread isMainThread]);
    _txt = txt;
    [self setBounds:{0, 0, [_txt width]/scale, [_txt height]/scale}];
    [self setNeedsDisplay];
}

- (void)display {
    if (!_txt) return;
    assert([_txt width]);
    assert([_txt height]);
    
    
//    if (!_ipm) return;
//    if (!_ipm->rawImage) return;
//    
//    [_ipm render];
//    
    const NSUInteger w = [_txt width];
    const NSUInteger h = [_txt height];
//    if (w*h <= 0) return;
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)w, (CGFloat)h}];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    id<MTLTexture> drawableTxt = [drawable texture];
    
    _renderer.copy(_txt, drawableTxt);
    _renderer.commitAndWait();
    [drawable present];
    
//    printf("Display took %f\n", start.durationMs()/1000.);
}

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

//- (void)setNeedsDisplay {
//    if ([NSThread isMainThread]) {
////        // Update our bounds
////        if (_ipm) {
////            assert(_ipm->rawImage);
////            const CGFloat scale = [self contentsScale];
////            [self setBounds:{0, 0, _ipm->rawImage->width/scale, _ipm->rawImage->height/scale}];
////        }
//        [super setNeedsDisplay];
//    
//    } else {
//        // Call -setNeedsDisplay on the main thread, so that drawing is
//        // sync'd with drawing triggered by the main thread.
//        // Don't use dispatch_async here, because dispatch_async's don't get drained
//        // while the runloop is run recursively, eg during mouse tracking.
//        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
//            [self setNeedsDisplay];
//        });
//        CFRunLoopWakeUp(CFRunLoopGetMain());
//    }
//}

@end

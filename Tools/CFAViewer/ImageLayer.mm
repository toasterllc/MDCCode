#import "ImageLayer.h"
#import <Metal/Metal.h>
#import "Assert.h"
#import "Util.h"
using namespace CFAViewer;
//using namespace MDCTools::MetalUtil;
//using namespace MDCTools::ImagePipeline;

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
//    ImagePipelineManager* _ipm;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [self setActions:LayerNullActions()];
    [self setPixelFormat:_PixelFormat];
    [self setColorspace:_LSRGBColorSpace()]; // See comment for _PixelFormat
    return self;
}

//- (void)setImagePipelineManager:(ImagePipelineManager*)ipm {
//    _ipm = ipm;
//    [self setDevice:_ipm->renderer.dev];
//}

- (void)display {
//    if (!_ipm) return;
//    if (!_ipm->rawImage) return;
//    
//    [_ipm render];
//    
//    NSUInteger w = [_ipm->result.txt width];
//    NSUInteger h = [_ipm->result.txt height];
//    if (w*h <= 0) return;
//    
//    // Update our drawable size using our view size (in pixels)
//    [self setDrawableSize:{(CGFloat)w, (CGFloat)h}];
//    
//    id<CAMetalDrawable> drawable = [self nextDrawable];
//    Assert(drawable, return);
//    
//    _ipm->renderer.copy(_ipm->result.txt, [drawable texture]);
//    _ipm->renderer.commitAndWait();
//    [drawable present];
    
//    printf("Display took %f\n", start.durationMs()/1000.);
}

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

- (void)setNeedsDisplay {
    if ([NSThread isMainThread]) {
//        // Update our bounds
//        if (_ipm) {
//            assert(_ipm->rawImage);
//            const CGFloat scale = [self contentsScale];
//            [self setBounds:{0, 0, _ipm->rawImage->width/scale, _ipm->rawImage->height/scale}];
//        }
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

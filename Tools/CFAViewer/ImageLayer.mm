#import "ImageLayer.h"
#import <Metal/Metal.h>
#import "Assert.h"
#import "Util.h"
#import "ImagePipelineManager.h"
using namespace CFAViewer;
using namespace MDCTools::MetalUtil;
using namespace MDCTools::ImagePipeline;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

@implementation ImageLayer {
    ImagePipelineManager* _ipm;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [self setActions:LayerNullActions()];
    [self setPixelFormat:_PixelFormat];
    return self;
}

- (void)setImagePipelineManager:(ImagePipelineManager*)ipm {
    _ipm = ipm;
    [self setDevice:_ipm->renderer.dev];
}

- (void)display {
    if (!_ipm) return;
    
    [_ipm render];
    
    NSUInteger w = [_ipm->result.txt width];
    NSUInteger h = [_ipm->result.txt height];
    if (w*h <= 0) return;
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)w, (CGFloat)h}];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    _ipm->renderer.copy(_ipm->result.txt, [drawable texture]);
    _ipm->renderer.commitAndWait();
    [drawable present];
    
//    printf("Display took %f\n", start.durationMs()/1000.);
}

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

- (void)setNeedsDisplay {
    if ([NSThread isMainThread]) {
        // Update our bounds
        if (_ipm) {
            const CGFloat scale = [self contentsScale];
            [self setBounds:{0, 0, _ipm->rawImage.width/scale, _ipm->rawImage.height/scale}];
        }
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

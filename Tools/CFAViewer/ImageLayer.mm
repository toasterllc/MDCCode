#import "ImageLayer.h"
#import <Metal/Metal.h>
#import "Assert.h"
#import "Util.h"
#import "TimeInstant.h"
#import "ImagePipelineManager.h"
using namespace CFAViewer;
using namespace MetalUtil;
using namespace ImagePipeline;

@implementation ImageLayer {
    ImagePipelineManager* _ipm;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [self setActions:LayerNullActions()];
    return self;
}

- (void)setImagePipelineManager:(ImagePipelineManager*)ipm {
    _ipm = ipm;
    [self setDevice:_ipm->renderer.dev];
}

- (void)display {
    if (!_ipm) return;
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)_ipm->rawImage.width, (CGFloat)_ipm->rawImage.height}];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    TimeInstant start;
    {
        [_ipm render];
        _ipm->renderer.copy(_ipm->result.txt, [drawable texture]);
        _ipm->renderer.present(drawable);
        _ipm->renderer.commit();
    }
    printf("Display took %f\n", start.durationMs()/1000.);
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

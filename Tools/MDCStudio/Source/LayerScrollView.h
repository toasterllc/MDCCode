#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@protocol LayerScrollViewLayer
- (void)setTranslation:(CGPoint)t magnification:(CGFloat)m;
@end

@interface LayerScrollView : NSScrollView
- (void)setScrollLayer:(CALayer<LayerScrollViewLayer>*)layer;

- (void)magnifyToFit;
// -magnifyToFitIfNeeded: only performs the magnify if the content is already nearly the
// size of the container. Visually this appears to the user as if the content 'snaps' to
// the size of the container when the content is within a threshold of the container size.
- (void)magnifyToFitIfNeeded;
@end

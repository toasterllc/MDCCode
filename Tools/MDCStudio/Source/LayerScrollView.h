#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@protocol LayerScrollViewLayer
- (void)setTranslation:(CGPoint)t magnification:(CGFloat)m;
@end

@interface LayerScrollView : NSScrollView

- (void)setScrollLayer:(CALayer<LayerScrollViewLayer>*)layer;

- (bool)magnifyToFit;
- (void)setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate;

// -magnifySnapToFit: only performs the magnify if the content is already near the size
// of the container. To the user this appears as if the content 'snaps' to the size of the
// container, when the content is near the container size.
- (void)magnifySnapToFit;

// Menu actions
- (void)magnifyIncrease:(id)sender;
- (void)magnifyDecrease:(id)sender;
- (void)magnifyToFit:(id)sender;

@end

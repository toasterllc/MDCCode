#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@protocol LayerScrollViewLayer
- (void)setTranslation:(CGPoint)t magnification:(CGFloat)m;
@end

@interface LayerScrollView : NSScrollView
- (void)setScrollLayer:(CALayer<LayerScrollViewLayer>*)layer;
- (void)magnifyToFit;
- (void)magnifyToFitIfNeeded;
@end

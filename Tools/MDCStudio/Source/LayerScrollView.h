#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@protocol LayerScrollViewLayer
- (void)setTranslation:(CGPoint)t magnification:(CGFloat)m;
@end

@interface LayerScrollView : NSScrollView
- (void)setScrollLayer:(CALayer<LayerScrollViewLayer>*)layer;
@end


// TODO: MetalScrollLayer should implement method to get transformation matrix
// TODO: LayerScrollView/MetalScrollLayer should use -[CALayer preferredFrameSize] to set document view size

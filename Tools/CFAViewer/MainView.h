#import <Cocoa/Cocoa.h>
#import <vector>
#import "BaseView.h"
@class ImageLayer;
@protocol MainViewDelegate;

@interface MainView : BaseView

- (void)reset;

- (ImageLayer*)imageLayer;
- (void)setDelegate:(id<MainViewDelegate>)delegate;

- (CGRect)sampleRect;
- (void)setSampleRect:(CGRect)x;

- (std::vector<CGPoint>)colorCheckerPositions;
- (void)setColorCheckerPositions:(const std::vector<CGPoint>&)points;
- (void)resetColorCheckerPositions;
- (void)setColorCheckerCircleRadius:(CGFloat)r;
- (void)setColorCheckersVisible:(bool)visible;
@end

@protocol MainViewDelegate
- (void)mainViewSampleRectChanged:(MainView*)v;
- (void)mainViewColorCheckerPositionsChanged:(MainView*)v;
- (NSDragOperation)mainViewDraggingEntered:(id<NSDraggingInfo>)sender;
- (bool)mainViewPerformDragOperation:(id<NSDraggingInfo>)sender;
@end

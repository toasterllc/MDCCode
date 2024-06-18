#import <Cocoa/Cocoa.h>
#import <vector>
#import "BaseView.h"
#import "ColorChecker.h"
@class ImageLayer;
@protocol MainViewDelegate;

using ColorCheckerPositions = std::array<CGPoint,ColorChecker::Count>;

@interface MainView : BaseView

- (void)reset;

- (ImageLayer*)imageLayer;
- (void)setDelegate:(id<MainViewDelegate>)delegate;

- (CGRect)sampleRect;

- (const ColorCheckerPositions&)colorCheckerPositions;
- (void)setColorCheckerPositions:(const ColorCheckerPositions&)x;

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

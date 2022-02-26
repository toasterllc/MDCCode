#import <Cocoa/Cocoa.h>
@class SourceListView;

// MainViewContentView: informal protocol instead of a real @protocol, so that content view
// classes don't have a dependency on MainView
@interface NSView (MainViewContentView)
- (NSResponder*)initialFirstResponder;
@end

enum class MainViewAnimation {
    None,
    SlideToLeft,
    SlideToRight,
};

@interface MainView : NSView

- (SourceListView*)sourceListView;

- (NSView*)contentView;
- (void)setContentView:(NSView*)contentView animation:(MainViewAnimation)animation;

@end

#import <Cocoa/Cocoa.h>
@class SourceListView;

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

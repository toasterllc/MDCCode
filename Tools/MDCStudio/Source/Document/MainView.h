#import <Cocoa/Cocoa.h>
@class SourceListView;

@interface MainView : NSView

- (SourceListView*)sourceListView;

- (NSView*)contentView;
- (void)setContentView:(NSView*)contentView;

@end

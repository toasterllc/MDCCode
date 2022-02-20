#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
@class SourceListView;

@protocol SourceListViewDelegate
@required
- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView;
@end

struct SourceListViewSelection {
    MDCStudio::MDCDevicePtr device;
    // library
};

@interface SourceListView : NSView
- (void)setDelegate:(id<SourceListViewDelegate>)delegate;
- (SourceListViewSelection)selection;
@end

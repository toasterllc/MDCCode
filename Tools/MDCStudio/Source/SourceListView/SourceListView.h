#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
@class SourceListView;

using SourceListViewSelectionChangedHandler = void(^)(SourceListView*);

struct SourceListViewSelection {
    MDCStudio::MDCDevicePtr device;
    // library
};

@interface SourceListView : NSView
- (void)setSelectionChangedHandler:(SourceListViewSelectionChangedHandler)handler;
- (SourceListViewSelection)selection;
@end

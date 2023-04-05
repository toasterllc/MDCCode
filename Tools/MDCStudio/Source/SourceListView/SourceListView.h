#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageSource.h"
@class SourceListView;

@protocol SourceListViewDelegate
@required
- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView;
- (void)sourceListView:(SourceListView*)sourceListView showDeviceSettings:(MDCStudio::MDCDevicePtr)device;
@end

@interface SourceListView : NSView
- (void)setDelegate:(id<SourceListViewDelegate>)delegate;
- (MDCStudio::ImageSourcePtr)selection;
@end

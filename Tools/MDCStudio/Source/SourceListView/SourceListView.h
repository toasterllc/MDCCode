#import <Cocoa/Cocoa.h>
#import "Shared/MDCDevice.h"
#import "Shared/ImageSource.h"
@class SourceListView;

@protocol SourceListViewDelegate
@required
- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView;
- (void)sourceListView:(SourceListView*)sourceListView showSettingsForDevice:(MDCStudio::MDCDevicePtr)device;
- (void)sourceListView:(SourceListView*)sourceListView factoryResetDevice:(MDCStudio::MDCDevicePtr)device;
- (void)sourceListView:(SourceListView*)sourceListView exportDiagnosticData:(MDCStudio::MDCDevicePtr)device;
@end

@interface SourceListView : NSView
- (void)setImageSources:(const std::set<MDCStudio::ImageSourcePtr>&)x;
- (void)setDelegate:(id<SourceListViewDelegate>)x;
- (MDCStudio::ImageSourcePtr)selection;
@end

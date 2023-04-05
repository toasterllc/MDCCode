#import <Cocoa/Cocoa.h>

// Informal protocol so sections don't depend on this header
@interface NSView (DeviceSettingsViewSection)
- (NSLayoutYAxisAnchor*)deviceSettingsView_HeaderBottomAnchor;
- (CGFloat)deviceSettingsView_HeaderBottomAnchorOffset;
@end

@interface DeviceSettingsView : NSView
- (instancetype)initWithFrame:(NSRect)frame;
@end

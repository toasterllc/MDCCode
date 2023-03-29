#import <Cocoa/Cocoa.h>

// Informal protocol so sections don't depend on this header
@interface NSView (DeviceSettingsViewSection)
- (NSView*)deviceSettingsView_HeaderEndView;
@end

@interface DeviceSettingsView : NSView
- (instancetype)initWithFrame:(NSRect)frame;
@end

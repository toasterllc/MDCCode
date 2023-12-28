#import <Cocoa/Cocoa.h>
@class DeviceSettingsView;

@interface DeviceSettingsSheet : NSWindow
- (instancetype)initWithView:(DeviceSettingsView*)view;
@end

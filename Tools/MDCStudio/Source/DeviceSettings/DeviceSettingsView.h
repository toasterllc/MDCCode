#import <Cocoa/Cocoa.h>
#import "Code/Shared/MSP.h"
@class DeviceSettingsView;

@protocol DeviceSettingsViewDelegate
@required
- (void)deviceSettingsView:(DeviceSettingsView*)view dismiss:(bool)save;
@end

// Informal protocol so sections don't depend on this header
@interface NSView (DeviceSettingsViewSection)
- (NSView*)deviceSettingsView_HeaderEndView;
@end

@interface DeviceSettingsView : NSView
- (instancetype)initWithSettings:(const MSP::Settings&)settings
    delegate:(id<DeviceSettingsViewDelegate>)delegate;

- (const MSP::Settings&)settings;
@end

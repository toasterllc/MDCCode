#import <Cocoa/Cocoa.h>
#import "MDCDevicesManager.h"
using namespace MDCStudio;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate

- (void)_handleDeviceIncompatibleVersion:(const MDCUSBDevice::IncompatibleVersion&)e {
    NSAlert* alert = [NSAlert new];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert setMessageText:@"Incompatible Photon"];
    [alert setInformativeText:[NSString stringWithFormat:@"A Photon was connected that is running firmware that is too new for this version of MDCStudio.\n\nPlease use a newer version of MDCStudio.\n\nError: %s", e.what()]];
    [alert runModal];
}

- (void)applicationWillFinishLaunching:(NSNotification*)note {
    __weak auto selfWeak = self;
    MDCDevicesManager::IncompatibleVersionHandler handler = [=] (const MDCUSBDevice::IncompatibleVersion& e) {
        MDCUSBDevice::IncompatibleVersion ecopy = e;
        dispatch_async(dispatch_get_main_queue(), ^{
            [selfWeak _handleDeviceIncompatibleVersion:ecopy];
        });
    };
    
    MDCDevicesManagerGlobal(Object::Create<MDCDevicesManager>(handler));
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    // no_destroy attribute is required, otherwise DeviceLocks would be destroyed and
    // relinquish the locks, which is exactly what we don't want to do! The locks need
    // to be held throughout termination to prevent device IO, to ensure the device is
    // kept out of host mode.
    [[clang::no_destroy]]
    static std::vector<std::unique_lock<std::mutex>> DeviceLocks;
    
    // Ensure that all devices are out of host mode when we exit, by acquiring each device's
    // device lock and stashing the locks in our global DeviceLocks.
    MDCDevicesManagerPtr devicesManager = MDCDevicesManagerGlobal();
    const std::vector<MDCDeviceRealPtr> devices = devicesManager->devices();
    for (MDCDeviceRealPtr device : devices) {
        DeviceLocks.push_back(device->deviceLock(true));
    }
    printf("applicationShouldTerminate\n");
    return NSTerminateNow;
}

@end

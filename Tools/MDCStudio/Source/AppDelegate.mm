#import <Cocoa/Cocoa.h>
#import "MDCDevicesManager.h"
using namespace MDCStudio;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate

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
    const std::vector<MDCDevicePtr> devices = devicesManager->devices();
    for (MDCDevicePtr device : devices) {
        DeviceLocks.push_back(device->deviceLock(true));
    }
    printf("applicationShouldTerminate\n");
    return NSTerminateNow;
}

@end

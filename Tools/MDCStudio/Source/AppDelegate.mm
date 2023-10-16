#import <Cocoa/Cocoa.h>
#import "MDCDevicesManager.h"
using namespace MDCStudio;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    MDCDevicesManagerPtr devicesManager = MDCDevicesManagerGlobal();
    const std::vector<MDCDevicePtr> devices = devicesManager->devices();
    for (MDCDevicePtr device : devices) {
        
    }
    printf("applicationShouldTerminate\n");
    return NSTerminateNow;
}

@end

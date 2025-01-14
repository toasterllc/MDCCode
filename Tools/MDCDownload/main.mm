#import <Foundation/Foundation.h>
#import "Shared/MDCDevicesManager.h"
using namespace MDCStudio;

int main(int argc, const char* argv[]) {
    
    for (;;) {
    
        MDCStudio::MDCDevicesManagerPtr devicesManager = MDCStudio::Object::Create<MDCDevicesManager>([] (const MDCUSBDevice::IncompatibleVersion& x) {
            throw x;
        });
        
        auto devices = devicesManager->devices();
        printf("device count: %ju\n", (uintmax_t)devices.size());
        
        sleep(1);
    
    }
    
    return 0;
}

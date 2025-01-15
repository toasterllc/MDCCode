#import <Foundation/Foundation.h>
#import "Shared/MDCDevicesManager.h"
#import "STMApp.elf.h"
#import "ICEApp.bin.h"
using namespace MDCStudio;

int main(int argc, const char* argv[]) {
    
    // Configure MDCDeviceHard
    {
        MDCDeviceHard::STMAppData(STMApp_elf, std::size(STMApp_elf));
        MDCDeviceHard::ICEAppData(ICEApp_bin, std::size(ICEApp_bin));
    }
    
    for (;;) {
        
        MDCStudio::MDCDevicesManagerPtr devicesManager = MDCStudio::Object::Create<MDCDevicesManager>([] (const MDCUSBDevice::IncompatibleVersion& x) {
            throw x;
        });
        
        auto devices = devicesManager->devices();
        printf("device count: %ju\n", (uintmax_t)devices.size());
        
//        sleep(1);
        
//        usleep(500000);
        
        usleep(100000);
    
    }
    
    return 0;
}

#import <Foundation/Foundation.h>
#import "Shared/MDCDevicesManager.h"
#import "Shared/ImageExporter/ImageExporter.h"
#import "STMApp.elf.h"
#import "ICEApp.bin.h"
using namespace MDCStudio;

static MDCDeviceHardPtr _DeviceGet() {
    MDCStudio::MDCDevicesManagerPtr devicesManager = MDCStudio::Object::Create<MDCDevicesManager>([] (const MDCUSBDevice::IncompatibleVersion& x) {
            throw x;
        });
    
    auto devices = devicesManager->devices();
    if (devices.empty()) {
        throw std::runtime_error("no devices connected");
    } else if (devices.size() > 1) {
        throw std::runtime_error("more than one device connected");
    }
    return *devices.begin();
}

int main(int argc, const char* argv[]) {
    // Configure MDCDeviceHard
    {
        MDCDeviceHard::Config(STMApp_elf, std::size(STMApp_elf), ICEApp_bin, std::size(ICEApp_bin));
    }
    
    try {
        MDCDeviceHardPtr device = _DeviceGet();
        ImageExporter::
    
    } catch (std::exception& e) {
        printf("Error: %s\n", e.what());
    }
    
    return 0;
}

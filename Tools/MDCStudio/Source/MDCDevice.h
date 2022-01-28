#import <Foundation/Foundation.h>
#import <filesystem>
#import "MDCUSBDevice.h"
#import "ImgStore.h"

class MDCDevice : public MDCUSBDevice {
public:
    using MDCUSBDevice::MDCUSBDevice;
    
    MDCDevice(USBDevice&& dev) : MDCUSBDevice(std::move(dev)) {
        printf("MDCDevice()\n");
    }
    
    ImgStorePtr imgStore() {
        if (!_imgStore) {
            auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
            if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
            
            const _Path appSupportDir = _Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
            std::filesystem::create_directories(appSupportDir);
            
            _imgStore = std::make_shared<ImgStore>(appSupportDir / "ImgStore");
        }
        return _imgStore;
    }
    
private:
    using _Path = std::filesystem::path;
    ImgStorePtr _imgStore;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

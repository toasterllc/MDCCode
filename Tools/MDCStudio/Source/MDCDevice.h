#import <Foundation/Foundation.h>
#import <filesystem>
#import "MDCUSBDevice.h"
#import "ImageLibrary.h"

class MDCDevice : public MDCUSBDevice {
public:
    using MDCUSBDevice::MDCUSBDevice;
    
    MDCDevice(USBDevice&& dev) : MDCUSBDevice(std::move(dev)) {
        printf("MDCDevice()\n");
    }
    
    ~MDCDevice() {
        auto lock = std::unique_lock(_state.lock);
        if (_state.updateImageLibraryThread.joinable()) {
            _state.updateImageLibraryThread.join();
        }
    }
    
    ImageLibraryPtr imgLib() {
        auto lock = std::unique_lock(_state.lock);
        if (!_state.imgLib) {
            auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
            if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
            
            const _Path appSupportDir = _Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
            std::filesystem::create_directories(appSupportDir);
            
            _state.imgLib = std::make_shared<ImageLibrary>(appSupportDir / "ImageLibrary");
        }
        return _state.imgLib;
    }
    
    void updateImageLibrary() {
        auto lock = std::unique_lock(_state.lock);
        _state.updateImageLibraryThread = std::thread([this] { _threadUpdateImageLibrary(); });
        _state.updateImageLibraryThread.detach();
    }
    
private:
    using _Path = std::filesystem::path;
    
    void _threadUpdateImageLibrary() {
        
    }
    
    struct {
        std::mutex lock;
        ImageLibraryPtr imgLib;
        std::thread updateImageLibraryThread;
    } _state;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

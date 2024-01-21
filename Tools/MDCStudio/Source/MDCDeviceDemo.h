#import "MDCDevice.h"

namespace MDCStudio {

struct MDCDeviceDemo; using MDCDeviceDemoPtr = SharedPtr<MDCDeviceDemo>;
struct MDCDeviceDemo : MDCDevice {
    void init() {
        printf("MDCDeviceDemo::init() %p\n", this);
        MDCDevice::init(XXX); // Call super
    }
    
    ~MDCDeviceDemo() {
        printf("~MDCDeviceDemo() %p\n", this);
    }
    
    // MARK: - Device Settings
    
    const MSP::Settings settings() override {
        return _settings;
    }
    
    void settings(const MSP::Settings& x) override {
        _settings = x;
    }
    
    void factoryReset() override {
        // Clear the image library
        {
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->clear();
            _imageLibrary->write();
        }
        
        _settings = {};
    }
    
    // MARK: - Image Syncing
    
    void sync() override {
        // No-op
    }
    
    // MARK: - Status
    
    std::optional<Status> status() override {
        return std::nullopt;
    }
    
    std::optional<float> syncProgress() override {
        return std::nullopt;
    }
    
    MSP::Settings _settings = {};
};

} // namespace MDCStudio

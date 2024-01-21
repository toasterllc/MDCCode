#import "MDCDevice.h"

namespace MDCStudio {

struct MDCDeviceTour : MDCDevice {

    void init() {
        printf("MDCDeviceTour::init() %p\n", this);
        MDCDevice::init(XXX); // Call super
    }
    
    ~MDCDeviceTour() {
        printf("~MDCDeviceTour() %p\n", this);
    }
    
    // MARK: - Device Settings
    
    const MSP::Settings settings() override {
        return _settings;
    }
    
    void settings(const MSP::Settings& x) override {
        _settings = x;
    }
    
    void factoryReset() override {
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

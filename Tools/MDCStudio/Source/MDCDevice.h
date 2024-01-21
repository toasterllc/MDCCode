#import "ImageSource.h"

namespace MDCStudio {

struct MDCDevice : ImageSource {

    void init(const Path& dir) {
        printf("MDCDevice::init() %p\n", this);
        ImageSource::init(dir); // Call super
        
        // Give device a default name
        if (name() == "") {
            name("Photon");
        }
    }
    
    // MARK: - Device Settings
    
    const MSP::Settings settings() = 0;
    void settings(const MSP::Settings& x) = 0;
    void factoryReset() = 0;
    
    // MARK: - Image Syncing
    
    void sync() = 0;
    
    // MARK: - Status
    
    std::optional<Status> status() = 0;
    std::optional<float> syncProgress() = 0;

};
using MDCDevicePtr = SharedPtr<MDCDevice>;

} // namespace MDCStudio

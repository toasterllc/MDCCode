#import "ImageSource.h"

namespace MDCStudio {

struct MDCDevice; using MDCDevicePtr = SharedPtr<MDCDevice>;
struct MDCDevice : ImageSource {
    struct Status {
        float batteryLevel = 0;
        size_t loadImageCount = 0;
    };
    
    ~MDCDevice() {
        printf("~MDCDevice() %p\n", this);
    }
    
    void init(const Path& dir) {
        printf("MDCDevice::init() %p\n", this);
        ImageSource::init(dir); // Call super
        
        // Give device a default name
        if (name() == "") {
            name("Photon");
        }
    }
    
    // MARK: - Device Settings
    
    virtual const MSP::Settings settings() = 0;
    virtual void settings(const MSP::Settings& x) = 0;
    virtual void factoryReset() = 0;
    
    // MARK: - Image Syncing
    
    virtual void sync() = 0;
    
    // MARK: - Status
    
    virtual std::optional<Status> status() = 0;
    virtual std::optional<float> syncProgress() = 0;

};

} // namespace MDCStudio

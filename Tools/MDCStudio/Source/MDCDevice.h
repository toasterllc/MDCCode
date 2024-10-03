#import "ImageSource.h"

namespace MDCStudio {

struct MDCDevice; using MDCDevicePtr = SharedPtr<MDCDevice>;
struct MDCDevice : ImageSource {
    struct Status {
        float batteryLevel = 0;
        size_t loadImageCount = 0;
    };
    
    static Path _DevicesDir() {
        auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
        
        const Path appSupportDir = Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
        return appSupportDir / "Devices";
    }
    
    static inline Path DevicesDir = _DevicesDir();
    
    static bool DevicesExist() {
        // Passing `ec` to directory_iterator() causes us to ignore the directory not existing
        std::error_code ec;
        for (const Path& p : std::filesystem::directory_iterator(DevicesDir, ec)) {
            if (p.filename().string().at(0) == '.') continue;
            return true;
        }
        return false;
    }
    
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

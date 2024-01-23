#import <iterator>
#import <unistd.h>
#import "MDCDevice.h"
#import "Toastbox/Mmap.h"
#import "Toastbox/NumForStr.h"

namespace MDCStudio {

struct MDCDeviceDemo; using MDCDeviceDemoPtr = SharedPtr<MDCDeviceDemo>;
struct MDCDeviceDemo : MDCDevice {
    static constexpr const char _TmpDirTemplate[] = "llc.toaster.photon-capture.XXXXXX";
    void init() {
        namespace fs = std::filesystem;
        printf("MDCDeviceDemo::init() %p\n", this);
        
        std::string tmpTemplate = fs::temp_directory_path() / _TmpDirTemplate;
        const Path tmpDir = mkdtemp(tmpTemplate.data());
        MDCDevice::init(tmpDir); // Call super
        name("Photon Demo");
        
        const Path demoDir = Path([[[NSBundle mainBundle] resourcePath] UTF8String]) / "demo";
        _thumbDir = demoDir / "thumb";
        _fullDir = demoDir / "full";
        
        // Collect the image ids into a sorted vector
        std::vector<Img::Id> thumbIds;
        for (const fs::path& p : fs::directory_iterator(_thumbDir)) {
            if (p.filename().string().at(0) == '.') continue;
            thumbIds.push_back(Toastbox::IntForStr<Img::Id>(p.filename().string()));
        }
        std::sort(thumbIds.begin(), thumbIds.end());
        
        // Create the image records in our image library
        std::set<ImageRecordPtr> recs;
        {
            auto lock = std::unique_lock(*_imageLibrary);
            
            _imageLibrary->add(thumbIds.size());
            
            size_t i = 0;
            auto it = _imageLibrary->begin();
            for (Img::Id id : thumbIds) {
                ImageRecordPtr rec = *it;
                ImageRecordInit(rec, id, 0, 0);
                recs.insert(rec);
                i++;
                it++;
            }
        }
        
        // Load the images!
        // This will cause our dataRead() functions to be called to actually supply the image data.
        _loadThumbs(Priority::Low, true, recs);
    }
    
    ~MDCDeviceDemo() {
        // Delete our temporary directory.
        // We have some sanity checks before we remove it, so a bug
        // doesn't cause us to delete the wrong directory.
        const Path d = dir();
        assert(!d.empty());
        assert(d.is_absolute());
        assert(d.string().size() > sizeof(_TmpDirTemplate));
        std::filesystem::remove_all(d);
        
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
        return Status{
            .batteryLevel = 0.75,
        };
    }
    
    std::optional<float> syncProgress() override {
        return std::nullopt;
    }
    
    // MARK: - Data Read
    
    void dataRead(const ImageRecordPtr& rec, const _ThumbBuffer& data) override {
        Toastbox::Mmap mmap(_thumbDir / std::to_string(rec->info.id));
        assert(mmap.len() == sizeof(*data));
        memcpy(*data, mmap.data(), sizeof(*data));
    }
    
    void dataRead(const ImageRecordPtr& rec, const _ImageBuffer& data) override {
        Toastbox::Mmap mmap(_fullDir / std::to_string(rec->info.id));
        assert(mmap.len() == sizeof(*data));
        memcpy(*data, mmap.data(), sizeof(*data));
    }
    
    Path _thumbDir;
    Path _fullDir;
    MSP::Settings _settings = {};
};

} // namespace MDCStudio

#import <iterator>
#import <unistd.h>
#import "Code/Lib/Toastbox/Mmap.h"
#import "Code/Lib/Toastbox/NumForStr.h"
#import "MDCDevice.h"
#import "TmpDir.h"

namespace MDCStudio {

struct MDCDeviceDemo; using MDCDeviceDemoPtr = SharedPtr<MDCDeviceDemo>;
struct MDCDeviceDemo : MDCDevice {
    static void _ImageOptionsInit(ImageOptions& opts) {
        const ColorRaw illum{0.56862, 1, 0.70588};
        const CCM ccm = CCM{
            .illum = illum,
            .matrix = ColorMatrixForIlluminant(illum).matrix,
        };
        
        ImageWhiteBalanceSet(opts.whiteBalance, false, ccm);
        
        opts.exposure   = -0.110;
        opts.saturation = +0.200;
        opts.localContrast = {
            .amount = 0.448,
            .radius = 62.651,
        };
        
        opts.reconstructHighlights = false;
    }
    
    void init() {
        namespace fs = std::filesystem;
        printf("MDCDeviceDemo::init() %p\n", this);
        
        const Path tmpDir = TmpDir::SubDirCreate("MDCDeviceDemo");
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
                ImageRecordInit(*rec, id, 0, 0);
                recs.insert(rec);
                i++;
                it++;
            }
        }
        
        // Perform our initial image import
        _loadThumbs(Priority::Low, true, recs);
        
        // Set our custom ImageOptions (just for aesthetics) on every image and re-render
        // the thumbnails.
        //
        // We have to render twice because the initial import populates rec.info and does
        // our illuminant estimation. (Illuminant estimation is necessary for
        // auto-white-balance to function, should the user modify one of the demo photos
        // to enable AWB).
        {
            auto lock = std::unique_lock(*_imageLibrary);
            for (auto it=_imageLibrary->begin(); it!=_imageLibrary->end(); it++) {
                ImageRecordPtr rec = *it;
                _ImageOptionsInit(rec->options);
            }
        }
        
        _loadThumbs(Priority::Low, false, recs);
    }
    
    ~MDCDeviceDemo() {
        printf("~MDCDeviceDemo() %p\n", this);
        
        // Delete our temporary directory.
        // We have some sanity checks before we remove it, so a bug
        // doesn't cause us to delete the wrong directory.
        const Path d = dir();
        assert(!d.empty());
        assert(d.is_absolute());
        std::filesystem::remove_all(d);
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

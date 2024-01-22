#import <iterator>
#import "MDCDevice.h"
#import "Toastbox/Mmap.h"
#import "Toastbox/NumForStr.h"

namespace MDCStudio {

struct MDCDeviceDemo; using MDCDeviceDemoPtr = SharedPtr<MDCDeviceDemo>;
struct MDCDeviceDemo : MDCDevice {
    void init() {
        namespace fs = std::filesystem;
        
        printf("MDCDeviceDemo::init() %p\n", this);
        MDCDevice::init("/Users/dave/Desktop/DemoImageSource"); // Call super
        
        _thumbDir = "/Users/dave/Desktop/demo/thumb";
        _fullDir = "/Users/dave/Desktop/demo/full";
        
        std::vector<Img::Id> thumbIds;
        for (const fs::path& p : fs::directory_iterator(_thumbDir)) {
            if (p.filename().string().at(0) == '.') continue;
            thumbIds.push_back(Toastbox::IntForStr<Img::Id>(p.filename().string()));
        }
        
        std::sort(thumbIds.begin(), thumbIds.end());
        
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
            
//            size_t i = 0;
//            for (auto it=_imageLibrary->begin(); it!=_imageLibrary->end(); it++) {
//                const Img::Id id = thumbIds.at(i);
//                ImageRecordPtr rec = _imageLibrary->back();
//                ImageRecordInit(rec, id, 0, 0);
//                recs.insert(rec);
//                i++;
//            }
            
//            for (Img::Id id : thumbIds) {
//    //            Toastbox::Mmap thumb(p);
//    //            Toastbox::Mmap full(fullDir / p.filename());
//                
//                
//                
//                ImageRecordPtr rec = _imageLibrary->back();
//                ImageRecordInit(rec, id, 0, 0);
//                recs.insert(rec);
//            }
        }
        
        _loadThumbs(Priority::Low, true, recs);
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

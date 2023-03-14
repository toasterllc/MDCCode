#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <set>
#import <array>
#import <chrono>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Toastbox/Mmap.h"
#import "Toastbox/Queue.h"
#import "Toastbox/Math.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/TimeConvert.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/BC7Encoder.h"
#import "ImageLibrary.h"
#import "ImageCache.h"
#import "ImageSource.h"

namespace MDCStudio {

class MDCDevice : public ImageSource {
private:
    using _ThumbCompressor = BC7Encoder<ImageThumb::ThumbWidth, ImageThumb::ThumbHeight>;
    
public:
    using Observer = std::function<bool()>;
    using Device = MDCTools::Lockable<MDCUSBDevice>;
    
    MDCDevice(MDCUSBDevice&& dev) :
    _dev(std::move(dev)),
    _dir(_DirForSerial(_dev.serial())),
    _imageLibrary(_dir / "ImageLibrary"),
    _imageCache(_imageLibrary, _imageProvider()) {
    
        printf("MDCDevice()\n");
        
        // Give device a default name
        char name[256];
        snprintf(name, sizeof(name), "MDC Device %s", _dev.serial().c_str());
        _name = std::string(name);
        
        // Read state from disk
        try {
            _SerializedState state = _SerializedStateRead(_dir);
            _name = std::string(state.name);
        } catch (const std::exception& e) {}
        
        // Perform device IO
        {
            auto lock = std::unique_lock(_dev);
            
            // Update our _mspState from the device
            _mspState = _dev.mspStateRead();
            
            // Enter host mode
            _dev.mspHostModeSet(true);
            
            // Update the device's time
            {
                using namespace std::chrono;
                using namespace date;
                
                const Time::Instant mdcTime = _dev.mspTimeGet();
                const Time::Instant actualTime = Time::Current();
                
                auto startTime = steady_clock::now();
                _dev.mspTimeSet(actualTime);
                const milliseconds timeSetDuration = duration_cast<milliseconds>(steady_clock::now()-startTime);
                
                if (Time::Absolute(mdcTime)) {
                    const microseconds deltaUs = clock_cast<utc_clock>(mdcTime)-clock_cast<utc_clock>(actualTime);
                    
                    printf("[Set device time] Time before update: 0x%016jx [absolute] (delta from actual time: %+jd us)\n", (uintmax_t)mdcTime,
                        (intmax_t)deltaUs.count());
                } else {
                    printf("[Set device time] Time before update: 0x%016jx [relative]\n", (uintmax_t)mdcTime);
                }
                
                printf("[Set device time] Time after update: 0x%016jx (took %ju ms)\n", (uintmax_t)actualTime,
                    (uintmax_t)timeSetDuration.count());
            }
            
            // Load ICE40 with our app
            _ICEConfigure(_dev);
            
            // Init SD card
            #warning TODO: how should we handle sdInit() failing (throwing)?
            _sdCardInfo = _dev.sdInit();
            
            if (!_mspState.sd.valid) {
                // MSPApp state isn't valid -- ignore
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: !_mspState.sd.valid");
            }
            
            if (memcmp(&_sdCardInfo.cardId, &_mspState.sd.cardId, sizeof(_mspState.sd.cardId))) {
                // Current SD card id doesn't match MSP's card id
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: memcmp(...)");
            }
        }
        
        // Load the library
        {
            auto lock = std::unique_lock(_imageLibrary);
            _imageLibrary.read();
        }
        
        // Start threads
        {
            _sync.thread = std::thread([&] { _sync_thread(); });
            
            _sdRead.thread = std::thread([&] { _sdRead_thread(); });
            
            for (int i=0; i<_ThreadCount(); i++) {
                _thumbRender.threads.emplace_back([&] { _thumbRender_thread(); });
            }
            
            _thumbUpdate.thread = std::thread([&] { _thumbUpdate_thread(); });
        }
    }
    
    ~MDCDevice() {
        // Signal our threads to stop
        _sync.loadImages.read.signal.stop();
        _sync.loadImages.render.signal.stop();
        _thumbUpdate.loadImages.read.signal.stop();
        _thumbUpdate.loadImages.render.signal.stop();
        _sync.signal.stop();
        _sdRead.signal.stop();
        _thumbRender.signal.stop();
        _thumbUpdate.signal.stop();
        
        // Wait for threads to stop
        _sync.thread.join();
        _sdRead.thread.join();
        for (std::thread& t : _thumbRender.threads) t.join();
        _thumbUpdate.thread.join();
    }
    
    const std::string& name() {
        assert([NSThread isMainThread]);
        return _name;
    }
    
    void name(const std::string_view& name) {
        assert([NSThread isMainThread]);
        _name = name;
        write();
        _notifyObservers();
    }
    
    const Toastbox::SendRight& service() const {
        return _dev.dev().service();
    }
    
//    Device& device() { return _dev; }
    
    void observerAdd(Observer&& observer) {
        assert([NSThread isMainThread]);
        _observers.push_front(std::move(observer));
    }
    
    void write() {
        assert([NSThread isMainThread]);
        
        _SerializedState state;
        state.version = _Version;
        // Copy UTF8 device name into state.name
        // state.name is initialized with zeroes, so we don't need to explicitly set a
        // null byte, but we do need to limit the number of copied bytes to
        // `sizeof(state.name)-1` to ensure that the null byte isn't overwritten
        _name.copy(state.name, sizeof(state.name)-1);
        
        _SerializedStateWrite(_dir, state);
    }
    
    // MARK: - ImageSource
    
    ImageLibrary& imageLibrary() override { return _imageLibrary; }
    
    ImageCache& imageCache() override { return _imageCache; }
    
    void visibleThumbs(ImageRecordIter begin, ImageRecordIter end) override {
//        // Determine whether we need to 
//        bool recreate = false;
//        for (auto it=begin; it!=end; it++) {
//            ImageRecordPtr rec = *it;
//            if (rec->options.thumb.render) {
//                if (_thumbUpdateWorkPrev.find() != _thumbUpdateWorkPrev.end()) {
//                    recreate = true;
//                    break;
//                }
//            }
//        }
//        
//        if (recreate) {
//            std::set<ImageRecordPtr> recs;
//            for (auto it=begin; it!=end; it++) {
//                ImageRecordPtr rec = *it;
//                if (rec->options.thumb.render) {
//                    recs.insert(rec);
//                }
//            }
//            {
//                auto lock = std::unique_lock(_thumbUpdate.lock);
//                _thumbUpdate.work = recs;
//            }
//            _thumbUpdateWorkPrev = std::move(recs);
//        }
        
        
//        _thumbUpdateWorkPrev
//        
//        #warning TODO: we should cache the last value set on _thumbUpdate, and only do something if there's a new record
        bool enqueued = false;
        {
            auto lock = _thumbUpdate.signal.lock();
            _thumbUpdate.work.clear();
            for (auto it=begin; it!=end; it++) {
                ImageRecordPtr rec = *it;
                if (rec->options.thumb.render) {
                    _thumbUpdate.work.insert(rec);
                    enqueued = true;
                }
            }
        }
        if (enqueued) _thumbUpdate.signal.signalOne();
    }
    
private:
    // MARK: - Private
    
    using _Path = std::filesystem::path;
    
    // _SDBlock: we're intentionally not using SD::Block because we want our block addressing type
    // to be wider than the SD card's addressing. This is because in our math logic, we want to be
    // able to use an 'end strategy' (ie last+1) instead of a 'last strategy', and the former can't
    // address the last block if it's the same width as the SD card's addressing.
    using _SDBlock = uint64_t;
    
    static constexpr uint32_t _Version = 0;
    static constexpr uint64_t _UnixTimeOffset = 1640995200; // 2022-01-01 00:00:00 +0000
    
    static constexpr MDCTools::CFADesc _CFADesc = {
        MDCTools::CFAColor::Green, MDCTools::CFAColor::Red,
        MDCTools::CFAColor::Blue, MDCTools::CFAColor::Green,
    };
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
        char name[128] = {}; // UTF-8 with NULL byte
    };
    
    enum class _Priority : uint8_t { High, Low, Count };
    
    struct _Signal {
        struct Stop : std::exception {};
        
        template <typename T_Cond>
        auto wait(T_Cond cond) {
            auto l = std::unique_lock(_lock);
            _cv.wait(l, [&] {
                if (_stop) throw Stop();
                return cond();
            });
            return l;
        }
        
        std::unique_lock<std::mutex> lock() {
            auto l = std::unique_lock(_lock);
            if (_stop) throw Stop();
            return l;
        }
        
        void signalOne() { _cv.notify_one(); }
        void signalAll() { _cv.notify_all(); }
        
        void stop() {
            {
                auto l = std::unique_lock(_lock);
                _stop = true;
            }
            _cv.notify_all();
        }
        
    private:
        std::mutex _lock;
        std::condition_variable _cv;
        bool _stop = false;
    };
    
    struct _LoadImagesWork {
        _Priority priority;
        std::vector<ImageRecordPtr> recs;
        bool initial = false;
    };
    
    struct _SDReadWork;
    struct _SDReadStatus {
        _Signal signal; // Protects this struct
        std::vector<_SDReadWork> done;
    };
    
    struct _SDReadContext {};
    
    struct _SDReadWork {
        _SDBlock block = 0;
        size_t len = 0;
        #warning TODO: switch status to be a reference
        _SDReadStatus* status = nullptr;
        ImageRecordPtr rec;
        std::unique_ptr<uint8_t[]> data;
//        
//        std::shared_ptr<_SDReadStatus> statusLock() {
//            return status.lock();
//        }
        
        bool operator<(const _SDReadWork& x) const {
            if (block != x.block) return block < x.block;
            if (len != x.len) return len < x.len;
            if (status != x.status) return (uintptr_t)status < (uintptr_t)x.status;
            return false;
        }
        
        bool operator==(const _SDReadWork& x) const {
            if (block != x.block) return false;
            if (len != x.len) return false;
            if (status != x.status) return false;
            return true;
        }
    };
    
    struct _SDReadWorkQueue {
//        std::queue<_SDReadWork> queue;
        std::set<_SDReadWork> set;
    };
    
    struct _SDCoalescedWork {
        std::vector<_SDReadWork> works;
        _SDBlock blockBegin = 0;
        _SDBlock blockEnd = 0;
    };
    
    struct _ThumbRenderWork {
        ImageRecordPtr rec;
        bool initial = false;
        std::unique_ptr<uint8_t[]> data;
    };
    
    struct _ThumbRenderStatus {
        _Signal signal; // Protects this struct
        std::vector<_ThumbRenderWork> done;
    };
    
    struct _LoadImagesState {
        _SDReadStatus read;
        _ThumbRenderStatus render;
    };
    
    static int _ThreadCount() {
        static int ThreadCount = std::max(1, (int)std::thread::hardware_concurrency());
        return ThreadCount;
    }
    
    static _SDBlock _AddrFull(const MSP::State& msp, uint32_t idx) {
        return msp.sd.fullBase + ((_SDBlock)idx * ImgSD::Full::ImageBlockCount);
    }
    
    static _SDBlock _AddrThumb(const MSP::State& msp, uint32_t idx) {
        return msp.sd.thumbBase + ((_SDBlock)idx * ImgSD::Thumb::ImageBlockCount);
    }
    
    static _Path _StatePath(const _Path& dir) { return dir / "State"; }
    
    static _Path _DirForSerial(const std::string_view& serial) {
        auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
        
        const _Path appSupportDir = _Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
        return appSupportDir / "Devices" / serial;
    }
    
    static _SerializedState _SerializedStateRead(const _Path& dir) {
        std::ifstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(dir));
        
        _SerializedState state;
        f.read((char*)&state, sizeof(state));
        state.name[sizeof(state.name)-1] = 0; // Ensure that state.name has a null byte
        
        if (state.version != _Version) {
            throw Toastbox::RuntimeError("invalid state version (expected: 0x%jx, got: 0x%jx)",
                (uintmax_t)_Version,
                (uintmax_t)state.version
            );
        }
        
        return state;
    }
    
    static void _SerializedStateWrite(const _Path& dir, const _SerializedState& state) {
        std::ofstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(dir));
        f.write((char*)&state, sizeof(state));
    }
    
    static const MSP::ImgRingBuf& _GetImgRingBuf(const MSP::State& state) {
        const MSP::ImgRingBuf& imgRingBuf0 = state.sd.imgRingBufs[0];
        const MSP::ImgRingBuf& imgRingBuf1 = state.sd.imgRingBufs[1];
        const std::optional<int> comp = MSP::ImgRingBuf::Compare(imgRingBuf0, imgRingBuf1);
        if (!comp) throw Toastbox::RuntimeError("both image ring buffers are invalid");
        return *comp>=0 ? imgRingBuf0 : imgRingBuf1;
    }
    
    static void _ICEConfigure(MDCUSBDevice& dev) {
        const char* ICEBinPath = "/Users/dave/repos/MDCCode/Code/ICE40/ICEAppSDReadoutSTM/Synth/Top.bin";
        Toastbox::Mmap mmap(ICEBinPath);
        
        // Write the ICE40 binary
        dev.iceRAMWrite(mmap.data(), mmap.len());
    }
    
    static bool _ImageChecksumValid(const void* data, Img::Size size) {
        const size_t ChecksumOffset = (size==Img::Size::Full ? Img::Full::ChecksumOffset : Img::Thumb::ChecksumOffset);
        // Validate thumbnail checksum
        const uint32_t checksumExpected = ChecksumFletcher32(data, ChecksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, (uint8_t*)data+ChecksumOffset, Img::ChecksumLen);
        if (checksumGot != checksumExpected) {
            printf("Checksum invalid (expected:0x%08x got:0x%08x)\n", checksumExpected, checksumGot);
            return false;
        }
        return true;
    }
    
    static constexpr size_t _ThumbTmpStorageLen = ImageThumb::ThumbWidth * ImageThumb::ThumbWidth * 4;
    using _ThumbTmpStorage = std::array<uint8_t, _ThumbTmpStorageLen>;
    
    // _ThumbRender(): renders a thumbnail from the RAW source pixels (src) into the
    // destination buffer (dst), as BC7-compressed data
    static CCM _ThumbRender(MDCTools::Renderer& renderer, _ThumbCompressor& compressor, _ThumbTmpStorage& tmpStorage,
        const ImageOptions& opts, bool estimateIlluminant, const void* src, void* dst) {
        
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        using namespace Toastbox;
        
        CCM ccm;
        
        // Render thumbnail into `thumbTxt`
        constexpr MTLTextureUsage ThumbTxtUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        const Renderer::Txt thumbTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm,
            ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, ThumbTxtUsage);
        {
            Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
                Img::Thumb::PixelWidth, Img::Thumb::PixelHeight, (const ImagePixel*)src);
            
            Renderer::Txt rgbTxt = renderer.textureCreate(rawTxt, MTLPixelFormatRGBA32Float);
            
            const Pipeline::DebayerOptions debayerOpts = {
                .cfaDesc        = _CFADesc,
                .illum          = (estimateIlluminant ? std::nullopt : std::optional<ColorRaw>(opts.whiteBalance.illum)),
                .debayerLMMSE   = { .applyGamma = true, },
            };
            
            const Pipeline::DebayerResult debayerResult = Pipeline::Debayer(renderer, debayerOpts, rawTxt, rgbTxt);
            
            ccm = {
                .illum = (estimateIlluminant ? debayerResult.illum : ColorRaw(opts.whiteBalance.illum)),
                .matrix = (estimateIlluminant ? ColorMatrixForIlluminant(debayerResult.illum).matrix : ColorMatrix((double*)opts.whiteBalance.colorMatrix))
            };
            
            const Pipeline::ProcessOptions processOpts = {
                .illum          = ccm.illum,
                .colorMatrix    = ccm.matrix,
                
                .exposure   = (float)opts.exposure,
                .saturation = (float)opts.saturation,
                .brightness = (float)opts.brightness,
                .contrast   = (float)opts.contrast,
                
                .localContrast = {
                    .en     = (opts.localContrast.amount!=0 && opts.localContrast.radius!=0),
                    .amount = (float)opts.localContrast.amount,
                    .radius = (float)opts.localContrast.radius,
                },
            };
            
            Pipeline::Process(renderer, processOpts, rgbTxt, thumbTxt);
            renderer.sync(thumbTxt);
            renderer.commitAndWait();
        }
        
        // Compress thumbnail into `dst`
        {
            [thumbTxt getBytes:&tmpStorage[0] bytesPerRow:ImageThumb::ThumbWidth*4
                fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
            
            compressor.encode(&tmpStorage[0], dst);
        }
        
        return ccm;
    }
    
    ImageCache::ImageProvider _imageProvider() {
        return [&] (uint64_t addr) -> ImagePtr {
            return _imageForAddr(addr);
        };
    }
    
    ImagePtr _imageForAddr(uint64_t addr) {
        abort();
//        auto data = std::make_unique<uint8_t[]>(Img::Full::ImageLen);
//        _sdRead(_Priority::Low, (_SDBlock)addr, Img::Full::ImageLen, data.get());
//        
//        if (_ImageChecksumValid(data.get(), Img::Size::Full)) {
////            printf("Checksum valid (size: full)\n");
//        } else {
//            printf("Checksum INVALID (size: full)\n");
////            abort();
//        }
//        
//        const Img::Header& header = *(const Img::Header*)data.get();
//        ImagePtr image = std::make_shared<Image>(Image{
//            .width      = header.imageWidth,
//            .height     = header.imageHeight,
//            .cfaDesc    = _CFADesc,
//            .data       = std::move(data),
//            .off        = sizeof(header),
//        });
//        return image;
    }
    
    void _notifyObservers() {
        auto prev = _observers.before_begin();
        for (auto it=_observers.begin(); it!=_observers.end();) {
            // Notify the observer; it returns whether it's still valid
            // If it's not valid (it returned false), remove it from the list
            if (!(*it)()) {
                it = _observers.erase_after(prev);
            } else {
                prev = it;
                it++;
            }
        }
    }
    
    // MARK: - Sync
    
    void _sync_thread() {
        try {
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(_mspState);
            const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
            const Img::Id deviceImgIdEnd = imgRingBuf.buf.idEnd;
            
            {
                // Modify the image library to reflect the images that have been added and removed
                // since the last time we sync'd
                uint32_t addCount = 0;
                {
                    auto lock = std::unique_lock(_imageLibrary);
                    
                    // Remove images from beginning of library: lib has, device doesn't
                    {
                        const auto removeBegin = _imageLibrary.begin();
                        
                        // Find the first image >= `deviceImgIdBegin`
                        const auto removeEnd = std::lower_bound(_imageLibrary.begin(), _imageLibrary.end(), 0,
                            [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                                return sample->info.id < deviceImgIdBegin;
                            });
                        
                        printf("Removing %ju images\n", (uintmax_t)std::distance(removeBegin, removeEnd));
                        _imageLibrary.remove(removeBegin, removeEnd);
                    }
                    
                    // Add images to end of library: device has, lib doesn't
                    {
                        const Img::Id libImgIdEnd = _imageLibrary.deviceImgIdEnd();
                        if (libImgIdEnd > deviceImgIdEnd) {
                            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                                (uintmax_t)libImgIdEnd,
                                (uintmax_t)deviceImgIdEnd
                            );
                        }
                        
                        addCount = 2048;//(uint32_t)(deviceImgIdEnd - std::max(deviceImgIdBegin, libImgIdEnd));
                        printf("Adding %ju images\n", (uintmax_t)addCount);
                        _imageLibrary.reserve(addCount);
                    }
                }
                
                // Populate .addr for each new ImageRecord that we added, and collect
                // the set of oldestRecs / newestRecs, which we'll then load from the
                // SD card
                std::set<ImageRecordPtr> oldestRecs;
                std::set<ImageRecordPtr> newestRecs;
                {
                    struct Range {
                        uint32_t idx  = 0;
                        uint32_t len = 0;
                    };
                    
                    Range newest;
                    newest.idx = imgRingBuf.buf.widx - std::min((uint32_t)imgRingBuf.buf.widx, addCount);
                    newest.len = imgRingBuf.buf.widx - newest.idx;
                    
                    Range oldest;
                    oldest.len = addCount - newest.len;
                    oldest.idx = _mspState.sd.imgCap - oldest.len;
                    
                    auto it = _imageLibrary.reservedBegin();
                    for (uint32_t i=0; i<oldest.len; i++) {
                        const uint32_t idx = oldest.idx+i;
                        ImageRecordPtr rec = *it;
                        rec->addr.full = _AddrFull(_mspState, idx);
                        rec->addr.thumb = _AddrThumb(_mspState, idx);
                        oldestRecs.insert(rec);
                        it++;
                    }
                    
                    for (uint32_t i=0; i<newest.len; i++) {
                        const uint32_t idx = newest.idx+i;
                        ImageRecordPtr rec = *it;
                        rec->addr.full = _AddrFull(_mspState, idx);
                        rec->addr.thumb = _AddrThumb(_mspState, idx);
                        newestRecs.insert(rec);
                        it++;
                    }
                }
                
                // Load the images from the SD card
                {
                    _loadImages(_sync.loadImages, _Priority::Low, true, oldestRecs);
                    _loadImages(_sync.loadImages, _Priority::Low, true, newestRecs);
                }
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    void _loadImages(_LoadImagesState& state, _Priority priority, bool initial, const std::set<ImageRecordPtr>& recs) {
        const size_t imageCount = recs.size();
        
        // Enqueue SD reads
        {
            auto lock = _sdRead.signal.lock();
            _SDReadWorkQueue& queue = _sdRead.queues[(size_t)priority];
            
            for (const ImageRecordPtr& rec : recs) {
                _SDReadWork work = {
                    .block = rec->addr.thumb,
                    .len = Img::Thumb::ImageLen,
                    .rec = rec,
                    .status = &state.read,
                };
                
                queue.set.insert(std::move(work));
            }
        }
        
        // Enqueue rendering as SD reads complete
        std::thread renderThread([&] {
            size_t doneCount = 0;
            while (doneCount < imageCount) {
                std::vector<_SDReadWork> done;
                {
                    auto lock = state.read.signal.wait([&] { return !state.read.done.empty(); });
                    done = std::move(state.read.done);
                }
                
                {
                    auto lock = _thumbRender.signal.lock();
                    for (_SDReadWork& read : done) {
                        _thumbRender.work.push(_ThumbRenderWork{
                            .rec = std::move(read.rec),
                            .initial = initial,
                            .data = std::move(read.data),
                        });
                    }
                }
                
                _thumbRender.signal.signalAll();
                doneCount += done.size();
            }
        });
        
        // Post notifications (in chunks of `NotifyThreshold`) as rendering completes
        {
            constexpr size_t NotifyThreshold = 32;
            size_t doneCount = 0;
            std::set<ImageRecordPtr> done;
            while (doneCount < imageCount) {
                {
                    auto lock = state.render.signal.wait([&] { return !state.render.done.empty(); });
                    
                    for (_ThumbRenderWork& work : state.render.done) {
                        done.insert(std::move(work.rec));
                    }
                    
                    doneCount += state.render.done.size();
                    state.render.done.clear();
                }
                
                if (done.size() >= NotifyThreshold) {
                    _imageLibrary.notifyChange(done);
                    done.clear();
                }
            }
            
            // Post notifications for remaining records
            if (!done.empty()) _imageLibrary.notifyChange(done);
        }
        
        // Wait for threads to return
        renderThread.join();
    }
    
    // MARK: - Thumb Render
    
    void _thumbRender_thread() {
        using namespace MDCTools;
        
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
        _ThumbCompressor compressor;
        std::unique_ptr<_ThumbTmpStorage> thumbTmpStorage = std::make_unique<_ThumbTmpStorage>();
        
        for (;;) @autoreleasepool {
            _ThumbRenderWork work;
            {
                auto lock = _thumbRender.signal.wait([&] { return !_thumbRender.work.empty(); });
                work = std::move(_thumbRender.work.front());
                _thumbRender.work.pop();
            }
            
            ImageRecord& rec = *work.rec;
            std::unique_ptr<uint8_t[]> data = std::move(work.data);
            
            // Validate checksum
            if (_ImageChecksumValid(data.get(), Img::Size::Thumb)) {
//                printf("Checksum valid (size: full)\n");
            } else {
                printf("Checksum INVALID (size: full)\n");
//                abort();
            }
            
            if (work.initial) {
                // Populate .info
                {
                    const Img::Header& imgHeader = *(const Img::Header*)data.get();
                    
                    rec.info.id             = imgHeader.id;
                    
                    rec.info.timestamp      = imgHeader.timestamp;
                    
                    rec.info.imageWidth     = imgHeader.imageWidth;
                    rec.info.imageHeight    = imgHeader.imageHeight;
                    
                    rec.info.coarseIntTime  = imgHeader.coarseIntTime;
                    rec.info.analogGain     = imgHeader.analogGain;
                }
                
                // Populate .options
                {
                    rec.options = {};
                }
            }
            
            // Render the thumbnail into rec.thumb
            {
                const void* thumbSrc = data.get()+Img::PixelsOffset;
                void* thumbDst = rec.thumb.data;
                
                // estimateIlluminant: only perform illuminant estimation upon our initial import
                const bool estimateIlluminant = work.initial;
                const CCM ccm = _ThumbRender(renderer, compressor, *thumbTmpStorage, rec.options,
                    estimateIlluminant, thumbSrc, thumbDst);
                
                if (estimateIlluminant) {
                    // Populate .info.illumEst
                    ccm.illum.m.get(rec.info.illumEst);
                    // Populate .options.whiteBalance
                    ImageWhiteBalanceSet(rec.options.whiteBalance, true, 0, ccm);
                }
            }
        }
    }
    
    // MARK: - SD Read
    
    static constexpr _SDBlock _SDRead_BlockEnd(_SDBlock block, size_t len) {
        const _SDBlock blockCount = Toastbox::DivCeil((_SDBlock)len, (_SDBlock)SD::BlockLen);
        // Verify that block+blockLen doesn't overflow _SDBlock
        assert(std::numeric_limits<_SDBlock>::max()-block >= blockCount);
        return block + blockCount;
    }
    
    static _SDCoalescedWork _SDRead_CoalesceWork(_SDReadWorkQueue& queue) {
        assert(!queue.set.empty());
        
        // CoalesceBudget: coalesce adjacent blocks until this budget is exceeded
        static constexpr _SDBlock CoalesceBudget = 8192;
        const _SDReadStatus& status = *queue.set.begin()->status;
        _SDCoalescedWork coalesced = {
            .blockBegin = queue.set.begin()->block,
            .blockEnd   = _SDRead_BlockEnd(queue.set.begin()->block, queue.set.begin()->len),
        };
        _SDBlock budget = CoalesceBudget;
        for (auto it=queue.set.begin(); it!=queue.set.end();) {
            const auto itPrev = it;
            const _SDReadWork& work = *it;
            const _SDBlock workBlockBegin = work.block;
            const _SDBlock workBlockEnd = _SDRead_BlockEnd(workBlockBegin, work.len);
            
            // The queue.set ordering guarantees that the blockBegins are in ascending order.
            // Check that assumption.
            assert(coalesced.blockBegin <= work.block);
            
            const _SDBlock cost = (workBlockEnd>coalesced.blockEnd ? workBlockEnd-coalesced.blockEnd : 0);
            // Stop coalescing work once the cost exceeds our budget
            if (cost > budget) break;
            // Stop coalescing work if the .status member doesn't match
            // (Ie, we don't coalesce across .status boundaries)
            if (work.status != &status) break;
            
            it++; // Increment before we extract, because extract invalidates iterator
            coalesced.blockEnd = std::max(coalesced.blockEnd, workBlockEnd);
            coalesced.works.push_back(std::move(queue.set.extract(itPrev).value()));
            budget -= cost;
        }
        return coalesced;
    }
    
//    void _sdRead(_Priority priority, _SDBlock block, size_t len, void* dst) {
//        abort();
////        const auto status = std::make_shared<_SDReadStatus>();
////        
////        // Enqueue the work
////        {
////            {
////                auto lock = std::unique_lock(_sdRead.lock);
////                _SDReadWorkQueue& queue = _sdRead.queues[priority];
////                queue.set.emplace(_SDReadWork{
////                    .block = block,
////                    .len = len,
////                    .dst = dst,
////                    .status = status,
////                });
////            }
////            _sdRead.signal.notify_one();
////        }
////        
////        // Wait for the work to be completed
////        {
////            auto lock = std::unique_lock(_sdReadConsume.lock);
////            _sdReadConsume.signal.wait(lock, [&] { return !status->done.empty(); });
////        }
//    }
    
    // _sdRead.lock must be held!
    _SDReadWorkQueue* _sdRead_nextWorkQueue() {
        for (_SDReadWorkQueue& x : _sdRead.queues) {
            if (!x.set.empty()) return &x;
        }
        return nullptr;
    }
    
    void _sdRead_handleWork(_SDCoalescedWork& coalesced) {
        assert(!coalesced.works.empty());
        _SDReadStatus& status = *coalesced.works.front().status;
        
        // Read the data from the device
        const size_t len = (size_t)SD::BlockLen * (coalesced.blockEnd-coalesced.blockBegin);
        std::unique_ptr<uint8_t[]> data = std::make_unique<uint8_t[]>(len);
        {
            auto lock = std::unique_lock(_dev);
            _dev.reset();
            assert(std::numeric_limits<SD::Block>::max() >= coalesced.blockBegin);
            _dev.sdRead((SD::Block)coalesced.blockBegin);
            _dev.readout(data.get(), len);
        }
        
        // Copy the data into each _SDReadWork
        {
            #warning TODO: use a preallocated storage associated with the _SDReadStatus, instead of making lots of individual allocations
            // Copy data into each individual _SDReadWork
            for (_SDReadWork& work : coalesced.works) {
                const uint8_t* d = data.get() + (size_t)(work.block-coalesced.blockBegin)*SD::BlockLen;
                work.data = std::make_unique<uint8_t[]>(work.len);
                memcpy(work.data.get(), d, work.len);
            }
        }
        
        // Move each _SDReadWork into status.work and send signal
        {
            {
                auto lock = status.signal.lock();
                for (_SDReadWork& work : coalesced.works) {
                    status.done.push_back(std::move(work));
                }
            }
            status.signal.signalOne();
        }
    }
    
    void _sdRead_thread() {
        for (;;) {
            _SDCoalescedWork coalesced;
            {
                // Wait for work, or to be signalled to stop
                _SDReadWorkQueue* queue = nullptr;
                
                auto lock = _sdRead.signal.wait([&] { return _sdRead_nextWorkQueue(); });
                coalesced = _SDRead_CoalesceWork(*queue);
            }
            _sdRead_handleWork(coalesced);
        }
    }
    
    // MARK: - Update Thumbs
    void _thumbUpdate_thread() {
        for (;;) {
            std::set<ImageRecordPtr> work;
            {
                auto lock = _thumbUpdate.signal.wait([&] { return !_thumbUpdate.work.empty(); });
                work = std::move(_thumbUpdate.work);
                // Update .thumb.render asap (ie before we've actually rendered) so that the
                // visibleThumbs() function on the main thread stops enqueuing work asap
                for (const ImageRecordPtr& rec : work) {
                    rec->options.thumb.render = false;
                }
            }
            
            _loadImages(_thumbUpdate.loadImages, _Priority::High, false, work);
        }
    }
    
    // MARK: - Members
    
    Device _dev;
    const _Path _dir;
    ImageLibrary _imageLibrary;
    ImageCache _imageCache;
    MSP::State _mspState;
    STM::SDCardInfo _sdCardInfo;
    
    std::string _name;
    std::forward_list<Observer> _observers;
    
    struct {
        _Signal signal; // Protects this struct
        std::thread thread;
        _LoadImagesState loadImages;
    } _sync;
    
    struct {
        _Signal signal; // Protects this struct
        std::thread thread;
        bool stop = false;
        _SDReadWorkQueue queues[(size_t)_Priority::Count];
    } _sdRead;
    
    struct {
        _Signal signal; // Protects this struct
        std::vector<std::thread> threads;
        bool stop = false;
        std::queue<_ThumbRenderWork> work;
    } _thumbRender;
    
    struct {
        _Signal signal; // Protects this struct
        std::thread thread;
        bool stop = false;
        std::set<ImageRecordPtr> work;
        _LoadImagesState loadImages;
    } _thumbUpdate;
    
    std::set<ImageRecordPtr> _thumbUpdateWorkPrev;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

} // namespace MDCStudio

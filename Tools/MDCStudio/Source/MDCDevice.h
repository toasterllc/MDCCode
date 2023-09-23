#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <set>
#import <array>
#import <chrono>
#import "Toastbox/Atomic.h"
#import "Toastbox/Mmap.h"
#import "Toastbox/Queue.h"
#import "Toastbox/Math.h"
#import "Toastbox/Signal.h"
#import "Toastbox/LRU.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/Clock.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Tools/Shared/ImagePipeline/EstimateIlluminant.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/BC7Encoder.h"
#import "ImageLibrary.h"
#import "ImageSource.h"
#import "BufferPool.h"
#import "Cache.h"

namespace MDCStudio {

class MDCDevice : public ImageSource {
private:
    using _ThumbCompressor = BC7Encoder<ImageThumb::ThumbWidth, ImageThumb::ThumbHeight>;
    
public:
    using Observer = std::function<bool()>;
    
    MDCDevice(MDCUSBDevice&& dev) :
    _device(decltype(_device){ .device = std::move(dev) }),
    _dir(_DirForSerial(_device.device.serial())),
    _imageLibrary(_dir / "ImageLibrary") {
        printf("MDCDevice()\n");
        
        // Give device a default name
        char name[256];
        snprintf(name, sizeof(name), "MDC Device %s", _device.device.serial().c_str());
        _name = std::string(name);
        
        // Read state from disk
        try {
            _SerializedState state = _SerializedStateRead(_dir);
            _name = std::string(state.name);
        } catch (const std::exception& e) {}
        
        // Perform device IO
        bool loadAndSync = false;
        {
            auto lock = _deviceLock();
            
            // Update our _mspState from the device
            _mspState = _device.device.mspStateRead();
            
            // Enter host mode
            _device.device.hostModeSet(true);
            
            // Adjust the device's time to correct it for crystal innaccuracy
            std::cout << "Adjusting device time:\n";
            _device.device.mspTimeAdjust();
            
            // Load ICE40 with our app
            _ICEConfigure(_device.device);
            
            try {
                // Init SD card
                _sdCardInfo = _device.device.sdInit();
                
                if (!_mspState.sd.valid) {
                    // _mspState.sd isn't valid, so there's no syncing that can be done
                    throw Toastbox::RuntimeError("!_mspState.sd.valid");
                }
                
                // Current SD card id doesn't match MSP's card id
                // Don't sync photos because we don't know what we're actually reading from the device
                if (memcmp(&_sdCardInfo.cardId, &_mspState.sd.cardId, sizeof(_mspState.sd.cardId))) {
                    throw Toastbox::RuntimeError("_sdCardInfo.cardId != _mspState.sd.cardId");
                }
                
                loadAndSync = true;
            
            } catch (const std::exception& e) {
                printf("[MDCDevice()] Can't load/sync library: %s\n", e.what());
            }
        }
        
        // Load the library
        if (loadAndSync) {
            auto lock = std::unique_lock(_imageLibrary);
            _imageLibrary.read();
        }
        
        // Start threads
        {
            if (loadAndSync) _sync.thread = std::thread([&] { _sync_thread(); });
            
            _sdRead.thread = std::thread([&] { _sdRead_thread(); });
            
            for (int i=0; i<_ThreadCount(); i++) {
                _thumbRender.threads.emplace_back([&] { _thumbRender_thread(); });
            }
            
            _batteryLevel.thread = std::thread([&] { _batteryLevel_thread(); });
        }
    }
    
    ~MDCDevice() {
        _sdRead.signal.stop();
        _thumbRender.signal.stop();
        _batteryLevel.signal.stop();
        
        // Wait for threads to stop
        if (_sync.thread.joinable()) _sync.thread.join();
        _sdRead.thread.join();
        for (std::thread& t : _thumbRender.threads) t.join();
        _batteryLevel.thread.join();
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
    
    float batteryLevel() {
        auto lock = _batteryLevel.signal.lock();
        return _batteryLevel.level;
    }
    
    const Toastbox::SendRight& service() const {
        return _device.device.dev().service();
    }
    
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
    
    const MSP::Settings& settings() {
        return _mspState.settings;
    }
    
    void settings(const MSP::Settings& x) {
        _mspState.settings = x;
        {
            auto lock = _deviceLock();
            _device.device.mspStateWrite(_mspState);
        }
    }
    
    // MARK: - ImageSource
    
    ImageLibrary& imageLibrary() override { return _imageLibrary; }
    
    void renderThumbs(Priority priority, std::set<ImageRecordPtr> recs) override {
        _loadImages(priority, false, recs);
    }
    
    Image getCachedImage(const ImageRecordPtr& rec) override {
        // If the image is in our cache, return it
        _ImageBuffer buf = _imageCache.get(_SDRegionForImage(rec));
        if (!buf) return {};
        return _imageCreate(buf);
    }
    
    Image loadImage(Priority priority, const ImageRecordPtr& rec) override {
        return _loadImage(priority, rec);
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
    
    struct _SDRegion {
        _SDBlock begin = 0;
        _SDBlock end   = 0;
        
        bool operator<(const _SDRegion& x) const {
            if (begin != x.begin) return begin < x.begin;
            if (end != x.end) return end < x.end;
            return false;
        }
        
        bool operator==(const _SDRegion& x) const {
            if (begin != x.begin) return false;
            if (end != x.end) return false;
            return true;
        }
        
        bool operator!=(const _SDRegion& x) const { return !(*this == x); }
    };
    
    struct _LoadState {
        Toastbox::Signal signal; // Protects this struct
        std::set<ImageRecordPtr> notify;
        Toastbox::Atomic<size_t> underway = 0;
    };
    
    using _LoadStatePool = Cache<int,_LoadState,4>;
    
    using __ThumbBuffer = uint8_t[ImgSD::Thumb::ImagePaddedLen];
    using _ThumbCache = Cache<_SDRegion,__ThumbBuffer,512,(uint8_t)Priority::Last>;
    using _ThumbBuffer = _ThumbCache::Entry;
    using _ThumbBufferReserved = _ThumbCache::Reserved;
    
    using __ImageBuffer = uint8_t[ImgSD::Full::ImagePaddedLen];
    using _ImageCache = Cache<_SDRegion,__ImageBuffer,8,(uint8_t)Priority::Last>;
    using _ImageBuffer = _ImageCache::Entry;
    using _ImageBufferReserved = _ImageCache::Reserved;
    
    struct _BufferReserved : std::variant<_ThumbBufferReserved,_ImageBufferReserved> {
        size_t cap() const {
            if (auto x=thumb())      return sizeof(*(x->entry()));
            else if (auto x =image()) return sizeof(*(x->entry()));
            else                     abort();
        }
        
        void* storage() const {
            if (auto x=thumb())      return &*(x->entry());
            else if (auto x=image()) return &*(x->entry());
            else                     abort();
        }
        
        bool operator<(const _BufferReserved& b) const {
            if (auto x=thumb())      return x->entry() < b.thumb()->entry();
            else if (auto x=image()) return x->entry() < b.image()->entry();
            else                     abort();
        }
        
        bool operator==(const _BufferReserved& b) const {
            if (auto x=thumb())      return x->entry() == b.thumb()->entry();
            else if (auto x=image()) return x->entry() == b.image()->entry();
            else                     abort();
        }
        
        bool operator!=(const _BufferReserved& b) const {
            if (auto x=thumb())      return x->entry() != b.thumb()->entry();
            else if (auto x=image()) return x->entry() != b.image()->entry();
            else                     abort();
        }
        
        const _ThumbBufferReserved* thumb() const { return std::get_if<_ThumbBufferReserved>(this); }
        const _ImageBufferReserved* image() const { return std::get_if<_ImageBufferReserved>(this); }
        
        _ThumbBufferReserved* thumb() { return std::get_if<_ThumbBufferReserved>(this); }
        _ImageBufferReserved* image() { return std::get_if<_ImageBufferReserved>(this); }
    };
    
    struct _SDReadWork {
        _SDRegion region;
        _BufferReserved buf;
        ImageRecordPtr rec;
        std::function<void(_SDReadWork&&)> callback;
        
        bool operator<(const _SDReadWork& x) const {
            if (region != x.region) return region < x.region;
            if (buf != x.buf) return buf < x.buf;
            return false;
        }
        
        bool operator==(const _SDReadWork& x) const {
            if (region != x.region) return false;
            if (buf != x.buf) return false;
            return true;
        }
        
        bool operator!=(const _SDReadWork& x) const { return !(*this == x); }
    };
    
    struct _RenderWork {
        bool initial = false;
        bool validateChecksum = false;
        ImageRecordPtr rec;
        _ThumbBuffer buf;
        std::function<void()> callback;
    };
    
    using _SDReadWorkQueue = std::queue<_SDReadWork>;
    using _RenderWorkQueue = std::queue<_RenderWork>;
//    using _ImageLoadQueue = std::queue<_RenderWork>;
    
    static int _ThreadCount() {
        static int ThreadCount = std::max(1, (int)std::thread::hardware_concurrency());
        return ThreadCount;
    }
    
    static constexpr _SDBlock _SDBlockEnd(_SDBlock block, size_t len) {
        const _SDBlock blockCount = Toastbox::DivCeil((_SDBlock)len, (_SDBlock)SD::BlockLen);
        // Verify that block+blockLen doesn't overflow _SDBlock
        assert(std::numeric_limits<_SDBlock>::max()-block >= blockCount);
        return block + blockCount;
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
            
            ccm.illum = (estimateIlluminant ? EstimateIlluminant::Run(renderer, _CFADesc, rawTxt) : ColorRaw(opts.whiteBalance.illum));
            ccm.matrix = (estimateIlluminant ? ColorMatrixForIlluminant(ccm.illum).matrix : ColorMatrix((double*)opts.whiteBalance.colorMatrix));
            
            const Pipeline::Options popts = {
                .cfaDesc                = _CFADesc,
                
                .illum                  = ccm.illum,
                .colorMatrix            = ccm.matrix,
                
                .defringe               = { .en = false, },
                .reconstructHighlights  = { .en = false, },
                .debayerLMMSE           = { .applyGamma = true, },
                
                .exposure               = (float)opts.exposure,
                .saturation             = (float)opts.saturation,
                .brightness             = (float)opts.brightness,
                .contrast               = (float)opts.contrast,
                
                .localContrast = {
                    .en                 = (opts.localContrast.amount!=0 && opts.localContrast.radius!=0),
                    .amount             = (float)opts.localContrast.amount,
                    .radius             = (float)opts.localContrast.radius,
                },
            };
            
            Pipeline::Run(renderer, popts, rawTxt, thumbTxt);
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
    
    Image _imageCreate(const _ImageBuffer& buf) {
//        assert(len >= Img::Full::ImageLen);
        auto data = std::make_unique<uint8_t[]>(Img::Full::PixelLen);
        memcpy(data.get(), *buf+Img::PixelsOffset, Img::Full::ImageLen);
        return Image{
            .width = Img::Full::PixelWidth,
            .height = Img::Full::PixelHeight,
            .cfaDesc = _CFADesc,
            .data = std::move(data),
        };
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
    
    void _readCompleteCallback(_LoadState& state, _SDReadWork&& work, bool initial) {
        _ThumbBufferReserved& buf = *work.buf.thumb();
        
        // Enqueue rendering
        {
            {
                auto lock = _thumbRender.signal.lock();
                _renderEnqueue(lock, state, initial, true, work.rec, buf.entry());
            }
            _thumbRender.signal.signalAll();
        }
        
        // Insert buffers into our cache, if this isn't the initial load.
        // We don't want to populate the cache on the initial load because we want the Cache buffers to
        // be available for SDReads, but if we store them in the cache, we have fewer buffers available
        // for use during initial import, which slows down the importing process.
        if (!initial) _thumbCache.set(work.region, std::move(buf));
    }
    
    void _renderCompleteCallback(_LoadState& state, ImageRecordPtr rec) {
        constexpr size_t NotifyThreshold = 8;
        
        const size_t count = --state.underway;
        
        std::set<ImageRecordPtr> notify;
        {
            auto lock = state.signal.lock();
            state.notify.insert(rec);
            if (state.notify.size()>=NotifyThreshold || !count) {
                notify = std::move(state.notify);
            }
        }
        
        if (!notify.empty()) {
            auto lock = std::unique_lock(_imageLibrary);
            _imageLibrary.notify(ImageLibrary::Event::Type::ChangeThumbnail, notify);
        }
        
        if (!count) state.signal.signalOne();
    }
    
    void _renderEnqueue(std::unique_lock<std::mutex>& lock, _LoadState& state, bool initial, bool validateChecksum, ImageRecordPtr rec, _ThumbBuffer buf) {
        // Enqueue _RenderWork into _thumbRender.queue
        _thumbRender.queue.push(_RenderWork{
            .initial = initial,
            .validateChecksum = validateChecksum,
            .rec = rec,
            .buf = std::move(buf),
            .callback = [=, &state] { _renderCompleteCallback(state, rec); },
        });
    }
    
    static _SDRegion _SDRegionForThumb(const ImageRecordPtr& rec) {
        return {
            .begin = rec->info.addrThumb,
            .end = _SDBlockEnd(rec->info.addrThumb, ImgSD::Thumb::ImagePaddedLen),
        };
    }
    
    static _SDRegion _SDRegionForImage(const ImageRecordPtr& rec) {
        return {
            .begin = rec->info.addrFull,
            .end = _SDBlockEnd(rec->info.addrFull, ImgSD::Full::ImagePaddedLen),
        };
    }
    
    void _loadImages(Priority priority, bool initial, std::set<ImageRecordPtr> recs) {
        const size_t imageCount = recs.size();
        auto timeStart = std::chrono::steady_clock::now();
        
        auto state = _loadStates.pop().entry();
        assert(!state->underway);
        state->underway += recs.size();
        
        // Kick off rendering for all the recs that are in the cache
        {
            bool enqueued = false;
            {
                auto lock = _thumbRender.signal.lock();
                
                for (auto it=recs.begin(); it!=recs.end();) {
                    const ImageRecordPtr& rec = *it;
                    const _SDRegion region = _SDRegionForThumb(rec);
                    
                    // If the thumbnail is in our cache, kick off rendering
                    _ThumbBuffer buf = _thumbCache.get(region);
                    if (buf) {
                        _renderEnqueue(lock, *state, initial, false, rec, std::move(buf));
                        enqueued = true;
                        it = recs.erase(it);
                    
                    // Otherwise, on to the next one
                    } else {
                        it++;
                    }
                }
            }
            
            // Notify _thumbRender of more work
            if (enqueued) _thumbRender.signal.signalAll();
        }
        
        // The remaining recs aren't in our cache, so kick off SD reading + rendering
        for (auto it=recs.rbegin(); it!=recs.rend(); it++) {
            const ImageRecordPtr& rec = *it;
            const _SDRegion region = _SDRegionForThumb(rec);
            
            _ThumbBufferReserved buf = _thumbCache.pop((uint8_t)priority);
            
//                printf("[_loadImages] Got buffer %p for image id %ju\n", &*buf, (uintmax_t)rec->info.id);
            
            _SDReadWork work = {
                .region = region,
                .buf = std::move(buf),
                .rec = rec,
                .callback = [&] (_SDReadWork&& work) {
                    _readCompleteCallback(*state, std::move(work), initial);
                },
            };
            
//            printf("[_loadImages:p%ju] Enqueuing %ju ops\n", (uintmax_t)priority, (uintmax_t)work.ops.size());
            {
                auto lock = _sdRead.signal.lock();
                _SDReadWorkQueue& queue = _sdRead.queues[(size_t)priority];
                queue.push(std::move(work));
            }
            _sdRead.signal.signalOne();
        }
        
        // Wait until everything's done
        state->signal.wait([&] { return !state->underway; });
        
        // Print profile stats
        {
            using namespace std::chrono;
            const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
            printf("[_loadImages:p%ju] _loadImages() took %ju ms for %ju images (avg %f ms / img)\n",
                (uintmax_t)priority,
                (uintmax_t)duration.count(), (uintmax_t)imageCount, ((double)duration.count()/imageCount));
        }
    }
    
    Image _loadImage(Priority priority, const ImageRecordPtr& rec) {
        const _SDRegion region = _SDRegionForImage(rec);
        auto state = _loadStates.pop().entry();
        _ImageBufferReserved buf = _imageCache.pop((uint8_t)priority);
        
        _SDReadWork work = {
            .region = region,
            .buf = std::move(buf),
            .rec = rec,
            .callback = [&] (_SDReadWork&& work) {
                buf = std::move(*work.buf.image());
                state->signal.signalOne();
            },
        };
        
        {
            auto lock = _sdRead.signal.lock();
            _SDReadWorkQueue& queue = _sdRead.queues[(size_t)priority];
            queue.push(std::move(work));
        }
        _sdRead.signal.signalOne();
        
        // Wait until the buffer is returned to us by our SDRead callback
        state->signal.wait([&] { return buf.entry(); });
        Image image = _imageCreate(buf.entry());
        _imageCache.set(region, std::move(buf));
        return image;
    }
    
    // MARK: - Sync
    
    void _sync_thread() {
        try {
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(_mspState);
            const Img::Id deviceImgIdBegin = imgRingBuf.buf.id - std::min(imgRingBuf.buf.id, (Img::Id)_mspState.sd.imgCap);
            const Img::Id deviceImgIdEnd = imgRingBuf.buf.id;
            
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
                        
                        printf("[_sync_thread] Removing %ju stale images\n", (uintmax_t)(removeEnd-removeBegin));
                        _imageLibrary.remove(removeBegin, removeEnd);
                    }
                    
                    // Calculate how many images to add to the end of the library: device has, lib doesn't
                    {
                        const Img::Id libImgIdEnd = (!_imageLibrary.empty() ? _imageLibrary.back()->info.id+1 : 0);
                        if (libImgIdEnd > deviceImgIdEnd) {
                            #warning TODO: how do we properly handle this situation?
                            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                                (uintmax_t)libImgIdEnd,
                                (uintmax_t)deviceImgIdEnd
                            );
                        }
                        
                        addCount = (uint32_t)(deviceImgIdEnd - std::max(deviceImgIdBegin, libImgIdEnd));
                        addCount = 10000;
                        printf("[_sync_thread] Adding %ju images\n", (uintmax_t)addCount);
                        _imageLibrary.add(addCount);
                    }
                    
                    // Populate .id / .addr for the ImageRecords that we're adding
                    {
                        auto it = _imageLibrary.end();
                        Img::Id id = deviceImgIdEnd;
                        uint32_t idx = imgRingBuf.buf.idx;
                        while (addCount) {
                            it--;
                            id--;
                            idx = (idx ? idx-1 : _mspState.sd.imgCap-1);
                            addCount--;
                            
                            ImageRecordPtr rec = *it;
                            rec->info.id = id;
                            rec->info.addrFull = MSP::SDBlockFull(_mspState.sd.baseFull, idx);
                            rec->info.addrThumb = MSP::SDBlockThumb(_mspState.sd.baseThumb, idx);
                            
                            rec->status.loadCount = 0;
                        }
                    }
                    
                    // Write library now that we've added our new images and populated their .id / .addr
                    _imageLibrary.write();
                }
                
                // Load all unloaded images from the SD card
                // Note that this will also load unloaded images from a previous session, since we may have
                // been killed or crashed before we finished loading all images.
                {
                    std::set<ImageRecordPtr> recs;
                    for (const ImageLibrary::RecordRef& rec : _imageLibrary) {
                        if (!rec->status.loadCount) {
                            recs.insert(rec);
                        }
                    }
                    
                    printf("[_sync_thread] Loading %ju images\n", (uintmax_t)recs.size());
                    _loadImages(Priority::Low, true, recs);
                }
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_sync_thread] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[_sync_thread] Error: %s\n", e.what());
        }
    }
    
    // MARK: - SD Read
    
    // _sdRead.lock must be held!
    _SDReadWorkQueue* _sdRead_nextQueue() {
        for (_SDReadWorkQueue& x : _sdRead.queues) {
            if (!x.empty()) return &x;
        }
        printf("[_sdRead_nextQueue] Stalled\n");
        return nullptr;
    }
    
    void _sdRead_handleWork(_SDReadWork&& work) {
        const _SDBlock blockBegin = work.region.begin;
        const size_t len = (size_t)SD::BlockLen * (size_t)(work.region.end-work.region.begin);
        // Verify that the length of data that we're reading will fit in our buffer
        assert(len <= work.buf.cap());
        
        {
//            printf("[__sdRead_handleWork] reading [%ju,%ju) (%.1f MB)\n", (uintmax_t)blockBegin, (uintmax_t)blockEnd, (float)len/(1024*1024));
            _deviceSDRead(blockBegin, len, work.buf.storage());
        }
        
        work.callback(std::move(work));
    }
    
    void _sdRead_thread() {
        try {
            for (;;) {
                _SDReadWork work;
                {
                    // Wait for work
                    _SDReadWorkQueue* queue = nullptr;
                    auto lock = _sdRead.signal.wait([&] { return (queue = _sdRead_nextQueue()); });
                    work = std::move(queue->front());
                    queue->pop();
                }
                _sdRead_handleWork(std::move(work));
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_sdRead_thread] Stopping\n");
        }
    }
    
    // MARK: - Thumb Render
    
    void _thumbRender_thread() {
        using namespace MDCTools;
        
        try {
            id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
            Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
            _ThumbCompressor compressor;
            std::unique_ptr<_ThumbTmpStorage> thumbTmpStorage = std::make_unique<_ThumbTmpStorage>();
            
            for (;;) @autoreleasepool {
                _RenderWork work;
                {
                    auto lock = _thumbRender.signal.wait([&] { return !_thumbRender.queue.empty(); });
                    work = _thumbRender.queue.front();
                    _thumbRender.queue.pop();
                }
                
                ImageRecord& rec = *work.rec;
                
                if (work.validateChecksum) {
                    if (_ImageChecksumValid(*work.buf, Img::Size::Thumb)) {
//                        printf("Checksum valid (thumb)\n");
                    } else {
                        printf("Checksum INVALID (thumb)\n");
//                        abort();
                    }
                }
                
                if (work.initial) {
                    // Populate .info
                    {
                        const Img::Header& imgHeader = *(const Img::Header*)(*work.buf);
                        
                        if (imgHeader.id != rec.info.id) {
                            #warning TODO: how do we properly handle this?
//                            printf("[_thumbRender_thread] Invalid image id (got: %ju, expected: %ju)\n", (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
//                            throw Toastbox::RuntimeError("invalid image id (got: %ju, expected: %ju)",
//                                (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
                        }
                        
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
                    const void* thumbSrc = (*work.buf)+Img::PixelsOffset;
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
                
                // Atomically increment loadCount, ensuring that we never write a value of 0, since 0 is a
                // special value that loadCount is initialized to that indicates that we've never rendered.
                // We're using an atomic store here, so there's an implicit seq_cst memory barrier that ensures
                // that the thumbnail update is complete before the loadCount change can be observed.
                {
                    // Verify that we can safely cast our loadCount field to a std::atomic<uint32_t>
                    // by checking loadCount's type and alignment.
                    using Atomic32 = std::atomic<uint32_t>;
                    static_assert(std::is_same_v<uint32_t, decltype(rec.status.loadCount)>);
                    static_assert(!(offsetof(ImageRecord, status.loadCount) % alignof(Atomic32)));
                    Atomic32& loadCount = reinterpret_cast<Atomic32&>(rec.status.loadCount);
                    uint32_t loadCountCopy = loadCount;
                    loadCountCopy++;
                    if (!loadCountCopy) loadCountCopy++; // Skip 0
                    loadCount = loadCountCopy;
                }
                
                work.callback();
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_thumbRender_thread] Stopping\n");
        }
    }
    
    std::unique_lock<std::mutex> _deviceLock() {
        auto lock = std::unique_lock(_device.lock);
        if (_device.sdReadEnd) {
            // Readout is in progress; stop it by resetting the device
            _device.device.reset();
            // Clear sdReadEnd to indicate that readout is no longer underway
            _device.sdReadEnd = std::nullopt;
        }
        return lock;
    }
    
    void _deviceSDRead(_SDBlock block, size_t len, void* dst) {
        auto lock = std::unique_lock(_device.lock);
        if (!_device.sdReadEnd || *_device.sdReadEnd!=block) {
            printf("[_deviceSDRead] Starting readout at %ju\n", (uintmax_t)block);
            // If readout was in progress at a different address, reset the device
            if (_device.sdReadEnd) {
                _device.device.reset();
            }
            
            // Verify that blockBegin can be safely cast to SD::Block
            assert(std::numeric_limits<SD::Block>::max() >= block);
            _device.device.sdRead((SD::Block)block);
            _device.device.readout(dst, len);
        
        } else {
//            printf("[_deviceSDRead] Continuing readout at %ju\n", (uintmax_t)block);
            _device.device.readout(dst, len);
        }
        _device.sdReadEnd = _SDBlockEnd(block, len);
    }
    
    // MARK: - Battery Level
    
    void _batteryLevel_thread() {
        constexpr auto UpdateInterval = std::chrono::seconds(2);
        
        try {
            for (;;) {
                auto lock = _batteryLevel.signal.lock();
                
                // Update battery level
                {
                    auto lock = _deviceLock();
                    
                    const STM::BatteryStatus batteryStatus = _device.device.batteryStatusGet();
                    
                    if (batteryStatus.chargeStatus == MSP::ChargeStatus::Complete) {
                        _batteryLevel.level = 1;
                    
                    } else if (batteryStatus.chargeStatus == MSP::ChargeStatus::Underway) {
                        _batteryLevel.level = std::min(.999f, (float)MSP::BatteryLevelLinearize(batteryStatus.level) / MSP::BatteryLevelMax);
                    
                    } else {
                        _batteryLevel.level = 0;
                    }
                    
                    printf("[_batteryLevel_thread] Updated battery level: %.3f\n", _batteryLevel.level);
                }
                
                _notifyObservers();
                
                // Sleep for 30 seconds
                _batteryLevel.signal.wait_for(lock, UpdateInterval, [] { return false; });
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_batteryLevel_thread] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[_batteryLevel_thread] Error: %s\n", e.what());
        }
    }
    
    // MARK: - Members
    
    struct {
        std::mutex lock; // Protects this struct
        MDCUSBDevice device;
        std::optional<_SDBlock> sdReadEnd;
    } _device;
    
    const _Path _dir;
    ImageLibrary _imageLibrary;
//    ImageCache _imageCache;
    MSP::State _mspState;
    STM::SDCardInfo _sdCardInfo;
    
    std::string _name;
    std::forward_list<Observer> _observers;
    Toastbox::Signal _imageForAddrSignal;
    _ThumbCache _thumbCache;
    _ImageCache _imageCache;
    _LoadStatePool _loadStates;
    
    struct {
        std::thread thread;
    } _sync;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        _SDReadWorkQueue queues[(size_t)Priority::Last+1];
    } _sdRead;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::vector<std::thread> threads;
        _RenderWorkQueue queue;
    } _thumbRender;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        float level = 0;
    } _batteryLevel;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

} // namespace MDCStudio

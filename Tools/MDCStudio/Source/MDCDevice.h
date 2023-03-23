#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <set>
#import <array>
#import <chrono>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Toastbox/Atomic.h"
#import "Toastbox/Mmap.h"
#import "Toastbox/Queue.h"
#import "Toastbox/Math.h"
#import "Toastbox/Signal.h"
#import "Toastbox/LRU.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/TimeConvert.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Tools/Shared/ImagePipeline/EstimateIlluminant.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/BC7Encoder.h"
#import "ImageLibrary.h"
#import "ImageCache.h"
#import "ImageSource.h"
#import "BufferPool.h"
#import "Cache.h"

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
            
            _thumbUpdate.thread = std::thread([&] { _thumbUpdate_thread(); });
            
            _sdRead.thread = std::thread([&] { _sdRead_thread(); });
            
            for (int i=0; i<_ThreadCount(); i++) {
                _thumbRender.threads.emplace_back([&] { _thumbRender_thread(); });
            }
        }
    }
    
    ~MDCDevice() {
        _thumbUpdate.signal.stop();
        _sdRead.signal.stop();
        _thumbRender.signal.stop();
        
        // Wait for threads to stop
        _sync.thread.join();
        _thumbUpdate.thread.join();
        _sdRead.thread.join();
        for (std::thread& t : _thumbRender.threads) t.join();
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
    
    void visibleThumbs(ImageRecordIterAny begin, ImageRecordIterAny end) override {
        bool enqueued = false;
        {
            auto lock = _thumbUpdate.signal.lock();
            _thumbUpdate.recs.clear();
            for (auto it=begin; it!=end; it++) {
                ImageRecordPtr rec = *it;
                if (rec->options.thumb.render) {
                    _thumbUpdate.recs.insert(rec);
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
    
    using _WorkCallback = std::function<void()>;
    
//    struct _SDReadOp;
//    struct _SDWork {
//        static constexpr size_t BufferThumbCount = 128;
//        uint8_t buffer[BufferThumbCount * ImgSD::Thumb::ImagePaddedLen];
//        
//        struct {
//            std::vector<_SDReadOp> ops; // Sorted by SD block
//            
//            struct {
//                _SDWorkCallback callback;
////                std::chrono::time_point<std::chrono::steady_clock> timeStart;
////                std::chrono::time_point<std::chrono::steady_clock> timeEnd;
//            } read;
//            
//            struct {
//                bool initial = false;
//                Toastbox::Atomic<size_t> idx = 0;
//                Toastbox::Atomic<size_t> idxDone = 0;
//                _SDWorkCallback callback;
//                std::chrono::time_point<std::chrono::steady_clock> timeStart;
////                std::chrono::time_point<std::chrono::steady_clock> timeEnd;
//            } render;
//        } state;
//    };
    
    struct _SDRegion {
        _SDBlock block = 0;
        size_t len     = 0;
        
        bool operator<(const _SDRegion& x) const {
            if (block != x.block) return block < x.block;
            if (len != x.len) return len < x.len;
            return false;
        }
        
        bool operator==(const _SDRegion& x) const {
            if (block != x.block) return false;
            if (len != x.len) return false;
            return true;
        }
        
        bool operator!=(const _SDRegion& x) const { return !(*this == x); }
    };
    
    using __ThumbBuffer = uint8_t[ImgSD::Thumb::ImagePaddedLen];
    using _ThumbCache = Cache<_SDRegion,__ThumbBuffer,512>;
    using _ThumbBuffer = _ThumbCache::Val;
    
    struct _SDReadOp {
        _SDRegion region;
        _ThumbBuffer buf;
        ImageRecordPtr rec;
        
        bool operator<(const _SDReadOp& x) const {
            if (region != x.region) return region < x.region;
            if (buf != x.buf) return buf < x.buf;
            return false;
        }
        
        bool operator==(const _SDReadOp& x) const {
            if (region != x.region) return false;
            if (buf != x.buf) return false;
            return true;
        }
        
        bool operator!=(const _SDReadOp& x) const { return !(*this == x); }
    };
    
    struct _SDReadWork {
        using Ops = std::set<_SDReadOp>;
        using OpsIter = std::set<_SDReadOp>::const_iterator;
        using Callback = std::function<void(const _SDReadWork&, OpsIter begin, OpsIter end)>;
        Ops ops;
        Callback callback;
    };
    
    struct _RenderWork {
        bool initial = false;
        ImageRecordPtr rec;
        _ThumbBuffer buf;
        _WorkCallback callback;
        
//        bool operator<(const _RenderWork& x) const {
//            if (initial != x.initial) return initial < x.initial;
//            if (rec != x.rec) return rec < x.rec;
//            if (buf != x.buf) return buf < x.buf;
//            return false;
//        }
//        
//        bool operator==(const _RenderWork& x) const {
//            if (initial != x.initial) return false;
//            if (rec != x.rec) return false;
//            if (buf != x.buf) return false;
//            return true;
//        }
//        
//        bool operator!=(const _RenderWork& x) const { return !(*this == x); }
    };
    
//    struct _SDReadOp {
//        _SDRegion region;
//        ImageRecordPtr rec;
//        const uint8_t* data = nullptr;
//        bool operator<(const _SDReadOp& x) const { return region < x.region; }
//        bool operator==(const _SDReadOp& x) const { return region == x.region; }
//    };
    
    using _SDReadWorkQueue = std::queue<_SDReadWork>;
    using _RenderWorkQueue = std::queue<_RenderWork>;
    
    struct _LoadImagesState {
        Toastbox::Signal signal; // Protects this struct
//        struct {
//            Toastbox::Atomic<size_t> count = 0;
//            std::set<ImageRecordPtr> notify;
//        } render;
        std::set<ImageRecordPtr> notify;
        Toastbox::Atomic<size_t> underway;
    };
    
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
    
    ImageCache::ImageProvider _imageProvider() {
        return [&] (uint64_t addr) -> ImagePtr {
            return _imageForAddr(addr);
        };
    }
    
    #warning TODO: add priority to this function
    #warning TODO: it'd be nice if we could avoid the memcpy by giving the buffer to _SDWork
    ImagePtr _imageForAddr(uint64_t addr) {
        return nullptr;
//        bool done = false;
//        auto work = std::make_unique<_SDWork>();
//        work->state = {
//            .ops = {_SDReadOp{
//                .region = {
//                    .block = addr,
//                    .len = Img::Full::ImageLen,
//                },
//            }},
//            .read = {
//                .callback = [&] {
//                    done = true;
//                    _imageForAddrSignal.signalAll();
//                },
//            },
//        };
//        
//        // Enqueue SD read
//        {
//            {
//                auto lock = _sdRead.signal.lock();
//                _SDWorkQueue& queue = _sdRead.queues[(size_t)_Priority::High];
//                queue.push(work.get());
//            }
//            _sdRead.signal.signalOne();
//        }
//        
//        _imageForAddrSignal.wait([&] { return done; });
//        
//        if (_ImageChecksumValid(work->buffer, Img::Size::Full)) {
////                printf("Checksum valid (full-size)\n");
//        } else {
//            printf("Checksum INVALID (full-size)\n");
////                abort();
//        }
//        
//        std::unique_ptr<uint8_t[]> data = std::make_unique<uint8_t[]>(Img::Full::ImageLen);
//        memcpy(data.get(), work->buffer, Img::Full::ImageLen);
//        
//        const Img::Header& header = *(const Img::Header*)work->buffer;
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
    
    void _readCompleteCallback(_LoadImagesState& state, const _SDReadWork& work, _SDReadWork::OpsIter begin, _SDReadWork::OpsIter end, bool initial) {
        // Insert buffers into our cache
        {
            auto lock = _thumbCache.lock();
            for (auto it=begin; it!=end; it++) {
                const _SDReadOp& op = *it;
                _thumbCache.set(lock, op.region, op.buf);
            }
        }
        
        // Enqueue rendering
        {
            {
                auto lock = _thumbRender.signal.lock();
                for (auto it=begin; it!=end; it++) {
                    const _SDReadOp& op = *it;
//                    printf("Enqueueing rendering for %ju\n", (uintmax_t)op.rec->info.id);
                    _renderEnqueue(lock, state, initial, op.rec, op.buf);
                }
            }
            _thumbRender.signal.signalAll();
        }
        
//        {
//            {
//                auto lock = _thumbRender.signal.lock();
//                _renderEnqueue(lock, state, initial, rec, buf);
//            }
//            _thumbRender.signal.signalOne();
//        }
        
        
//        work.state.read.timeEnd = std::chrono::steady_clock::now();
//        work.state.render.timeStart = std::chrono::steady_clock::now();
//        
//        // Enqueue _SDWork into _thumbRender.work
//        {
//            auto lock = _thumbRender.signal.lock();
//            _thumbRender.work.push(&work);
//        }
//        
//        // Notify _thumbRender of more work
//        _thumbRender.signal.signalAll();
    }
    
    
//    void _readCompleteCallback(_LoadImagesState& state, _SDRegion region, bool initial, ImageRecordPtr rec, _ThumbBuffer buf) {
//        // Insert buffer into our cache
//        _cacheSet(region, buf);
//        
//        {
//            {
//                auto lock = _thumbRender.signal.lock();
//                _renderEnqueue(lock, state, initial, rec, buf);
//            }
//            _thumbRender.signal.signalOne();
//        }
//        
//        
////        work.state.read.timeEnd = std::chrono::steady_clock::now();
////        work.state.render.timeStart = std::chrono::steady_clock::now();
////        
////        // Enqueue _SDWork into _thumbRender.work
////        {
////            auto lock = _thumbRender.signal.lock();
////            _thumbRender.work.push(&work);
////        }
////        
////        // Notify _thumbRender of more work
////        _thumbRender.signal.signalAll();
//    }
    
    void _renderCompleteCallback(_LoadImagesState& state, ImageRecordPtr rec) {
//        work.state.render.timeEnd = std::chrono::steady_clock::now();
        
//        {
//            using namespace std::chrono;
//            const milliseconds readDuration = duration_cast<milliseconds>(work.state.read.timeEnd-work.state.read.timeStart);
//            const milliseconds renderDuration = duration_cast<milliseconds>(work.state.render.timeEnd-work.state.render.timeStart);
//            const size_t thumbCount = work.state.ops.size();
//            const double readThroughputMBPerSec = (((double)(thumbCount*ImgSD::Thumb::ImagePaddedLen) / (1024*1024)) / ((double)readDuration.count()/1000));
//            printf("[_renderCompleteCallback] Read took %ju ms for %ju images (avg %f ms / img, %f MB/sec)\n",
//                (uintmax_t)readDuration.count(), (uintmax_t)thumbCount, ((double)readDuration.count()/thumbCount), readThroughputMBPerSec);
//            printf("[_renderCompleteCallback] Render took %ju ms for %ju images (avg %f ms / img)\n",
//                (uintmax_t)renderDuration.count(), (uintmax_t)thumbCount, ((double)renderDuration.count()/thumbCount));
//        }
        
//        std::set<ImageRecordPtr> recs;
//        for (const _SDReadOp& op : work.state.ops) {
//            recs.insert(op.rec);
//        }
//        
        
        constexpr size_t NotifyThreshold = 8;
//        
//        const size_t count = --state.render.count;
//        
//        
//        #warning TODO: we should coalesce the recs and notify after we hit a threshold
//        // Post notification
//        if (!notify.empty()) {
//            auto lock = std::unique_lock(_imageLibrary);
//            _imageLibrary.notifyChange(notify);
//            printf("NOTIFY: %ju\n", (uintmax_t)notify.size());
//        }
        
        
//        {
//            auto lock = std::unique_lock(_imageLibrary);
//            _imageLibrary.notifyChange({ rec });
//        }
        
        const size_t count = --state.underway;
        if (!count) state.signal.signalOne();
        
        std::set<ImageRecordPtr> notify;
        {
            auto lock = state.signal.lock();
            state.notify.insert(rec);
            if (state.notify.size()>=NotifyThreshold || !count) {
                notify = std::move(state.notify);
            }
        }
        
        {
            auto lock = std::unique_lock(_imageLibrary);
            _imageLibrary.notifyChange(notify);
        }
        
        
//        // Announce that `work` is done
//        {
//            auto lock = state.signal.lock();
//            state.underway.erase(&work);
//        }
//        state.signal.signalOne();
    }
    
    void _renderEnqueue(std::unique_lock<std::mutex>& lock, _LoadImagesState& state, bool initial, ImageRecordPtr rec, _ThumbBuffer buf) {
        // Enqueue _RenderWork into _thumbRender.queue
        _thumbRender.queue.push(_RenderWork{
            .initial = initial,
            .rec = rec,
            .buf = std::move(buf),
            .callback = [=, &state] { _renderCompleteCallback(state, rec); },
        });
    }
    
    
    
//    void _renderEnqueueNoSignal(_LoadImagesState& state, bool initial, ImageRecordPtr rec, _ThumbBuffer buf) {
//        state.render.count++;
//        
//        // Enqueue _RenderWork into _thumbRender.queue
//        {
//            auto lock = _thumbRender.signal.lock();
//            assert(buf);
//            _thumbRender.queue.insert(_RenderWork{
//                .initial = initial,
//                .rec = rec,
//                .buf = std::move(buf),
//                .callback = [=, &state] { _renderCompleteCallback(state, rec); },
//            });
//        }
//    }
    
//    _ThumbBuffer _cacheGet(const _SDRegion& region) {
//        auto lock = std::unique_lock(_thumbCache.lock);
//        if (auto find=_thumbCache.cache.find(region); find!=_thumbCache.cache.end()) {
//            return find->val;
//        }
//        return {};
//    }
//    
//    void _cacheSet(std::unique_lock<std::mutex>& lock, const _SDRegion& region, _ThumbBuffer buf) {
//        assert(lock);
//        _thumbCache.cache[region] = std::move(buf);
//    }
//    
//    void _cacheSet(const _SDRegion& region, _ThumbBuffer buf) {
//        auto lock = std::unique_lock(_thumbCache.lock);
//        _cacheSet(lock, region, buf);
//    }
    
    void _loadImages(_LoadImagesState& state, _Priority priority,
        bool initial, std::set<ImageRecordPtr> recs) {
        
        state.underway += recs.size();
        
        // Kick off rendering for all the recs that are in the cache
        {
            bool enqueued = false;
            {
                auto lock = _thumbRender.signal.lock();
                
                for (auto it=recs.begin(); it!=recs.end();) {
                    const ImageRecordPtr& rec = *it;
                    const _SDRegion region = {
                        .block = rec->info.addrThumb,
                        .len = ImgSD::Thumb::ImagePaddedLen,
                    };
                    
                    // If the thumbnail is in our cache, kick off rendering
                    _ThumbBuffer buf = _thumbCache.get(region);
                    if (buf) {
                        _renderEnqueue(lock, state, initial, rec, std::move(buf));
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
        
        // The remaining recs aren't in our cache, so kick of SD reading + rendering
        for (auto it=recs.rbegin(); it!=recs.rend();) {
            _SDReadWork work = {
                .callback = [=, &state] (const _SDReadWork& work, _SDReadWork::OpsIter begin, _SDReadWork::OpsIter end) { _readCompleteCallback(state, work, begin, end, initial); },
            };
            
            for (; it!=recs.rend(); it++) {
                const ImageRecordPtr& rec = *it;
                const _SDRegion region = {
                    .block = rec->info.addrThumb,
                    .len = ImgSD::Thumb::ImagePaddedLen,
                };
                
                _ThumbBuffer buf;
                {
                    auto lock = _thumbCache.lock();
                    if (!_thumbCache.sizeFree(lock)) {
                        _thumbCache.evict(lock);
                        if (!work.ops.empty()) {
                            printf("[_loadImages] No free buffer, enqueueing %ju read ops\n", (uintmax_t)work.ops.size());
                            break;
                        } else {
                            printf("[_loadImages] No free buffer, waiting...\n");
                        }
                    }
                    buf = _thumbCache.pop(lock);
                }
                
//                #warning TODO: if work has ops and we're about to wait, enqueue the work so we don't hold up the existing ops waiting for a buffer
//                #warning TODO: implement waiting on state.pool if the pool is empty
//                _ThumbBuffer buf = _thumbCache.pop();
                
                work.ops.insert(_SDReadOp{
                    .region = region,
                    .buf = buf,
                    .rec = rec,
                });
                
//                // Enqueue _SDWork into _sdRead.queues
//                {
//                    printf("[_loadImages] Enqueue _SDReadWork\n");
//                    
//                    {
//                        auto lock = _sdRead.signal.lock();
//                        _SDReadWorkQueue& queue = _sdRead.queues[(size_t)priority];
//                        auto [_,ok] = queue.push(_SDReadWork{
//                            .region = region,
//                            .buf = buf,
//                            .callback = [=, &state] { _readCompleteCallback(state, region, initial, rec, buf); },
//                        });
//                        assert(ok);
//                    }
//                    
//                    #warning TODO: only signal after we've enqueued some number of _SDReadWork's
//                    _sdRead.signal.signalOne();
//                }
            }
            
            assert(!work.ops.empty());
            
            {
                auto lock = _sdRead.signal.lock();
                _SDReadWorkQueue& queue = _sdRead.queues[(size_t)priority];
                queue.push(std::move(work));
            }
            _sdRead.signal.signalOne();
        }
        
        state.signal.wait([&] { return !state.underway; });
        
//        // Print profile stats
//        {
//            using namespace std::chrono;
//            const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
//            const size_t imageCount = recs.size();
//            printf("[_loadImages] _loadImages() took %ju ms for %ju images (avg %f ms / img)\n",
//                (uintmax_t)duration.count(), (uintmax_t)imageCount, ((double)duration.count()/imageCount));
//        }
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
                            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                                (uintmax_t)libImgIdEnd,
                                (uintmax_t)deviceImgIdEnd
                            );
                        }
                        
                        addCount = (uint32_t)(deviceImgIdEnd - std::max(deviceImgIdBegin, libImgIdEnd));
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
                        if (!(rec->info.flags & ImageFlags::Loaded)) {
                            recs.insert(rec);
                        }
                    }
                    
                    printf("[_sync_thread] Loading %ju images\n", (uintmax_t)recs.size());
                    _loadImages(_sync.loadImages, _Priority::Low, true, recs);
                }
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_sync_thread] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[_sync_thread] Failed to update image library: %s", e.what());
        }
    }
    
    // MARK: - Thumb Update
    
    void _thumbUpdate_thread() {
        try {
            for (;;) {
                std::set<ImageRecordPtr> recs;
                {
                    auto lock = _thumbUpdate.signal.wait([&] { return !_thumbUpdate.recs.empty(); });
                    recs = std::move(_thumbUpdate.recs);
                    // Update .thumb.render asap (ie before we've actually rendered) so that the
                    // visibleThumbs() function on the main thread stops enqueuing work asap
                    for (const ImageRecordPtr& rec : recs) {
                        rec->options.thumb.render = false;
                    }
                }
                
                _loadImages(_thumbUpdate.loadImages, _Priority::High, false, recs);
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_thumbUpdate_thread] Stopping\n");
        }
    }
    
    // MARK: - SD Read
    
    // _sdRead.lock must be held!
    _SDReadWorkQueue* _sdRead_nextQueue() {
        for (_SDReadWorkQueue& x : _sdRead.queues) {
            if (!x.empty()) return &x;
        }
        return nullptr;
    }
    
//    struct _SDCoalescedWork {
//        std::vector<_SDReadWork> works;
//        _SDBlock blockBegin = 0;
//        _SDBlock blockEnd = 0;
//    };
//    
//    template<size_t T_Cap>
//    static _SDCoalescedWork _SDRead_CoalesceWork(_SDReadWorkQueue& queue) {
//        assert(!queue.empty());
//        
//        // CoalesceBudget: coalesce adjacent blocks until this budget is exceeded
//        std::vector<_SDReadWork> works;
//        std::optional<_SDBlock> blockBegin;
//        std::optional<_SDBlock> blockEnd;
//        size_t budget = T_Cap;
//        auto it = queue.begin();
//        for (; it!=queue.end(); it++) {
//            const _SDReadWork& work = *it;
//            const _SDBlock workBlockBegin = work.region.block;
//            const _SDBlock workBlockEnd = _SDBlockEnd(workBlockBegin, work.region.len);
//            
//            size_t cost = 0;
//            if (!blockEnd) {
//                cost = (size_t)SD::BlockLen * (workBlockEnd-workBlockBegin);
//            } else if (workBlockEnd > *blockEnd) {
//                cost = (size_t)SD::BlockLen * (workBlockEnd-*blockEnd);
//            }
//            
//            // Stop coalescing work once the cost exceeds our budget
//            if (cost > budget) break;
//            
//            if (!blockBegin) blockBegin = workBlockBegin;
//            if (!blockEnd || workBlockEnd>*blockEnd) blockEnd = workBlockEnd;
//            
//            works.push_back(*it);
//            budget -= cost;
//        }
//        // Ensure that we enqueued at least one work
//        assert(!works.empty());
//        // Remove the coalesced work from `queue`
//        queue.erase(queue.begin(), it);
//        return _SDCoalescedWork{
//            .works = std::move(works),
//            .blockBegin = *blockBegin,
//            .blockEnd = *blockEnd,
//        };
//    }
    
    using _SDReadOpIter = std::set<_SDReadOp>::const_iterator;
    void __sdRead_handleWork(_SDReadOpIter begin, _SDReadOpIter end) {
        assert(begin != end);
        const _SDReadOp& front = *begin;
        const _SDReadOp& back = *std::prev(end);
        const _SDBlock blockBegin = front.region.block;
        const _SDBlock blockEnd = _SDBlockEnd(back.region.block, back.region.len);
        const size_t len = (size_t)SD::BlockLen * (size_t)(blockEnd-blockBegin);
        // Verify that the length of data that we're reading will fit in our buffer
        assert(len <= sizeof(_sdRead.buffer));
        
        {
            printf("[__sdRead_handleWork] reading [%ju,%ju) (%.1f MB)\n", (uintmax_t)blockBegin, (uintmax_t)blockEnd, (float)len/(1024*1024));
            auto lock = std::unique_lock(_dev);
            _dev.reset();
            // Verify that blockBegin can be safely cast to SD::Block
            assert(std::numeric_limits<SD::Block>::max() >= blockBegin);
            _dev.sdRead((SD::Block)blockBegin);
            _dev.readout(_sdRead.buffer, len);
        }
        
        // Copy data into each _SDReadOp
        for (auto it=begin; it!=end; it++) {
            const _SDReadOp& op = *it;
            const size_t off = (size_t)SD::BlockLen * (size_t)(op.region.block-blockBegin);
            memcpy(*op.buf, _sdRead.buffer+off, op.region.len);
        }
    }
    
    void _sdRead_handleWork(const _SDReadWork& work) {
        for (auto it=work.ops.begin(); it!=work.ops.end();) {
            const auto begin = it;
            const _SDBlock blockBegin = begin->region.block;
            _SDBlock blockEnd = 0;
            for (; it!=work.ops.end(); it++) {
                // blockEndCandidate: std::max() is necessary because this op's blockEnd could be less
                // than our accumulated blockEnd, because this op is allowed to read data that stops
                // before the previous op's blockEnd.
                const _SDBlock blockEndCandidate = std::max(blockEnd, _SDBlockEnd(it->region.block, it->region.len));
                const size_t len = (size_t)SD::BlockLen * (size_t)(blockEndCandidate-blockBegin);
                if (len > sizeof(_sdRead.buffer)) break;
                blockEnd = blockEndCandidate;
            }
            __sdRead_handleWork(begin, it);
            work.callback(work, begin, it);
        }
        
//        assert(!coalesced.works.empty());
//        const size_t len = (size_t)SD::BlockLen * (size_t)(coalesced.blockEnd-coalesced.blockBegin);
//        // Verify that the length of data that we're reading will fit in our buffer. Our _SDRead_CoalesceWork()
//        // logic guarantees this should be the case, so check that assumption.
//        assert(len <= sizeof(_sdRead.buffer));
//        
//        {
//            auto lock = std::unique_lock(_dev);
//            _dev.reset();
//            // Verify that blockBegin can be safely cast to SD::Block
//            assert(std::numeric_limits<SD::Block>::max() >= coalesced.blockBegin);
//            _dev.sdRead((SD::Block)coalesced.blockBegin);
//            _dev.readout(_sdRead.buffer, len);
//        }
//        
//        // Update each _SDReadOp with its data address
//        {
//            for (const _SDReadWork& work : coalesced.works) {
//                const size_t off = (size_t)SD::BlockLen * (size_t)(work.region.block-coalesced.blockBegin);
//                memcpy(work.buf, _sdRead.buffer+off, work.region.len);
//                work.callback();
//            }
//        }
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
                _sdRead_handleWork(work);
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
//                    const size_t idx = rand() % _thumbRender.queue.size();
//                    auto it = _thumbRender.queue.begin();
//                    std::advance(it,idx);
//                    work = *it;
//                    _thumbRender.queue.erase(it);
                    work = _thumbRender.queue.front();
                    _thumbRender.queue.pop();
                }
                
                ImageRecord& rec = *work.rec;
                
                // Validate checksum
                if (_ImageChecksumValid(*work.buf, Img::Size::Thumb)) {
    //                printf("Checksum valid (thumb)\n");
                } else {
                    printf("Checksum INVALID (thumb)\n");
    //                abort();
                }
                
                if (work.initial) {
                    // Populate .info
                    {
                        const Img::Header& imgHeader = *(const Img::Header*)(*work.buf);
                        
                        if (imgHeader.id != rec.info.id) {
                            #warning TODO: how do we properly handle this?
                            printf("[_thumbRender_thread] Invalid image id (got: %ju, expected: %ju)\n", (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
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
                
                // Once the thumbnail is fully loaded, set the Loaded flag
                if (work.initial) {
                    // Issue a memory barrier to ensure all the previous writes are complete before we set the Loaded flag
                    std::atomic_thread_fence(std::memory_order_seq_cst);
                    rec.info.flags = ImageFlags::Loaded;
                }
                
                work.callback();
                
//                // Increment state.render.idxDone, and call the callback if this
//                // was last _SDReadOp in the _SDWork.
//                const size_t idxDone = work->state.render.idxDone.fetch_add(1);
//                assert(idxDone < work->state.ops.size());
//                if (idxDone == work->state.ops.size()-1) {
//                    {
//                        using namespace std::chrono;
//                        const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-work->state.render.timeStart);
//                        const size_t thumbCount = work->state.ops.size();
//                        printf("[_thumbRender_thread] Render took %ju ms for %ju images (avg %f ms / img)\n",
//                            (uintmax_t)duration.count(), (uintmax_t)thumbCount, ((double)duration.count()/thumbCount));
//                    }
//                    work->state.render.callback();
//                }
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_thumbRender_thread] Stopping\n");
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
    Toastbox::Signal _imageForAddrSignal;
    _ThumbCache _thumbCache;
    
    struct {
        std::thread thread;
        _LoadImagesState loadImages;
    } _sync;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        _LoadImagesState loadImages;
        std::set<ImageRecordPtr> recs;
    } _thumbUpdate;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        _SDReadWorkQueue queues[(size_t)_Priority::Count];
        uint8_t buffer[16*1024*1024];
    } _sdRead;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::vector<std::thread> threads;
        _RenderWorkQueue queue;
    } _thumbRender;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

} // namespace MDCStudio

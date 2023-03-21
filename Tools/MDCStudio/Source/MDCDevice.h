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
    
    void visibleThumbs(ImageRecordAnyIter begin, ImageRecordAnyIter end) override {
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
    
    using _SDWorkCallback = std::function<void()>;
    
    struct _SDReadOp;
    struct _SDWork {
        static constexpr size_t BufferThumbCount = 32;
        uint8_t buffer[BufferThumbCount * ImgSD::Thumb::ImagePaddedLen];
        
        struct {
            std::vector<_SDReadOp> ops; // Sorted by SD block
            
            struct {
                _SDWorkCallback callback;
//                std::chrono::time_point<std::chrono::steady_clock> timeStart;
//                std::chrono::time_point<std::chrono::steady_clock> timeEnd;
            } read;
            
            struct {
                bool initial = false;
                Toastbox::Atomic<size_t> idx = 0;
                Toastbox::Atomic<size_t> idxDone = 0;
                _SDWorkCallback callback;
                std::chrono::time_point<std::chrono::steady_clock> timeStart;
//                std::chrono::time_point<std::chrono::steady_clock> timeEnd;
            } render;
        } state;
    };
    
    struct _SDReadOp {
        _SDBlock block = 0;
        size_t len = 0;
        ImageRecordPtr rec;
        const uint8_t* data = nullptr;
        
        bool operator<(const _SDReadOp& x) const {
            if (block != x.block) return block < x.block;
            if (len != x.len) return len < x.len;
            return false;
        }
        
        bool operator==(const _SDReadOp& x) const {
            if (block != x.block) return false;
            if (len != x.len) return false;
            return true;
        }
    };
    
    using _SDWorkQueue = std::queue<_SDWork*>;
    
    struct _LoadImagesState {
        Toastbox::Signal signal;
        std::vector<_SDWork> works;
        std::set<_SDWork*> underway;
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
        bool done = false;
        auto work = std::make_unique<_SDWork>();
        work->state = {
            .ops = {_SDReadOp{
                .block = addr,
                .len = Img::Full::ImageLen,
            }},
            .read = {
                .callback = [&] {
                    done = true;
                    _imageForAddrSignal.signalAll();
                },
            },
        };
        
        // Enqueue SD read
        {
            {
                auto lock = _sdRead.signal.lock();
                _SDWorkQueue& queue = _sdRead.queues[(size_t)_Priority::High];
                queue.push(work.get());
            }
            _sdRead.signal.signalOne();
        }
        
        _imageForAddrSignal.wait([&] { return done; });
        
        if (_ImageChecksumValid(work->buffer, Img::Size::Full)) {
//                printf("Checksum valid (full-size)\n");
        } else {
            printf("Checksum INVALID (full-size)\n");
//                abort();
        }
        
        std::unique_ptr<uint8_t[]> data = std::make_unique<uint8_t[]>(Img::Full::ImageLen);
        memcpy(data.get(), work->buffer, Img::Full::ImageLen);
        
        const Img::Header& header = *(const Img::Header*)work->buffer;
        ImagePtr image = std::make_shared<Image>(Image{
            .width      = header.imageWidth,
            .height     = header.imageHeight,
            .cfaDesc    = _CFADesc,
            .data       = std::move(data),
            .off        = sizeof(header),
        });
        return image;
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
    
    void _readCompleteCallback(_LoadImagesState& state, _SDWork& work) {
//        work.state.read.timeEnd = std::chrono::steady_clock::now();
//        work.state.render.timeStart = std::chrono::steady_clock::now();
        
        // Enqueue _SDWork into _thumbRender.work
        {
            auto lock = _thumbRender.signal.lock();
            _thumbRender.work.push(&work);
        }
        
        // Notify _thumbRender of more work
        _thumbRender.signal.signalAll();
    }
    
    void _renderCompleteCallback(_LoadImagesState& state, _SDWork& work) {
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
        
        std::set<ImageRecordPtr> recs;
        for (const _SDReadOp& op : work.state.ops) {
            recs.insert(op.rec);
        }
        
        // Post notification
        {
            auto lock = std::unique_lock(_imageLibrary);
            _imageLibrary.notifyChange(recs);
        }
        
        // Announce that `work` is done
        {
            auto lock = state.signal.lock();
            state.underway.erase(&work);
        }
        state.signal.signalOne();
    }
    
    void _loadImages(_LoadImagesState& state, _Priority priority,
        bool initial, const std::set<ImageRecordPtr>& recs) {
        
        // WriteIntervalThumbCount: the number of loaded thumbnails after which we'll write the ImageLibrary to disk
        constexpr size_t WriteIntervalThumbCount = 256;
        
        const auto timeStart = std::chrono::steady_clock::now();
        
        // Reset each work
        // This is necessary because our loop below interprets _SDWork.state.ops as the _SDReadOps from its
        // previous iteration, so _SDWork.state.ops needs to start off empty for correct operation.
        for (_SDWork& work : state.works) {
            work.state = {};
        }
        
//        if (initial) {
//            auto lock = std::unique_lock(_imageLibrary);
//            printf("[_loadImages] reserving %ju images\n", (uintmax_t)recs.size());
//            _imageLibrary.reserve(recs.size());
//        }
        
        size_t writeCount = 0;
        size_t workIdx = 0;
        for (auto it=recs.rbegin(); it!=recs.rend();) {
            // Get a _SDWork
            _SDWork& work = state.works.at(workIdx);
            workIdx++;
            if (workIdx == state.works.size()) workIdx = 0;
            
            // Wait until the _SDWork is ready
            {
                auto lock = state.signal.wait([&] { return state.underway.find(&work) == state.underway.end(); });
                state.underway.insert(&work);
            }
            
            // Populate _SDWork
            {
                // Prepare the _SDWork
                work.state = {
                    .read = {
                        .callback = [&] { _readCompleteCallback(state, work); },
                    },
                    
                    .render = {
                        .initial = initial,
                        .callback = [&] { _renderCompleteCallback(state, work); },
                    },
                };
                
                // Push _SDReadOps until we run out, or we hit the capacity of _SDWork.buffer
                const _SDBlock workBlockBegin = (*it)->info.addrThumb;
                for (; it!=recs.rend(); it++) {
                    const ImageRecordPtr& rec = *it;
                    const _SDBlock blockBegin = rec->info.addrThumb;
                    // If the block addresses wrap around, start a new _SDWork
                    if (blockBegin < workBlockBegin) break;
                    const _SDBlock blockEnd = _SDBlockEnd(blockBegin, ImgSD::Thumb::ImagePaddedLen);
                    const size_t span = (size_t)SD::BlockLen * (size_t)(blockEnd-workBlockBegin);
                    // Bail if we hit a _SDReadOp that would put us over the capacity of work.buffer
                    if (span > sizeof(work.buffer)) break;
                    work.state.ops.push_back(_SDReadOp{
                        .block = blockBegin,
                        .len = ImgSD::Thumb::ImagePaddedLen,
                        .rec = rec,
                    });
                }
//                
//                work.state.read.timeStart = std::chrono::steady_clock::now();
                
                printf("[_loadImages] Enqueued _SDWork:%p ops.size():%ju idx:%zu idxDone:%zu\n",
                    &work, (uintmax_t)work.state.ops.size(), work.state.render.idx.load(), work.state.render.idxDone.load());
            }
            
            // Enqueue _SDWork into _sdRead.queues
            {
                {
                    auto lock = _sdRead.signal.lock();
                    _SDWorkQueue& queue = _sdRead.queues[(size_t)priority];
                    queue.push(&work);
                }
                _sdRead.signal.signalOne();
            }
            
            // Periodically write the image library
            if (initial) {
                auto lock = std::unique_lock(_imageLibrary);
                writeCount += work.state.ops.size();
                if (writeCount >= WriteIntervalThumbCount) {
                    printf("[_loadImages] Write library (writeCount: %ju)\n", (uintmax_t)writeCount);
                    writeCount = 0;
                    _imageLibrary.write();
                }
            }
        }
        
        // Wait until remaining _SDWorks are complete
        state.signal.wait([&] { return state.underway.empty(); });
        
        // Add remaining images and write library
        if (initial) {
            auto lock = std::unique_lock(_imageLibrary);
            printf("[_loadImages] Write library remainder\n");
            _imageLibrary.write();
        }
        
        // Print profile stats
        {
            using namespace std::chrono;
            const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
            const size_t imageCount = recs.size();
            printf("[_loadImages] _loadImages() took %ju ms for %ju images (avg %f ms / img)\n",
                (uintmax_t)duration.count(), (uintmax_t)imageCount, ((double)duration.count()/imageCount));
        }
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
    _SDWorkQueue* _sdRead_nextWorkQueue() {
        for (_SDWorkQueue& x : _sdRead.queues) {
            if (!x.empty()) return &x;
        }
        return nullptr;
    }
    
    void _sdRead_handleWork(_SDWork& work) {
        assert(!work.state.ops.empty());
        
        // Read the data from the device
        const _SDBlock blockBegin = work.state.ops.front().block;
        {
            const _SDBlock blockEnd = _SDBlockEnd(work.state.ops.back().block, work.state.ops.back().len);
            const size_t len = (size_t)SD::BlockLen * (size_t)(blockEnd-blockBegin);
            assert(len <= sizeof(work.buffer));
            
            const auto timeStart = std::chrono::steady_clock::now();
            {
                auto lock = std::unique_lock(_dev);
                _dev.reset();
                // Verify that blockBegin can be safely cast to SD::Block
                assert(std::numeric_limits<SD::Block>::max() >= blockBegin);
                _dev.sdRead((SD::Block)blockBegin);
                _dev.readout(work.buffer, len);
            }
            
            const std::chrono::milliseconds duration = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-timeStart);
            const double throughputMBPerSec = ((double)(len * 1000) / (duration.count() * 1024*1024));
            printf("[_sdRead_handleWork] Read [%ju,%ju) took %ju ms (avg: %f ms / op, throughput: %.1f MB/sec)\n",
                (uintmax_t)blockBegin, (uintmax_t)blockEnd, (uintmax_t)duration.count(),
                ((double)duration.count()/work.state.ops.size()), throughputMBPerSec);
        }
        
        // Update each _SDReadOp with its data address
        {
            for (_SDReadOp& op : work.state.ops) {
                const size_t off = (size_t)SD::BlockLen * (size_t)(op.block-blockBegin);
                op.data = work.buffer + off;
            }
        }
        
        // Execute the _SDWork callback
        {
            work.state.read.callback();
        }
    }
    
    void _sdRead_thread() {
        try {
            for (;;) {
                _SDWork* work = nullptr;
                {
                    // Wait for work
                    _SDWorkQueue* queue = nullptr;
                    auto lock = _sdRead.signal.wait([&] { return (queue = _sdRead_nextWorkQueue()); });
                    work = queue->front();
                    queue->pop();
                }
                _sdRead_handleWork(*work);
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
                _SDWork* work = nullptr;
                size_t idx = 0;
                {
                    auto lock = _thumbRender.signal.wait([&] { return !_thumbRender.work.empty(); });
                    work = _thumbRender.work.front();
                    idx = work->state.render.idx.fetch_add(1);
                    if (!idx) work->state.render.timeStart = std::chrono::steady_clock::now();
                    
                    // Our logic guarantees that we should never observe a _SDWork in _thumbRender.work
                    // unless it has available indexes (state.render.idx) that need to be handled.
                    // Confirm that's true.
                    assert(idx < work->state.ops.size());
                    // If we're handling the last _SDReadOp in the _SDWork, remove the _SDWork
                    // from _thumbRender.work. See assertion comment directly above.
                    if (idx == work->state.ops.size()-1) {
                        _thumbRender.work.pop();
                    }
                    
//                    printf("[_thumbRender_thread] Dequeued _SDWork=%p idx:%zu ops.size():%zu\n", work, idx, work->state.ops.size());
                }
                
                const _SDReadOp& op = work->state.ops.at(idx);
                ImageRecord& rec = *op.rec;
                
                // Validate checksum
                if (_ImageChecksumValid(op.data, Img::Size::Thumb)) {
    //                printf("Checksum valid (thumb)\n");
                } else {
                    printf("Checksum INVALID (thumb)\n");
    //                abort();
                }
                
                if (work->state.render.initial) {
                    // Populate .info
                    {
                        const Img::Header& imgHeader = *(const Img::Header*)op.data;
                        
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
                    const void* thumbSrc = op.data+Img::PixelsOffset;
                    void* thumbDst = rec.thumb.data;
                    
                    // estimateIlluminant: only perform illuminant estimation upon our initial import
                    const bool estimateIlluminant = work->state.render.initial;
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
                if (work->state.render.initial) {
                    // Issue a memory barrier to ensure all the previous writes are complete before we set the Loaded flag
                    std::atomic_thread_fence(std::memory_order_seq_cst);
                    rec.info.flags = ImageFlags::Loaded;
                }
                
                // Increment state.render.idxDone, and call the callback if this
                // was last _SDReadOp in the _SDWork.
                const size_t idxDone = work->state.render.idxDone.fetch_add(1);
                assert(idxDone < work->state.ops.size());
                if (idxDone == work->state.ops.size()-1) {
                    {
                        using namespace std::chrono;
                        const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-work->state.render.timeStart);
                        const size_t thumbCount = work->state.ops.size();
                        printf("[_thumbRender_thread] Render took %ju ms for %ju images (avg %f ms / img)\n",
                            (uintmax_t)duration.count(), (uintmax_t)thumbCount, ((double)duration.count()/thumbCount));
                    }
                    work->state.render.callback();
                }
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
    
    struct {
        std::thread thread;
        _LoadImagesState loadImages = {
            .works = std::vector<_SDWork>(2),
        };
    } _sync;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        _LoadImagesState loadImages = {
            .works = std::vector<_SDWork>(1),
        };
        std::set<ImageRecordPtr> recs;
    } _thumbUpdate;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        _SDWorkQueue queues[(size_t)_Priority::Count];
    } _sdRead;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::vector<std::thread> threads;
        _SDWorkQueue work;
    } _thumbRender;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

} // namespace MDCStudio

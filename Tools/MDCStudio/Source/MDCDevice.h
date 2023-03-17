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
#import "Toastbox/SignalQueue.h"
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
            
            _thumbUpdate.thread = std::thread([&] { _thumbUpdate_thread(); });
            
            _sdRead.thread = std::thread([&] { _sdRead_thread(); });
            
            for (int i=0; i<_ThreadCount(); i++) {
                _thumbRender.threads.emplace_back([&] { _thumbRender_thread(); });
            }
        }
    }
    
    ~MDCDevice() {
        // Signal our threads to stop
        _sync.signal.stop();
        _sync.loadImages.read.signal.stop();
        _sync.loadImages.render.signal.stop();
        _thumbUpdate.signal.stop();
        _thumbUpdate.loadImages.read.signal.stop();
        _thumbUpdate.loadImages.render.signal.stop();
        _sdRead.signal.stop();
        _thumbRender.signal.stop();
        
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
    
    using _SDWorkCallback = std::function<void()>;
    
    struct _SDReadOp;
    struct _SDWork {
        static constexpr size_t BufferThumbCount = 128;
        Toastbox::Signal signal; // Protects this struct
        uint8_t buffer[BufferThumbCount * ImgSD::Thumb::ImagePaddedLen];
        
        struct {
            std::vector<_SDReadOp> ops;
            
            struct {
                _SDWorkCallback callback;
            } read;
            
            struct {
                bool initial = false;
                Toastbox::Atomic<size_t> idx = 0;
                _SDWorkCallback callback;
            } render;
        } state;
    };
    
    struct _SDReadOp {
        _SDBlock block = 0;
        size_t len = 0;
        ImageRecordPtr rec;
        void* data = nullptr;
        
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
    
    struct _SDCoalescedOps {
        std::vector<_SDReadOp> works;
        _SDBlock blockBegin = 0;
        _SDBlock blockEnd = 0;
    };
    
//    struct _ThumbRenderWork;
//    struct _ThumbRenderStatus {
//        Toastbox::Signal signal; // Protects this struct
//        std::vector<_ThumbRenderWork> done;
//    };
//    
//    struct _ThumbRenderWork {
//        ImageRecordPtr rec;
//        bool initial = false;
//        std::unique_ptr<uint8_t[]> data;
//        _ThumbRenderStatus& status;
//    };
    
    using _SDWorkPopFn  = _SDWork&(MDCDevice::*)();
    using _SDWorkPushFn = void(MDCDevice::*)(_SDWork&);
    
    struct _LoadImagesState {
        _SDWorkPopFn workPop;
        _SDWorkPushFn workPush;
        Toastbox::Signal signal; // Protects this struct
        std::queue<_SDWork*> queue;
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
    
    #warning TODO: add priority to this function
    ImagePtr _imageForAddr(uint64_t addr) {
        auto work = std::make_unique<_SDWork>();
        work->state.ops.push_back({
            .block = addr,
            .len = Img::Full::ImageLen,
        });
        
        // Enqueue SD read
        {
            {
                auto lock = _sdRead.signal.lock();
                _SDWorkQueue& queue = _sdRead.queues[(size_t)_Priority::High];
                queue.push(work.get());
            }
            _sdRead.signal.signalOne();
        }
        
        work->signal.wait([&] { return (bool)work->state.ops.front().data; });
        
        if (_ImageChecksumValid(work->buffer, Img::Size::Full)) {
//                printf("Checksum valid (size: full)\n");
        } else {
            printf("Checksum INVALID (size: full)\n");
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
    
    _SDWork& _sdWorkPop(const _LoadImagesState& state) {
        return (this->*(state.workPop))();
    }
    
    void _sdWorkPush(const _LoadImagesState& state, _SDWork& work) {
        (this->*(state.workPush))(work);
    }
    
    void _readComplete(_LoadImagesState& state, _SDWork& work) {
        // Enqueue _SDWork into _thumbRender.work
        {
            auto lock = _thumbRender.signal.lock();
            _thumbRender.work.push(&work);
        }
        
        // Notify _thumbRender of more work
        _thumbRender.signal.signalAll();
    }
    
    void _renderComplete(_LoadImagesState& state, _SDWork& work) {
        // Post notification
        {
            std::set<ImageRecordPtr> recs;
            for (_SDReadOp& op : work.state.ops) {
                recs.insert(op.rec);
            }
            
            {
                auto lock = std::unique_lock(_imageLibrary);
                _imageLibrary.notifyChange(recs);
            }
        }
        
        #warning TODO: update our imageIdEnd or equivalent (make sure doing so is properly serialized though, so we can't clobber imageIdEnd with the wrong value because things completed out of order)
        
        // Return _SDWork to pool
        _sdWorkPush(state, work);
    }
    
    void _loadImages(_LoadImagesState& state, _Priority priority,
        bool initial, const std::set<ImageRecordPtr>& recs) {
        
        for (auto it=recs.begin(); it!=recs.end();) {
            // Get a _SDWork
            _SDWork& work = _sdWorkPop(state);
            
            // Populate _SDWork
            {
                // Prepare the _SDWork
                work.state = {
                    .read = {
                        .callback = [&] { _readComplete(state, work); },
                    },
                    .render = {
                        .initial = initial,
                        .callback = [&] { _renderComplete(state, work); },
                    },
                };
                
                // Create a _SDReadOp for each ImageRecordPtr, until no more can be held in the buffer of the _SDWork
                size_t cap = sizeof(work.buffer);
                for (; it!=recs.end(); it++) {
                    if (cap < ImgSD::Thumb::ImagePaddedLen) break;
                    work.state.ops.push_back({
                        .block = (*it)->addr.thumb,
                        .len = ImgSD::Thumb::ImagePaddedLen,
                        .rec = *it,
                    });
                    cap -= ImgSD::Thumb::ImagePaddedLen;
                }
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
                        
                        addCount = 1024;//(uint32_t)(deviceImgIdEnd - std::max(deviceImgIdBegin, libImgIdEnd));
                        printf("Adding %ju images\n", (uintmax_t)addCount);
                        _imageLibrary.reserve(addCount);
                        _imageLibrary.add();
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
        
        } catch (const Toastbox::Signal::Stop&) {
            fprintf(stderr, "_sync_thread stopping\n");
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    // MARK: - Thumb Update
    
    void _thumbUpdate_thread() {
        try {
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
        
        } catch (const Toastbox::Signal::Stop&) {
            fprintf(stderr, "_thumbUpdate_thread stopping\n");
        }
    }
    
    // MARK: - SD Read
    
    static constexpr _SDBlock _SDRead_BlockEnd(_SDBlock block, size_t len) {
        const _SDBlock blockCount = Toastbox::DivCeil((_SDBlock)len, (_SDBlock)SD::BlockLen);
        // Verify that block+blockLen doesn't overflow _SDBlock
        assert(std::numeric_limits<_SDBlock>::max()-block >= blockCount);
        return block + blockCount;
    }
    
    static _SDCoalescedOps _SDRead_CoalesceWork(_SDWorkQueue& queue) {
        assert(!queue.empty());
        
        // CoalesceBudget: coalesce adjacent blocks until this budget is exceeded
        static constexpr _SDBlock CoalesceBudget = 8192;
        const _SDWork& status = queue.begin()->status;
        _SDCoalescedOps coalesced = {
            .blockBegin = queue.begin()->block,
            .blockEnd   = _SDRead_BlockEnd(queue.begin()->block, queue.begin()->len),
        };
        _SDBlock budget = CoalesceBudget;
        for (auto it=queue.begin(); it!=queue.end();) {
            const auto itPrev = it;
            const _SDReadOp& work = *it;
            const _SDBlock workBlockBegin = work.block;
            const _SDBlock workBlockEnd = _SDRead_BlockEnd(workBlockBegin, work.len);
            
            // The queue ordering guarantees that the blockBegins are in ascending order.
            // Check that assumption.
            assert(coalesced.blockBegin <= work.block);
            
            const _SDBlock cost = (workBlockEnd>coalesced.blockEnd ? workBlockEnd-coalesced.blockEnd : 0);
            // Stop coalescing work once the cost exceeds our budget
            if (cost > budget) break;
            // Stop coalescing work if the .status member doesn't match
            // (Ie, we don't coalesce across .status boundaries)
            if (&work.status != &status) break;
            
            it++; // Increment before we extract, because extract invalidates iterator
            coalesced.blockEnd = std::max(coalesced.blockEnd, workBlockEnd);
            coalesced.works.push_back(std::move(queue.extract(itPrev).value()));
            budget -= cost;
        }
        return coalesced;
    }
    
//    void _sdRead(_Priority priority, _SDBlock block, size_t len, void* dst) {
//        abort();
////        const auto status = std::make_shared<_SDWork>();
////        
////        // Enqueue the work
////        {
////            {
////                auto lock = std::unique_lock(_sdRead.lock);
////                _SDWorkQueue& queue = _sdRead.queues[priority];
////                queue.emplace(_SDReadOp{
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
    _SDWorkQueue* _sdRead_nextWorkQueue() {
        for (_SDWorkQueue& x : _sdRead.queues) {
            if (!x.empty()) return &x;
        }
        return nullptr;
    }
    
    void _sdRead_handleWork(_SDCoalescedOps& coalesced) {
        assert(!coalesced.works.empty());
        _SDWork& status = coalesced.works.front().status;
        
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
        
        // Copy the data into each _SDReadOp
        {
            #warning TODO: use a preallocated storage associated with the _SDWork, instead of making lots of individual allocations
            // Copy data into each individual _SDReadOp
            for (_SDReadOp& work : coalesced.works) {
                const uint8_t* d = data.get() + (size_t)(work.block-coalesced.blockBegin)*SD::BlockLen;
                work.data = std::make_unique<uint8_t[]>(work.len);
                memcpy(work.data.get(), d, work.len);
            }
        }
        
        // Move each _SDReadOp into status.work and send signal
        {
            {
                auto lock = status.signal.lock();
                for (_SDReadOp& work : coalesced.works) {
                    status.done.push_back(std::move(work));
                }
            }
            status.signal.signalOne();
        }
    }
    
    void _sdRead_thread() {
        try {
            for (;;) {
                _SDCoalescedOps coalesced;
                {
                    // Wait for work
                    _SDWorkQueue* queue = nullptr;
                    auto lock = _sdRead.signal.wait([&] { return (queue = _sdRead_nextWorkQueue()); });
                    coalesced = _SDRead_CoalesceWork(*queue);
                }
                _sdRead_handleWork(coalesced);
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            fprintf(stderr, "_sdRead_thread stopping\n");
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
                auto lock = _thumbRender.signal.wait([&] { return !_thumbRender.work.empty(); });
                    _ThumbRenderWork work = std::move(_thumbRender.work.front());
                    _thumbRender.work.pop();
                lock.unlock();
                
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
                        rec.info.flags          = ImageFlags::Loaded;
                        
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
                
                // Move the _ThumbRenderWork to the .done vector and send signal
                {
                    auto lock = work.status.signal.lock();
                    work.status.done.push_back(std::move(work));
                    work.status.signal.signalOne();
                }
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            fprintf(stderr, "_thumbRender_thread stopping\n");
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
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        _LoadImagesState loadImages;
    } _sync;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        std::set<ImageRecordPtr> work;
        _LoadImagesState loadImages;
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

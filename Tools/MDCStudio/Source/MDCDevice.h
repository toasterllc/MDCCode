#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <set>
#import <array>
#import <chrono>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Toastbox/Mmap.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/TimeConvert.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Code/Shared/BufQueue.h"
#import "Code/Shared/Util.h"
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
        _sync.thread = std::thread([&] { _sync_thread(); });
        _renderThumbs.thread = std::thread([&] { _renderThumbs_thread(); });
        _sdReadProduce.thread = std::thread([&] { _sdRead_thread(); });
    }
    
    ~MDCDevice() {
        _sync.thread.join();
        
        // Wait for _renderThumbs.thread to exit
        {
            auto lock = std::unique_lock(_renderThumbs.lock);
            _renderThumbs.stop = true;
        }
        _renderThumbs.signal.notify_one();
        _renderThumbs.thread.join();
        
        // Wait for _sdReadProduce.thread to exit
        {
            auto lock = std::unique_lock(_sdReadProduce.lock);
            // Upon our destruction, there shouldn't be any work to do, because whatever was
            // scheduling work should've ensured that we'd stay alive. Check that assumption.
            assert(!_sdRead_nextWorkQueue());
            _sdReadProduce.stop = true;
        }
        _sdReadProduce.signal.notify_one();
        _sdReadProduce.thread.join();
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
    
    void renderThumbs(ImageRecordIter begin, ImageRecordIter end) override {
        bool enqueued = false;
        {
            auto lock = std::unique_lock(_renderThumbs.lock);
            for (auto it=begin; it!=end; it++) {
                ImageRecordPtr ref = *it;
                if (ref->options.thumb.render) {
                    ref->options.thumb.render = false;
                    _renderThumbs.work.insert(ref);
                    enqueued = true;
                }
            }
        }
        if (enqueued) _renderThumbs.signal.notify_one();
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
    
    struct _Range {
        uint32_t idx  = 0;
        uint32_t len = 0;
    };
    
    template <size_t T_BufCap>
    class _BufQueue {
    public:
        auto& rget() {
            auto lock = std::unique_lock(_lock);
            while (!_bufs.rok()) _signal.wait(lock);
            return _bufs.rget();
        }
        
        void rpop() {
            auto lock = std::unique_lock(_lock);
            _bufs.rpop();
            _signal.notify_all();
        }
        
        auto& wget() {
            auto lock = std::unique_lock(_lock);
            while (!_bufs.wok()) _signal.wait(lock);
            return _bufs.wget();
        }
        
        void wpush() {
            auto lock = std::unique_lock(_lock);
            _bufs.wpush();
            _signal.notify_all();
        }
        
    private:
        std::mutex _lock;
        std::condition_variable _signal;
        BufQueue<uint8_t, T_BufCap, 2> _bufs;
    };
    
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
    
//    static MSP::Time _MSPTimeCurrent() {
//        return MSP::TimeFromUnixTime(std::time(nullptr));
//        const std::time_t t = std::time(nullptr);
//        return MSP::TimeAbsoluteBase | (t-MSP::TimeAbsoluteUnixReference);
//    }
    
    ImageCache::ImageProvider _imageProvider() {
        return [&] (uint64_t addr) -> ImagePtr {
            return _imageForAddr(addr);
        };
    }
    
    ImagePtr _imageForAddr(uint64_t addr) {
        auto data = std::make_unique<uint8_t[]>(Img::Full::ImageLen);
        _sdRead(_SDReadWork::Priority::Low, (_SDBlock)addr, Img::Full::ImageLen, data.get());
        
        if (_ImageChecksumValid(data.get(), Img::Size::Full)) {
//            printf("Checksum valid (size: full)\n");
        } else {
            printf("Checksum INVALID (size: full)\n");
//            abort();
        }
        
        const Img::Header& header = *(const Img::Header*)data.get();
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
    
    // MARK: - Sync
    
    void _sync_thread() {
        try {
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(_mspState);
            const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
            const Img::Id deviceImgIdEnd = imgRingBuf.buf.idEnd;
            
            {
                // Remove images from beginning of library: lib has, device doesn't
                {
                    auto lock = std::unique_lock(_imageLibrary);
                    
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
                    Img::Id libImgIdEnd = 0;
                    {
                        auto lock = std::unique_lock(_imageLibrary);
                        libImgIdEnd = _imageLibrary.deviceImgIdEnd();
                    }
                    
                    if (libImgIdEnd > deviceImgIdEnd) {
                        throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                            (uintmax_t)libImgIdEnd,
                            (uintmax_t)deviceImgIdEnd
                        );
                    }
                    
                    const uint32_t addCount = 1024;//(uint32_t)(deviceImgIdEnd - std::max(deviceImgIdBegin, libImgIdEnd));
                    printf("Adding %ju images\n", (uintmax_t)addCount);
                    
                    _Range newest;
                    newest.idx = imgRingBuf.buf.widx - std::min((uint32_t)imgRingBuf.buf.widx, addCount);
                    newest.len = imgRingBuf.buf.widx - newest.idx;
                    
                    _Range oldest;
                    oldest.len = addCount - newest.len;
                    oldest.idx = _mspState.sd.imgCap - oldest.len;
                    
                    _sync_loadImages(oldest);
                    _sync_loadImages(newest);
                }
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    void _sync_loadImages(const _Range& range) {
        using namespace MDCTools;
        if (!range.len) return; // Short-circuit if there are no images to read in this range
        
        constexpr size_t ChunkImgCount = 128; // Number of images to read at a time
        constexpr size_t BufCap = ChunkImgCount * ImgSD::Thumb::ImagePaddedLen;
        auto bufQueuePtr = std::make_unique<_BufQueue<BufCap>>();
        auto& bufQueue = *bufQueuePtr;
        const _SDBlock fullBlockStart = range.idx * ImgSD::Full::ImageBlockCount;
        const _SDBlock thumbBlockStart = _mspState.sd.thumbBlockStart + (range.idx * ImgSD::Thumb::ImageBlockCount);
        
        // Consumer
        std::thread consumerThread([&] {
            constexpr size_t WriteInterval = ChunkImgCount*8;
            _SDBlock block = fullBlockStart;
            size_t addedImageCount = 0;
            
            for (;;) @autoreleasepool {
                auto startTime = std::chrono::steady_clock::now();
                
                const auto& buf = bufQueue.rget();
                const size_t imageCount = buf.len;
                if (!imageCount) break; // We're done when we get an empty buffer
                _sync_addImages(buf.data, imageCount, block);
                
                block += imageCount * ImgSD::Full::ImageBlockCount;
                addedImageCount += imageCount;
                bufQueue.rpop();
                
                auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
                printf("Consumer took %ju ms for %ju images (avg %f ms / img)\n", (uintmax_t)durationMs, (uintmax_t)imageCount, ((double)durationMs/imageCount));
                
                // Periodically write the library
                if (!(addedImageCount % WriteInterval)) {
                    auto lock = std::unique_lock(_imageLibrary);
                    printf("Writing library (%ju images)\n", (uintmax_t)_imageLibrary.recordCount());
                    _imageLibrary.write();
                }
            }
            
            // Write the library
            {
                auto lock = std::unique_lock(_imageLibrary);
                printf("Writing library (%ju images)\n", (uintmax_t)_imageLibrary.recordCount());
                _imageLibrary.write();
            }
        });
        
        // Producer
        for (size_t i=0; i<range.len;) {
            auto startTime = std::chrono::steady_clock::now();
            
            const size_t chunkImgCount = std::min(ChunkImgCount, range.len-i);
            auto& buf = bufQueue.wget();
            buf.len = chunkImgCount; // buffer length = count of images (not byte count)
            _sdRead(_SDReadWork::Priority::Low, thumbBlockStart, chunkImgCount*ImgSD::Thumb::ImagePaddedLen, buf.data);
            bufQueue.wpush();
            i += chunkImgCount;
            
            auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
            printf("Read %ju images (took %ju ms)\n", (uintmax_t)chunkImgCount, (uintmax_t)durationMs);
        }
        
        // Wait until we're complete
        {
            // Tell consumerThread to bail by sending an empty buf
            auto& buf = bufQueue.wget();
            buf.len = 0;
            bufQueue.wpush();
            // Wait for thread to exit...
            consumerThread.join();
        }
    }
    
    static constexpr size_t _ThumbTmpStorageLen = ImageThumb::ThumbWidth * ImageThumb::ThumbWidth * 4;
    using _ThumbTmpStorage = std::array<uint8_t, _ThumbTmpStorageLen>;
    
    static CCM _ThumbRender(MDCTools::Renderer& renderer, _ThumbCompressor& compressor, _ThumbTmpStorage& tmpStorage,
        const std::optional<CCM>& ccmOpt, const void* src, void* dst) {
        
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
                .illum          = (ccmOpt ? std::optional<ColorRaw>(ccmOpt->illum) : std::nullopt),
                .debayerLMMSE   = { .applyGamma = true, },
            };
            
            const Pipeline::DebayerResult debayerResult = Pipeline::Debayer(renderer, debayerOpts, rawTxt, rgbTxt);
            
            ccm = {
                .illum = (ccmOpt ? ccmOpt->illum : debayerResult.illum),
                .matrix = (ccmOpt ? ccmOpt->matrix : ColorMatrixForIlluminant(debayerResult.illum).matrix)
            };
            
            const Pipeline::ProcessOptions processOpts = {
                .illum = ccm.illum,
                .colorMatrix = ccm.matrix,
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
    
    
    void _sync_addImages(const uint8_t* data, size_t imgCount, _SDBlock block) {
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        using namespace Toastbox;
        
        // Reserve space for `imgCount` additional images
        {
            auto lock = std::unique_lock(_imageLibrary);
            _imageLibrary.reserve(imgCount);
        }
        
        #warning TODO: perf: in the future we could ensure that our `data` argument is mmap'd and
        #warning             use -newBufferWithBytesNoCopy: to avoid creating a bunch of temporary buffers
        auto thumbTxts = std::make_unique<id<MTLTexture>[]>(imgCount);
        {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
            
            std::vector<std::thread> workers;
            std::atomic<size_t> workIdx = 0;
            const uint32_t threadCount = std::max(1,(int)std::thread::hardware_concurrency());
            for (uint32_t i=0; i<threadCount; i++) {
                workers.emplace_back([&](){
                    Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
                    _ThumbCompressor compressor;
                    std::unique_ptr<_ThumbTmpStorage> thumbTmpStorage = std::make_unique<_ThumbTmpStorage>();
                    std::vector<Renderer::Txt> txts;
                    
                    for (;;) {
                        const size_t idx = workIdx.fetch_add(1);
                        if (idx >= imgCount) break;
                        
                        const uint8_t* imgData = data+idx*ImgSD::Thumb::ImagePaddedLen;
                        const Img::Header& imgHeader = *(const Img::Header*)imgData;
                        
                        // Accessing `_imageLibrary` without a lock because we're the only entity using the image library's reserved space
                        const auto recordRefIter = _imageLibrary.reservedBegin()+idx;
                        ImageRecord& rec = **recordRefIter;
                        
                        // Validate thumbnail checksum
                        if (_ImageChecksumValid(imgData, Img::Size::Thumb)) {
                            printf("Checksum valid (size: thumb)\n");
                        } else {
                            printf("Invalid checksum\n");
//                            throw Toastbox::RuntimeError("invalid checksum");
//                            abort();
//                            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
                        }
                        
                        // Populate .info
                        {
                            rec.info.id              = imgHeader.id;
                            rec.info.addr            = block;
                            
                            rec.info.timestamp       = imgHeader.timestamp;
                            
                            rec.info.imageWidth      = imgHeader.imageWidth;
                            rec.info.imageHeight     = imgHeader.imageHeight;
                            
                            rec.info.coarseIntTime   = imgHeader.coarseIntTime;
                            rec.info.analogGain      = imgHeader.analogGain;
                            
                            block += ImgSD::Full::ImageBlockCount;
                        }
                        
                        // Populate .options
                        {
                            rec.options = {};
                        }
                        
                        // Render the thumbnail into rec.thumb
                        {
                            const void* src = imgData+Img::PixelsOffset;
                            void* dst = rec.thumb.data;
                            const CCM ccm = _ThumbRender(renderer, compressor, *thumbTmpStorage, std::nullopt, src, dst);
                            
                            // Populate .info.illumEst
                            ccm.illum.m.get(rec.info.illumEst);
                            
                            // Populate .options.whiteBalance
                            ImageWhiteBalanceSet(rec.options.whiteBalance, true, 0, ccm);
                        }
                    }
                });
            }
            
            // Wait for workers to complete
            for (std::thread& t : workers) t.join();
        }
        
        {
            const Img::Id deviceImgIdLast = _imageLibrary.reservedBack()->info.id;
            auto lock = std::unique_lock(_imageLibrary);
            // Add the records that we previously reserved
            _imageLibrary.add();
            // Update the device's image id 'end' == last image id that we've observed from the device +1
            _imageLibrary.deviceImgIdEnd(deviceImgIdLast+1);
        }
    }
    
    // MARK: - Render Thumbs
    
    void _renderThumbs_thread() {
        using namespace MDCStudio;
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
        _ThumbCompressor compressor;
        auto thumbData = std::make_unique<uint8_t[]>(ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4);
        
        for (;;) @autoreleasepool {
            std::set<ImageRecordPtr> work;
            {
                auto lock = std::unique_lock(_renderThumbs.lock);
                // Wait for work, or to be signalled to stop
                _renderThumbs.signal.wait(lock, [&] { return !_renderThumbs.work.empty() || _renderThumbs.stop; });
                if (_renderThumbs.stop) return;
                work = std::move(_renderThumbs.work);
            }
            
            // Render thumbnails
            {
            }
            
            // Notify image library that the images changed
            {
                auto lock = std::unique_lock(_imageLibrary);
                _imageLibrary.notifyChange(work);
            }
        }
    }
    
    // MARK: - SDRead
    
    struct _SDReadWork {
        enum Priority : uint8_t { High, Low, Count };
        
        enum class Status {
            Underway,
            Finished,
            Error,
        };
        
        _SDBlock block = 0;
        size_t len = 0;
        void* dst = nullptr;
        std::shared_ptr<Status> status = std::make_shared<Status>(Status::Underway);
        
        bool operator<(const _SDReadWork& x) const {
            if (block != x.block) return block < x.block;
            if (len != x.len) return len < x.len;
            if (status != x.status) return (uintptr_t)status.get() < (uintptr_t)x.status.get();
            return false;
        }
        
        bool operator==(const _SDReadWork& x) const {
            if (block != x.block) return false;
            if (len != x.len) return false;
            if (status.get() != x.status.get()) return false;
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
    
    static constexpr _SDBlock _SDBlockEnd(_SDBlock block, size_t len) {
        const _SDBlock blockLen = Util::DivCeil((_SDBlock)len, (_SDBlock)SD::BlockLen);
        // Verify that block+blockLen doesn't overflow _SDBlock
        assert(std::numeric_limits<_SDBlock>::max()-block >= blockLen);
        return block + blockLen;
    }
    
    void _sdRead(_SDReadWork::Priority priority, _SDBlock block, size_t len, void* dst) {
        const _SDReadWork work = {
            .block = block,
            .len = len,
            .dst = dst,
        };
        
        // Enqueue the work
        {
            {
                auto lock = std::unique_lock(_sdReadProduce.lock);
                _SDReadWorkQueue& queue = _sdReadProduce.queues[priority];
                queue.set.insert(work);
            }
            _sdReadProduce.signal.notify_one();
        }
        
        // Wait for the work to be completed
        {
            auto lock = std::unique_lock(_sdReadConsume.lock);
            _sdReadConsume.signal.wait(lock, [&] { return *work.status!=_SDReadWork::Status::Underway; });
            if (*work.status != _SDReadWork::Status::Finished) {
                throw Toastbox::RuntimeError("SDRead failed; status: %d", (int)*work.status);
            }
        }
    }
    
    // _sdReadProduce.lock must be held!
    _SDReadWorkQueue* _sdRead_nextWorkQueue() {
        for (_SDReadWorkQueue& x : _sdReadProduce.queues) {
            if (!x.set.empty()) return &x;
        }
        return nullptr;
    }
    
    // _sdReadProduce.lock must be held!
    _SDCoalescedWork _sdRead_coalesceWork(_SDReadWorkQueue& queue) {
        assert(!queue.set.empty());
        
        // CoalesceBudget: coalesce adjacent blocks until this budget is exceeded
        static constexpr _SDBlock CoalesceBudget = 8192;
        _SDCoalescedWork coalesced = {
            .blockBegin = queue.set.begin()->block,
            .blockEnd   = _SDBlockEnd(queue.set.begin()->block, queue.set.begin()->len),
        };
        _SDBlock budget = CoalesceBudget;
        for (auto it=queue.set.begin(); it!=queue.set.end();) {
            const _SDReadWork& work = *it;
            const _SDBlock workBlockBegin = work.block;
            const _SDBlock workBlockEnd = _SDBlockEnd(workBlockBegin, work.len);
            
            // The queue.set ordering guarantees that the blockBegins are in ascending order.
            // Check that assumption.
            assert(coalesced.blockBegin <= work.block);
            
            const _SDBlock cost = (workBlockEnd>coalesced.blockEnd ? workBlockEnd-coalesced.blockEnd : 0);
            // Stop coalescing work once the cost exceeds our budget
            if (cost > budget) break;
            
            coalesced.blockEnd = std::max(coalesced.blockEnd, workBlockEnd);
            coalesced.works.push_back(work);
            budget -= cost;
            it = queue.set.erase(it);
        }
        return coalesced;
    }
    
    void _sdRead_handleWork(const _SDCoalescedWork& coalesced) {
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
        
        // Copy the data into each work
        for (const _SDReadWork& work : coalesced.works) {
            const uint8_t* d = data.get() + (size_t)(work.block-coalesced.blockBegin)*SD::BlockLen;
            memcpy(work.dst, d, work.len);
            
            {
                auto lock = std::unique_lock(_sdReadConsume.lock);
                *work.status = _SDReadWork::Status::Finished;
            }
        }
        
        // Notify the works that they're done
        _sdReadConsume.signal.notify_all();
    }
    
    void _sdRead_thread() {
        for (;;) {
            _SDCoalescedWork coalesced;
            {
                auto lock = std::unique_lock(_sdReadProduce.lock);
                // Wait for work, or to be signalled to stop
                _SDReadWorkQueue* queue = nullptr;
                _sdReadProduce.signal.wait(lock, [&] { queue = _sdRead_nextWorkQueue(); return (queue || _sdReadProduce.stop); });
                if (_sdReadProduce.stop) return;
                coalesced = _sdRead_coalesceWork(*queue);
            }
            _sdRead_handleWork(coalesced);
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
        std::thread thread;
    } _sync;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        std::thread thread;
        bool stop = false;
        std::set<ImageRecordPtr> work;
    } _renderThumbs;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        std::thread thread;
        bool stop = false;
        _SDReadWorkQueue queues[_SDReadWork::Priority::Count];
    } _sdReadProduce;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
    } _sdReadConsume;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

} // namespace MDCStudio

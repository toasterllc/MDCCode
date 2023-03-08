#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <chrono>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Toastbox/Mmap.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/TimeConvert.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Code/Shared/BufQueue.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/BC7Encoder.h"
#import "ImageLibrary.h"
#import "ImageCache.h"
#import "ImageSource.h"

namespace MDCStudio {

class MDCDevice : public std::enable_shared_from_this<MDCDevice>, public ImageSource {
private:
    using _ThumbCompressor = BC7Encoder<ImageThumb::ThumbWidth, ImageThumb::ThumbHeight>;
    
public:
    using Observer = std::function<bool()>;
    
    MDCDevice(MDCUSBDevice&& dev) :
    _dev(std::make_shared<MDCTools::Lockable<MDCUSBDevice>>(std::move(dev))),
    _dir(_DirForSerial(_dev->serial())),
    _imageLibrary(std::make_shared<MDCTools::Lockable<ImageLibrary>>(_dir / "ImageLibrary")) {
    
        auto lock = std::unique_lock(_state.lock);
        
        printf("MDCDevice()\n");
        
        // Give device a default name
        char name[256];
        snprintf(name, sizeof(name), "MDC Device %s", _dev->serial().c_str());
        _state.name = std::string(name);
        
        // Read state from disk
        try {
            _SerializedState state = _SerializedStateRead(_dir);
            _state.name = std::string(state.name);
        } catch (const std::exception& e) {}
        
        // Perform device IO
        {
            auto lock = std::unique_lock(*_dev);
            
            // Update our _mspState from the device
            _mspState = _dev->mspStateRead();
            
            // Enter host mode
            _dev->mspHostModeSet(true);
            
            // Update the device's time
            {
                using namespace std::chrono;
                using namespace date;
                
                const Time::Instant mdcTime = _dev->mspTimeGet();
                const Time::Instant actualTime = Time::Current();
                
                auto startTime = steady_clock::now();
                _dev->mspTimeSet(actualTime);
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
            
            
//            
//            sleep(15);
            
//            // Update device time
//            {
//                _dev->mspSBWConnect();
//                _dev->mspSBWRead(MSP::StateAddr, &_mspState, sizeof(_mspState));
//                
//                if (_mspState.magic != MSP::State::MagicNumber) {
//                    // Program MSPApp onto MSP
//                    #warning TODO: implement
//                    throw Toastbox::RuntimeError("TODO: _mspState.magic != MSP::State::MagicNumber");
//                }
//                
//                if (_mspState.version > MSP::State::Version) {
//                    // Newer version than we understand -- tell user to upgrade or re-program
//                    #warning TODO: implement
//                    throw Toastbox::RuntimeError("TODO: _mspState.version > MSP::State::Version");
//                }
//                
//                _mspState.startTime.time = MSP::TimeFromUnixTime(std::time(nullptr));
//                _mspState.startTime.valid = true;
//                _dev->mspSBWWrite(MSP::StateAddr, &_mspState, sizeof(_mspState));
//                
//                // MSPHostMode=true: make MSP enter host mode until physically disconnected from USB.
//                // (When USB is disconnected, STM will lose power, causing STM to stop asserting
//                // MSP_HOST_MODE_, allowing MSP_HOST_MODE_ to be pulled high by MSP's pullup, thereby
//                // allowing MSP to run again.)
//                constexpr bool MSPHostMode = true;
//                
//                startTime = std::chrono::steady_clock::now();
//                _dev->mspSBWDisconnect(MSPHostMode);
//            }
            
//            usleep(180000);
            
//            exit(0);
            
//            auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//            printf("durationMs: %ju\n", (uintmax_t)durationMs);
            
            // Load ICE40 with our app
            _ICEConfigure(*_dev);
            
            // Init SD card
            #warning TODO: how should we handle sdInit() failing (throwing)?
            _sdCardInfo = _dev->sdInit();
            
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
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->read();
        }
        
        // Start updating image library
        _state.updateImageLibraryThread = std::thread([this] { _threadUpdateImageLibrary(); });
        _state.updateImageLibraryThread.detach();
    }
    
    ~MDCDevice() {
        auto lock = std::unique_lock(_state.lock);
        #warning TODO: this will deadlock if the thread tries to acquire the lock...
        if (_state.updateImageLibraryThread.joinable()) {
            _state.updateImageLibraryThread.join();
        }
    }
    
    const std::string& name() {
        auto lock = std::unique_lock(_state.lock);
        return _state.name;
    }
    
    void setName(const std::string_view& name) {
        auto lock = std::unique_lock(_state.lock);
        _state.name = name;
        _write();
        _notifyObservers();
    }
    
    MDCUSBDevicePtr device() { return _dev; }
    
    void observerAdd(Observer&& observer) {
        auto lock = std::unique_lock(_state.lock);
        _state.observers.push_front(std::move(observer));
    }
    
    void write() {
        auto lock = std::unique_lock(_state.lock);
        _write();
    }
    
    // MARK: - ImageSource Functions
    
    ImageLibraryPtr imageLibrary() override { return _imageLibrary; }
    
    ImageCachePtr imageCache() override {
        // We're implementing this lazily because shared_from_this()
        // can't be called from the constructor
        auto lock = std::unique_lock(_state.lock);
        if (!_state.imageCache) {
            std::weak_ptr<MDCDevice> weakThis = shared_from_this();
            ImageCache::ImageProvider imageProvider = [=] (uint64_t addr) -> ImagePtr {
                auto strongThis = weakThis.lock();
                if (!strongThis) return nullptr;
                return strongThis->_imageProvider(addr);
            };
            
            _state.imageCache = std::make_shared<ImageCache>(_imageLibrary, std::move(imageProvider));
        }
        return _state.imageCache;
    }
    
    void renderThumbs(ImageRecordIter begin, ImageRecordIter end) override {
        printf("renderThumbs %zu\n", end-begin);
    }
    
private:
    // MARK: - Private
    
    using _Path = std::filesystem::path;
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
    
//    static MSP::Time _MSPTimeCurrent() {
//        return MSP::TimeFromUnixTime(std::time(nullptr));
//        const std::time_t t = std::time(nullptr);
//        return MSP::TimeAbsoluteBase | (t-MSP::TimeAbsoluteUnixReference);
//    }
    
    ImagePtr _imageProvider(uint64_t addr) {
        // Lock the device for the duration of this function
        auto lock = std::unique_lock(*_dev);
        
        auto imageData = std::make_unique<uint8_t[]>(ImgSD::Full::ImagePaddedLen);
        _dev->reset();
        _dev->sdRead((SD::Block)addr);
        _dev->readout(imageData.get(), ImgSD::Full::ImagePaddedLen);
        
        if (_ChecksumValid(imageData.get(), Img::Size::Full)) {
//            printf("Checksum valid (size: full)\n");
        } else {
            printf("Checksum INVALID (size: full)\n");
//            abort();
        }
        
//        // Validate checksum
//        const size_t checksumOffset = (size==Img::Size::Full ? Img::Full::ChecksumOffset : Img::Thumb::ChecksumOffset);
//        const uint32_t checksumExpected = ChecksumFletcher32(buf.get(), checksumOffset);
//        uint32_t checksumGot = 0;
//        memcpy(&checksumGot, (uint8_t*)buf.get()+checksumOffset, Img::ChecksumLen);
//        if (checksumGot != checksumExpected) {
//            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
//        }
        
        const Img::Header& header = *(const Img::Header*)imageData.get();
        ImagePtr image = std::make_shared<Image>(Image{
            .width      = header.imageWidth,
            .height     = header.imageHeight,
            .cfaDesc    = _CFADesc,
            .data       = std::move(imageData),
            .off        = sizeof(header),
        });
        return image;
    }
    
    // _state.lock must be held
    void _write() {
        _SerializedState state;
        state.version = _Version;
        // Copy UTF8 device name into state.name
        // state.name is initialized with zeroes, so we don't need to explicitly set a
        // null byte, but we do need to limit the number of copied bytes to
        // `sizeof(state.name)-1` to ensure that the null byte isn't overwritten
        _state.name.copy(state.name, sizeof(state.name)-1);
        
        _SerializedStateWrite(_dir, state);
    }
    
    void _threadUpdateImageLibrary() {
        try {
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(_mspState);
            const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
            const Img::Id deviceImgIdEnd = imgRingBuf.buf.idEnd;
            
            {
                // Remove images from beginning of library: lib has, device doesn't
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    
                    const auto removeBegin = _imageLibrary->begin();
                    
                    // Find the first image >= `deviceImgIdBegin`
                    const auto removeEnd = std::lower_bound(_imageLibrary->begin(), _imageLibrary->end(), 0,
                        [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                            return sample->info.id < deviceImgIdBegin;
                        });
                    
                    printf("Removing %ju images\n", (uintmax_t)std::distance(removeBegin, removeEnd));
                    _imageLibrary->remove(removeBegin, removeEnd);
                }
                
                // Add images to end of library: device has, lib doesn't
                {
                    Img::Id libImgIdEnd = 0;
                    {
                        auto lock = std::unique_lock(*_imageLibrary);
                        libImgIdEnd = _imageLibrary->deviceImgIdEnd();
                    }
                    
                    if (libImgIdEnd > deviceImgIdEnd) {
                        throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                            (uintmax_t)libImgIdEnd,
                            (uintmax_t)deviceImgIdEnd
                        );
                    }
                    
                    const uint32_t addCount = (uint32_t)(deviceImgIdEnd - std::max(deviceImgIdBegin, libImgIdEnd));
                    printf("Adding %ju images\n", (uintmax_t)addCount);
                    
                    _Range newest;
                    newest.idx = imgRingBuf.buf.widx - std::min((uint32_t)imgRingBuf.buf.widx, addCount);
                    newest.len = imgRingBuf.buf.widx - newest.idx;
                    
                    _Range oldest;
                    oldest.len = addCount - newest.len;
                    oldest.idx = _mspState.sd.imgCap - oldest.len;
                    
                    _loadImages(oldest);
                    _loadImages(newest);
                }
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    void _loadImages(const _Range& range) {
        using namespace MDCTools;
        if (!range.len) return; // Short-circuit if there are no images to read in this range
        
        // Lock the device for the duration of this function
        auto lock = std::unique_lock(*_dev);
        
        constexpr size_t ChunkImgCount = 128; // Number of images to read at a time
        constexpr size_t BufCap = ChunkImgCount * ImgSD::Thumb::ImagePaddedLen;
        auto bufQueuePtr = std::make_unique<_BufQueue<BufCap>>();
        auto& bufQueue = *bufQueuePtr;
        const SD::Block fullBlockStart = range.idx * ImgSD::Full::ImageBlockCount;
        const SD::Block thumbBlockStart = _mspState.sd.thumbBlockStart + (range.idx * ImgSD::Thumb::ImageBlockCount);
        
        _dev->reset();
        _dev->sdRead(thumbBlockStart);
        
        // Consumer
        std::thread consumerThread([&] {
            constexpr size_t WriteInterval = ChunkImgCount*8;
            SD::Block block = fullBlockStart;
            size_t addedImageCount = 0;
            
            for (;;) @autoreleasepool {
                const auto& buf = bufQueue.rget();
                
                auto startTime = std::chrono::steady_clock::now();
                const size_t imageCount = buf.len;
                if (!imageCount) break; // We're done when we get an empty buffer
                _addImages(buf.data, imageCount, block);
                
                block += imageCount * ImgSD::Full::ImageBlockCount;
                addedImageCount += imageCount;
                
                bufQueue.rpop();
                
                auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
                printf("Consumer took %ju ms for %ju images (avg %f ms / img)\n", (uintmax_t)durationMs, (uintmax_t)imageCount, ((double)durationMs/imageCount));
                
                // Periodically write the library
                if (!(addedImageCount % WriteInterval)) {
                    auto lock = std::unique_lock(*_imageLibrary);
                    printf("Writing library (%ju images)\n", (uintmax_t)_imageLibrary->recordCount());
                    _imageLibrary->write();
                }
            }
            
            // Write the library
            {
                auto lock = std::unique_lock(*_imageLibrary);
                printf("Writing library (%ju images)\n", (uintmax_t)_imageLibrary->recordCount());
                _imageLibrary->write();
            }
        });
        
        // Producer
        for (size_t i=0; i<range.len;) {
            const size_t chunkImgCount = std::min(ChunkImgCount, range.len-i);
            auto& buf = bufQueue.wget();
            buf.len = chunkImgCount; // buffer length = count of images (not byte count)
            _dev->readout(buf.data, chunkImgCount*ImgSD::Thumb::ImagePaddedLen);
            bufQueue.wpush();
            i += chunkImgCount;
            
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch());
            printf("Read %ju images (ms: %ju)\n", (uintmax_t)chunkImgCount, (uintmax_t)ms.count());
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
    
    static bool _ChecksumValid(const void* data, Img::Size size) {
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
    
    void _addImages(const uint8_t* data, size_t imgCount, SD::Block block) {
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        using namespace Toastbox;
        
        // Reserve space for `imgCount` additional images
        {
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->reserve(imgCount);
        }
        
        const ImageLibrary::Chunk* chunkPrev = nullptr;
        
        #warning TODO: perf: in the future we could ensure that our `data` argument is mmap'd and
        #warning             use -newBufferWithBytesNoCopy: to avoid creating a bunch of temporary buffers
        auto thumbTxts = std::make_unique<id<MTLTexture>[]>(imgCount);
        {
            std::vector<std::thread> workers;
            std::atomic<size_t> workIdx = 0;
            for (int i=0; i<std::max(1,(int)std::thread::hardware_concurrency()); i++) {
                workers.emplace_back([&](){
                    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
                    if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
                    Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
                    std::vector<Renderer::Txt> txts;
                    
                    for (;;) {
                        const size_t idx = workIdx.fetch_add(1);
                        if (idx >= imgCount) break;
                        
                        const uint8_t* imgData = data+idx*ImgSD::Thumb::ImagePaddedLen;
                        const Img::Header& imgHeader = *(const Img::Header*)imgData;
                        
                        // Accessing `_imageLibrary` without a lock because we're the only entity using the image library's reserved space
                        const auto recordRefIter = _imageLibrary->reservedBegin()+idx;
                        ImageRecord& rec = **recordRefIter;
                        
                        // Validate thumbnail checksum
                        if (_ChecksumValid(imgData, Img::Size::Thumb)) {
                            printf("Checksum valid (size: thumb)\n");
                        } else {
                            printf("Invalid checksum\n");
            //                throw Toastbox::RuntimeError("invalid checksum");
            //                abort();
            //                throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
                        }
                        
                        // Populate ImageInfo fields
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
                        
                        // Render the thumbnail into rec.thumb
                        {
                            const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
                            
                            Pipeline::RawImage rawImage = {
                                .cfaDesc = _CFADesc,
                                .width = Img::Thumb::PixelWidth,
                                .height = Img::Thumb::PixelHeight,
                                .pixels = (ImagePixel*)(imgData+Img::PixelsOffset),
                            };
                            
            //                const Color<MDCTools::ColorSpace::Raw> illum(0.879884, 0.901580, 0.341031);
            //                const Mat<double,3,3> colorMatrix(
            //                    +0.626076, +0.128755, +0.245169,
            //                    -0.396581, +1.438671, -0.042090,
            //                    -0.195309, -0.784350, +1.979659
            //                );
                            
                            const Pipeline::Options pipelineOpts = {
            //                    .illum = illum,
            //                    .colorMatrix = colorMatrix,
            //                    .reconstructHighlights  = { .en = true, },
                                .debayerLMMSE           = { .applyGamma = true, },
                            };
                            
                            constexpr MTLTextureUsage ThumbTxtUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
                            Renderer::Txt& thumbTxt = txts.emplace_back(renderer.textureCreate(MTLPixelFormatRGBA8Unorm,
                                ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, ThumbTxtUsage));
                            thumbTxts[idx] = thumbTxt;
                            
                            Pipeline::Result renderResult = Pipeline::Run(renderer, pipelineOpts, rawImage, thumbTxt);
                            renderer.sync(thumbTxt);
                            
                            
                            
            //                const size_t thumbDataOff = (uintptr_t)&rec.thumb - (uintptr_t)chunk.mmap.data();
            //                
            //                if (&chunk != chunkPrev) {
            //                    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
            //                    chunkBuf = [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data() length:Mmap::PageCeil(chunk.mmap.len()) options:BufOpts deallocator:nil];
            //                }
            //                
            //                const RenderThumb::Options thumbOpts = {
            //                    .thumbWidth = ImageThumb::ThumbWidth,
            //                    .thumbHeight = ImageThumb::ThumbHeight,
            //                    .dataOff = thumbDataOff,
            //                };
            //                
            //                RenderThumb::RGB3FromTexture(renderer, thumbOpts, renderResult.txt, chunkBuf);
                            
                            // Populate the illuminant (ImageRecord.info.illumEst)
                            rec.info.illumEst[0] = renderResult.illum[0];
                            rec.info.illumEst[1] = renderResult.illum[1];
                            rec.info.illumEst[2] = renderResult.illum[2];
                            
                            chunkPrev = &chunk;
                        }
                        
                        // Populate ImageOptions fields
                        {
                            rec.options = {};
                            // Set image white balance options
                            const simd::float3 illum = { rec.info.illumEst[0], rec.info.illumEst[1], rec.info.illumEst[2] };
                            ImageWhiteBalanceSetAuto(rec.options.whiteBalance, illum);
                        }
                    }
                    
                    renderer.commitAndWait();
                });
            }
            
            // Wait for workers to complete
            for (std::thread& t : workers) t.join();
        }
        
        // Compress each thumbnail and copy the compressed data into the respective ImageRecord
        // Spawn N worker threads (N=number of cores) to do the work in parallel
        // The work is complete when all threads have exited
        {
            std::vector<std::thread> workers;
            std::atomic<size_t> workIdx = 0;
            for (int i=0; i<std::max(1,(int)std::thread::hardware_concurrency()); i++) {
                workers.emplace_back([&](){
                    _ThumbCompressor compressor;
                    auto thumbData = std::make_unique<uint8_t[]>(ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4);
                    
                    for (;;) {
                        const size_t idx = workIdx.fetch_add(1);
                        if (idx >= imgCount) break;
                        
                        const auto recordRefIter = _imageLibrary->reservedBegin()+idx;
                        id<MTLTexture> thumbTxt = thumbTxts[idx];
                        ImageRecord& rec = **recordRefIter;
                        
                        [thumbTxt getBytes:thumbData.get() bytesPerRow:ImageThumb::ThumbWidth*4
                            fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
                        
                        compressor.encode(thumbData.get(), rec.thumb.data);
                    }
                });
            }
            
            // Wait for workers to complete
            for (std::thread& t : workers) t.join();
        }
        
        {
            
            const Img::Id deviceImgIdLast = (*_imageLibrary->reservedBack()).info.id;
            auto lock = std::unique_lock(*_imageLibrary);
            // Add the records that we previously reserved
            _imageLibrary->add();
            // Update the device's image id 'end' == last image id that we've observed from the device +1
            _imageLibrary->deviceImgIdEnd(deviceImgIdLast+1);
        }
    }
    
    // _state.lock must be held
    void _notifyObservers() {
        auto prev = _state.observers.before_begin();
        for (auto it=_state.observers.begin(); it!=_state.observers.end();) {
            // Notify the observer; it returns whether it's still valid
            // If it's not valid (it returned false), remove it from the list
            if (!(*it)()) {
                it = _state.observers.erase_after(prev);
            } else {
                prev = it;
                it++;
            }
        }
    }
    
    MDCUSBDevicePtr _dev;
    const _Path _dir;
    ImageLibraryPtr _imageLibrary;
    MSP::State _mspState;
    STM::SDCardInfo _sdCardInfo;
    
    struct {
        std::mutex lock; // Protects this struct
        std::string name;
        std::forward_list<Observer> observers;
        std::thread updateImageLibraryThread;
        ImageCachePtr imageCache;
    } _state;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

} // namespace MDCStudio

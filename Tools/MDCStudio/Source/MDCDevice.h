#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Toastbox/Mmap.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Code/Shared/BufQueue.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "ImageLibrary.h"
#import "ImagePipeline/ImagePipeline.h"
#import "ImagePipeline/RenderThumb.h"
#import "ImageCache.h"
#import "ImageSource.h"

namespace MDCStudio {

class MDCDevice : public std::enable_shared_from_this<MDCDevice>, public ImageSource {
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
            
//            {
//                _dev->mspConnect();
//                _dev->mspRead(MSP::StateAddr, &_mspState, sizeof(_mspState));
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
//                // Load ICE40 with our app
//                _ICEConfigure(*_dev);
//                
//                _mspState.startTime.time = MSP::TimeFromUnixTime(std::time(nullptr));
//                _mspState.startTime.valid = true;
//                _dev->mspWrite(MSP::StateAddr, &_mspState, sizeof(_mspState));
//                
//                // MSPHostMode=true: make MSP enter host mode until physically disconnected from USB.
//                // (When USB is disconnected, STM will lose power, causing STM to stop asserting
//                // MSP_HOST_MODE_, allowing MSP_HOST_MODE_ to be pulled high by MSP's pullup, thereby
//                // allowing MSP to run again.)
//                constexpr bool MSPHostMode = true;
//                _dev->mspDisconnect(MSPHostMode);
//            }
//            
//            sleep(15);
            
//            // Update device time
//            {
//                _dev->mspConnect();
//                _dev->mspRead(MSP::StateAddr, &_mspState, sizeof(_mspState));
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
//                _dev->mspWrite(MSP::StateAddr, &_mspState, sizeof(_mspState));
//                
//                // MSPHostMode=true: make MSP enter host mode until physically disconnected from USB.
//                // (When USB is disconnected, STM will lose power, causing STM to stop asserting
//                // MSP_HOST_MODE_, allowing MSP_HOST_MODE_ to be pulled high by MSP's pullup, thereby
//                // allowing MSP to run again.)
//                constexpr bool MSPHostMode = true;
//                
//                startTime = std::chrono::steady_clock::now();
//                _dev->mspDisconnect(MSPHostMode);
//            }
            
//            usleep(180000);
            
//            exit(0);
            
//            auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//            printf("durationMs: %ju\n", (uintmax_t)durationMs);
            
            // Init SD card
            #warning TODO: how should we handle sdInit() failing (throwing)?
            _sdCardInfo = _dev->sdInit();
            
            if (!_mspState.sd.valid) {
                // MSPApp state isn't valid -- ignore
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            if (memcmp(&_sdCardInfo.cardId, &_mspState.sd.cardId, sizeof(_mspState.sd.cardId))) {
                // Current SD card id doesn't match MSP's card id
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
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
    ImageLibraryPtr imageLibrary() override { return _imageLibrary; }
    
    ImageCachePtr imageCache() override {
        // We're implementing this lazily because shared_from_this()
        // can't be called from the constructor
        auto lock = std::unique_lock(_state.lock);
        if (!_state.imageCache) {
            std::weak_ptr<MDCDevice> weakThis = shared_from_this();
            ImageCache::ImageProvider imageProvider = [=] (const ImageRef& imageRef) -> ImagePtr {
                auto strongThis = weakThis.lock();
                if (!strongThis) return nullptr;
                return strongThis->_imageProvider(imageRef);
            };
            
            _state.imageCache = std::make_shared<ImageCache>(_imageLibrary, std::move(imageProvider));
        }
        return _state.imageCache;
    }
    
    void addObserver(Observer&& observer) {
        auto lock = std::unique_lock(_state.lock);
        _state.observers.push_front(std::move(observer));
    }
    
    void write() {
        auto lock = std::unique_lock(_state.lock);
        _write();
    }
    
private:
    using _Path = std::filesystem::path;
    static constexpr uint32_t _Version = 0;
    static constexpr uint64_t _UnixTimeOffset = 1640995200; // 2022-01-01 00:00:00 +0000
    
    static constexpr CFADesc _CFADesc = {
        CFAColor::Green, CFAColor::Red,
        CFAColor::Blue, CFAColor::Green,
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
        const char* ICEBinPath = "/Users/dave/repos/MDC/Code/ICE40/ICEAppSDReadoutSTM/Synth/Top.bin";
        Toastbox::Mmap mmap(ICEBinPath);
        
        // Write the ICE40 binary
        dev.iceRAMWrite(mmap.data(), mmap.len());
    }
    
//    static MSP::Time _MSPTimeCurrent() {
//        return MSP::TimeFromUnixTime(std::time(nullptr));
//        const std::time_t t = std::time(nullptr);
//        return MSP::TimeAbsoluteBase | (t-MSP::TimeAbsoluteUnixReference);
//    }
    
    ImagePtr _imageProvider(const ImageRef& imageRef) {
        // Lock the device for the duration of this function
        auto lock = std::unique_lock(*_dev);
        
        auto imageData = std::make_unique<uint8_t[]>(ImgSD::ImgPaddedLen);
        _dev->endpointsFlush();
        _dev->sdRead((SD::BlockIdx)imageRef.addr);
        _dev->readout(imageData.get(), ImgSD::ImgPaddedLen);
        
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
            
            {
                // Remove images from beginning of library: lib has, device doesn't
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
                    const auto removeBegin = _imageLibrary->begin();
                    
                    // Find the first image >= `deviceImgIdBegin`
                    const auto removeEnd = std::lower_bound(_imageLibrary->begin(), _imageLibrary->end(), 0,
                        [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                            return _imageLibrary->recordGet(sample)->ref.id < deviceImgIdBegin;
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
                    
                    const Img::Id deviceImgIdEnd = imgRingBuf.buf.idEnd;
                    
                    if (libImgIdEnd > deviceImgIdEnd) {
                        throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, deviceImgIdEnd: %ju)",
                            (uintmax_t)libImgIdEnd,
                            (uintmax_t)deviceImgIdEnd
                        );
                    }
                    
                    const uint32_t addCount = deviceImgIdEnd-libImgIdEnd;
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
                
                // Write the library
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    printf("Writing library (%ju images)\n", (uintmax_t)_imageLibrary->recordCount());
                    _imageLibrary->write();
                }
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    void _loadImages(const _Range& range) {
        using namespace MDCTools;
        // Lock the device for the duration of this function
        auto lock = std::unique_lock(*_dev);
        
        if (!range.len) return; // Short-circuit if there are no images to read in this range
        
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
        Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
        
        constexpr size_t ChunkImgCount = 16; // Number of images to read at a time
        constexpr size_t BufCap = ChunkImgCount * ImgSD::ImgPaddedLen;
        auto bufQueuePtr = std::make_unique<_BufQueue<BufCap>>();
        auto& bufQueue = *bufQueuePtr;
        const SD::BlockIdx blockIdxStart = range.idx * ImgSD::ImgBlockCount;
        
        _dev->endpointsFlush();
        _dev->sdRead(blockIdxStart);
        
        // Consumer
        std::thread consumerThread([&] {
            auto startTime = std::chrono::steady_clock::now();
            SD::BlockIdx blockIdx = blockIdxStart;
            size_t addedImageCount = 0;
            
            for (;;) {
                auto& buf = bufQueue.rget();
                if (!buf.len) break; // We're done when we get an empty buffer
                _addImages(renderer, buf.data, buf.len, blockIdx);
                bufQueue.rpop();
                
                blockIdx += buf.len * ImgSD::ImgBlockCount;
                addedImageCount += buf.len;
            }
            
            auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
            printf("Consumer took %ju ms for %ju images (avg %ju ms / img)\n", (uintmax_t)durationMs, (uintmax_t)addedImageCount, ((uintmax_t)durationMs/addedImageCount));
        });
        
        // Producer
        for (size_t i=0; i<range.len;) {
            const size_t chunkImgCount = std::min(ChunkImgCount, range.len-i);
            auto& buf = bufQueue.wget();
            buf.len = chunkImgCount; // buffer length = count of images (not byte count)
            _dev->readout(buf.data, chunkImgCount*ImgSD::ImgPaddedLen);
            bufQueue.wpush();
            i += chunkImgCount;
            
            printf("Read %ju images\n", (uintmax_t)chunkImgCount);
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
    
    void _addImages(MDCTools::Renderer& renderer, const uint8_t* data, size_t imgCount, SD::BlockIdx blockIdx) {
        using namespace MDCTools;
        using namespace MDCStudio::ImagePipeline;
        
        ImageId imageId = 0;
        {
            auto lock = std::unique_lock(*_imageLibrary);
            
            // Reserve space for `imgCount` additional images
            _imageLibrary->reserve(imgCount);
            
            // Load `imageId` by looking at the last record's image id +1, and reserve space
            if (_imageLibrary->recordCount()) {
                imageId = _imageLibrary->recordGet(_imageLibrary->back())->ref.id+1;
            }
        }
        
        Img::Id deviceImgIdLast = 0;
        for (size_t idx=0; idx<imgCount; idx++) {
            const uint8_t* imgData = data+idx*ImgSD::ImgPaddedLen;
            const Img::Header& imgHeader = *(const Img::Header*)imgData;
            // Accessing `_imageLibrary` without a lock because we're the only entity using the image library's reserved space
            const auto recordRefIter = _imageLibrary->reservedBegin()+idx;
            ImageThumb& imageThumb = *_imageLibrary->recordGet(recordRefIter);
            ImageRef& imageRef = imageThumb.ref; // Safe without a lock because we're the only entity using the image library's reserved space
            
            // Validate checksum
            const uint32_t checksumExpected = ChecksumFletcher32(imgData, Img::ChecksumOffset);
            uint32_t checksumGot = 0;
            memcpy(&checksumGot, imgData+Img::ChecksumOffset, Img::ChecksumLen);
            if (checksumGot != checksumExpected) {
                throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
            } else {
                printf("Checksum OK\n");
            }
            
            // Populate ImageRef fields
            {
                imageRef.id = imageId;
                
                // If the image has an absolute time, use it
                // If the image has a relative time (ie time since device boot), drop it
                if (imgHeader.timestamp & MSP::TimeAbsoluteBase) {
                    imageRef.timestamp = MSP::UnixTimeFromTime(imgHeader.timestamp);
                }
                
                imageRef.addr           = blockIdx;
                
                imageRef.imageWidth     = imgHeader.imageWidth;
                imageRef.imageHeight    = imgHeader.imageHeight;
                
                imageRef.coarseIntTime  = imgHeader.coarseIntTime;
                imageRef.analogGain     = imgHeader.analogGain;
                
                imageId++;
                blockIdx += ImgSD::ImgBlockCount;
            }
            
            // Render the thumbnail into imageRef.thumbData
            {
                const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
                
                Pipeline::RawImage rawImage = {
                    .cfaDesc = _CFADesc,
                    .width = Img::PixelWidth,
                    .height = Img::PixelHeight,
                    .pixels = (ImagePixel*)(imgData+Img::PixelsOffset),
                };
                
                const Pipeline::Options pipelineOpts = {
                    .reconstructHighlights  = { .en = true, },
                    .debayerLMMSE           = { .applyGamma = true, },
                };
                
                Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
                const size_t thumbDataOff = (uintptr_t)&imageThumb.thumb - (uintptr_t)chunk.mmap.data();
                
                constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
                id<MTLBuffer> buf = [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data() length:chunk.mmap.len() options:BufOpts deallocator:nil];
                
                const RenderThumb::Options thumbOpts = {
                    .thumbWidth = ImageThumb::ThumbWidth,
                    .thumbHeight = ImageThumb::ThumbHeight,
                    .dataOff = thumbDataOff,
                };
                
                RenderThumb::RGB3FromTexture(renderer, thumbOpts, renderResult.txt, buf);
            }
            
            deviceImgIdLast = imgHeader.id;
        }
        
        // Make sure all rendering is complete before adding the images to the library
        renderer.commitAndWait();
        
        {
            auto lock = std::unique_lock(*_imageLibrary);
            // Add the records that we previously reserved
            _imageLibrary->add();
            // Update the device's image id 'end' == last image id that we've observed from the device +1
            _imageLibrary->setDeviceImgIdEnd(deviceImgIdLast+1);
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

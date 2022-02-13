#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Toastbox/Mmap.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Code/Shared/BufQueue.h"
#import "Tools/Shared/Vendor.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "ImageLibrary.h"
#import "ImagePipeline/ImagePipeline.h"
#import "ImagePipeline/RenderThumb.h"

class MDCDevice : public MDCUSBDevice {
public:
    using MDCUSBDevice::MDCUSBDevice;
    using Observer = std::function<bool()>;
    
    MDCDevice(USBDevice&& dev) : MDCUSBDevice(std::move(dev)), _devDir(_DevDirForSerial(serial())) {
        printf("MDCDevice()\n");
        
        auto lock = std::unique_lock(_state.lock);
        
        // Give device a default name
        char name[256];
        snprintf(name, sizeof(name), "MDC Device %s", serial().c_str());
        _state.name = std::string(name);
        
        try {
            _SerializedState state = _SerializedStateRead(_devDir);
            _state.name = std::string(state.name);
        } catch (const std::exception& e) {}
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
    
    ImageLibraryPtr imgLib() {
        auto lock = std::unique_lock(_state.lock);
        if (!_state.imgLib) {
            _state.imgLib = std::make_shared<MDCTools::Vendor<ImageLibrary>>(_devDir / "ImageLibrary");
            // Load the library
            _state.imgLib->vend()->read();
        }
        return _state.imgLib;
    }
    
    void updateImageLibrary() {
        auto lock = std::unique_lock(_state.lock);
        assert(!_state.updateImageLibraryThread.joinable());
        #warning TODO: what should we do if the thread's already running?
        _state.updateImageLibraryThread = std::thread([this] { _threadUpdateImageLibrary(); });
        _state.updateImageLibraryThread.detach();
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
    
    static _Path _StatePath(const _Path& devDir) { return devDir / "State"; }
    
    static _Path _DevDirForSerial(const std::string_view& serial) {
        auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
        
        const _Path appSupportDir = _Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
        return appSupportDir / "Devices" / serial;
    }
    
    static _SerializedState _SerializedStateRead(const _Path& devDir) {
        std::ifstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(devDir));
        
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
    
    static void _SerializedStateWrite(const _Path& devDir, const _SerializedState& state) {
        std::ofstream f;
        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
        f.open(_StatePath(devDir));
        f.write((char*)&state, sizeof(state));
    }
    
    static const MSP::ImgRingBuf& _GetImgRingBuf(const MSP::State& state) {
        const MSP::ImgRingBuf& imgRingBuf0 = state.sd.imgRingBufs[0];
        const MSP::ImgRingBuf& imgRingBuf1 = state.sd.imgRingBufs[1];
        const std::optional<int> comp = MSP::ImgRingBuf::Compare(imgRingBuf0, imgRingBuf1);
        if (!comp) throw Toastbox::RuntimeError("both image ring buffers are invalid");
        return *comp>=0 ? imgRingBuf0 : imgRingBuf1;
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
        
        _SerializedStateWrite(_devDir, state);
    }
    
    void _threadUpdateImageLibrary() {
        try {
            mspConnect();
            
            MSP::State state;
            mspRead(MSP::StateAddr, &state, sizeof(state));
            
            if (state.magic != MSP::State::MagicNumber) {
                // Program MSPApp onto MSP
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            if (state.version > MSP::State::Version) {
                // Newer version than we understand -- tell user to upgrade or re-program
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            if (!state.sd.valid) {
                // MSPApp state isn't valid -- ignore
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            const STM::SDCardInfo sdCardInfo = sdInit();
            if (memcmp(&sdCardInfo.cardId, &state.sd.cardId, sizeof(state.sd.cardId))) {
                // Current SD card id doesn't match MSP's card id
                #warning TODO: implement
                throw Toastbox::RuntimeError("TODO: implement");
            }
            
            const MSP::ImgRingBuf& imgRingBuf = _GetImgRingBuf(state);
            
            {
                // Remove images from beginning of library: lib has, device doesn't
                {
                    auto il = imgLib()->vend();
                    const Img::Id deviceImgIdBegin = imgRingBuf.buf.idBegin;
                    const auto removeBegin = il->begin();
                    
                    // Find the first image >= `deviceImgIdBegin`
                    const auto removeEnd = std::lower_bound(il->begin(), il->end(), 0,
                        [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                            return il->recordGet(sample)->id < deviceImgIdBegin;
                        });
                    
                    printf("Removing %ju images\n", (uintmax_t)std::distance(removeBegin, removeEnd));
                    il->remove(removeBegin, removeEnd);
                }
                
                // Add images to end of library: device has, lib doesn't
                {
                    const Img::Id libImgIdEnd = imgLib()->vend()->imgIdEnd();
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
                    oldest.idx = state.sd.imgCap - oldest.len;
                    
                    _loadImages(oldest);
                    _loadImages(newest);
                }
                
                printf("Writing library\n");
                // Write the library
                imgLib()->vend()->write();
            }
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to update image library: %s", e.what());
        }
    }
    
    void _loadImages(const _Range& range) {
        using namespace MDCTools;
        
        if (!range.len) return; // Short-circuit if there are no images to read in this range
        
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
        Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
        
        constexpr size_t ChunkImgCount = 16; // Number of images to read at a time
        constexpr size_t BufCap = ChunkImgCount * ImgSD::ImgPaddedLen;
        auto bufQueuePtr = std::make_unique<_BufQueue<BufCap>>();
        auto& bufQueue = *bufQueuePtr;
        
        sdRead(range.idx * ImgSD::ImgBlockCount);
        
        // Consumer
        std::thread consumerThread([&] {
            auto startTime = std::chrono::steady_clock::now();
            size_t addedImageCount = 0;
            
            for (;;) {
                auto& buf = bufQueue.rget();
                if (!buf.len) break; // We're done when we get an empty buffer
                _addImages(renderer, buf.data, buf.len);
                bufQueue.rpop();
                
                addedImageCount += buf.len;
            }
            
            auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
            printf("Consumer took %ju ms for %ju images (avg %ju ms / img)\n", (uintmax_t)durationMs, (uintmax_t)addedImageCount, ((uintmax_t)durationMs/addedImageCount));
        });
        
        // Producer
        for (size_t i=0; i<range.len;) {
            const size_t chunkImgCount = std::min(ChunkImgCount, range.len-i);
            auto& buf = bufQueue.wget();
            buf.len = chunkImgCount; // Use the buffer length for the count of images, rather than the byte count
            readout(buf.data, chunkImgCount*ImgSD::ImgPaddedLen);
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
    
    void _addImages(MDCTools::Renderer& renderer, const uint8_t* data, size_t imgCount) {
        using namespace MDCTools;
        using namespace MDCStudio::ImagePipeline;
        
        // We're intentionally not holding onto the vended library (imgLib()->vend()) because
        // we don't want to hold the library lock while we process images, since that would
        // block the main thread.
        // Instead we access methods via imgLibVendor->method(), which only acquires the
        // image library lock for the duration of the function call.
        auto& imgLibVendor = *imgLib();
        
        // Reserve space for `imgCount` additional images
        imgLibVendor->reserve(imgCount);
        
        for (size_t idx=0; idx<imgCount; idx++) {
            const uint8_t* imgData = data+idx*ImgSD::ImgPaddedLen;
            const Img::Header& imgHeader = *(const Img::Header*)imgData;
            const auto recordRefIter = imgLibVendor->reservedBegin()+idx;
            ImageRef& imageRef = *imgLibVendor->recordGet(recordRefIter);
            
            // Validate checksum
            const uint32_t checksumExpected = ChecksumFletcher32(imgData, Img::ChecksumOffset);
            uint32_t checksumGot = 0;
            memcpy(&checksumGot, imgData+Img::ChecksumOffset, Img::ChecksumLen);
            if (checksumGot != checksumExpected) {
                throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
            }
            
            // Populate ImageRef fields
            {
                imageRef.id = imgHeader.id;
            }
            
            // Render the thumbnail into the ImageLibrary
            {
                const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
                
                Pipeline::RawImage rawImage = {
                    .cfaDesc = {
                        CFAColor::Green, CFAColor::Red,
                        CFAColor::Blue, CFAColor::Green,
                    },
                    .width = Img::PixelWidth,
                    .height = Img::PixelHeight,
                    .pixels = (ImagePixel*)(imgData+Img::PixelsOffset),
                };
                
                const Pipeline::Options pipelineOpts = {
                    .reconstructHighlights  = { .en = true, },
                    .debayerLMMSE           = { .applyGamma = true, },
                };
                
                Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
                const size_t thumbDataOff = (uintptr_t)&imageRef.thumbData - (uintptr_t)chunk.mmap.data();
                
                RenderThumb::Options thumbOpts = {
                    .thumbWidth = ImageRef::ThumbWidth,
                    .thumbHeight = ImageRef::ThumbHeight,
                    .dst = (void*)chunk.mmap.data(),
                    .dstOff = thumbDataOff,
                    .dstCap = chunk.mmap.len(),
                };
                
                RenderThumb::Run(renderer, thumbOpts, renderResult.txt);
            }
        }
        
        // Make sure all rendering is complete before adding the images to the library
        renderer.commitAndWait();
        
        // Add the records that we previously reserved
        imgLibVendor->add();
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
    
    const _Path _devDir;
    
    struct {
        std::mutex lock; // Protects this struct
        std::string name;
        ImageLibraryPtr imgLib;
        std::forward_list<Observer> observers;
        std::thread updateImageLibraryThread;
    } _state;
};

using MDCDevicePtr = std::shared_ptr<MDCDevice>;

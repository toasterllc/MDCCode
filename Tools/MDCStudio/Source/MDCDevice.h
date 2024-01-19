#import <Foundation/Foundation.h>
#import <filesystem>
#import <thread>
#import <set>
#import <array>
#import <chrono>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <AppleTextureEncoder.h>
#import "Toastbox/Atomic.h"
#import "Toastbox/Mmap.h"
#import "Toastbox/Queue.h"
#import "Toastbox/Math.h"
#import "Toastbox/Signal.h"
#import "Toastbox/LRU.h"
#import "Toastbox/Util.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/Clock.h"
#import "Code/Shared/MSP.h"
#import "Code/Shared/ImgSD.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "Tools/Shared/ImagePipeline/EstimateIlluminant.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/AssertionCounter.h"
#import "Tools/Shared/ELF32Binary.h"
#import "ImageLibrary.h"
#import "ImageSource.h"
#import "Cache.h"

namespace MDCStudio {

struct MDCDevice : ImageSource {
    using _SendRight = Toastbox::SendRight;
    using _USBDevice = Toastbox::USBDevice;
    using _USBDevicePtr = std::unique_ptr<Toastbox::USBDevice>;
    using _MDCUSBDevicePtr = std::unique_ptr<MDCUSBDevice>;
    using _IONotificationPtr = std::unique_ptr<IONotificationPortRef, void(*)(IONotificationPortRef*)>;
    
    struct ImageRange {
        Img::Id begin = 0;
        Img::Id end = 0;
    };
    
    struct Status {
        float batteryLevel = 0;
        size_t loadImageCount = 0;
    };
    
    // _Thread: convenience to automatically join() the thread upon instance destruction
    struct _Thread : std::thread {
        using std::thread::thread;
        
        // Move constructor
        _Thread(_Thread&& x) { set(std::move(x)); }
        // Move assignment operator
        _Thread& operator=(_Thread&& x) { set(std::move(x)); return *this; }
        
        ~_Thread() {
            if (joinable()) join();
        }
        
        void set(_Thread&& x) {
            if (joinable()) join();
            std::thread::operator=(std::move(x));
        }
    };
    
    void init(_MDCUSBDevicePtr&& dev) {
        printf("MDCDevice::init() %p\n", this);
        Object::init(); // Call super
        
        _serial = dev->serial();
        _dir = _DirForSerial(_serial);
        _imageLibrary = Object::Create<ImageLibrary>();
        
        // Give device a default name
        _name = "Photon";
        
        // Read state from disk
        try {
            _SerializedState state = _SerializedStateRead(_dir);
            _name = std::string(state.name);
        } catch (const std::exception& e) {}
        
        // Load the library
        {
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->read(_dir / "ImageLibrary");
        }
        
        _device.thread = _Thread([&] (_MDCUSBDevicePtr&& dev) {
            _device_thread(std::move(dev));
        }, std::move(dev));
        
        // Wait until thread starts
        // TODO: use std::binary_semaphore when we can use C++20
        while (!_device.runLoop) usleep(1000);
    }
    
    ~MDCDevice() {
        printf("~MDCDevice()\n");
        
        // Tell _device_thread to bail
        // We have to check for _device.runLoop, even though the constructor waits
        // for _device.runLoop to be set, because the constructor may not have
        // completed due to an exception!
        if (_device.runLoop) {
            CFRunLoopPerformBlock((CFRunLoopRef)_device.runLoop, kCFRunLoopCommonModes, ^{
                CFRunLoopStop(CFRunLoopGetCurrent());
            });
            CFRunLoopWakeUp((CFRunLoopRef)_device.runLoop);
        }
    }
    
    ObjectProperty(std::string, name);
    
    void changed(const Event& ev) override {
        if (ev.prop == &_name) {
            write();
        }
    }
    
//    const Toastbox::SendRight& service() {
//        auto lock = deviceLock();
//        return _device.device->dev().service();
//    }
    
    const std::string& serial() {
        return _serial;
    }
    
    bool alive() {
        try {
            deviceLock();
        } catch (const Toastbox::Signal::Stop&) {
            return false;
        }
        return true;
    }
    
    std::unique_lock<std::mutex> deviceLock(bool interrupt=false) {
        // Pause the SD thread (if interrupt==true) to allow us to acquire the device lock ASAP
        if (interrupt) {
            auto lock = _sdRead.signal.lock();
            _sdRead.pause++;
            _sdRead.signal.signalAll();
        }
        
        auto lock = _device.signal.lock();
        
        // Un-pause the SD thread
        if (interrupt) {
            auto lock = _sdRead.signal.lock();
            _sdRead.pause--;
            _sdRead.signal.signalAll();
        }
        
        return lock;
    }
    
    // MARK: - Serialization
    
    void write() {
        _SerializedState state;
        state.version = _Version;
        // Copy UTF8 device name into state.name
        // state.name is initialized with zeroes, so we don't need to explicitly set a
        // null byte, but we do need to limit the number of copied bytes to
        // `sizeof(state.name)-1` to ensure that the null byte isn't overwritten
        name().copy(state.name, sizeof(state.name)-1);
        
        _SerializedStateWrite(_dir, state);
    }
    
    // MARK: - Read/Write Device Settings
    
    const MSP::Settings settings() {
        auto lock = _status.signal.wait([&] { return (bool)_status.status; });
        return _status.status->state.settings;
    }
    
    void settings(const MSP::Settings& x) {
        // Wait until _status.status is loaded
        _status.signal.wait([&] { return (bool)_status.status; });
        
        auto hostMode = _hostModeEnter(true);
        
        {
            auto lock = _status.signal.lock();
            assert(_status.status);
            _status.status->state.settings = x;
        }
        
        _device.device->mspStateWrite(_status.status->state);
    }
    
    void factoryReset() {
        // Wait until _status.status is loaded
        _status.signal.wait([&] { return (bool)_status.status; });
        
        // Clear the image library
        {
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->clear();
            _imageLibrary->write();
        }
        
        // Wait for the sync thread to exit
        // We do this so we're sure that the caches won't have stale data
        // placed in them when we clear them next.
        {
            _sync.signal.wait([&] { return !_sync.progress; });
        }
        
        // Reset MSP430 state, and erase the SD card
        {
            auto sdMode = _sdModeEnter(true);
            
            // Reset MSP430 state
            {
                auto lock = _status.signal.lock();
                    _status.status->state.sd = {};
                    _status.status->state.settings = {};
                    const MSP::State mspState = _status.status->state;
                lock.unlock();
                
                _device.device->mspStateWrite(mspState);
            }
            
            // Erase the entire SD card
            {
                const _SDRegion region = { 0, SD::BlockCapacity(_sdMode.cardInfo.cardData) };
                _sdRegionsErase({ region });
            }
        }
        
        // Clear our caches
        // This is necessary because future images that are captured will occupy the
        // same region of previous images in the cache, which will result in stale
        // images being supplied from the cache, from before the factory reset.
        {
            _thumbCache.clear();
            _imageCache.clear();
        }
    }
    
    // MARK: - Image Syncing
    
    void sync() {
        {
            auto lock = _sync.signal.lock();
            // Bail if syncing is already underway
            if (_sync.progress) return;
            _sync.progress = 0;
            _sync.thread = _Thread([&] { _sync_thread(); });
        }
        
        // Notify observers that syncing started
        _sync_observersNotify();
    }
    
    // MARK: - Status
    
    // status(): returns nullopt if the status hasn't been loaded yet
    std::optional<Status> status() {
        try {
            auto statusLock = _status.signal.lock();
                if (!_status.status) return std::nullopt;
                const auto state = _status.status->state;
                const auto batteryLevel = _status.status->batteryLevel;
            statusLock.unlock();
            
            const ImageRange deviceImageRange = _GetImageRange(_GetImgRingBuf(state.sd), state.sd.imgCap);
            const std::optional<size_t> loadImageCount = LoadImageCount(std::unique_lock(*_imageLibrary),
                _imageLibrary, deviceImageRange);
            
            return Status{
                .batteryLevel = batteryLevel,
                .loadImageCount = loadImageCount.value_or(0),
            };
        } catch (const Toastbox::Signal::Stop&) {
            return std::nullopt;
        }
    }
    
    std::optional<float> syncProgress() {
        try {
            auto lock = _sync.signal.lock();
            return _sync.progress;
        } catch (const Toastbox::Signal::Stop&) {
            return std::nullopt;
        }
    }
    
    // MARK: - ImageSource
    
    ImageLibraryPtr imageLibrary() override { return _imageLibrary; }
    
    void renderThumbs(std::set<ImageRecordPtr> recs) override {
        {
            auto lock = _thumbRender.master.signal.lock();
            _thumbRender.master.recs = std::move(recs);
        }
        _thumbRender.master.signal.signalOne();
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
    
    void deleteImages(const ImageSet& images) override {
        ImageSource::deleteImages(images);
        
        {
            std::vector<_SDBlock> addrFull;
            std::vector<_SDBlock> addrThumb;
            for (const ImageRecordPtr& rec : images) {
                addrFull.push_back(rec->info.addrFull);
                addrThumb.push_back(rec->info.addrThumb);
            }
            
            std::sort(addrFull.begin(), addrFull.end());
            std::sort(addrThumb.begin(), addrThumb.end());
            
            const std::vector<_SDRegion> regionsFull = _SDBlocksCoalesce(addrFull, ImgSD::Full::ImageBlockCount);
            const std::vector<_SDRegion> regionsThumb = _SDBlocksCoalesce(addrThumb, ImgSD::Thumb::ImageBlockCount);
            
            {
                auto sdMode = _sdModeEnter(true);
                _sdRegionsErase(regionsFull);
                _sdRegionsErase(regionsThumb);
            }
        }
    }
    
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
    
    struct __Cleanup {
        __Cleanup(std::function<void()> fn) : _fn(fn) {}
        ~__Cleanup() { _fn(); }
        std::function<void()> _fn;
    };
    
    using _Cleanup = std::unique_ptr<__Cleanup>;
    
    static int _CPUCount() {
//        return 1;
        static int CPUCount = std::max(1, (int)std::thread::hardware_concurrency());
        return CPUCount;
    }
    
    static std::vector<_SDRegion> _SDBlocksCoalesce(const std::vector<_SDBlock>& addrs, _SDBlock len) {
        std::vector<_SDRegion> regions;
        std::optional<_SDRegion> current;
        for (_SDBlock addr : addrs) {
            if (current && current->end==addr) {
                current->end = addr+len;
            
            } else {
                if (current) regions.push_back(*current);
                current = {
                    .begin = addr,
                    .end = addr+len,
                };
            }
        }
        if (current) regions.push_back(*current);
        return regions;
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
    
    static MSP::ImgRingBuf _GetImgRingBuf(const MSP::SDState& sd) {
        const MSP::ImgRingBuf& imgRingBuf0 = sd.imgRingBufs[0];
        const MSP::ImgRingBuf& imgRingBuf1 = sd.imgRingBufs[1];
        const std::optional<int> comp = MSP::ImgRingBuf::Compare(imgRingBuf0, imgRingBuf1);
        if (!comp) return {};
        return *comp>=0 ? imgRingBuf0 : imgRingBuf1;
    }
    
    static ImageRange _GetImageRange(const MSP::ImgRingBuf& imgRingBuf, uint32_t imageCap) {
        if (!imgRingBuf.valid) return {};
        return {
            .begin = imgRingBuf.buf.id - std::min(imgRingBuf.buf.id, (Img::Id)imageCap),
            .end = imgRingBuf.buf.id,
        };
    }
    
//    static ImageRange _GetImageRange(const MSP::SDState& sd) {
//        return _GetImageRange(_GetImgRingBuf(sd), sd.imgCap);
//    }
    
    static void _ICEConfigure(MDCUSBDevice& dev) {
        std::string iceBinPath = [[[NSBundle mainBundle] pathForResource:@"ICEApp" ofType:@"bin"] UTF8String];
        Toastbox::Mmap mmap(iceBinPath);
        
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
    
    static constexpr size_t _ThumbTmpStorageLen = ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4;
    using _ThumbTmpStorage = std::array<uint8_t, _ThumbTmpStorageLen>;
    
    // _ThumbRender(): renders a thumbnail from the RAW source pixels (src) into the
    // destination buffer (dst), as BC7-compressed data
    static CCM _ThumbRender(MDCTools::Renderer& renderer, at_encoder_t compressor, _ThumbTmpStorage& tmpStorage,
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
                .reconstructHighlights  = { .en = opts.reconstructHighlights, },
                .debayerLMMSE           = { .applyGamma = true, },
                
                .exposure               = (float)opts.exposure,
                .saturation             = (float)opts.saturation,
                .brightness             = (float)opts.brightness,
                .contrast               = (float)opts.contrast,
                
                .localContrast = {
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
//            constexpr float CompressErrorThreshold = 0.0009765625;    // Fast
            constexpr float CompressErrorThreshold = 0.00003051757812;  // High quality
            
            [thumbTxt getBytes:&tmpStorage[0] bytesPerRow:ImageThumb::ThumbWidth*4
                fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
            
            const at_texel_region_t srcTexels = {
                .texels = (void*)&tmpStorage[0],
                .validSize = {
                    .x = ImageThumb::ThumbWidth,
                    .y = ImageThumb::ThumbHeight,
                    .z = 1,
                },
                .rowBytes = ImageThumb::ThumbWidth*4,
                .sliceBytes = 0,
            };
            
            const at_block_buffer_t dstBuffer = {
                .blocks = dst,
                .rowBytes = ImageThumb::ThumbWidth*4,
                .sliceBytes = 0,
            };
            
            const float cr = at_encoder_compress_texels(
                compressor,
                &srcTexels,
                &dstBuffer,
                CompressErrorThreshold,
        //        at_flags_default
                at_flags_print_debug_info
            );
            
            if (cr < 0) {
                throw Toastbox::RuntimeError("at_encoder_compress_texels failed");
            }
        }
        
        return ccm;
    }
    
    static void _RemoveStaleImages(const std::unique_lock<ImageLibrary>& lock,
        ImageLibraryPtr imageLibrary, const ImageRange& deviceImageRange) {
    
        // Remove images from beginning of library: lib has, device doesn't
        const auto removeBegin = imageLibrary->begin();
        
        // Find the first image >= `deviceImageRange.begin`
        const auto removeEnd = std::lower_bound(imageLibrary->begin(), imageLibrary->end(), 0,
            [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                return sample->info.id < deviceImageRange.begin;
            });
        
        printf("[_RemoveStaleImages] Removing %ju stale images\n", (uintmax_t)(removeEnd-removeBegin));
        imageLibrary->remove(removeBegin, removeEnd);
    }
    
    // MARK: - Init
    
    static _IONotificationPtr _IONotificationCreate() {
        _IONotificationPtr note(new IONotificationPortRef(IONotificationPortCreate(kIOMasterPortDefault)),
            _IONotificationDestroy);
        
        if (!*note) throw Toastbox::RuntimeError("IONotificationPortCreate returned null");
        
        CFRunLoopSourceRef rls = IONotificationPortGetRunLoopSource(*note);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
        return note;
    } 
    
    static void _IONotificationDestroy(IONotificationPortRef* x) {
        assert(x);
        if (*x) IONotificationPortDestroy(*x);
    }
    
    static _MDCUSBDevicePtr _WaitForDeviceReenumerate(const _USBDevice& existing, std::string_view serial) {
        constexpr CFTimeInterval Timeout = 2;
        _IONotificationPtr note = _IONotificationCreate();
        
        _SendRight serviceIter;
        {
            io_iterator_t iter = MACH_PORT_NULL;
            kern_return_t kr = IOServiceAddMatchingNotification(*note, kIOMatchedNotification,
                IOServiceMatching(kIOUSBDeviceClassName), _Nop, nullptr, &iter);
            if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddMatchingNotification failed: 0x%x", kr);
            serviceIter = _SendRight(_SendRight::NoRetain, iter);
        }
        
        _MDCUSBDevicePtr dev;
        for (;;) @autoreleasepool {
            // Handle connected devices
            for (;;) {
                _SendRight service(_SendRight::NoRetain, IOIteratorNext(serviceIter));
                if (!service) break;
                
                if (dev) {
                    printf("[MDCDevice : _WaitForDevice] Multiple devices matching serial: %s\n",
                        std::string(serial).c_str());
                    continue;
                }
                
                try {
                    _USBDevicePtr usbDev = std::make_unique<_USBDevice>(service);
                    if (!MDCUSBDevice::USBDeviceMatches(*usbDev)) continue; // Ignore if this isn't an MDC
                    if (usbDev->serialNumber() != serial) continue; // Ignore if the serial doesn't match
                    if (*usbDev == existing) continue; // Ignore if this is the same device as `existing`
                    dev = std::make_unique<MDCUSBDevice>(std::move(usbDev));
                
                } catch (const std::exception& e) {
                    // Ignore failures to create USBDevice
                    printf("Ignoring USB device: %s\n", e.what());
                }
            }
            
            if (dev) return dev;
            
            // Wait for matching services to appear
            CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, Timeout, true);
            if (r==kCFRunLoopRunTimedOut || r==kCFRunLoopRunStopped) throw Toastbox::Signal::Stop(); // Signalled to stop
            assert(r == kCFRunLoopRunHandledSource);
        }
    }
    
    static void _ServiceInterestCallback(void* ctx, io_service_t service, uint32_t msgType, void* msgArg) {
        if (msgType == kIOMessageServiceIsTerminated) {
            printf("kIOMessageServiceIsTerminated\n");
            bool* stop = (bool*)ctx;
            *stop = true;
        }
    }
    
    static void _Nop(void* ctx, io_iterator_t iter) {}
    
    static void _DeviceBootload(const _MDCUSBDevicePtr& dev) {
        std::string stmBinPath = [[[NSBundle mainBundle] pathForResource:@"STMApp" ofType:@"elf"] UTF8String];
        ELF32Binary elf(stmBinPath);
        
        elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
        size_t size, const char* name) {
            dev->stmRAMWrite(paddr, data, size);
        });
        
        // Reset the device, triggering it to load the program we just wrote
        dev->stmReset(elf.entryPointAddr());
    }
    
    static void _DeviceModeCheck(const _MDCUSBDevicePtr& dev, STM::Status::Mode mode) {
        if (dev->mode() != mode) {
            throw Toastbox::RuntimeError("invalid mode (expected %ju, got %ju)",
                (uintmax_t)mode, (uintmax_t)dev->mode());
        }
    }
    
    static _MDCUSBDevicePtr _DevicePrepare(_MDCUSBDevicePtr&& dev) {
        const std::string serial = dev->serial();
        
//        _MDCUSBDevicePtr dev = std::make_unique<MDCUSBDevice>(std::move(usbDev));
        
        // Invoke bootloader
        {
            dev->bootloaderInvoke();
            dev = _WaitForDeviceReenumerate(dev->dev(), serial);
            _DeviceModeCheck(dev, STM::Status::Mode::STMLoader);
        }
        
        // Bootload device with STMApp
        {
            _DeviceBootload(dev);
            dev = _WaitForDeviceReenumerate(dev->dev(), serial);
            _DeviceModeCheck(dev, STM::Status::Mode::STMApp);
        }
        
        return std::move(dev);
    }
    
    static void _DeviceWaitForTerminate(const _MDCUSBDevicePtr& dev) {
        _IONotificationPtr note = _IONotificationCreate();
        
        // Watch the service so we know when it goes away
        io_object_t ioObj = MACH_PORT_NULL;
        bool stop = false;
        kern_return_t kr = IOServiceAddInterestNotification(*note, dev->dev().service(),
            kIOGeneralInterest, _ServiceInterestCallback, &stop, &ioObj);
        if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddInterestNotification failed: 0x%x", kr);
        _SendRight obj(_SendRight::NoRetain, ioObj); // Make sure port gets cleaned up
        
        for (;;) @autoreleasepool {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
            if (stop) throw Toastbox::Signal::Stop(); // Signalled to stop
        }
    }
    
    // MARK: - Device
    
    void _device_thread(_MDCUSBDevicePtr&& dev) {
        try {
            {
                auto lock = deviceLock();
                _device.runLoop = CFBridgingRelease(CFRetain(CFRunLoopGetCurrent()));
                _device.device = _DevicePrepare(std::move(dev));
            }
            
            // Update the device's time
            {
                // Enter host mode to adjust the device time
                auto hostMode = _hostModeEnter();
                
                // Adjust the device's time to correct it for crystal innaccuracy
                std::cout << "Adjusting device time:\n";
                _device.device->mspTimeAdjust();
            }
            
            // Init _status
            {
                _status.thread = _Thread([&] { _status_thread(); });
            }
            
            // Init _sdRead
            {
                _sdRead.thread = _Thread([&] { _sdRead_thread(); });
            }
            
            // Init _thumbRender
            {
                _thumbRender.master.thread = _Thread([&] { _thumbRender_masterThread(); });
                
                for (int i=0; i<_CPUCount(); i++) {
                    _thumbRender.slave.threads.emplace_back([&] { _thumbRender_slaveThread(); });
                }
            }
            
            // Start syncing
            sync();
            
            // Wait for device to disappear
            _DeviceWaitForTerminate(_device.device);
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_device_thread] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[_device_thread] Error: %s\n", e.what());
        }
        
        // Trigger all our threads to exit
        {
            auto lock = deviceLock(true);
            _device.signal.stop(lock);
        }
        
        _sdRead.signal.stop();
        _thumbRender.master.signal.stop();
        _thumbRender.slave.signal.stop();
        _status.signal.stop();
        
        for (_LoadState& loadState : _loadStates.mem()) {
            loadState.signal.stop();
        }
        
        // Use selfOrNull() instead of self() because self() will throw a bad_weak_ptr
        // exception if our MDCDevice is undergoing destruction on a different thread.
        // The destructor waits for this thread to terminate, so this should be safe.
        const auto self = selfOrNull();
        if (self) observersNotify(self, {});
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
    
    void _readCompleteCallback(_LoadState& state, _SDReadWork&& work, bool initial) {
        _ThumbBufferReserved& buf = *work.buf.thumb();
        
        // Enqueue rendering
        {
            {
                auto lock = _thumbRender.slave.signal.lock();
                _renderEnqueue(lock, state, initial, true, work.rec, buf.entry());
            }
            _thumbRender.slave.signal.signalAll();
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
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->observersNotify(ImageLibrary::Event::Type::ChangeThumbnail, notify);
        }
        
        if (!count || !notify.empty()) state.signal.signalAll();
    }
    
    void _renderEnqueue(const std::unique_lock<std::mutex>& lock, _LoadState& state, bool initial, bool validateChecksum, ImageRecordPtr rec, _ThumbBuffer buf) {
        // Enqueue _RenderWork into _thumbRender.slave.queue
        _thumbRender.slave.queue.push(_RenderWork{
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
    
    void _loadThumbs(Priority priority, bool initial,
        std::set<ImageRecordPtr> recs, std::function<void(float)> progressCallback=nullptr) {
        
        const size_t imageCount = recs.size();
        auto timeStart = std::chrono::steady_clock::now();
        
        auto state = _loadStates.pop().entry();
        assert(!state->underway);
        state->underway += imageCount;
        
        _Thread progressThread;
        if (progressCallback && imageCount) {
            progressThread = _Thread([&] {
                try {
                    state->signal.wait([&] {
                        const float progress = (float)(imageCount - state->underway) / imageCount;
                        progressCallback(progress);
                        return !state->underway;
                    });
                } catch (const Toastbox::Signal::Stop&) {
                    printf("[_loadThumbs:progressThread] Stopping\n");
                }
            });
        }
        
        // Kick off rendering for all the recs that are in the cache
        {
            bool enqueued = false;
            {
                auto lock = _thumbRender.slave.signal.lock();
                
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
            if (enqueued) _thumbRender.slave.signal.signalAll();
        }
        
        // The remaining recs aren't in our cache, so kick off SD reading + rendering
        for (auto it=recs.rbegin(); it!=recs.rend(); it++) {
            const ImageRecordPtr& rec = *it;
            
            // Only load the record if it's still needed
            if (rec.alive()) {
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
                
//                printf("[_loadImages:p%ju] Enqueuing _SDReadWork\n", (uintmax_t)priority);
                {
                    auto lock = _sdRead.signal.lock();
                    _SDReadWorkQueue& queue = _sdRead.queues[(size_t)priority];
                    queue.push(std::move(work));
                }
                _sdRead.signal.signalOne();
            
            } else {
                state->underway--;
            }
        }
        
        // Wait until everything's done
        state->signal.wait([&] { return !state->underway; });
        
        // Print profile stats
        {
            using namespace std::chrono;
            const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
            const double msPerImage = ((double)duration.count()/imageCount);
            const double mibPerSec = ((imageCount * ImgSD::Thumb::ImagePaddedLen) /
                (duration.count() / 1000.)) / (1024*1024);
            printf("[_loadImages:p%ju] _loadThumbs() took %ju ms for %ju images (avg = %.1f ms/img; throughput = %.1f MiB/sec)\n",
                (uintmax_t)priority,
                (uintmax_t)duration.count(),
                (uintmax_t)imageCount,
                msPerImage,
                mibPerSec);
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
    
    void _sdRegionsErase(const std::vector<_SDRegion>& regions) {
        for (const _SDRegion& region : regions) {
            _device.device->sdErase(
                Toastbox::Cast<SD::Block>(region.begin),
                Toastbox::Cast<SD::Block>(region.end-1)
            );
        }
    }
    
    // MARK: - Sync
    
    static std::optional<size_t> LoadImageCount(const std::unique_lock<ImageLibrary>& lock,
        ImageLibraryPtr imageLibrary, const ImageRange& deviceImageRange) {
        const Img::Id libImageIdEnd = imageLibrary->imageIdEnd();
        // If our image library claims to have newer images than the device, return an error
        if (libImageIdEnd > deviceImageRange.end) {
            return std::nullopt;
        }
        return deviceImageRange.end - std::max(deviceImageRange.begin, libImageIdEnd);
    }
    
    void _sync_thread() {
        struct StaleLibrary : std::runtime_error {
            using std::runtime_error::runtime_error;
        };
        
        try {
            auto lock = _status.signal.wait([&] { return (bool)_status.status; });
                const MSP::SDState sd = _status.status->state.sd;
            lock.unlock();
            
            const MSP::ImgRingBuf imgRingBuf = _GetImgRingBuf(sd);
            if (!imgRingBuf.valid) throw StaleLibrary("image ring buf invalid");
            const ImageRange deviceImageRange = _GetImageRange(imgRingBuf, sd.imgCap);
            
            {
                // Modify the image library to reflect the images that have been added and removed
                // since the last time we sync'd
                uint32_t addCount = 0;
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    
                    // Remove images from beginning of library: lib has, device doesn't
                    _RemoveStaleImages(lock, _imageLibrary, deviceImageRange);
                    
                    // Calculate how many images to add to the end of the library: device has, lib doesn't
                    {
                        const std::optional<size_t> count = LoadImageCount(lock, _imageLibrary, deviceImageRange);
                        if (count) {
                            addCount = (uint32_t)*count;
                        } else {
                            throw StaleLibrary("LoadImageCount failed");
                        }
                        
//                        addCount = 1000;
//                        addCount = 20000;
                        printf("[_sync_thread] Adding %ju images\n", (uintmax_t)addCount);
                        _imageLibrary->add(addCount);
                    }
                    
                    // Populate .id / .addr for the ImageRecords that we're adding
                    {
                        auto it = _imageLibrary->end();
                        Img::Id id = deviceImageRange.end;
                        uint32_t idx = imgRingBuf.buf.idx;
                        while (addCount) {
                            it--;
                            id--;
                            idx = (idx ? idx-1 : sd.imgCap-1);
                            addCount--;
                            
                            ImageRecordPtr rec = *it;
                            rec->info.id = id;
                            rec->info.addrFull = MSP::SDBlockFull(sd.baseFull, idx);
                            rec->info.addrThumb = MSP::SDBlockThumb(sd.baseThumb, idx);
                            
                            rec->status.loadCount = 0;
                        }
                    }
                    
                    // Write library now that we've added our new images and populated their .id / .addr
                    _imageLibrary->imageIdEnd(deviceImageRange.end);
                    _imageLibrary->write();
                }
                
                // Load all unloaded images from the SD card
                // Note that this will also load unloaded images from a previous session, since we may have
                // been killed or crashed before we finished loading all images.
                {
                    std::set<ImageRecordPtr> recs;
                    for (const ImageLibrary::RecordRef& rec : *_imageLibrary) {
                        if (!rec->status.loadCount) {
                            recs.insert(rec);
                        }
                    }
                    
                    printf("[_sync_thread] Loading %ju images\n", (uintmax_t)recs.size());
                    _loadThumbs(Priority::Low, true, recs, [=] (float progress) {
                        {
                            auto lock = _sync.signal.lock();
                            _sync.progress = progress;
                            _sync.signal.signalAll();
                        }
                        _sync_observersNotify();
                    });
                }
                
                // Prune unloaded images
                // The unloaded images at this point are unloaded because they failed to load,
                // so we presume that they've been deleted from the device from a previous
                // MDCStudio session.
                {
                    std::set<ImageRecordPtr> recs;
                    for (const ImageLibrary::RecordRef& rec : *_imageLibrary) {
                        if (!rec->status.loadCount) {
                            recs.insert(rec);
                        }
                    }
                    printf("[_sync_thread] Pruning %ju unloaded images\n", (uintmax_t)recs.size());
                    _imageLibrary->remove(recs);
                }
                
                // Write the image library now that we're done syncing
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    _imageLibrary->write();
                }
            }
        
        } catch (const StaleLibrary& e) {
            printf("[_sync_thread] Stale ImageLibrary: %s\n", e.what());
            printf("[_sync_thread] Clearing ImageLibrary\n");
            auto lock = std::unique_lock(*_imageLibrary);
            _imageLibrary->clear();
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_sync_thread] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[_sync_thread] Error: %s\n", e.what());
        }
        
        // Update syncing status
        {
            auto lock = _sync.signal.lock();
            _sync.progress = std::nullopt;
            _sync.signal.signalAll();
        }
        
        // Use selfOrNull() instead of self() because self() will throw a bad_weak_ptr
        // exception if our MDCDevice is undergoing destruction on a different thread.
        // The destructor waits for this thread to terminate, so this should be safe.
        const auto self = selfOrNull();
        if (self) _sync_observersNotify(self);
    }
    
    void _sync_observersNotify(ObjectPtr self) {
        Object::Event ev;
        ev.prop = &_sync;
        observersNotify(self, ev);
    }
    
    void _sync_observersNotify() {
        _sync_observersNotify(self());
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
    
//    void _sdRead_handleWork(_SDReadWork&& work) {
//        const _SDBlock blockBegin = work.region.begin;
//        const size_t len = (size_t)SD::BlockLen * (size_t)(work.region.end-work.region.begin);
//        // Verify that the length of data that we're reading will fit in our buffer
//        assert(len <= work.buf.cap());
//        
//        {
//            printf("[_sdRead_handleWork] reading blockBegin:%ju len:%ju (%.1f MB)\n",
//                (uintmax_t)blockBegin, (uintmax_t)len, (float)len/(1024*1024));
//            
//            _deviceSDRead(blockBegin, len, work.buf.storage());
//        }
//        
//        work.callback(std::move(work));
//    }
    
    void _sdRead_thread() {
        constexpr auto SDModeTimeout = std::chrono::seconds(3);
        try {
            for (;;) {
                // Wait for work
                printf("[_sdRead_thread] Waiting for work...\n");
                _sdRead.signal.wait([&] { return _sdRead_nextQueue() && !_sdRead.pause; });
                
                // Initiate SD mode
                printf("[_sdRead_thread] Entering SD mode...\n");
                auto sdMode = _sdModeEnter();
                printf("[_sdRead_thread] Entered SD mode\n");
                
                std::optional<_SDBlock> sdReadEnd;
                for (;;) {
                    _SDReadWork work;
                    {
                        // Wait for work
                        _SDReadWorkQueue* queue = nullptr;
                        bool pause = false;
                        auto lock = _sdRead.signal.wait_for(SDModeTimeout, [&] {
                            queue = _sdRead_nextQueue();
                            pause = _sdRead.pause;
                            return queue || pause;
                        });
                        // Check if we timed out waiting for work
                        if (!queue || pause) break;
//                        printf("[_sdRead_thread] Dequeued work\n");
                        work = std::move(queue->front());
                        queue->pop();
                    }
                    
                    {
                        const _SDBlock blockBegin = work.region.begin;
                        const size_t len = (size_t)SD::BlockLen * (size_t)(work.region.end-work.region.begin);
                        // Verify that the length of data that we're reading will fit in our buffer
                        assert(len <= work.buf.cap());
                        
                        {
//                            printf("[_sdRead_thread] reading blockBegin:%ju len:%ju (%.1f MB)\n",
//                                (uintmax_t)blockBegin, (uintmax_t)len, (float)len/(1024*1024));
                            
                            const _SDBlock block = blockBegin;
                            void*const dst = work.buf.storage();
                            if (!sdReadEnd || *sdReadEnd!=block) {
                                printf("[_deviceSDRead] Starting readout at %ju\n", (uintmax_t)block);
                                // If readout was in progress at a different address, reset the device
                                if (sdReadEnd) {
                                    _device.device->reset();
                                }
                                
                                // Verify that blockBegin can be safely cast to SD::Block
                                assert(std::numeric_limits<SD::Block>::max() >= block);
                                _device.device->sdRead((SD::Block)block);
                                _device.device->readout(dst, len);
                            
                            } else {
//                                printf("[_deviceSDRead] Continuing readout at %ju\n", (uintmax_t)block);
                                _device.device->readout(dst, len);
                            }
                            sdReadEnd = _SDBlockEnd(block, len);
                        }
                        
                        work.callback(std::move(work));
                    }
                }
                
                printf("[_sdRead_thread] Exiting SD mode\n");
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_sdRead_thread] Stopping\n");
        } catch (const std::exception& e) {
            printf("[_sdRead_thread] Error: %s\n", e.what());
        }
    }
    
    // MARK: - Thumb Render
    
    template<MTLPixelFormat T_Format>
    static constexpr at_block_format_t _ATBlockFormatForMTLPixelFormat() {
// For compilation on macOS 10.15
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_15_1
        return at_block_format_bc7;
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        if constexpr (T_Format == MTLPixelFormatASTC_4x4_LDR) {
            return at_block_format_astc_4x4_ldr;
        } else if constexpr (T_Format == MTLPixelFormatBC7_RGBAUnorm) {
            return at_block_format_bc7;
        } else {
            static_assert(Toastbox::AlwaysFalse_v<T_Format>);
        }
#pragma clang diagnostic pop
#endif
    }
    
    void _thumbRender_masterThread() {
        printf("[_thumbRender_masterThread] Starting\n");
        try {
            for (;;) {
                ImageSet recs;
                {
                    auto lock = _thumbRender.master.signal.wait([&] { return !_thumbRender.master.recs.empty(); });
                    recs = std::move(_thumbRender.master.recs);
                    // Update .thumb.render asap (ie before we've actually rendered) so that the
                    // visibleThumbs() function on the main thread stops enqueuing work asap
                    for (const ImageRecordPtr& rec : recs) {
                        rec->options.thumb.render = false;
                    }
                }
                
                printf("[_thumbRender_masterThread] Enqueueing %ju thumbnails for rendering\n", (uintmax_t)recs.size());
                _loadThumbs(ImageSource::Priority::High, false, recs);
                printf("[_thumbRender_masterThread] Rendered %ju thumbnails\n", (uintmax_t)recs.size());
            }
        
        } catch (const Toastbox::Signal::Stop&) {
        }
        printf("[_thumbRender_masterThread] Exiting\n");
    }
    
    
    void _thumbRender_slaveThread() {
        using namespace MDCTools;
        
        try {
            id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
            Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
            std::unique_ptr<_ThumbTmpStorage> thumbTmpStorage = std::make_unique<_ThumbTmpStorage>();
            
            at_encoder_t compressor = at_encoder_create(
                at_texel_format_rgba8_unorm,
                at_alpha_opaque,
                _ATBlockFormatForMTLPixelFormat<ImageThumb::PixelFormat>(),
                at_alpha_opaque,
                nullptr
            );
            
            if (!compressor) {
                throw Toastbox::RuntimeError("failed to create at_encoder_create");
            }
            
            
            for (;;) @autoreleasepool {
                _RenderWork work;
                {
                    auto lock = _thumbRender.slave.signal.wait([&] { return !_thumbRender.slave.queue.empty(); });
                    work = _thumbRender.slave.queue.front();
                    _thumbRender.slave.queue.pop();
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
                        
                        // Validate the magic number
                        if (imgHeader.magic.u24 != Img::Header::MagicNumber.u24) {
                            printf("[_thumbRender_slaveThread] Invalid magic number (got: %jx, expected: %jx)\n",
                                (uintmax_t)imgHeader.magic.u24, (uintmax_t)Img::Header::MagicNumber.u24);
                            printf("[_thumbRender_slaveThread] Skipping image\n");
                            // Skip this image
                            // In particular, we want to make sure loadCount==0, so that _sync_thread() can observe
                            // it and remove this image.
                            goto thumbDone;
                        }
                        
                        if (imgHeader.id != rec.info.id) {
                            #warning TODO: how do we properly handle this?
//                            printf("[_thumbRender_slaveThread] Invalid image id (got: %ju, expected: %ju)\n", (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
//                            throw Toastbox::RuntimeError("invalid image id (got: %ju, expected: %ju)",
//                                (uintmax_t)imgHeader.id, (uintmax_t)rec.info.id);
                        }
                        
                        rec.info.timestamp      = imgHeader.timestamp;
                        
                        rec.info.imageWidth     = imgHeader.imageWidth;
                        rec.info.imageHeight    = imgHeader.imageHeight;
                        
                        rec.info.coarseIntTime  = imgHeader.coarseIntTime;
                        rec.info.analogGain     = imgHeader.analogGain;
                        
                        rec.info.batteryLevelMv = imgHeader.batteryLevelMv;
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
                        ImageWhiteBalanceSet(rec.options.whiteBalance, true, ccm);
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
                
            thumbDone:
                work.callback();
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_thumbRender_slaveThread] Stopping\n");
        }
    }
    
    // MARK: - Device Status
    static float _BatteryLevel(const STM::BatteryStatus& batteryStatus) {
        // Update _device.status.batteryLevel
        if (batteryStatus.chargeStatus == MSP::ChargeStatus::Complete) {
            return 1;
        
        } else if (batteryStatus.chargeStatus == MSP::ChargeStatus::Underway) {
            return std::min(.999f, (float)MSP::BatteryLevelLinearize(batteryStatus.level) / MSP::BatteryLevelMax);
        
        } else {
            #warning Debug to catch invalid battery state, remove!
//            abort();
            return 0;
        }
    }
    
    void _status_update() {
        auto lock = deviceLock();
            const auto bat = _device.device->batteryStatusGet();
            const auto msp = _device.device->mspStateRead();
        lock.unlock();
        
        {
            auto lock = _status.signal.lock();
            _status.status = {
                .state = msp,
                .batteryLevel = _BatteryLevel(bat),
            };
        }
        
        // Remove images from beginning of library: lib has, device doesn't
        {
            const ImageRange deviceImageRange = _GetImageRange(_GetImgRingBuf(msp.sd), msp.sd.imgCap);
            _RemoveStaleImages(std::unique_lock(*_imageLibrary), _imageLibrary, deviceImageRange);
        }
        
        _status.signal.signalAll();
    }
    
    void _status_observersNotify() {
        Object::Event ev;
        ev.prop = &_status;
        observersNotify(ev);
    }
    
    void _status_thread() {
        printf("[_status_thread] Started\n");
        constexpr auto UpdateInterval = std::chrono::seconds(2);
        try {
            for (;;) {
                _status_update();
                printf("[_status_thread] Updated\n");
                _status_observersNotify();
                _status.signal.wait_for(UpdateInterval, [] { return false; });
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[_status_thread] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[_status_thread] Error: %s\n", e.what());
        }
        printf("[_status_thread] Terminating\n");
    }
    
    // Host mode: acquires the device lock, and tells the device to enter host mode
    _Cleanup _hostModeEnter(bool interrupt=false) {
        _hostModeSet(true, interrupt);
        return std::make_unique<__Cleanup>([=] { _hostModeSet(false); });
    }
    
    // SD mode: acquires the device lock, tells the device to enter host mode,
    // loads ICEAppSDReadoutSTM onto the ICE40, and initializes the SD card.
    _Cleanup _sdModeEnter(bool interrupt=false) {
        _sdModeSet(true, interrupt);
        return std::make_unique<__Cleanup>([=] { _sdModeSet(false); });
    }
    
    _Cleanup _suddenTerminationDisable() {
        [[NSProcessInfo processInfo] disableSuddenTermination];
        return std::make_unique<__Cleanup>([=] {
            [[NSProcessInfo processInfo] enableSuddenTermination];
        });
    }
    
    void _hostModeSet(bool en, bool interrupt=false) {
        try {
            if (en) {
                _hostMode.suddenTermination = _suddenTerminationDisable();
                _hostMode.deviceLock = deviceLock(interrupt);
                _device.device->hostModeSet(true);
                // Only stash the lock in our ivar if hostModeSet() didn't throw
                
                printf("_hostModeSet(1)\n");
            
            } else {
                printf("_hostModeSet(0)\n");
                
                // Move the lock to the stack to ensure that it's destroyed if hostModeSet() throws
                _device.device->hostModeSet(false);
                _hostMode.deviceLock = {};
                _hostMode.suddenTermination = {};
            }
        } catch (...) {
            // If device IO fails (ie hostModeSet()), clean up our state and rethrow the exception
            _hostMode.deviceLock = {};
            _hostMode.suddenTermination = {};
            // Only throw when enabling; when disabling we're executing within a destructor,
            // so we don't want to throw in that case.
            if (en) throw;
        }
    }
    
    void _sdModeSet(bool en, bool interrupt=false) {
        try {
            if (en) {
                auto timeStart = std::chrono::steady_clock::now();
                
                // Enter host mode while we're in SD mode, since MSP can't talk to
                // ICE40 or SD card while we're using it.
                _sdMode.hostMode = _hostModeEnter(interrupt);
                
                // Load ICE40 with our app
                _ICEConfigure(*_device.device);
                
                // Init SD card
                _sdMode.cardInfo = _device.device->sdInit();
                
                // If _device.state.sd is valid, verify that the current SD card id matches MSP's card id
                {
                    auto lock = _status.signal.wait([&] { return (bool)_status.status; });
                    if (_status.status->state.sd.valid) {
                        if (memcmp(&_sdMode.cardInfo.cardId, &_status.status->state.sd.cardId,
                            sizeof(_status.status->state.sd.cardId))) {
                            throw Toastbox::RuntimeError("_sdMode.cardInfo.cardId != _status.status->state.sd.cardId");
                        }
                    }
                }
                
                // Print timing
                {
                    using namespace std::chrono;
                    const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
                    printf("[_sync_thread] SD init took %ju ms\n", (uintmax_t)duration.count());
                }
            
            } else {
                // Assume that we were in the middle of readout; reset the device to exit readout.
                _device.device->reset();
                // Exit host mode
                _sdMode.hostMode = {};
            }
        } catch (...) {
            // If device IO fails (ie via _hostModeEnter()), clean up our state and rethrow the exception
            _sdMode.hostMode = {};
            // Only throw when enabling; when disabling we're executing within a destructor,
            // so we don't want to throw in that case.
            if (en) throw;
        }
    }
    
    // MARK: - Members
    
    std::string _serial;
    _Path _dir;
    ImageLibraryPtr _imageLibrary;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        _Thread thread;
        id /* CFRunLoopRef */ runLoop;
        std::unique_ptr<MDCUSBDevice> device;
    } _device;
    
    Toastbox::Signal _imageForAddrSignal;
    _ThumbCache _thumbCache;
    _ImageCache _imageCache;
    _LoadStatePool _loadStates;
    
    struct {
        std::unique_lock<std::mutex> deviceLock;
        _Cleanup suddenTermination;
    } _hostMode;
    
    struct {
        _Cleanup hostMode;
        STM::SDCardInfo cardInfo;
    } _sdMode;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        _Thread thread;
        std::optional<float> progress;
    } _sync;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        _Thread thread;
        _SDReadWorkQueue queues[(size_t)Priority::Last+1];
        uint32_t pause = 0;
    } _sdRead;
    
    struct {
        struct {
            Toastbox::Signal signal; // Protects this struct
            _Thread thread;
            ImageSet recs;
        } master;
        
        struct {
            Toastbox::Signal signal; // Protects this struct
            std::vector<_Thread> threads;
            _RenderWorkQueue queue;
        } slave;
    } _thumbRender;
    
    struct _Status {
        MSP::State state = {};
        float batteryLevel = 0;
    };
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        _Thread thread;
        std::optional<_Status> status;
    } _status;
};
using MDCDevicePtr = SharedPtr<MDCDevice>;

} // namespace MDCStudio

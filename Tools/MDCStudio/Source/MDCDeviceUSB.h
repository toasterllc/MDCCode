#import "MDCDevice.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>

namespace MDCStudio {

struct MDCDeviceUSB : MDCDevice {
    using _MDCUSBDevicePtr = std::unique_ptr<MDCUSBDevice>;
    using _SendRight = Toastbox::SendRight;
    using _USBDevice = Toastbox::USBDevice;
    using _USBDevicePtr = std::unique_ptr<Toastbox::USBDevice>;
    using _IONotificationPtr = std::unique_ptr<IONotificationPortRef, void(*)(IONotificationPortRef*)>;
    
    struct ImageRange {
        Img::Id begin = 0;
        Img::Id end = 0;
    };
    
    static Path _DirForSerial(const std::string_view& serial) {
        auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
        
        const Path appSupportDir = Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
        return appSupportDir / "Devices" / serial;
    }
    
// _SDBlock: we're intentionally not using SD::Block because we want our block addressing type
    // to be wider than the SD card's addressing. This is because in our math logic, we want to be
    // able to use an 'end strategy' (ie last+1) instead of a 'last strategy', and the former can't
    // address the last block if it's the same width as the SD card's addressing.
    using _SDBlock = uint64_t;
    
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
    
    void init(_MDCUSBDevicePtr&& dev) {
        printf("MDCDeviceUSB::init() %p\n", this);
        
        _serial = dev->serial();
        MDCDevice::init(_DirForSerial(_serial)); // Call super
        
        _device.thread = Thread([&] (_MDCUSBDevicePtr&& dev) {
            _device_thread(std::move(dev));
        }, std::move(dev));
        
        // Wait until thread starts
        // TODO: use std::binary_semaphore when we can use C++20
        while (!_device.runLoop) usleep(1000);
    }
    
    ~MDCDeviceUSB() {
        printf("~MDCDeviceUSB()\n");
        
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
    
    const std::string& serial() {
        return _serial;
    }
    
    // MARK: - Device Settings
    
    const MSP::Settings settings() override {
        auto lock = _status.signal.wait([&] { return (bool)_status.status; });
        return _status.status->state.settings;
    }
    
    void settings(const MSP::Settings& x) override {
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
    
    void factoryReset() override {
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
    
    void sync() override {
        {
            auto lock = _sync.signal.lock();
            // Bail if syncing is already underway
            if (_sync.progress) return;
            _sync.progress = 0;
            _sync.thread = Thread([&] { _sync_thread(); });
        }
        
        // Notify observers that syncing started
        _sync_observersNotify();
    }
    
    // MARK: - Status
    
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
    
    // status(): returns nullopt if the status hasn't been loaded yet
    std::optional<Status> status() override {
        try {
            auto statusLock = _status.signal.lock();
                if (!_status.status) return std::nullopt;
                const auto state = _status.status->state;
                const auto batteryLevel = _status.status->batteryLevel;
            statusLock.unlock();
            
            const ImageRange deviceImageRange = _GetImageRange(_GetImgRingBuf(state.sd), state.sd.imgCap);
            const std::optional<size_t> loadImageCount = _LoadImageCount(std::unique_lock(*_imageLibrary),
                _imageLibrary, deviceImageRange);
            
            return Status{
                .batteryLevel = batteryLevel,
                .loadImageCount = loadImageCount.value_or(0),
            };
        } catch (const Toastbox::Signal::Stop&) {
            return std::nullopt;
        }
    }
    
    std::optional<float> syncProgress() override {
        try {
            auto lock = _sync.signal.lock();
            return _sync.progress;
        } catch (const Toastbox::Signal::Stop&) {
            return std::nullopt;
        }
    }
    
    // MARK: - ImageSource Overrides
    
    void _sdRegionsErase(const std::vector<_SDRegion>& regions) {
        for (const _SDRegion& region : regions) {
            _device.device->sdErase(
                Toastbox::Cast<SD::Block>(region.begin),
                Toastbox::Cast<SD::Block>(region.end-1)
            );
        }
    }
    
    virtual void deleteImages(const ImageSet& images) override {
        MDCDevice::deleteImages(images);
        
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
    
    virtual Cleanup dataReadStart() override {
        return _sdModeEnter();
    }
    
    void _dataRead(const _SDRegion& region, void* dst, size_t dstCap) {
        const _SDBlock blockBegin = region.begin;
        const size_t len = (size_t)SD::BlockLen * (size_t)(region.end-region.begin);
        // Verify that the length of data that we're reading will fit in our buffer
        assert(len <= dstCap);
        
        {
//            printf("[_dataRead_thread] reading blockBegin:%ju len:%ju (%.1f MB)\n",
//                (uintmax_t)blockBegin, (uintmax_t)len, (float)len/(1024*1024));
            
            const _SDBlock block = blockBegin;
            if (!_sdMode.state.dataReadEnd || *_sdMode.state.dataReadEnd!=block) {
                printf("[_dataRead_thread] Starting readout at %ju\n", (uintmax_t)block);
                // If readout was in progress at a different address, reset the device
                if (_sdMode.state.dataReadEnd) {
                    _device.device->reset();
                }
                
                // Verify that blockBegin can be safely cast to SD::Block
                assert(std::numeric_limits<SD::Block>::max() >= block);
                _device.device->sdRead((SD::Block)block);
                _device.device->readout(dst, len);
            
            } else {
//                printf("[_dataRead_thread] Continuing readout at %ju\n", (uintmax_t)block);
                _device.device->readout(dst, len);
            }
            _sdMode.state.dataReadEnd = _SDBlockEnd(block, len);
        }
    }
    
    virtual void dataRead(const ImageRecordPtr& rec, const _ThumbBuffer& data) override {
        _dataRead(_SDRegionForThumb(rec), *data, sizeof(*data));
    }
    
    virtual void dataRead(const ImageRecordPtr& rec, const _ImageBuffer& data) override {
        _dataRead(_SDRegionForImage(rec), *data, sizeof(*data));
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
                _status.thread = Thread([&] { _status_thread(); });
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
        
        _status.signal.stop();
        
        // Use selfOrNull() instead of self() because self() will throw a bad_weak_ptr
        // exception if our MDCDevice is undergoing destruction on a different thread.
        // The destructor waits for this thread to terminate, so this should be safe.
        const auto self = selfOrNull();
        if (self) observersNotify(self, {});
    }
    
    // MARK: - Device Status
    static float _BatteryLevel(const STM::BatteryStatus& batteryStatus) {
        // Update _device.status.batteryLevel
        if (batteryStatus.chargeStatus == MSP::ChargeStatus::Complete) {
            return 1;
        
        } else if (batteryStatus.chargeStatus == MSP::ChargeStatus::Underway) {
            return std::min(.999f, (float)MSP::BatteryLevelLinearize(batteryStatus.level) / MSP::BatteryLevelMax);
        
        } else {
            #warning TODO: Debug to catch invalid battery state, remove!
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
    Cleanup _hostModeEnter(bool interrupt=false) {
        _hostModeSet(true, interrupt);
        return std::make_unique<_Cleanup>([=] { _hostModeSet(false); });
    }
    
    // SD mode: acquires the device lock, tells the device to enter host mode,
    // loads ICEAppSDReadoutSTM onto the ICE40, and initializes the SD card.
    Cleanup _sdModeEnter(bool interrupt=false) {
        _sdModeSet(true, interrupt);
        return std::make_unique<_Cleanup>([=] { _sdModeSet(false); });
    }
    
    Cleanup _suddenTerminationDisable() {
        [[NSProcessInfo processInfo] disableSuddenTermination];
        return std::make_unique<_Cleanup>([=] {
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
                _sdMode.state = {
                    .hostMode = _hostModeEnter(interrupt),
                };
                
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
                _sdMode.state = {};
            }
        } catch (...) {
            // If device IO fails (ie via _hostModeEnter()), clean up our state and rethrow the exception
            _sdMode.state = {};
            // Only throw when enabling; when disabling we're executing within a destructor,
            // so we don't want to throw in that case.
            if (en) throw;
        }
    }
    
    // MARK: - Sync
    
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
    
    static std::optional<size_t> _LoadImageCount(const std::unique_lock<ImageLibrary>& lock,
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
                        const std::optional<size_t> count = _LoadImageCount(lock, _imageLibrary, deviceImageRange);
                        if (count) {
                            addCount = (uint32_t)*count;
                        } else {
                            throw StaleLibrary("_LoadImageCount failed");
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
    
    static MSP::ImgRingBuf _GetImgRingBuf(const MSP::SDState& sd) {
        const MSP::ImgRingBuf& imgRingBuf0 = sd.imgRingBufs[0];
        const MSP::ImgRingBuf& imgRingBuf1 = sd.imgRingBufs[1];
        const std::optional<int> comp = MSP::ImgRingBuf::Compare(imgRingBuf0, imgRingBuf1);
        if (!comp) return {};
        return *comp>=0 ? imgRingBuf0 : imgRingBuf1;
    }
    
    static void _ICEConfigure(MDCUSBDevice& dev) {
        std::string iceBinPath = [[[NSBundle mainBundle] pathForResource:@"ICEApp" ofType:@"bin"] UTF8String];
        Toastbox::Mmap mmap(iceBinPath);
        
        // Write the ICE40 binary
        dev.iceRAMWrite(mmap.data(), mmap.len());
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
        Cleanup pause;
        if (interrupt) pause = dataReadPause();
        auto lock = _device.signal.lock();
        return lock;
    }
    
    
    
    
    
//    void _dataRead_thread() {
//        constexpr auto SDModeTimeout = std::chrono::seconds(3);
//        try {
//            for (;;) {
//                // Wait for work
//                printf("[_dataRead_thread] Waiting for work...\n");
//                _dataRead.signal.wait([&] { return _dataRead_nextQueue() && !_dataRead.pause; });
//                
//                // Initiate SD mode
//                printf("[_dataRead_thread] Entering SD mode...\n");
//                auto sdMode = _sdModeEnter();
//                printf("[_dataRead_thread] Entered SD mode\n");
//                
//                std::optional<_SDBlock> dataReadEnd;
//                for (;;) {
//                    _DataReadWork work;
//                    {
//                        // Wait for work
//                        _DataReadWorkQueue* queue = nullptr;
//                        bool pause = false;
//                        auto lock = _dataRead.signal.wait_for(SDModeTimeout, [&] {
//                            queue = _dataRead_nextQueue();
//                            pause = _dataRead.pause;
//                            return queue || pause;
//                        });
//                        // Check if we timed out waiting for work
//                        if (!queue || pause) break;
////                        printf("[_dataRead_thread] Dequeued work\n");
//                        work = std::move(queue->front());
//                        queue->pop();
//                    }
//                    
//                    {
//                        const _SDBlock blockBegin = work.region.begin;
//                        const size_t len = (size_t)SD::BlockLen * (size_t)(work.region.end-work.region.begin);
//                        // Verify that the length of data that we're reading will fit in our buffer
//                        assert(len <= work.buf.cap());
//                        
//                        {
////                            printf("[_dataRead_thread] reading blockBegin:%ju len:%ju (%.1f MB)\n",
////                                (uintmax_t)blockBegin, (uintmax_t)len, (float)len/(1024*1024));
//                            
//                            const _SDBlock block = blockBegin;
//                            void*const dst = work.buf.storage();
//                            if (!dataReadEnd || *dataReadEnd!=block) {
//                                printf("[_dataRead_thread] Starting readout at %ju\n", (uintmax_t)block);
//                                // If readout was in progress at a different address, reset the device
//                                if (sdReadEnd) {
//                                    _device.device->reset();
//                                }
//                                
//                                // Verify that blockBegin can be safely cast to SD::Block
//                                assert(std::numeric_limits<SD::Block>::max() >= block);
//                                _device.device->sdRead((SD::Block)block);
//                                _device.device->readout(dst, len);
//                            
//                            } else {
////                                printf("[_dataRead_thread] Continuing readout at %ju\n", (uintmax_t)block);
//                                _device.device->readout(dst, len);
//                            }
//                            sdReadEnd = _SDBlockEnd(block, len);
//                        }
//                        
//                        work.callback(std::move(work));
//                    }
//                }
//                
//                printf("[_dataRead_thread] Exiting SD mode\n");
//            }
//        
//        } catch (const Toastbox::Signal::Stop&) {
//            printf("[_dataRead_thread] Stopping\n");
//        } catch (const std::exception& e) {
//            printf("[_dataRead_thread] Error: %s\n", e.what());
//        }
//    }
    
    
    
    
    
    std::string _serial;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        Thread thread;
        id /* CFRunLoopRef */ runLoop;
        std::unique_ptr<MDCUSBDevice> device;
    } _device;
    
    struct {
        std::unique_lock<std::mutex> deviceLock;
        Cleanup suddenTermination;
    } _hostMode;
    
    struct {
        struct {
            Cleanup hostMode;
            std::optional<_SDBlock> dataReadEnd;
        } state;
        STM::SDCardInfo cardInfo;
    } _sdMode;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        Thread thread;
        std::optional<float> progress;
    } _sync;
    
    struct _Status {
        MSP::State state = {};
        float batteryLevel = 0;
    };
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        Thread thread;
        std::optional<_Status> status;
    } _status;
};
using MDCDeviceUSBPtr = SharedPtr<MDCDeviceUSB>;

} // namespace MDCStudio

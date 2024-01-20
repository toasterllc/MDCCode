#import "MDCDevice.h"

namespace MDCStudio {

struct MDCDeviceUSB : MDCDevice {
    
    static Path _DirForSerial(const std::string_view& serial) {
        auto urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
        if (![urls count]) throw Toastbox::RuntimeError("failed to get NSApplicationSupportDirectory");
        
        const Path appSupportDir = Path([urls[0] fileSystemRepresentation]) / [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
        return appSupportDir / "Devices" / serial;
    }
    
    void init(_MDCUSBDevicePtr&& dev) {
        printf("MDCDevice::init() %p\n", this);
        
        _serial = dev->serial();
        MDCDevice::init(_DirForSerial(_serial)); // Call super
        
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
    
    const std::string& serial() {
        return _serial;
    }
    
    std::string _serial;
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        _Thread thread;
        id /* CFRunLoopRef */ runLoop;
        std::unique_ptr<MDCUSBDevice> device;
    } _device;

};

} // namespace MDCStudio

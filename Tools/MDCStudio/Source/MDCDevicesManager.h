#import <Foundation/Foundation.h>
#import <thread>
#import <forward_list>
#import <chrono>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import "Toastbox/RuntimeError.h"
#import "Toastbox/SendRight.h"
#import "Toastbox/USBDevice.h"
#import "Toastbox/Signal.h"
#import "MDCDevice.h"
#import "Object.h"

namespace MDCStudio {

struct MDCDevicesManager : Object {
    void init() {
        Object::init();
        
        _state.thread = std::thread([&] { _threadHandleDevices(); });
        // Wait for _state.runLoop to be populated
        for (;;) {
            {
                auto lock = std::unique_lock(_state.lock);
                if (_state.runLoop) break;
            }
            usleep(1000);
        }
    }
    
    ~MDCDevicesManager() {
        printf("[MDCDevicesManager] ~MDCDevicesManager()\n");
        // Tell thread to bail
        for (;;) {
            auto lock = std::unique_lock(_state.lock);
            if (!_state.runLoop) break;
            CFRunLoopStop((CFRunLoopRef)_state.runLoop);
        }
        
        assert(_state.thread.joinable());
        _state.thread.join();
    }
    
    std::vector<MDCDevicePtr> devices() {
        auto lock = std::unique_lock(_state.lock);
        std::vector<MDCDevicePtr> devs;
        for (const auto& kv : _state.devices) {
            devs.push_back(kv.second.device);
        }
        return devs;
    }
    
    using _SendRight = Toastbox::SendRight;
    using _USBDevice = Toastbox::USBDevice;
    using _USBDevicePtr = std::unique_ptr<Toastbox::USBDevice>;
    using _MDCUSBDevicePtr = std::unique_ptr<MDCUSBDevice>;
    
    struct _Device {
        MDCDevicePtr device;
        Object::ObserverPtr observer;
    };
    
//    static bool _DeviceAlreadyExists(const std::vector<_Device>& devices, std::string_view serial) {
//        for (const _Device& d : devices) {
//            if (d.serial == serial) {
//                return true;
//            }
//        }
//        return false;
//    }
    
    void _threadHandleDevices() {
        printf("[MDCDevicesManager : _threadHandleDevices] Start\n");
        
        {
            auto lock = std::unique_lock(_state.lock);
            _state.runLoop = CFBridgingRelease(CFRetain(CFRunLoopGetCurrent()));
        }
        
        IONotificationPortRef notePort = IONotificationPortCreate(kIOMasterPortDefault);
        if (!notePort) throw Toastbox::RuntimeError("IONotificationPortCreate returned null");
        Defer(IONotificationPortDestroy(notePort));
        
        _SendRight serviceIter;
        {
            io_iterator_t iter = MACH_PORT_NULL;
            kern_return_t kr = IOServiceAddMatchingNotification(notePort, kIOMatchedNotification,
                IOServiceMatching(kIOUSBDeviceClassName), _Nop, nullptr, &iter);
            if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddMatchingNotification failed: 0x%x", kr);
            serviceIter = _SendRight(_SendRight::NoRetain, iter);
        }
        
        CFRunLoopSourceRef rls = IONotificationPortGetRunLoopSource(notePort);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
        
        for (;;) @autoreleasepool {
            bool changed = false;
            
            // Handle connected devices
            for (;;) {
                _SendRight service(_SendRight::NoRetain, IOIteratorNext(serviceIter));
                if (!service) break;
                
                _USBDevicePtr usbDev;
                try {
                    usbDev = std::make_unique<_USBDevice>(service);
                    if (!MDCUSBDevice::USBDeviceMatches(*usbDev)) continue;
                
                } catch (const std::exception& e) {
                    // Ignore failures to create USBDevice
                    printf("Ignoring USB device: %s\n", e.what());
                    continue;
                }
                
                const std::string serial = usbDev->serialNumber();
                
                // If we already have a device in `_devices` for the given serial,
                // add the _USBDevicePtr to _state.pending.
                {
                    auto lock = std::unique_lock(_state.lock);
                    
                    if (_state.devices.find(serial) == _state.devices.end()) {
                        _state.pending[serial].push_back(std::move(usbDev));
                        continue;
                    }
                }
                
                // Create a MDCUSBDevice from the USBDevice
                _MDCUSBDevicePtr dev;
                try {
                    dev = std::make_unique<MDCUSBDevice>(std::move(usbDev));
                
                } catch (const std::exception& e) {
                    // Ignore failures to create MDCUSBDevice
                    printf("Ignoring USB device: %s\n", e.what());
                    continue;
                }
                
                // Create our final MDCDevice instance
                auto selfWeak = selfOrNullWeak<MDCDevicesManager>();
                if (!selfWeak.lock()) goto done;
                MDCDevicePtr mdc = Object::Create<MDCDevice>(std::move(dev));
                Object::ObserverPtr ob = mdc->observerAdd([=] (MDCDevicePtr device, const Object::Event& ev) {
                    auto selfStrong = selfWeak.lock();
                    if (!selfStrong) return;
                    selfStrong->_deviceChanged(device);
                });
                
                // Add the device to our _state.devices
                {
                    auto lock = std::unique_lock(_state.lock);
                    _state.devices[serial] = {
                        .device = mdc,
                        .observer = ob,
                    };
                    changed = true;
                }
                
                printf("Device connected\n");
            }
            
            // Let observers know that a device appeared
            if (changed) observersNotify({});
            
            // Wait for matching services to appear
            CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
            if (r == kCFRunLoopRunStopped) break; // Signalled to stop
            assert(r == kCFRunLoopRunHandledSource);
        }
        
    done:
        // Signal that we've stopped
        {
            auto lock = std::unique_lock(_state.lock);
            _state.runLoop = nullptr;
        }
        
        printf("[MDCDevicesManager : _threadHandleDevices] Returning\n");
    }
    
    void _deviceChanged(MDCDevicePtr device) {
        // Ignore if the device is still alive
        if (device->alive()) return;
        
        // Remove `device` from _state.devices
        {
            auto lock = std::unique_lock(_state.lock);
            auto it = _state.devices.find(device->serial());
            assert(it != _state.devices.end());
            assert(it->second.device == device);
            _state.devices.erase(it);
        }
        
        // Signal runloop that it needs to recheck its pending devices
        #warning TODO: implement comment ^^^
        
        // Let observers know that a device disappeared
        observersNotify({});
    }
    
    static void _Nop(void* ctx, io_iterator_t iter) {}
    
    struct {
        std::mutex lock; // Protects this struct
        std::thread thread;
        id /* CFRunLoopRef */ runLoop;
        std::map<std::string,_Device> devices;
        std::map<std::string,std::vector<_USBDevicePtr>> pending;
    } _state;
};

using MDCDevicesManagerPtr = SharedPtr<MDCDevicesManager>;

inline MDCDevicesManagerPtr MDCDevicesManagerGlobal() {
    static MDCDevicesManagerPtr x = Object::Create<MDCDevicesManager>();
    return x;
}

} // namespace MDCStudio

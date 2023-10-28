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
        
        _thread = std::thread([&] { _threadHandleDevices(); });
        // Wait for the thread to initialize, so that we know the devices
        // are valid as soon as we're instantiated.
        _state.signal.wait([&] { return _state.init; });
    }
    
    ~MDCDevicesManager() {
        printf("[MDCDevicesManager : _threadHandleDevices] ~MDCDevicesManager()\n");
        
        // Tell thread to bail
        _state.signal.stop();
        _RunLoopInterrupt(_runLoop);
        
        assert(_thread.joinable());
        _thread.join();
    }
    
    std::vector<MDCDevicePtr> devices() {
        auto lock = _state.signal.lock();
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
    
    void _threadHandleDevices() {
        printf("[MDCDevicesManager : _threadHandleDevices] Start\n");
        
        _runLoop = CFBridgingRelease(CFRetain(CFRunLoopGetCurrent()));
        
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
        
        try {
            for (;;) @autoreleasepool {
                bool changed = false;
                
                // Remove dead devices from _state.devices
                {
                    auto lock = _state.signal.lock();
                    for (auto it=_state.devices.begin(); it!=_state.devices.end();) {
                        const _Device& device = it->second;
                        if (!device.device->alive()) {
                            it = _state.devices.erase(it);
                            changed = true;
                        } else {
                            it++;
                        }
                    }
                }
                
                // Add new devices to _state.pending
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
                    
                    // Add the device to _state.pending.
                    const std::string serial = usbDev->serialNumber();
                    {
                        auto lock = _state.signal.lock();
                        _state.pending[serial].push_back(std::move(usbDev));
                    }
                }
                
                // Promote devices from _state.pending to _state.devices, if no device
                // exists for the given serial in _state.devices.
                // We loop until `promote` is empty, because the first device for a
                // given serial might not work, so we need to try the next one, etc.
                for (;;) {
                    // Assemble devices to promote
                    std::map<std::string,_USBDevicePtr> promote;
                    {
                        auto lock = _state.signal.lock();
                        for (auto& kv : _state.pending) {
                            const std::string& serial = kv.first;
                            std::vector<_USBDevicePtr>& devices = kv.second;
                            if (devices.empty()) continue;
                            // If we have a device for the serial
                            if (_state.devices.find(kv.first) != _state.devices.end()) continue;
                            promote[serial] = std::move(devices.back());
                            devices.pop_back();
                        }
                    }
                    
                    if (promote.empty()) break;
                    
                    for (auto& kv : promote) {
                        const std::string& serial = kv.first;
                        _USBDevicePtr& usbDev = kv.second;
                        
                        // Create a MDCUSBDevice from the USBDevice
                        _MDCUSBDevicePtr mdcUSBDev;
                        try {
                            mdcUSBDev = std::make_unique<MDCUSBDevice>(std::move(usbDev));
                        
                        } catch (const std::exception& e) {
                            // Ignore failures to create MDCUSBDevice
                            printf("Ignoring USB device: %s\n", e.what());
                            continue;
                        }
                        
                        // Create our final MDCDevice instance
                        auto selfWeak = selfOrNullWeak<MDCDevicesManager>();
                        if (!selfWeak.lock()) throw Toastbox::Signal::Stop();
                        MDCDevicePtr mdc = Object::Create<MDCDevice>(std::move(mdcUSBDev));
                        Object::ObserverPtr ob = mdc->observerAdd([=] (MDCDevicePtr device, const Object::Event& ev) {
                            auto selfStrong = selfWeak.lock();
                            if (!selfStrong) return;
                            if (ev.prop == &device->_status) return; // Ignore status changes
                            selfStrong->_deviceChanged(device);
                        });
                        
                        // Add the device to our _state.devices
                        {
                            auto lock = _state.signal.lock();
                            _state.devices[serial] = {
                                .device = mdc,
                                .observer = ob,
                            };
                            changed = true;
                        }
                        
                        printf("[MDCDevicesManager : _threadHandleDevices] Device connected\n");
                    }
                }
                
                // Let observers know that a device appeared
                if (changed) observersNotify({});
                
                // Wait for matching services to appear
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
                {
                    // Check if we need to bail, and set _state.init if needed
                    auto lock = _state.signal.lock();
                    if (!_state.init) {
                        _state.init = true;
                        _state.signal.signalAll();
                    }
                }
            }
        
        } catch (const Toastbox::Signal::Stop&) {
            printf("[MDCDevicesManager : _threadHandleDevices] Stopping\n");
        
        } catch (const std::exception& e) {
            printf("[MDCDevicesManager : _threadHandleDevices] Error: %s\n", e.what());
        }
        
        printf("[MDCDevicesManager : _threadHandleDevices] Terminating\n");
    }
    
    static void _RunLoopInterrupt(id /* CFRunLoopRef */ x) {
        CFRunLoopPerformBlock((CFRunLoopRef)x, kCFRunLoopCommonModes, ^{
            CFRunLoopStop(CFRunLoopGetCurrent());
        });
        CFRunLoopWakeUp((CFRunLoopRef)x);
    }
    
    void _deviceChanged(MDCDevicePtr device) {
        printf("[MDCDevicesManager : _threadHandleDevices] _deviceChanged\n");
        // Signal runloop that it needs to recheck its pending devices
        _RunLoopInterrupt(_runLoop);
    }
    
    static void _Nop(void* ctx, io_iterator_t iter) {}
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::map<std::string,_Device> devices;
        std::map<std::string,std::vector<_USBDevicePtr>> pending;
        bool init = false;
    } _state;
    
    std::thread _thread;
    id /* CFRunLoopRef */ _runLoop;
};

using MDCDevicesManagerPtr = SharedPtr<MDCDevicesManager>;

inline MDCDevicesManagerPtr MDCDevicesManagerGlobal() {
    static MDCDevicesManagerPtr x = Object::Create<MDCDevicesManager>();
    return x;
}

} // namespace MDCStudio

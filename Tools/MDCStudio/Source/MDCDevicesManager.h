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
        printf("[MDCDevicesManager] ~MDCDevicesManager()\n");
        
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
        auto timeStart = std::chrono::steady_clock::now();
        
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
                // We do this in a way that avoids calling MDCDevice::alive() while our _state.signal
                // lock is held, otherwise devices() would be blocked while we call alive(), and
                // during MDCDevice initialization, alive() won't return until the device is
                // initialized, which effectively means our devices() function can't return until the
                // MDCDevice is fully initialized. MDCDevice initialization can take a few seconds,
                // so we don't want to block devices() that long.
                {
                    // Copy devices into `devices`
                    std::set<MDCDevicePtr> devices;
                    {
                        auto lock = _state.signal.lock();
                        for (const auto& kv : _state.devices) {
                            devices.insert(kv.second.device);
                        }
                    }
                    
                    // Filter `devices` down to the alive devices
                    std::set<MDCDevicePtr> alive;
                    for (const MDCDevicePtr& device : devices) {
                        if (device->alive()) alive.insert(device);
                    }
                    
                    // Remove the dead devices from _state.devices
                    {
                        auto lock = _state.signal.lock();
                        for (auto it=_state.devices.begin(); it!=_state.devices.end();) {
                            const _Device& device = it->second;
                            if (alive.find(device.device) == alive.end()) {
                                it = _state.devices.erase(it);
                                changed = true;
                            } else {
                                it++;
                            }
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
                        printf("Ignoring USB device (_USBDevice): %s\n", e.what());
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
                        
                        // Create our final MDCDevice instance
                        auto selfWeak = selfOrNullWeak<MDCDevicesManager>();
                        if (!selfWeak.lock()) throw Toastbox::Signal::Stop();
                        
                        MDCDevicePtr mdc;
                        try {
                            mdc = Object::Create<MDCDevice>(std::move(usbDev));
                        } catch (const std::exception& e) {
                            // Ignore failures to create MDCDevice
                            printf("Ignoring USB device (MDCDevice): %s\n", e.what());
                            continue;
                        }
                        
                        Object::ObserverPtr ob = mdc->observerAdd([=] (MDCDevicePtr device, const Object::Event& ev) {
                            auto selfStrong = selfWeak.lock();
                            if (!selfStrong) return;
                            if (ev.prop == &device->_status) return; // Ignore status changes
                            if (ev.prop == &device->_sync) return; // Ignore sync changes
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
                
                {
                    // Set _state.init if needed
                    auto lock = _state.signal.lock();
                    if (!_state.init) {
                        using namespace std::chrono;
                        const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
                        printf("[MDCDevicesManager : _threadHandleDevices] Initial init took %ju ms\n", (uintmax_t)duration.count());
                        _state.init = true;
                        _state.signal.signalAll();
                    }
                }
                
                // Wait for matching services to appear
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
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
        printf("[MDCDevicesManager] _deviceChanged\n");
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

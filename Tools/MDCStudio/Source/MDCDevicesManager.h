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
#import "Tools/Shared/ELF32Binary.h"
#import "MDCDevice.h"
#import "Object.h"

namespace MDCStudio {

struct MDCDevicesManager : Object {
    void init() {
        Object::init();
        
        _thread.thread = std::thread([&] { _threadHandleDevices(); });
        // Wait for _thread.runLoop to be populated
        _thread.signal.wait([&] { return (bool)_thread.runLoop; });
    }
    
    ~MDCDevicesManager() {
        printf("[MDCDevicesManager] ~MDCDevicesManager()\n");
        for (;;) {
            auto lock = std::unique_lock(_state.lock);
            if (!_thread.runLoop) break;
            CFRunLoopStop((CFRunLoopRef)_thread.runLoop);
        }
        assert(_thread.thread.joinable());
        _thread.thread.join();
    }
    
    std::vector<MDCDevicePtr> devices() {
        auto lock = std::unique_lock(_state.lock);
        std::vector<MDCDevicePtr> devs;
        for (const _Device& dev : _state.devices) {
            devs.push_back(dev.dev);
        }
        return devs;
    }
    
    using _SendRight = Toastbox::SendRight;
    using _USBDevice = Toastbox::USBDevice;
    
    void _threadHandleDevices() {
        printf("[MDCDevicesManager : _threadHandleDevices] Start\n");
        
        enum class _DeviceState {
            STMLoaderInvoke,
            STMLoaderCheck,
            STMAppWrite,
            STMAppCheck,
            Finish,
        };
        
        {
            auto lock = _thread.signal.lock();
            _thread.runLoop = CFBridgingRelease(CFRetain(CFRunLoopGetCurrent()));
            _thread.signal.signalAll();
        }
        
        // Signal that we've exited by clearing the runloop
        Defer(
            auto lock = _thread.signal.lock();
            _thread.runLoop = nil;
        );
        
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
        
        std::map<std::string,_DeviceState> deviceStates;
        for (;;) @autoreleasepool {
            bool changed = false;
            {
                auto lock = _thread.signal.lock();
                
                // Handle connected devices
                for (;;) {
                    _SendRight service(_SendRight::NoRetain, IOIteratorNext(serviceIter));
                    if (!service) break;
                    
                    std::unique_ptr<MDCUSBDevice> dev;
                    try {
                        _USBDevice usbDev(service);
                        if (!MDCUSBDevice::USBDeviceMatches(usbDev)) continue;
                        dev = std::make_unique<MDCUSBDevice>(std::move(usbDev));
                    
                    } catch (const std::exception& e) {
                        // Ignore failures to create USBDevice
                        printf("Ignoring USB device: %s\n", e.what());
                        continue;
                    }
                    
                    try {
                        for (;;) {
                            _DeviceState& state = deviceStates[dev->serial()];
                            switch (state) {
                            case _DeviceState::STMLoaderInvoke: {
                                dev->bootloaderInvoke();
                                state = _DeviceState::STMLoaderCheck;
                                break; // Device will re-enumerate; continue to the next device
                            }
                            
                            case _DeviceState::STMLoaderCheck: {
                                if (dev->statusGet().mode == STM::Status::Mode::STMLoader) {
                                    state = _DeviceState::STMAppWrite;
                                } else {
                                    state = _DeviceState::STMLoaderInvoke; // Start over
                                }
                                continue;
                            }
                            
                            case _DeviceState::STMAppWrite: {
                                _deviceBootload(*dev);
                                state = _DeviceState::STMAppCheck;
                                break; // Device will re-enumerate; continue to the next device
                            }
                            
                            case _DeviceState::STMAppCheck: {
                                if (dev->statusGet().mode == STM::Status::Mode::STMApp) {
                                    state = _DeviceState::Finish;
                                } else {
                                    state = _DeviceState::STMLoaderInvoke; // Start over
                                }
                                continue;
                            }
                            
                            case _DeviceState::Finish: {
                                state = _DeviceState::STMLoaderInvoke; // Start over if this device appears again
                                
                                // Create our final MDCDevice instance
                                MDCDevicePtr mdc = Object::Create<MDCDevice>(std::move(*dev));
                                
                                // Watch the service so we know when it goes away
                                io_object_t ioObj = MACH_PORT_NULL;
                                kern_return_t kr = IOServiceAddInterestNotification(notePort, service,
                                    kIOGeneralInterest, _ServiceInterestCallback, this, &ioObj);
                                if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddInterestNotification failed: 0x%x", kr);
                                
                                // Add the device to our _state.devices
                                {
                                    auto lock = std::unique_lock(_state.lock);
                                    _state.devices.push_back(_Device{
                                        .dev = mdc,
                                        .note = _SendRight(_SendRight::NoRetain, ioObj),
                                    });
                                }
                                
                                printf("Device connected\n");
                                changed = true;
                                break; // Device is fully configured
                            }}
                            
                            break;
                        }
                    
                    } catch (const std::exception& e) {
                        // Ignore failures to create USBDevice
                        printf("Configure MDCDevice failed: %s\n", e.what());
                    }
                }
                
                // Handle disconnected devices
                {
                    for (const _SendRight& service : _thread.terminatedServices) {
                        auto lock = std::unique_lock(_state.lock);
                        for (auto it=_state.devices.begin(); it!=_state.devices.end(); it++) {
                            if (it->dev->service() == service) {
                                _state.devices.erase(it);
                                changed = true;
                                printf("Device disconnected\n");
                                break;
                            }
                        }
                    }
                    
                    _thread.terminatedServices.clear();
                }
            }
            
            // Notify observers that something changed
            if (changed) observersNotify({});
            
            sleep(5);
            
            // Wait for matching services to appear
            CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
            if (r == kCFRunLoopRunStopped) break; // Signalled to stop
            assert(r == kCFRunLoopRunHandledSource);
        }
        
        printf("[MDCDevicesManager : _threadHandleDevices] Returning\n");
    }
    
    void _deviceBootload(MDCUSBDevice& dev) {
        const char* STMBinPath = "/Users/dave/repos/MDCCode/Code/STM32/STApp/Release/STApp.elf";
        ELF32Binary elf(STMBinPath);
        
        elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
        size_t size, const char* name) {
            dev.stmWrite(paddr, data, size);
        });
        
        // Reset the device, triggering it to load the program we just wrote
        dev.stmReset(elf.entryPointAddr());
    }
    
    static void _ServiceInterestCallback(void* ctx, io_service_t service, uint32_t msgType, void* msgArg) {
        ((MDCDevicesManager*)ctx)->_serviceInterestCallback(service, msgType, msgArg);
    }
    
    void _serviceInterestCallback(io_service_t service, uint32_t msgType, void* msgArg) {
        if (msgType == kIOMessageServiceIsTerminated) {
            _thread.terminatedServices.emplace_back(_SendRight::Retain, service);
        }
    }
    
    static void _Nop(void* ctx, io_iterator_t iter) {}
    
    struct _Device {
        MDCDevicePtr dev;
        _SendRight note;
    };
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::thread thread;
        id /* CFRunLoopRef */ runLoop;
        std::vector<_SendRight> terminatedServices;
    } _thread;
    
    struct {
        std::mutex lock; // Protects this struct
        std::vector<_Device> devices;
    } _state = {};
};

using MDCDevicesManagerPtr = SharedPtr<MDCDevicesManager>;

inline MDCDevicesManagerPtr MDCDevicesManagerGlobal() {
    static MDCDevicesManagerPtr x = Object::Create<MDCDevicesManager>();
    return x;
}

} // namespace MDCStudio

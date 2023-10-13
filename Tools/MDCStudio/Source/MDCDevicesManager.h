#import <Foundation/Foundation.h>
#import <thread>
#import <forward_list>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import "Toastbox/RuntimeError.h"
#import "Toastbox/SendRight.h"
#import "Toastbox/USBDevice.h"
#import "Tools/Shared/ELF32Binary.h"
#import "MDCDevice.h"

namespace MDCStudio {

class MDCDevicesManager {
public:
    using Observer = std::function<bool()>;
    
    static void Start() {
        std::thread thread(_ThreadHandleDevices);
        thread.detach();
    }
    
    static std::vector<MDCDevicePtr> Devices() {
        auto lock = std::unique_lock(_State.lock);
        std::vector<MDCDevicePtr> devs;
        for (const _Device& dev : _State.devices) {
            devs.push_back(dev.dev);
        }
        return devs;
    }
    
    static void AddObserver(Observer&& observer) {
        auto lock = std::unique_lock(_State.lock);
        _State.observers.push_front(std::move(observer));
    }
    
private:
    
    using _SendRight = Toastbox::SendRight;
    using _USBDevice = Toastbox::USBDevice;
    
    static void _ThreadHandleDevices() {
        enum class _DeviceState {
            STMLoaderInvoke,
            STMLoaderCheck,
            STMAppWrite,
            STMAppCheck,
            Finish,
        };
        
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
                            _DeviceBootload(*dev);
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
                                kIOGeneralInterest, _ServiceInterestCallback, nullptr, &ioObj);
                            if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddInterestNotification failed: 0x%x", kr);
                            
                            // Add the device to our _State.devices
                            {
                                auto lock = std::unique_lock(_State.lock);
                                _State.devices.push_back(_Device{
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
                for (const _SendRight& service : _TerminatedServices) {
                    auto lock = std::unique_lock(_State.lock);
                    for (auto it=_State.devices.begin(); it!=_State.devices.end(); it++) {
                        if (it->dev->service() == service) {
                            _State.devices.erase(it);
                            changed = true;
                            printf("Device disconnected\n");
                            break;
                        }
                    }
                }
                
                _TerminatedServices.clear();
            }
            
            // Notify observers that something changed
            if (changed) {
                _NotifyObservers();
            }
            
            // Wait for matching services to appear
            CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
            assert(r == kCFRunLoopRunHandledSource);
        }
    }
    
    static void _DeviceBootload(MDCUSBDevice& dev) {
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
        if (msgType == kIOMessageServiceIsTerminated) {
            _TerminatedServices.emplace_back(_SendRight::Retain, service);
        }
    }
    
    static void _NotifyObservers() {
        auto lock = std::unique_lock(_State.lock);
        auto prev = _State.observers.before_begin();
        for (auto it=_State.observers.begin(); it!=_State.observers.end();) {
            // Notify the observer; it returns whether it's still valid
            // If it's not valid (it returned false), remove it from the list
            if (!(*it)()) {
                it = _State.observers.erase_after(prev);
            } else {
                prev = it;
                it++;
            }
        }
    }
    
    static void _Nop(void* ctx, io_iterator_t iter) {}
    
    struct _Device {
        MDCDevicePtr dev;
        _SendRight note;
    };
    
    // _TerminatedServices: no locking required because it's only accessed by the thread
    static inline std::vector<_SendRight> _TerminatedServices;
    
    static inline struct {
        std::mutex lock; // Protects this struct
        std::vector<_Device> devices;
        std::forward_list<Observer> observers;
    } _State = {};
};

} // namespace MDCStudio

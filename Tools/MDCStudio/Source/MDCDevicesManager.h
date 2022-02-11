#import <Foundation/Foundation.h>
#import <thread>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import "Toastbox/RuntimeError.h"
#import "Toastbox/SendRight.h"
#import "Toastbox/USBDevice.h"
#import "Tools/Shared/ELF32Binary.h"
#import "MDCDevice.h"

class MDCDevicesManager {
public:
    using Observer = std::function<void()>;
    
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
    
    static void AddObserver(const Observer& obs) {
        auto lock = std::unique_lock(_State.lock);
        _State.observers.push_back(obs);
    }
    
private:
    
    using _SendRight = Toastbox::SendRight;
    using _USBDevice = Toastbox::USBDevice;
    
    static void _ThreadHandleDevices() {
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
        
        std::set<std::string> bootloadedDeviceSerials;
        for (;;) {
            // Drain all services from the iterator
            for (;;) {
                _SendRight service(_SendRight::NoRetain, IOIteratorNext(serviceIter));
                if (!service) break;
                
                MDCDevicePtr dev;
                try {
                    _USBDevice usbDev(service);
                    if (!MDCDevice::USBDeviceMatches(usbDev)) continue;
                    dev = std::make_shared<MDCDevice>(std::move(usbDev));
                
                } catch (const std::exception& e) {
                    // Ignore failures to create USBDevice
                    printf("Ignoring USB device: %s\n", e.what());
                    continue;
                }
                
                try {
                    const STM::Status status = dev->statusGet();
                    switch (status.mode) {
                    case STM::Status::Modes::STMLoader:
                        _DeviceBootload(dev);
                        bootloadedDeviceSerials.insert(dev->serial());
                        break;
                    
                    case STM::Status::Modes::STMApp:
                        // If we previously configured this device, this device is ready!
                        if (bootloadedDeviceSerials.find(dev->serial()) != bootloadedDeviceSerials.end()) {
                            bootloadedDeviceSerials.erase(dev->serial());
                            
                            // Load ICE40 with our app
                            _ICEConfigure(dev);
                            
                            // Watch the service so we know when it goes away
                            io_object_t ioObj = MACH_PORT_NULL;
                            kern_return_t kr = IOServiceAddInterestNotification(notePort, service, 
                                kIOGeneralInterest, _ServiceInterestCallback, nullptr, &ioObj);
                            if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddInterestNotification failed: 0x%x", kr);
                            
                            // Add the device to our _State.devices
                            {
                                auto lock = std::unique_lock(_State.lock);
                                _State.devices.push_back(_Device{
                                    .dev = dev,
                                    .note = _SendRight(_SendRight::NoRetain, ioObj),
                                });
                            }
                            
                            _HandleDeviceConnected(dev);
                            
                        // If we didn't previously configure this device, trigger the bootloader so we can configure it
                        } else {
                            dev->bootloaderInvoke();
                        }
                        break;
                    
                    default:
                        bootloadedDeviceSerials.erase(dev->serial());
                        dev->bootloaderInvoke();
                        break;
                    }
                
                } catch (const std::exception& e) {
                    // Ignore failures to create USBDevice
                    printf("Configure MDCDevice failed: %s\n", e.what());
                }
            }
            
            // Wait for matching services to appear
            CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
            assert(r == kCFRunLoopRunHandledSource);
        }
    }
    
    static void _HandleDeviceConnected(MDCDevicePtr dev) {
        printf("_HandleDeviceConnected\n");
        dispatch_async(dispatch_get_main_queue(), ^{
            _NotifyObservers();
        });
    }
    
    static void _HandleDeviceDisconnected(MDCDevicePtr dev) {
        printf("_HandleDeviceDisconnected\n");
        dispatch_async(dispatch_get_main_queue(), ^{
            _NotifyObservers();
        });
    }
    
    static void _DeviceBootload(MDCDevicePtr dev) {
        const char* STMBinPath = "/Users/dave/repos/MDC/Code/STM32/STApp/Release/STApp.elf";
        ELF32Binary elf(STMBinPath);
        
        elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
        size_t size, const char* name) {
            dev->stmWrite(paddr, data, size);
        });
        
        // Reset the device, triggering it to load the program we just wrote
        dev->stmReset(elf.entryPointAddr());
    }
    
    static void _ICEConfigure(MDCDevicePtr dev) {
        const char* ICEBinPath = "/Users/dave/repos/MDC/Code/ICE40/ICEAppSDReadoutSTM/Synth/Top.bin";
        Mmap mmap(ICEBinPath);
        
        // Write the ICE40 binary
        dev->iceWrite(mmap.data(), mmap.len());
    }
    
    static void _ServiceInterestCallback(void* ctx, io_service_t service, uint32_t msgType, void* msgArg) {
        if (msgType == kIOMessageServiceIsTerminated) {
            auto lock = std::unique_lock(_State.lock);
            
            for (auto it=_State.devices.begin(); it!=_State.devices.end(); it++) {
                if (it->dev->usbDevice().service() == service) {
                    MDCDevicePtr dev = it->dev;
                    _State.devices.erase(it);
                    _HandleDeviceDisconnected(dev);
                    break;
                }
            }
        }
    }
    
    static void _NotifyObservers() {
        std::vector<Observer> observersCopy;
        {
            auto lock = std::unique_lock(_State.lock);
            observersCopy = _State.observers;
        }
        
        for (const Observer& obs : observersCopy) {
            obs();
        }
    }
    
    static void _Nop(void* ctx, io_iterator_t iter) {}
    
    struct _Device {
        MDCDevicePtr dev;
        _SendRight note;
    };
    
    static inline struct {
        std::mutex lock; // Protects this struct
        std::vector<_Device> devices;
        std::vector<Observer> observers;
    } _State = {};
};

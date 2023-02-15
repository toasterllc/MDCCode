#include <vector>
#include <iostream>
#include <fstream>
#include <algorithm>
#include <cstring>
#include <cmath>
#include <thread>
#include <csignal>
#include <condition_variable>
#include <chrono>
#include "STM.h"
#include "MDCUSBDevice.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/IntForStr.h"
#include "ChecksumFletcher32.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"
#include "MSP.h"
#include "ELF32Binary.h"
using namespace Toastbox;
using namespace std::chrono_literals;

static constexpr const char* _ICEBinPath = "/Users/dave/repos/MDCCode/Code/ICE40/ICEAppImgCaptureSTM/Synth/Top.bin";
static constexpr const char* _STMAppPath = "/Users/dave/repos/MDCCode/Code/STM32/STApp/Release/STApp.elf";
static constexpr auto _HangTimeout = 250ms;

static std::mutex _Lock;
static std::condition_variable _Condition;
static bool _Signal = false;

static void _Abort() {
    printf("\a");
    fflush(stdout);
    _exit(0);
}

static void _STMWrite(MDCUSBDevice& device, const char* file) {
    ELF32Binary elf(file);
    
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        device.stmWrite(paddr, data, size);
    });
    
    // Reset the device, triggering it to load the program we just wrote
    device.stmReset(elf.entryPointAddr());
}



static void _ThreadStreamImages(std::unique_ptr<MDCUSBDevice>&& mdc) {
    constexpr Img::Size ImageSize = Img::Size::Thumb;
    constexpr uint8_t DstBlock = 0; // Always save to RAM block 0
    
    mdc->imgInit();
    
    try {
        for (uintmax_t i=0;; i++) {
    //        dispatch_async(dispatch_get_main_queue(), ^{
    //            printf("Watchdog\n");
    //            alarm(1);
    //        });
            
            const STM::ImgCaptureStats imgStats = mdc->imgCapture(DstBlock, 0, ImageSize);
            std::unique_ptr<uint8_t[]> img = mdc->imgReadout(ImageSize);
            printf("Got image %ju\n", i);
            
            {
                auto lock = std::unique_lock(_Lock);
                _Signal = true;
            }
            _Condition.notify_all();
        }
    
    } catch (...) {
        _Abort();
    }
}




static void _Nop(void* ctx, io_iterator_t iter) {}

static void _ThreadHandleDevices() {
    IONotificationPortRef p = IONotificationPortCreate(kIOMasterPortDefault);
    if (!p) throw Toastbox::RuntimeError("IONotificationPortCreate returned null");
    Defer(IONotificationPortDestroy(p));
    
    SendRight serviceIter;
    {
        io_iterator_t iter = MACH_PORT_NULL;
        kern_return_t kr = IOServiceAddMatchingNotification(p, kIOMatchedNotification,
            IOServiceMatching(kIOUSBDeviceClassName), _Nop, nullptr, &iter);
        if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddMatchingNotification failed: 0x%x", kr);
        serviceIter = SendRight(SendRight::NoRetain, iter);
    }
    
    CFRunLoopSourceRef rls = IONotificationPortGetRunLoopSource(p);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
    
//    std::set<std::string> configuredDevices;
    for (;;) {
        // Drain all services from the iterator
        for (;;) {
            SendRight service(SendRight::NoRetain, IOIteratorNext(serviceIter));
            if (!service) break;
            
            try {
                USBDevice dev(service);
                if (!MDCUSBDevice::USBDeviceMatches(dev)) continue;
                
                std::unique_ptr<MDCUSBDevice> mdc = std::make_unique<MDCUSBDevice>(std::move(dev));
                
                const STM::Status status = mdc->statusGet();
                switch (status.mode) {
                case STM::Status::Mode::STMLoader: {
                    _STMWrite(*mdc, _STMAppPath);
                    break;
                }
                
                case STM::Status::Mode::STMApp: {
                    const char* ICEBinPath = _ICEBinPath;
                    Mmap mmap(ICEBinPath);
                    
                    // Enter host mode
                    mdc->mspHostModeSet(true);
                    
                    // Write the ICE40 binary
                    mdc->iceRAMWrite(mmap.data(), mmap.len());
                    
                    std::thread t(_ThreadStreamImages, std::move(mdc));
                    t.detach();
                    
//                    // If we previously configured this device, this device is ready!
//                    if (configuredDevices.find(mdc->serial()) != configuredDevices.end()) {
//                        dispatch_async(dispatch_get_main_queue(), ^{
//                            [self _setMDCUSBDevice:std::move(mdc)];
//                        });
//                        
//                        configuredDevices.erase(mdc->serial());
//                        
//                    // If we didn't previously configure this device, trigger the bootloader so we can configure it
//                    } else {
//                        mdc->bootloaderInvoke();
//                    }
                    break;
                }
                
                default: {
                    abort();
                }
                
//                default:
////                    configuredDevices.erase(mdc->serial());
////                    mdc->bootloaderInvoke();
//                    break;
                }
            
            } catch (const std::exception& e) {
                // Ignore failures to create USBDevice
                printf("Configure MDCUSBDevice failed: %s\n", e.what());
            }
        }
        
        // Wait for matching services to appear
        CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
        assert(r == kCFRunLoopRunHandledSource);
    }
}




int main(int argc, const char* argv[]) {
    std::thread t(_ThreadHandleDevices);
    t.detach();
    
    for (;;) {
        auto lock = std::unique_lock(_Lock);
        _Condition.wait_for(lock, _HangTimeout, []{ return _Signal; });
        if (!_Signal) _Abort();
        _Signal = false;
        
//        printf("Main thread loop\n");
    }
    return 0;
}

#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STAppTypes.h"

class MDCDevice : public USBDevice {
public:
    static std::vector<MDCDevice> FindDevices() {
        std::vector<MDCDevice> devices;
        NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
        match[@kIOPropertyMatchKey] = @{
            @"idVendor": @1155,
            @"idProduct": @57105,
        };
        
        io_iterator_t ioServicesIter = MACH_PORT_NULL;
        kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFDictionaryRef)CFBridgingRetain(match), &ioServicesIter);
        if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceGetMatchingServices failed: %x", kr);
        
        SendRight servicesIter(ioServicesIter);
        while (servicesIter) {
            SendRight service(IOIteratorNext(servicesIter.port()));
            if (!service) break;
            try {
                MDCDevice device(std::move(service));
                devices.push_back(device);
            } catch (...) {}
        }
        return devices;
    }
    
    // Default constructor: empty
    MDCDevice() {}
    
    IOReturn reset() {
        // Send the reset vendor-defined control request
        IOReturn ior = vendorRequestOut(STApp::CtrlReqs::Reset, nullptr, 0);
        if (ior != kIOReturnSuccess) return ior;
        
        // Reset our pipes now that the device is reset
        for (const USBPipe& pipe : {cmdOutPipe, cmdInPipe, pixInPipe}) {
            ior = pipe.reset();
            if (ior != kIOReturnSuccess) return ior;
        }
        return kIOReturnSuccess;
    }
    
    USBPipe cmdOutPipe;
    USBPipe cmdInPipe;
    USBPipe pixInPipe;
    
private:
    MDCDevice(SendRight&& service) :
    USBDevice(std::move(service)) {
        std::vector<USBInterface> interfaces = usbInterfaces();
        if (interfaces.size() != 1) throw std::runtime_error("invalid number of USB interfaces");
        _interface = interfaces[0];
        cmdOutPipe = USBPipe(_interface, STApp::EndpointIdxs::CmdOut);
        cmdInPipe = USBPipe(_interface, STApp::EndpointIdxs::CmdIn);
        pixInPipe = USBPipe(_interface, STApp::EndpointIdxs::PixIn);
    }
    
    USBInterface _interface;
};

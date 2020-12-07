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
    
    void reset() {
        // Send the reset vendor-defined control request
        IOReturn ior = vendorRequestOut(STApp::CtrlReqs::Reset, nullptr, 0);
        if (ior != kIOReturnSuccess) throw RuntimeError("vendorRequestOut() failed: %x", ior);
        
        // Reset our pipes now that the device is reset
        for (const USBPipe& pipe : {cmdOutPipe, cmdInPipe, pixInPipe}) {
            ior = pipe.reset();
            if (ior != kIOReturnSuccess) throw RuntimeError("pipe.reset() failed: %x", ior);
        }
    }
    
    STApp::PixInfo pixInfo() {
        using namespace STApp;
        // Get Pix info
        PixInfo pixInfo;
        Cmd cmd = { .op = Cmd::Op::GetPixInfo };
        IOReturn ior = cmdOutPipe.write(cmd);
        if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
        ior = cmdInPipe.read(pixInfo);
        if (ior != kIOReturnSuccess) throw RuntimeError("cmdInPipe.read() failed: %x", ior);
        return pixInfo;
    }
    
    void pixStartStream() {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixStartStream,
            .arg = { .pixStream = { .test = false, } }
        };
        IOReturn ior = cmdOutPipe.write(cmd);
        if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
    }
    
    void pixReadImage(void* buf, size_t len) {
        IOReturn ior = pixInPipe.read(buf, len);
        if (ior != kIOReturnSuccess) throw RuntimeError("pixInPipe.read() failed: %x", ior);
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

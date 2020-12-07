#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STAppTypes.h"

class MDCDevice : public USBDevice {
public:
    static std::vector<MDCDevice> FindDevices() {
        return USBDevice::FindDevices<MDCDevice>(1155, 57105);
    }
    
    // Default constructor: empty
    MDCDevice() {}
    
    MDCDevice(SendRight&& service) :
    USBDevice(std::move(service)) {
        std::vector<USBInterface> interfaces = usbInterfaces();
        if (interfaces.size() != 1) throw std::runtime_error("invalid number of USB interfaces");
        _interface = interfaces[0];
        cmdOutPipe = USBPipe(_interface, STApp::EndpointIdxs::CmdOut);
        cmdInPipe = USBPipe(_interface, STApp::EndpointIdxs::CmdIn);
        pixInPipe = USBPipe(_interface, STApp::EndpointIdxs::PixIn);
    }
    
    void reset() {
        // Send the reset vendor-defined control request
        vendorRequestOut(STApp::CtrlReqs::Reset, nullptr, 0);
        
        // Reset our pipes now that the device is reset
        for (const USBPipe& pipe : {cmdOutPipe, cmdInPipe, pixInPipe}) {
            pipe.reset();
        }
    }
    
    STApp::PixInfo pixInfo() {
        using namespace STApp;
        Cmd cmd = { .op = Cmd::Op::GetPixInfo };
        cmdOutPipe.write(cmd);
        
        PixInfo pixInfo;
        cmdInPipe.read(pixInfo);
        return pixInfo;
    }
    
    void pixStartStream() {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixStartStream,
            .arg = { .pixStream = { .test = false, } }
        };
        cmdOutPipe.write(cmd);
    }
    
    void pixReadImage(void* buf, size_t len) {
        pixInPipe.read(buf, len);
    }
    
    USBPipe cmdOutPipe;
    USBPipe cmdInPipe;
    USBPipe pixInPipe;
    
private:
    USBInterface _interface;
};

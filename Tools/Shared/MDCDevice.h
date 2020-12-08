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
    
    STApp::PixStatus pixStatus() {
        using namespace STApp;
        Cmd cmd = { .op = Cmd::Op::PixGetStatus };
        cmdOutPipe.write(cmd);
        
        PixStatus pixStatus;
        cmdInPipe.read(pixStatus);
        return pixStatus;
    }
    
    void pixReset() {
        using namespace STApp;
        Cmd cmd = { .op = Cmd::Op::PixReset };
        cmdOutPipe.write(cmd);
        // Wait for completion by getting status
        pixStatus();
    }
    
    uint16_t pixI2CRead(uint16_t addr) {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixI2CTransaction,
            .arg = {
                .pixI2CTransaction = {
                    .write = false,
                    .addr = addr,
                }
            }
        };
        cmdOutPipe.write(cmd);
        return pixStatus().i2cReadVal;
    }
    
    void pixI2CWrite(uint16_t addr, uint16_t val) {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixI2CTransaction,
            .arg = {
                .pixI2CTransaction = {
                    .write = true,
                    .addr = addr,
                    .val = val,
                }
            }
        };
        cmdOutPipe.write(cmd);
        
        // Wait for completion by getting status
        pixStatus();
    }
    
    void pixStartStream() {
        using namespace STApp;
        Cmd cmd = {
            .op = Cmd::Op::PixStartStream,
            .arg = { .pixStream = { .test = false, } }
        };
        cmdOutPipe.write(cmd);
    }
    
    void pixReadImage(STApp::Pixel* pixels, size_t count) {
        pixInPipe.read(pixels, count*sizeof(STApp::Pixel));
    }
    
    USBPipe cmdOutPipe;
    USBPipe cmdInPipe;
    USBPipe pixInPipe;
    
private:
    USBInterface _interface;
};

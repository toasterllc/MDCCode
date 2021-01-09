#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STLoaderTypes.h"

class MDCLoaderDevice : public USBDevice {
public:
    static std::vector<MDCLoaderDevice> FindDevice() {
        return USBDevice::FindDevice<MDCLoaderDevice>(1155, 57105);
    }
    
    // Default constructor: empty
    MDCLoaderDevice() {}
    
    MDCLoaderDevice(SendRight&& service) :
    USBDevice(std::move(service)) {
        std::vector<USBInterface> interfaces = usbInterfaces();
        if (interfaces.size() != 2) throw std::runtime_error("invalid number of USB interfaces");
        _stInterface = interfaces[0];
        _iceInterface = interfaces[1];
        
        stCmdOutPipe = USBPipe(_stInterface, STLoader::EndpointIdxs::STCmdOut);
        stDataOutPipe = USBPipe(_stInterface, STLoader::EndpointIdxs::STDataOut);
        stStatusInPipe = USBPipe(_stInterface, STLoader::EndpointIdxs::STStatusIn);
        
        iceCmdOutPipe = USBPipe(_iceInterface, STLoader::EndpointIdxs::ICECmdOut);
        iceDataOutPipe = USBPipe(_iceInterface, STLoader::EndpointIdxs::ICEDataOut);
        iceStatusInPipe = USBPipe(_iceInterface, STLoader::EndpointIdxs::ICEStatusIn);
    }
    
    void ledSet(uint8_t idx, bool on) {
        using namespace STLoader;
        STCmd cmd = {
            .op = STCmd::Op::LEDSet,
            .arg = {
                .ledSet = {
                    .idx = idx,
                    .on = on,
                },
            },
        };
        stCmdOutPipe.write(cmd);
    }
    
    STLoader::STStatus stGetStatus() {
        using namespace STLoader;
        // Request status
        const STCmd cmd = { .op = STCmd::Op::GetStatus };
        stCmdOutPipe.write(cmd);
        // Read status
        STStatus status;
        stStatusInPipe.read(status);
        return status;
    }
    
    void stWriteData(uint32_t addr, const void* data, size_t len) {
        using namespace STLoader;
        
        // Send WriteData command
        const STCmd cmd = {
            .op = STCmd::Op::WriteData,
            .arg = {
                .writeData = {
                    .addr = addr,
                },
            },
        };
        stCmdOutPipe.write(cmd);
        // Send actual data
        stDataOutPipe.writeBuf(data, len);
    }
    
    void stReset(uint32_t entryPointAddr) {
        using namespace STLoader;
        const STCmd cmd = {
            .op = STCmd::Op::Reset,
            .arg = {
                .reset = {
                    .entryPointAddr = entryPointAddr,
                },
            },
        };
        
        stCmdOutPipe.write(cmd);
    }
    
    void iceStart(size_t len) {
        using namespace STLoader;
        const ICECmd cmd = {
            .op = ICECmd::Op::Start,
            .arg = {
                .start = {
                    .len = (uint32_t)len,
                }
            }
        };
        iceCmdOutPipe.write(cmd);
    }
    
    STLoader::ICEStatus iceGetStatus() {
        using namespace STLoader;
        // Request status
        const ICECmd cmd = { .op = ICECmd::Op::GetStatus, };
        iceCmdOutPipe.write(cmd);
        
        // Read status
        ICEStatus status;
        iceStatusInPipe.read(status);
        return status;
    }
    
    void iceFinish() {
        using namespace STLoader;
        const ICECmd cmd = { .op = ICECmd::Op::Finish };
        iceCmdOutPipe.write(cmd);
    }
    
    USBPipe stCmdOutPipe;
    USBPipe stDataOutPipe;
    USBPipe stStatusInPipe;
    
    USBPipe iceCmdOutPipe;
    USBPipe iceDataOutPipe;
    USBPipe iceStatusInPipe;
    
private:
    USBInterface _stInterface;
    USBInterface _iceInterface;
};

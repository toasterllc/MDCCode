#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STLoaderTypes.h"

class MDCLoaderDevice : public USBDevice {
public:
    static std::vector<MDCLoaderDevice> FindDevices() {
        return USBDevice::FindDevices<MDCLoaderDevice>(1155, 57105);
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

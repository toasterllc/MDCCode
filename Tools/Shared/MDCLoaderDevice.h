#pragma once
#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STLoaderTypes.h"

class MDCLoaderDevice : public USBDevice {
public:
    static NSDictionary* MatchingDictionary() {
        return USBDevice::MatchingDictionary(1155, 57105);
    }
    
    static std::vector<MDCLoaderDevice> FindDevice() {
        return USBDevice::FindDevice<MDCLoaderDevice>(MatchingDictionary());
    }
    
    // Default constructor: empty
    MDCLoaderDevice() {}
    
    MDCLoaderDevice(SendRight&& service) :
    USBDevice(std::move(service)) {
        std::vector<USBInterface> interfaces = usbInterfaces();
        if (interfaces.size() != 1) throw std::runtime_error("invalid number of USB interfaces");
        _interface = interfaces[0];
        
        dataOutPipe = USBPipe(
            _interface,
            STLoader::EndpointIdxs::DataOut,
            USBPipe::Options::WriteZeroLengthPacket
        );
    }
    
    USBPipe dataOutPipe;
    
private:
    USBInterface _interface;
};

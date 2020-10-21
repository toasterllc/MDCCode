#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <vector>
#import <string>
#import <iostream>
#import <optional>
#import "ELFBinary.h"
#import "SendRight.h"
#import "USBInterface.h"
#import "STLoaderTypes.h"

static USBInterface findUSBInterface(uint8_t interfaceNum) {
    NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBInterfaceClassName));
    match[@kIOPropertyMatchKey] = @{
        @"bInterfaceNumber": @(interfaceNum),
        @"idVendor": @1155,
        @"idProduct": @57105,
    };
    
    io_iterator_t ioServicesIter = MACH_PORT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFDictionaryRef)CFBridgingRetain(match), &ioServicesIter);
    if (kr != KERN_SUCCESS) throw std::runtime_error("IOServiceGetMatchingServices failed");
    
    SendRight servicesIter(ioServicesIter);
    std::vector<SendRight> services;
    while (servicesIter) {
        SendRight service(IOIteratorNext(servicesIter.port()));
        if (!service) break;
        services.push_back(std::move(service));
    }
    
    // Confirm that we have exactly one matching service
    if (services.empty()) throw std::runtime_error("no matching services");
    if (services.size() != 1) throw std::runtime_error("more than 1 matching service");
    
    SendRight& service = services[0];
    
    IOCFPlugInInterface** plugin = nullptr;
    SInt32 score = 0;
    kr = IOCreatePlugInInterfaceForService(service.port(), kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
    if (!plugin) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
    
    IOUSBInterfaceInterface** usbInterface = nullptr;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&usbInterface);
    if (hr) throw std::runtime_error("QueryInterface failed");
    (*plugin)->Release(plugin);
    
    return USBInterface(usbInterface);
}

namespace Endpoint {
    // These values aren't the same as the endpoint addresses in firmware!
    // These values are the determined by the order that the endpoints are
    // listed in the interface descriptor.
    const uint8_t STCmdOut = 1;
    const uint8_t STCmdIn = 2;
    const uint8_t STDataOut = 3;
}

using Cmd = std::string;
const Cmd LEDSetCmd = "ledset";
const Cmd STLoadCmd = "stload";
const Cmd ICELoadCmd = "iceload";

void printUsage() {
    using namespace std;
    cout << "STLoaderUtil commands:\n";
    cout << "  " << LEDSetCmd    << " <idx> <0/1>\n";
    cout << "  " << STLoadCmd    << " <file>\n";
    cout << "  " << ICELoadCmd   << " <file>\n";
    cout << "\n";
}

struct Args {
    Cmd cmd;
    struct {
        uint8_t idx;
        uint8_t on;
    } ledSet;
    std::string filePath;
};

static Args parseArgs(int argc, const char* argv[]) {
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = strs[0];
    
    if (args.cmd == LEDSetCmd) {
        if (strs.size() < 3) throw std::runtime_error("LED index/state not specified");
        args.ledSet.idx = std::stoi(strs[1]);
        args.ledSet.on = std::stoi(strs[2]);
    
    } else if (args.cmd == STLoadCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else if (args.cmd == ICELoadCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void ledSet(const Args& args, USBInterface& stInterface) {
    STLoaderCmd cmd = {
        .op = STLoaderCmd::Op::LEDSet,
        .arg = {
            .ledSet = {
                .idx = args.ledSet.idx,
                .on = args.ledSet.on,
            },
        },
    };
    
    IOReturn ior = stInterface.write(Endpoint::STCmdOut, &cmd, sizeof(cmd));
    if (ior != kIOReturnSuccess) throw std::runtime_error("pipe write failed");
}

static void stLoad(const Args& args, USBInterface& stInterface) {
    ELFBinary bin(args.filePath.c_str());
    auto sections = bin.sections();
    std::optional<uint32_t> vectorTableAddr;
    for (const auto& s : sections) {
        // Ignore sections that don't have the ALLOC flag ("The section occupies
        // memory during process execution.")
        if (!(s.flags & ELFBinary::SectionFlags::ALLOC)) continue;
        const void*const data = bin.sectionData(s);
        const size_t dataLen = s.size;
        const uint32_t dataAddr = s.addr;
        if (!dataLen) continue; // Ignore sections with zero length
        
        printf("Writing %s @ 0x%jx [length: 0x%jx]\n", s.name.c_str(), (uintmax_t)dataAddr, (uintmax_t)dataLen);
        
        // Send WriteData command
        {
            const STLoaderCmd cmd = {
                .op = STLoaderCmd::Op::WriteData,
                .arg = {
                    .writeData = {
                        .addr = dataAddr,
                    },
                },
            };
            
            IOReturn ior = stInterface.write(Endpoint::STCmdOut, &cmd, sizeof(cmd));
            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STCmdOut");
        }
        
        // Send actual data
        {
            IOReturn ior = stInterface.write(Endpoint::STDataOut, data, dataLen);
            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STDataOut");
        }
        
        // Remember the vector table address when we find it
        if (s.name == ".isr_vector") {
            if (vectorTableAddr) throw std::runtime_error("more than one vector table");
            vectorTableAddr = dataAddr;
        }
    }
    printf("\n");
    
    
    // Verify that we had a vector table
    if (!vectorTableAddr) throw std::runtime_error("no vector table");
    
    // Reset the device, triggering it to load the program we just wrote
    {
        printf("Resetting device...\n");
        const STLoaderCmd cmd = {
            .op = STLoaderCmd::Op::Reset,
            .arg = {
                .reset = {
                    .vectorTableAddr = *vectorTableAddr,
                },
            },
        };
        
        IOReturn ior = stInterface.write(Endpoint::STCmdOut, &cmd, sizeof(cmd));
        if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STCmdOut");
    }
    printf("Done\n");
}

static void iceLoad(const Args& args, USBInterface& stInterface) {
}

int main(int argc, const char* argv[]) {
    Args args;
    try {
        args = parseArgs(argc-1, argv+1);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
        printUsage();
        return 1;
    }
    
    USBInterface stInterface;
    USBInterface iceInterface;
    try {
        stInterface = findUSBInterface(0);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get STM32 interface: %s\n", e.what());
        return 1;
    }
    
//    try {
//        iceInterface = findUSBInterface(1);
//    } catch (const std::exception& e) {
//        fprintf(stderr, "Failed to get ICE40 interface: %s\n", e.what());
//        return 1;
//    }
    
    try {
        if (args.cmd == LEDSetCmd)          ledSet(args, stInterface);
        else if (args.cmd == STLoadCmd)     stLoad(args, stInterface);
        else if (args.cmd == ICELoadCmd)    iceLoad(args, iceInterface);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

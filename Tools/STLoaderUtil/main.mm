#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <vector>
#import <string>
#import <iostream>
#import <optional>
#import "ELF32Binary.h"
#import "SendRight.h"
#import "USBInterface.h"
#import "STLoaderTypes.h"

using namespace STLoader;

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

namespace Interface {
    enum : uint8_t {
        STM32 = 0,
        ICE40 = 1,
    };
}

namespace STEndpoint {
    enum : uint8_t {
        // These values aren't the same as the endpoint addresses in firmware!
        // These values are the determined by the order that the endpoints are
        // listed in the interface descriptor.
        CmdOut = 1,
        DataOut,
        StatusIn,
    };
}

namespace ICEEndpoint {
    enum : uint8_t {
        // These values aren't the same as the endpoint addresses in firmware!
        // These values are the determined by the order that the endpoints are
        // listed in the interface descriptor.
        CmdOut = 1,
        DataOut,
        StatusIn,
    };
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
    STCmd cmd = {
        .op = STCmd::Op::LEDSet,
        .arg = {
            .ledSet = {
                .idx = args.ledSet.idx,
                .on = args.ledSet.on,
            },
        },
    };
    
    IOReturn ior = stInterface.write(STEndpoint::CmdOut, cmd);
    if (ior != kIOReturnSuccess) throw std::runtime_error("pipe write failed");
}

static void stLoad(const Args& args, USBInterface& stInterface) {
    ELF32Binary bin(args.filePath.c_str());
    auto sections = bin.sections();
    
    uint32_t entryPointAddr = bin.entryPointAddr();
    if (!entryPointAddr) throw std::runtime_error("no entry point");
    
    for (const auto& s : sections) {
        // Ignore NOBITS sections (NOBITS = "occupies no space in the file"),
        if (s.type == ELF32Binary::SectionTypes::NOBITS) continue;
        // Ignore non-ALLOC sections (ALLOC = "occupies memory during process execution")
        if (!(s.flags & ELF32Binary::SectionFlags::ALLOC)) continue;
        const void*const data = bin.sectionData(s);
        const size_t dataLen = s.size;
        const uint32_t dataAddr = s.addr;
        if (!dataLen) continue; // Ignore sections with zero length
        
        printf("Writing %s @ 0x%jx [length: 0x%jx]\n", s.name.c_str(), (uintmax_t)dataAddr, (uintmax_t)dataLen);
        
        // Wait for interface to be idle
        // Without this, it's possible for the next `WriteData` command to update the write
        // address while we're still sending data from this iteration.
        for (;;) {
            // Request status
            {
                const STCmd cmd = {
                    .op = STCmd::Op::GetStatus,
                };
                
                IOReturn ior = stInterface.write(STEndpoint::CmdOut, cmd);
                if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STEndpoint::CmdOut");
            }
            
            // Read status
            {
                auto [status, ior] = stInterface.read<STStatus>(STEndpoint::StatusIn);
                if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on STEndpoint::StatusIn");
                if (status == STStatus::Idle) break;
            }
        }
        
        // Send WriteData command
        {
            const STCmd cmd = {
                .op = STCmd::Op::WriteData,
                .arg = {
                    .writeData = {
                        .addr = dataAddr,
                    },
                },
            };
            
            IOReturn ior = stInterface.write(STEndpoint::CmdOut, cmd);
            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STEndpoint::CmdOut");
        }
        
        // Send actual data
        {
            IOReturn ior = stInterface.write(STEndpoint::DataOut, data, dataLen);
            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STEndpoint::DataOut");
        }
    }
    
    // Reset the device, triggering it to load the program we just wrote
    {
        printf("Resetting device\n");
        const STCmd cmd = {
            .op = STCmd::Op::Reset,
            .arg = {
                .reset = {
                    .entryPointAddr = entryPointAddr,
                },
            },
        };
        
        IOReturn ior = stInterface.write(STEndpoint::CmdOut, cmd);
        if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on STEndpoint::CmdOut");
    }
    printf("Done\n");
}

static void iceLoad(const Args& args, USBInterface& iceInterface) {
    Mmap mmap(args.filePath.c_str());
    
    // Start ICE40 configuration
    {
        printf("Starting configuration\n");
        const ICECmd cmd = {
            .op = ICECmd::Op::Start,
            .arg = {
                .start = {
                    .len = (uint32_t)mmap.len(),
                }
            }
        };
        
        IOReturn ior = iceInterface.write(ICEEndpoint::CmdOut, cmd);
        if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on ICEEndpoint::CmdOut");
    }
    
    // Send ICE40 binary
    {
        printf("Writing %ju bytes\n", (uintmax_t)mmap.len());
        IOReturn ior = iceInterface.write(ICEEndpoint::DataOut, mmap.data(), mmap.len());
        if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on ICEEndpoint::DataOut");
    }
    
    // Wait for interface to be idle
    // Without this, the next 'Finish' command would interupt the SPI configuration process
    for (;;) {
        // Request status
        {
            const ICECmd cmd = {
                .op = ICECmd::Op::GetStatus,
            };
            
            IOReturn ior = iceInterface.write(ICEEndpoint::CmdOut, cmd);
            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on ICEEndpoint::CmdOut");
        }
        
        // Read status
        {
            auto [status, ior] = iceInterface.read<ICEStatus>(ICEEndpoint::StatusIn);
            if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on ICEEndpoint::StatusIn");
            if (status == ICEStatus::Idle) break;
        }
    }
    
    // Finish ICE40 configuration
    {
        printf("Finishing configuration\n");
        const ICECmd cmd = {
            .op = ICECmd::Op::Finish,
        };
        
        IOReturn ior = iceInterface.write(ICEEndpoint::CmdOut, cmd);
        if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on ICEEndpoint::CmdOut");
    }
    
    // Request status
    {
        const ICECmd cmd = {
            .op = ICECmd::Op::GetStatus,
        };
        
        IOReturn ior = iceInterface.write(ICEEndpoint::CmdOut, cmd);
        if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on ICEEndpoint::CmdOut");
    }
    
    // Read status
    {
        auto [status, ior] = iceInterface.read<ICEStatus>(ICEEndpoint::StatusIn);
        if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on ICEEndpoint::StatusIn");
        printf("%s\n", (status==ICEStatus::Done ? "Success" : "Failed"));
    }
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
        stInterface = findUSBInterface(Interface::STM32);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get STM32 interface: %s\n", e.what());
        return 1;
    }
    
    try {
        iceInterface = findUSBInterface(Interface::ICE40);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get ICE40 interface: %s\n", e.what());
        return 1;
    }
    
    try {
        if (args.cmd == LEDSetCmd)          ledSet(args, stInterface);
        else if (args.cmd == STLoadCmd)     stLoad(args, stInterface);
        else if (args.cmd == ICELoadCmd)    iceLoad(args, iceInterface);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

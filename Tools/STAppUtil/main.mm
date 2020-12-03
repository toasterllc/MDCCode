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
#import "STAppTypes.h"
#import "MyTime.h"

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
    enum : uint8_t {
        // These values aren't the same as the endpoint addresses in firmware!
        // These values are the determined by the order that the endpoints are
        // listed in the interface descriptor.
        CmdOut = 1,
        PixIn,
    };
}

using Cmd = std::string;
const Cmd PixStreamCmd = "pixstream";
const Cmd LEDSetCmd = "ledset";

void printUsage() {
    using namespace std;
    cout << "STAppUtil commands:\n";
    cout << "  " << PixStreamCmd << "\n";
    cout << "  " << LEDSetCmd    << " <idx> <0/1>\n";
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
    
    if (args.cmd == PixStreamCmd) {
    
    } else if (args.cmd == LEDSetCmd) {
        if (strs.size() < 3) throw std::runtime_error("LED index/state not specified");
        args.ledSet.idx = std::stoi(strs[1]);
        args.ledSet.on = std::stoi(strs[2]);
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void pixStream(const Args& args, USBInterface& interface) {
    STApp::Cmd cmd = {
        .op = STApp::Cmd::Op::PixStream,
        .arg = {
            .pixStream = {
                .enable = true,
            },
        },
    };
    
    IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
    if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on Endpoint::CmdOut");
    
    std::optional<uint16_t> lastNum;
    for (;;) {
        const size_t bufCap = 128*1024*1024;
        auto buf = std::make_unique<uint8_t[]>(bufCap);
        
        auto startTime = MyTime::Now();
        auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), bufCap);
        if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on Endpoint::PixIn");
        assert(!(len % 2));
        
        auto durationNs = MyTime::DurationNs(startTime);
        double bitsPerSecond = ((double)len*8) / ((double)durationNs/UINT64_C(1000000000));
        double megabytesPerSecond = bitsPerSecond/(8*1024*1024);
        printf("%ju bytes took %ju ns == %.0f bits/sec == %.1f MB/sec\n",
            (uintmax_t)len, (uintmax_t)durationNs, bitsPerSecond, megabytesPerSecond);
        
        uint8_t* nums = (uint8_t*)buf.get();
        bool good = true;
        for (size_t i=0; i<len; i+=2) {
            uint16_t num = nums[i]<<8|nums[i+1];
//            printf("%04x\n", num);
            if (lastNum) {
//                uint16_t expected = 0x3742;
                uint16_t expected = (uint16_t)(*lastNum+1);
                if (num != expected) {
                    printf("Bad number; expected: %04x, got %04x ❌\n", expected, num);
                    good = false;
                }
            }
            lastNum = num;
        }
        if (good) printf("Numbers valid ✅\n");
        
        
//        const size_t imageSize = 1024;
//        const size_t imageSize = 2304*1296*2;
//        auto buf = std::make_unique<uint8_t[]>(imageSize);
//        // Read status
//        {
//            double start = CFAbsoluteTimeGetCurrent()
//            auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), imageSize);
////            printf("USB read result: len=0x%jx ior=0x%x\n", (uintmax_t)len, ior);
//            if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on Endpoint::PixIn");
//            const size_t printWidth = 16;
//            for (size_t i=0; i<len; i+=printWidth) {
//                for (size_t ii=i; ii<std::min(i+printWidth,len); ii++) {
//                    printf("%02x ", buf[ii]);
//                }
//                printf("\n");
//            }
//        }
    }
}

static void ledSet(const Args& args, USBInterface& interface) {
    STApp::Cmd cmd = {
        .op = STApp::Cmd::Op::LEDSet,
        .arg = {
            .ledSet = {
                .idx = args.ledSet.idx,
                .on = args.ledSet.on,
            },
        },
    };
    
    IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
    if (ior != kIOReturnSuccess) throw std::runtime_error("pipe write failed");
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
    
    USBInterface interface;
    try {
        interface = findUSBInterface(0);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get STM32 interface: %s\n", e.what());
        return 1;
    }
    
    try {
        if (args.cmd == PixStreamCmd)   pixStream(args, interface);
        else if (args.cmd == LEDSetCmd) ledSet(args, interface);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

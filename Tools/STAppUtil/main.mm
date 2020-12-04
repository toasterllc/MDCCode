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
    using namespace STApp;
    // Get PixInfo
    PixInfo pixInfo;
    {
        STApp::Cmd cmd = {
            .op = STApp::Cmd::Op::GetPixInfo,
        };
        
        {
            IOReturn ior = interface.write(EndpointIdxs::CmdOut, cmd);
            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on CmdOut endpoint");
        }
        
        {
            auto [pi, ior] = interface.read<PixInfo>(EndpointIdxs::CmdIn);
            if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on CmdIn endpoint");
            pixInfo = pi;
        }
    }
    
    STApp::Cmd cmd = {
        .op = STApp::Cmd::Op::PixStream,
        .arg = {
            .pixStream = {
                .enable = true,
            },
        },
    };
    
    IOReturn ior = interface.write(EndpointIdxs::CmdOut, cmd);
    if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on CmdOut endpoint");
    
    const size_t imageLen = pixInfo.width*pixInfo.height*sizeof(Pixel);
    auto buf = std::make_unique<uint8_t[]>(imageLen);
    for (;;) {
        auto startTime = MyTime::Now();
        auto [len, ior] = interface.read(EndpointIdxs::PixIn, buf.get(), imageLen);
        if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on PixIn endpoint");
        if (len != imageLen) throw std::runtime_error("read returned invalid length");
        
        auto durationNs = MyTime::DurationNs(startTime);
        double bitsPerSecond = ((double)len*8) / ((double)durationNs/UINT64_C(1000000000));
        double megabytesPerSecond = bitsPerSecond/(8*1024*1024);
        printf("%ju bytes took %ju ns == %.0f bits/sec == %.1f MB/sec\n",
            (uintmax_t)len, (uintmax_t)durationNs, bitsPerSecond, megabytesPerSecond);
        
        std::optional<Pixel> lastPixel;
        bool good = true;
        for (size_t i=0; i<len; i+=2) {
            const uint16_t pixel = buf[i]<<8|buf[i+1];
            // First pixel is expected to be 0x00
            const uint16_t expected = (lastPixel ? (uint16_t)(*lastPixel+1) : 0);
            if (pixel != expected) {
                printf("Bad pixel; expected: %04x, got %04x ❌\n", expected, pixel);
                good = false;
            }
            lastPixel = pixel;
        }
        if (good) printf("Pixels valid ✅\n");
        
        
//        const size_t imageSize = 1024;
//        const size_t imageSize = 2304*1296*2;
//        auto buf = std::make_unique<uint8_t[]>(imageSize);
//        // Read status
//        {
//            double start = CFAbsoluteTimeGetCurrent()
//            auto [len, ior] = interface.read(EndpointIdxs::PixIn, buf.get(), imageSize);
////            printf("USB read result: len=0x%jx ior=0x%x\n", (uintmax_t)len, ior);
//            if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on PixIn endpoint");
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
    using namespace STApp;
    
    STApp::Cmd cmd = {
        .op = STApp::Cmd::Op::LEDSet,
        .arg = {
            .ledSet = {
                .idx = args.ledSet.idx,
                .on = args.ledSet.on,
            },
        },
    };
    
    IOReturn ior = interface.write(EndpointIdxs::CmdOut, cmd);
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

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
#import "USBDevice.h"
#import "USBInterface.h"
#import "USBPipe.h"
#import "STAppTypes.h"
#import "MyTime.h"

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

struct Args {
    Cmd cmd;
    struct {
        uint8_t idx;
        uint8_t on;
    } ledSet;
    std::string filePath;
};

void printUsage() {
    using namespace std;
    cout << "STAppUtil commands:\n";
    cout << "  " << PixStreamCmd << "\n";
    cout << "  " << LEDSetCmd    << " <idx> <0/1>\n";
    cout << "\n";
}

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

static std::vector<USBDevice> findUSBDevices() {
    std::vector<USBDevice> devices;
    NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
    match[@kIOPropertyMatchKey] = @{
        @"idVendor": @1155,
        @"idProduct": @57105,
    };
    
    io_iterator_t ioServicesIter = MACH_PORT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFDictionaryRef)CFBridgingRetain(match), &ioServicesIter);
    if (kr != KERN_SUCCESS) throw std::runtime_error("IOServiceGetMatchingServices failed");
    
    SendRight servicesIter(ioServicesIter);
    while (servicesIter) {
        SendRight service(IOIteratorNext(servicesIter.port()));
        if (!service) break;
        devices.emplace_back(std::move(service));
    }
    return devices;
}

static void resetDevice(USBDevice& device) {
    using namespace STApp;
    
    // Reset the device
    IOReturn ior = device.vendorRequestOut(CtrlReqs::Reset, nullptr, 0);
    if (ior != kIOReturnSuccess) throw std::runtime_error("device.vendorRequestOut() failed");
    
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, Endpoint::CmdOut);
    USBPipe pixInPipe(interface, Endpoint::PixIn);
    
    // Reset our pipes
    for (const USBPipe& pipe : {cmdOutPipe, pixInPipe}) {
        ior = pipe.reset();
        if (ior != kIOReturnSuccess) throw std::runtime_error("pipe.reset() failed");
    }
}

static void pixStream(const Args& args, USBDevice& device) {
    using namespace STApp;
    
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, Endpoint::CmdOut);
    USBPipe pixInPipe(interface, Endpoint::PixIn);
    
    for (;;) {
        // Start PixStream
        {
            printf("Enabling PixStream...\n");
            STApp::Cmd cmd = { .op = STApp::Cmd::Op::PixStream };
            IOReturn ior = cmdOutPipe.write(cmd);
            if (ior != kIOReturnSuccess) {
                printf("-> write failed on Endpoint::CmdOut: 0x%x ❌\n", ior);
                return;
            }
            printf("-> Done\n\n");
        }
        
        // Read data and make sure it's synchronized (by making
        // sure it starts with the byte we expect)
        {
            const size_t bufCap = (63*1024);
            auto buf = std::make_unique<uint8_t[]>(bufCap);
            for (int i=0; i<3; i++) {
                printf("Reading from PixIn...\n");
                memset(buf.get(), 0x42, bufCap);
                auto [len, ior] = pixInPipe.read(buf.get(), bufCap);
                if (ior != kIOReturnSuccess) {
                    printf("-> PixIn read failed: 0x%x ❌\n", ior);
                    return;
                }
                
                if (ior == kIOReturnSuccess) {
                    bool good = true;
                    uint8_t expected = 0x37;
                    for (size_t ii=0; ii<len; ii++) {
                        if (buf[ii] != expected) {
                            printf("-> Bad byte @ %zu; expected: %02x, got %02x ❌\n", ii, expected, buf[ii]);
                            good = false;
                        }
                        expected = 0xFF;
                    }
                    if (good) {
                        printf("-> Bytes valid ✅\n");
                    }
                }
            }
            printf("-> Done\n\n");
        }
        
        // Trigger the data to be de-synchronized, by performing a truncated read
        {
            printf("Corrupting PixIn endpoint...\n");
            for (int i=0; i<3; i++) {
                uint8_t buf[512];
                auto [len, ior] = pixInPipe.read(buf, sizeof(buf));
                if (ior != kIOReturnSuccess) {
                    printf("-> PixIn read returned: 0x%x ❌\n", ior);
                    return;
                }
            }
            printf("-> Done\n\n");
        }
        
        {
            printf("Recovering device...\n");
            resetDevice(device);
            printf("-> Done\n\n");
        }
    }
}

static void ledSet(const Args& args, USBDevice& device) {
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, Endpoint::CmdOut);
    
    STApp::Cmd cmd = {
        .op = STApp::Cmd::Op::LEDSet,
        .arg = {
            .ledSet = {
                .idx = args.ledSet.idx,
                .on = args.ledSet.on,
            },
        },
    };
    
    IOReturn ior = cmdOutPipe.write(cmd);
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
    
    std::vector<USBDevice> devices;
    try {
        devices = findUSBDevices();
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to find USB device: %s\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching USB devices\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching USB devices\n");
        return 1;
    }
    
    USBDevice& device = devices[0];
    try {
        resetDevice(device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Reset device failed: %s\n\n", e.what());
        return 1;
    }
    
    try {
        if (args.cmd == PixStreamCmd)   pixStream(args, device);
        else if (args.cmd == LEDSetCmd) ledSet(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

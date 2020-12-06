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
#import "STAppTypes.h"
#import "MyTime.h"

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

static void pixStream(const Args& args, USBDevice& device) {
    using namespace STApp;
    
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    
    
    
    
    for (;;) {
//        // Tell the device to reset
//        {
//            printf("Sending Reset control request...\n");
//            device._openIfNeeded();
//            IOUSBDevRequest req = {
//                .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
//                .bRequest       = CtrlReqs::Reset,
//            };
//            IOReturn ior = (*device.interface())->DeviceRequest(device.interface(), &req);
//            printf("DeviceRequest returned: 0x%x\n", ior);
//        }
        
        // Start PixStream
        {
            printf("Enabling PixStream...\n");
            STApp::Cmd cmd = { .op = STApp::Cmd::Op::PixStream };
            IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
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
                auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), bufCap);
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
                auto [len, ior] = interface.read(Endpoint::PixIn, buf, sizeof(buf));
                if (ior != kIOReturnSuccess) {
                    printf("-> PixIn read returned: 0x%x ❌\n", ior);
                    return;
                }
            }
            printf("-> Done\n\n");
        }
        
        // Tell the device to reset
        {
            printf("Sending Reset control request...\n");
            IOReturn ior = device.vendorRequestOut(CtrlReqs::Reset, nullptr, 0);
            if (ior != kIOReturnSuccess) {
                printf("-> DeviceRequest failed: 0x%x ❌\n", ior);
                return;
            }
            printf("-> Done\n\n");
        }
        
        // Reset our pipes
        {
            printf("Resetting pipes...\n");
            IOReturn ior = interface.resetPipe(Endpoint::CmdOut);
            if (ior != kIOReturnSuccess) {
                printf("-> ResetPipe failed: 0x%x ❌\n", ior);
                return;
            }
            
            interface.resetPipe(Endpoint::PixIn);
            ior = interface.resetPipe(Endpoint::PixIn);
            if (ior != kIOReturnSuccess) {
                printf("-> ResetPipe failed: 0x%x ❌\n", ior);
                return;
            }
            printf("-> Done\n\n");
        }
    }

    
    
    
    
    
    
    
    
    
//    // 
//    // Test if flushing the Rx FIFO flushes the region of the FIFO dedicated to SETUP packets
//    //
//    {
//        printf("Sending Reset control request...\n");
//        device._openIfNeeded();
//        IOUSBDevRequest req = {
//            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
//            .bRequest       = CtrlReqs::Reset,
//        };
//        IOReturn ior = (*device.interface())->DeviceRequest(device.interface(), &req);
//        printf("DeviceRequest returned: 0x%x\n", ior);
//    }
//    
//    sleep(1);
//    
//    for (;;) {
//        printf("Sending vendor requests...\n");
//        device._openIfNeeded();
//        uint32_t counter = 0;
//        IOUSBDevRequestTO req = {
//            .bmRequestType      = USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice),
//            .bRequest           = 0,
//            .wLength            = sizeof(counter),
//            .pData              = &counter,
//            .noDataTimeout      = 10,
//            .completionTimeout  = 10,
//        };
//        IOReturn ior = (*device.interface())->DeviceRequestTO(device.interface(), &req);
//        printf("DeviceRequest returned: 0x%x\n", ior);
//        if (ior == kIOReturnSuccess) {
//            printf("Counter: %jx\n", (uintmax_t)counter);
//        }
////        sleep(1);
//    }
//    
//    exit(0);
    
    
    
    
    
    
    
    
    
    
//    {
//        printf("Sending Reset control request...\n");
//        device._openIfNeeded();
//        IOUSBDevRequest req = {
//            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
//            .bRequest       = CtrlReqs::Reset,
//        };
//        IOReturn ior = (*device.interface())->DeviceRequest(device.interface(), &req);
//        printf("DeviceRequest returned: 0x%x\n", ior);
//    }
//    
//    for (;;) {
//        printf("Polling reset state...\n");
//        device._openIfNeeded();
//        bool resetDone = false;
//        IOUSBDevRequest req = {
//            .bmRequestType  = USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice),
//            .bRequest       = CtrlReqs::Reset,
//            .wLength        = sizeof(resetDone),
//            .pData          = &resetDone,
//        };
//        IOReturn ior = (*device.interface())->DeviceRequest(device.interface(), &req);
//        printf("DeviceRequest returned: 0x%x\n", ior);
//        if (ior == kIOReturnSuccess) {
//            printf("Reset done: %d\n", resetDone);
//        }
//    }
    
    
    
//    for (;;) {
//        for (int i=0; i<3; i++) {
//            uint8_t buf[512];
//            auto [len, ior] = interface.read(Endpoint::PixIn, buf, sizeof(buf));
//            printf("[BEFORE RESET] PixIn read returned: 0x%x\n", ior);
//        }
//        
//        {
//            printf("Doing ResetDevice...\n");
//            device._openIfNeeded();
//            IOReturn ior = (*device.interface())->ResetDevice(device.interface());
//            printf("ResetDevice returned: 0x%x\n", ior);
//        }
//        
//        // Start PixStream
//        {
//            STApp::Cmd cmd = { .op = STApp::Cmd::Op::PixStreamStart };
//            IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
//            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on Endpoint::CmdOut");
//        }
//        
//        const size_t bufCap = (63*1024);
//        auto buf = std::make_unique<uint8_t[]>(bufCap);
//        for (int i=0; i<3; i++) {
//            printf("Reading from PixIn...\n");
//            memset(buf.get(), 0x42, bufCap);
//            auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), bufCap);
//            printf("[AFTER START] PixIn read returned: 0x%x (got %ju bytes)\n", ior, (uintmax_t)len);
//            if (ior == kIOReturnSuccess) {
//                bool good = true;
//                uint8_t expected = 0x37;
//                for (size_t ii=0; ii<len; ii++) {
//                    if (buf[ii] != expected) {
//                        printf("Bad byte @ %zu; expected: %02x, got %02x ❌\n", ii, expected, buf[ii]);
//                        good = false;
//                    }
//                    expected = 0xFF;
//                }
//                if (good) {
//                    printf("Bytes valid ✅\n");
//                }
//            } else {
//                printf("[AFTER START] PixIn read returned: 0x%x (got %ju bytes)\n", ior, (uintmax_t)len);
//            }
//        }
//    }
    
    
    
    
    
    
    
    
//    for (;;) {
//        const size_t bufCap = (63*1024);
////        const size_t bufCap = (63*1024) + (63*1024)/2;
////        const size_t bufCap = 128*1024*1024;
//        auto buf = std::make_unique<uint8_t[]>(bufCap);
//        
////        // Abort the pipe, so that we know when we see a pipe stall, it's from our most recent reset
////        {
////            interface._openIfNeeded();
////            IOReturn ior = (*interface.interface())->AbortPipe(interface.interface(), Endpoint::PixIn);
////            printf("AbortPipe returned: 0x%x\n", ior);
////        }
//        
////        {
////            interface._openIfNeeded();
////            IOReturn ior = (*interface.interface())->ResetPipe(interface.interface(), Endpoint::PixIn);
////            printf("ResetPipe returned: 0x%x\n", ior);
////        }
////        
//        
////        {
////            printf("STARTING ReadPipeTO\n");
////            interface._openIfNeeded();
////            uint32_t len = bufCap;
////            IOReturn ior = (*interface.interface())->ReadPipeTO(interface.interface(), Endpoint::PixIn,
////                buf.get(), &len, 1, 1);
////            printf("ReadPipeTO returned: 0x%x\n", ior);
////        }
//
////        {
////            printf("STARTING ReadPipe\n");
////            interface._openIfNeeded();
////            uint32_t len = bufCap;
////            IOReturn ior = (*interface.interface())->ReadPipe(interface.interface(), Endpoint::PixIn,
////                buf.get(), &len);
////            printf("ReadPipeTO returned: 0x%x\n", ior);
////        }
////
////        
////        {
////            printf("STARTING GetPipeStatus\n");
////            interface._openIfNeeded();
////            IOReturn ior = (*interface.interface())->GetPipeStatus(interface.interface(), Endpoint::PixIn);
////            printf("GetPipeStatus returned: 0x%x\n", ior);
////        }
//        
//        {
//            printf("Doing ResetPipe...\n");
//            interface._openIfNeeded();
//            IOReturn ior = (*interface.interface())->ResetPipe(interface.interface(), Endpoint::PixIn);
//            printf("ResetPipe returned: 0x%x\n", ior);
//        }
//        
//        {
//            STApp::Cmd cmd = { .op = STApp::Cmd::Op::PixStreamReset };
//            IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
//            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on Endpoint::CmdOut");
//        }
//        
//        // Wait until we get a pipe stall
//        for (;;) {
////            printf("Wait for pipe stall...\n");
//            printf("STARTING GetPipeStatus\n");
//            interface._openIfNeeded();
//            IOReturn ior = (*interface.interface())->GetPipeStatus(interface.interface(), Endpoint::PixIn);
//            printf("GetPipeStatus returned: 0x%x\n", ior);
//            if (ior == kIOUSBPipeStalled) break;
//        }
//        
//        
////        // Wait until we get a pipe stall
////        for (;;) {
////            uint8_t tmpbuf[333];
//////            printf("Wait for pipe stall...\n");
//////            printf("STARTING ReadPipeTO\n");
////            interface._openIfNeeded();
////            uint32_t len = sizeof(tmpbuf);
////            IOReturn ior = (*interface.interface())->ReadPipeTO(interface.interface(), Endpoint::PixIn,
////                tmpbuf, &len, 1, 1);
//////            printf("ReadPipeTO returned: 0x%x\n", ior);
////            if (ior == kIOUSBPipeStalled) break;
////        }
//        
//        {
//            interface._openIfNeeded();
//            IOReturn ior = (*interface.interface())->ResetPipe(interface.interface(), Endpoint::PixIn);
////            printf("ResetPipe returned: 0x%x\n", ior);
//        }
//        
////        {
////            interface._openIfNeeded();
////            IOReturn ior = (*interface.interface())->ResetPipe(interface.interface(), Endpoint::PixIn);
////            printf("ResetPipe returned: 0x%x\n", ior);
////        }
//        
////        for (;;) {
////            printf("STARTING ReadPipeTO\n");
////            interface._openIfNeeded();
////            uint32_t len = bufCap;
////            IOReturn ior = (*interface.interface())->ReadPipeTO(interface.interface(), Endpoint::PixIn,
////                buf.get(), &len, 1, 1);
////            printf("ReadPipeTO returned: 0x%x\n", ior);
////        }
//        
////        exit(0);
////        
////        for (int i=0; i<3; i++) {
////            uint8_t buf[512];
////            auto [len, ior] = interface.read(Endpoint::PixIn, buf, sizeof(buf));
////            printf("[BEFORE RESET] PixIn read returned: 0x%x\n", ior);
////            usleep(500000);
////        }
////        
////        // Reset PixStream
////        {
////            STApp::Cmd cmd = { .op = STApp::Cmd::Op::PixStreamReset };
////            IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
////            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on Endpoint::CmdOut");
////        }
////        
////        // Abort the pipe, so that we know when we see a pipe stall, it's from our most recent reset
////        {
////            interface._openIfNeeded();
////            IOReturn ior = (*interface.interface())->AbortPipe(interface.interface(), Endpoint::PixIn);
////            printf("AbortPipe returned: 0x%x\n", ior);
////        }
////        
////        for (int i=0; i<3; i++) {
////            uint8_t buf[512];
////            auto [len, ior] = interface.read(Endpoint::PixIn, buf, sizeof(buf));
////            printf("[AFTER RESET] PixIn read returned: 0x%x\n", ior);
////            usleep(500000);
////        }
//        
////        {
////            interface._openIfNeeded();
////            IOReturn ior = (*interface.interface())->ClearPipeStallBothEnds(interface.interface(), Endpoint::PixIn);
////            printf("ClearPipeStallBothEnds returned: 0x%x\n", ior);
////        }
//        
//        // Start PixStream
//        {
////            printf("Sending PixStreamStart...\n");
//            STApp::Cmd cmd = { .op = STApp::Cmd::Op::PixStreamStart };
//            IOReturn ior = interface.write(Endpoint::CmdOut, cmd);
//            if (ior != kIOReturnSuccess) throw std::runtime_error("write failed on Endpoint::CmdOut");
//        }
//        
//        for (int i=0; i<3; i++) {
////            printf("Reading from PixIn...\n");
//            memset(buf.get(), 0x42, bufCap);
//            auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), bufCap);
////            printf("[AFTER START] PixIn read returned: 0x%x (got %ju bytes)\n", ior, (uintmax_t)len);
//            if (ior == kIOReturnSuccess) {
//                bool good = true;
//                uint8_t expected = 0x37;
//                for (size_t ii=0; ii<len; ii++) {
//                    if (buf[ii] != expected) {
////                        printf("Bad byte @ %zu; expected: %02x, got %02x ❌\n", ii, expected, buf[ii]);
//                        good = false;
//                    }
//                    expected = 0xFF;
//                }
//                if (good) {
//                    printf("Bytes valid ✅\n");
//                }
//            } else {
////                printf("[AFTER START] PixIn read returned: 0x%x (got %ju bytes)\n", ior, (uintmax_t)len);
//                exit(0);
//            }
////            usleep(500000);
//        }
//        
////        printf("\n\n\n\n\n");
//    }
//    
//    std::optional<uint16_t> lastNum;
////    for (;;) {
//////        {
//////            interface._openIfNeeded();
//////            IOReturn ior = (*interface.interface())->AbortPipe(interface.interface(), Endpoint::PixIn);
//////            printf("AbortPipe returned: 0x%x\n", ior);
//////        }
//////        
//////        {
//////            interface._openIfNeeded();
//////            IOReturn ior = (*interface.interface())->ResetPipe(interface.interface(), Endpoint::PixIn);
//////            printf("ResetPipe returned: 0x%x\n", ior);
//////        }
//////        
//////        {
//////            interface._openIfNeeded();
//////            IOReturn ior = (*interface.interface())->ClearPipeStall(interface.interface(), Endpoint::PixIn);
//////            printf("ClearPipeStall returned: 0x%x\n", ior);
//////        }
//////        
//////        {
//////            interface._openIfNeeded();
//////            IOReturn ior = (*interface.interface())->ClearPipeStallBothEnds(interface.interface(), Endpoint::PixIn);
//////            printf("ClearPipeStallBothEnds returned: 0x%x\n", ior);
//////        }
////        
////        
////        
////        auto startTime = MyTime::Now();
////        auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), bufCap);
////        if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on Endpoint::PixIn");
////        assert(!(len % 2));
////        
////        uint8_t* nums = (uint8_t*)buf.get();
////        {
////            const size_t idx = 0;
////            uint16_t num = nums[idx]<<8|nums[idx+1];
////            printf("%d (%04x)\n", num, num);
////        }
////        
////        printf("...\n");
////        
////        {
////            const size_t idx = len-2;
////            uint16_t num = nums[idx]<<8|nums[idx+1];
////            printf("%d (%04x)\n", num, num);
////        }
////        
////        printf("Got %ju (0x%jx) bytes\n", (uintmax_t)len, (uintmax_t)len);
////        exit(0);
////        
//////        auto durationNs = MyTime::DurationNs(startTime);
//////        double bitsPerSecond = ((double)len*8) / ((double)durationNs/UINT64_C(1000000000));
//////        double megabytesPerSecond = bitsPerSecond/(8*1024*1024);
//////        printf("%ju bytes took %ju ns == %.0f bits/sec == %.1f MB/sec\n",
//////            (uintmax_t)len, (uintmax_t)durationNs, bitsPerSecond, megabytesPerSecond);
//////        
//////        bool good = true;
//////        for (size_t i=0; i<len; i+=2) {
//////            uint16_t num = nums[i]<<8|nums[i+1];
////////            printf("%04x\n", num);
//////            if (lastNum) {
////////                uint16_t expected = 0x3742;
//////                uint16_t expected = (uint16_t)(*lastNum+1);
//////                if (num != expected) {
//////                    printf("Bad number; expected: %04x, got %04x ❌\n", expected, num);
//////                    good = false;
//////                }
//////            }
//////            lastNum = num;
//////        }
//////        if (good) printf("Numbers valid ✅\n");
////        
////        
//////        const size_t imageSize = 1024;
//////        const size_t imageSize = 2304*1296*2;
//////        auto buf = std::make_unique<uint8_t[]>(imageSize);
//////        // Read status
//////        {
//////            double start = CFAbsoluteTimeGetCurrent()
//////            auto [len, ior] = interface.read(Endpoint::PixIn, buf.get(), imageSize);
////////            printf("USB read result: len=0x%jx ior=0x%x\n", (uintmax_t)len, ior);
//////            if (ior != kIOReturnSuccess) throw std::runtime_error("read failed on Endpoint::PixIn");
//////            const size_t printWidth = 16;
//////            for (size_t i=0; i<len; i+=printWidth) {
//////                for (size_t ii=i; ii<std::min(i+printWidth,len); ii++) {
//////                    printf("%02x ", buf[ii]);
//////                }
//////                printf("\n");
//////            }
//////        }
////    }
}

static void ledSet(const Args& args, USBDevice& device) {
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    
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
    
    try {
        if (args.cmd == PixStreamCmd)   pixStream(args, devices[0]);
        else if (args.cmd == LEDSetCmd) ledSet(args, devices[0]);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

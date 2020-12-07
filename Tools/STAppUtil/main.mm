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
#import "SystemError.h"

using Cmd = std::string;
const Cmd PixStreamCmd = "PixStream";
const Cmd LEDSetCmd = "LEDSet";
const Cmd TestResetStream = "TestResetStream";

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
    cout << "  " << PixStreamCmd    << "\n";
    cout << "  " << LEDSetCmd       << " <idx> <0/1>\n";
    cout << "  " << TestResetStream << "\n";
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
    
    } else if (args.cmd == TestResetStream) {
    
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
    if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceGetMatchingServices failed: %x", kr);
    
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
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, EndpointIdxs::CmdOut);
    USBPipe cmdInPipe(interface, EndpointIdxs::CmdIn);
    USBPipe pixInPipe(interface, EndpointIdxs::PixIn);
    
    // Send the reset vendor-defined control request
    IOReturn ior = device.vendorRequestOut(CtrlReqs::Reset, nullptr, 0);
    if (ior != kIOReturnSuccess) throw RuntimeError("device.vendorRequestOut() failed: %x", ior);
    
    // Reset our pipes now that the device is reset
    for (const USBPipe& pipe : {cmdOutPipe, cmdInPipe, pixInPipe}) {
        ior = pipe.reset();
        if (ior != kIOReturnSuccess) throw RuntimeError("pipe.reset() failed: %x", ior);
    }
}

static void pixStream(const Args& args, USBDevice& device) {
    using namespace STApp;
    
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, EndpointIdxs::CmdOut);
    USBPipe cmdInPipe(interface, EndpointIdxs::CmdIn);
    USBPipe pixInPipe(interface, EndpointIdxs::PixIn);
    
    // Get Pix info
    PixInfo pixInfo;
    STApp::Cmd cmd = { .op = STApp::Cmd::Op::GetPixInfo };
    IOReturn ior = cmdOutPipe.write(cmd);
    if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
    ior = cmdInPipe.read(pixInfo);
    if (ior != kIOReturnSuccess) throw RuntimeError("cmdInPipe.read() failed: %x", ior);
    
    // Start PixStream
    cmd = { .op = STApp::Cmd::Op::PixStream };
    ior = cmdOutPipe.write(cmd);
    if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
    
    const size_t imageLen = pixInfo.width*pixInfo.height*sizeof(Pixel);
    auto buf = std::make_unique<uint8_t[]>(imageLen);
    for (;;) {
        ior = pixInPipe.read(buf.get(), imageLen);
        if (ior != kIOReturnSuccess) throw RuntimeError("pixInPipe.read() failed: %x", ior);
        printf("Got %ju bytes\n", imageLen);
    }
}

static void ledSet(const Args& args, USBDevice& device) {
    using namespace STApp;
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, EndpointIdxs::CmdOut);
    
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
    if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
}

static void testResetStream(const Args& args, USBDevice& device) {
    // TODO: for this to work we need to enable a test mode on the device, and fill the first byte of every transfer with a counter
    using namespace STApp;
    
    std::vector<USBInterface> interfaces = device.usbInterfaces();
    if (interfaces.size() != 1) throw std::runtime_error("unexpected number of USB interfaces");
    USBInterface& interface = interfaces[0];
    USBPipe cmdOutPipe(interface, EndpointIdxs::CmdOut);
    USBPipe cmdInPipe(interface, EndpointIdxs::CmdIn);
    USBPipe pixInPipe(interface, EndpointIdxs::PixIn);
    
    // Get Pix info
    PixInfo pixInfo;
    STApp::Cmd cmd = { .op = STApp::Cmd::Op::GetPixInfo };
    IOReturn ior = cmdOutPipe.write(cmd);
    if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
    ior = cmdInPipe.read(pixInfo);
    if (ior != kIOReturnSuccess) throw RuntimeError("cmdInPipe.read() failed: %x", ior);
    
    const size_t imageLen = pixInfo.width*pixInfo.height*sizeof(Pixel);
    auto buf = std::make_unique<uint8_t[]>(imageLen);
    
    for (;;) {
        // Start PixStream
        printf("Enabling PixStream...\n");
        STApp::Cmd cmd = {
            .op = STApp::Cmd::Op::PixStream,
            .arg = { .pixStream = { .test = true, } }
        };
        ior = cmdOutPipe.write(cmd);
        if (ior != kIOReturnSuccess) throw RuntimeError("cmdOutPipe.write() failed: %x", ior);
        printf("-> Done\n\n");
        
        // Read data and make sure it's synchronized (by making
        // sure it starts with the magic number)
        printf("Reading from PixIn...\n");
        for (int i=0; i<3; i++) {
            ior = pixInPipe.read(buf.get(), imageLen);
            if (ior != kIOReturnSuccess) throw RuntimeError("pixInPipe.read() failed: %x", ior);
            uint32_t magicNum = 0;
            memcpy(&magicNum, buf.get(), sizeof(magicNum));
            if (magicNum != PixTestMagicNumber) throw std::runtime_error("invalid magic number");
        }
        printf("-> Done\n\n");
        
        // De-synchronize the data by performing a truncated read
        printf("Corrupting PixIn endpoint...\n");
        for (int i=0; i<3; i++) {
            uint8_t buf[512];
            ior = pixInPipe.read(buf, sizeof(buf));
            if (ior != kIOReturnSuccess) throw RuntimeError("pixInPipe.read() failed: %x", ior);
        }
        printf("-> Done\n\n");
        
        // Recover device
        printf("Recovering device...\n");
        resetDevice(device);
        printf("-> Done\n\n");
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
    
    // Reset the device to put it back in a pre-defined state
    USBDevice& device = devices[0];
    try {
        resetDevice(device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Reset device failed: %s\n\n", e.what());
        return 1;
    }
    
    try {
        if (args.cmd == PixStreamCmd)           pixStream(args, device);
        else if (args.cmd == LEDSetCmd)         ledSet(args, device);
        else if (args.cmd == TestResetStream)   testResetStream(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

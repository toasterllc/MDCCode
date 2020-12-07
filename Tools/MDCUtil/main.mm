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
#import "RuntimeError.h"
#import "MDCDevice.h"

using Cmd = std::string;
const Cmd PixStreamCmd = "PixStream";
const Cmd LEDSetCmd = "LEDSet";
const Cmd TestResetStream = "TestResetStream";
const Cmd TestResetStreamInc = "TestResetStreamInc";

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
    cout << "MDCUtil commands:\n";
    cout << "  " << PixStreamCmd        << "\n";
    cout << "  " << LEDSetCmd           << " <idx> <0/1>\n";
    cout << "  " << TestResetStream     << "\n";
    cout << "  " << TestResetStreamInc  << "\n";
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
    
    } else if (args.cmd == TestResetStreamInc) {
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void pixStream(const Args& args, MDCDevice& device) {
    using namespace STApp;
    // Get Pix info
    PixInfo pixInfo = device.pixInfo();
    // Start Pix stream
    device.pixStartStream();
    
    const size_t pixelCount = pixInfo.width*pixInfo.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    for (;;) {
        device.pixReadImage(pixels.get(), pixelCount);
        printf("Got %ju pixels (%ju x %ju)\n",
            (uintmax_t)pixelCount, (uintmax_t)pixInfo.width, (uintmax_t)pixInfo.height);
//        [[NSData dataWithBytes:buf.get() length:imageLen] writeToFile:@"/Users/dave/Desktop/img.bin" atomically:true];
//        exit(0);
    }
}

static void ledSet(const Args& args, MDCDevice& device) {
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
    
    device.cmdOutPipe.write(cmd);
}

static void testResetStream(const Args& args, MDCDevice& device) {
    // TODO: for this to work we need to enable a test mode on the device, and fill the first byte of every transfer with a counter
    using namespace STApp;
    
    // Get Pix info
    PixInfo pixInfo = device.pixInfo();
    const size_t pixelCount = pixInfo.width*pixInfo.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    for (;;) {
        // Start Pix stream
        device.pixStartStream();
        
        // Read data and make sure it's synchronized (by making
        // sure it starts with the magic number)
        printf("Reading from PixIn...\n");
        for (int i=0; i<3; i++) {
            device.pixReadImage(pixels.get(), pixelCount);
            uint32_t magicNum = 0;
            memcpy(&magicNum, pixels.get(), sizeof(magicNum));
            if (magicNum != PixTestMagicNumber) throw std::runtime_error("invalid magic number");
        }
        printf("-> Done\n\n");
        
        // De-synchronize the data by performing a truncated read
        printf("Corrupting PixIn endpoint...\n");
        for (int i=0; i<3; i++) {
            uint8_t buf[512];
            device.pixInPipe.read(buf, sizeof(buf));
        }
        printf("-> Done\n\n");
        
        // Recover device
        printf("Recovering device...\n");
        device.reset();
        printf("-> Done\n\n");
    }
}

static void testResetStreamInc(const Args& args, MDCDevice& device) {
    // TODO: for this to work we need to enable a test mode on the device, and fill the first byte of every transfer with a counter
    using namespace STApp;
    
    // Get Pix info
    PixInfo pixInfo = device.pixInfo();
    const size_t pixelCount = pixInfo.width*pixInfo.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    for (;;) {
        // Start Pix stream
        device.pixStartStream();
        
        // Read data and make sure it's synchronized (by making
        // sure it starts with the magic number)
        printf("Reading from PixIn...\n");
        for (int i=0; i<3; i++) {
            device.pixReadImage(pixels.get(), pixelCount);
            uint32_t magicNum = 0;
            memcpy(&magicNum, pixels.get(), sizeof(magicNum));
            if (magicNum != PixTestMagicNumber) throw std::runtime_error("invalid magic number");
            
            // Verify that the values are incrementing numbers
            std::optional<uint16_t> lastNum;
            // Start off past the magic number
            for (size_t i=2; i<pixelCount; i++) {
                const uint16_t num = pixels[i];
                if (lastNum) {
                    uint16_t expected = *lastNum+1;
                    if (num != expected) {
                        throw RuntimeError("invalid number; expected: 0x%04x, got: 0x%04x", expected, num);
                    }
                }
                lastNum = num;
            }
        }
        printf("-> Done\n\n");
        
        // De-synchronize the data by performing a truncated read
        printf("Corrupting PixIn endpoint...\n");
        for (int i=0; i<3; i++) {
            uint8_t buf[512];
            device.pixInPipe.read(buf, sizeof(buf));
        }
        printf("-> Done\n\n");
        
        // Recover device
        printf("Recovering device...\n");
        device.reset();
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
    
    std::vector<MDCDevice> devices;
    try {
        devices = MDCDevice::FindDevices();
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to find MDC devices: %s\n\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC devices\n\n");
        return 1;
    }
    
    // Reset the device to put it back in a pre-defined state
    MDCDevice& device = devices[0];
    try {
        device.reset();
    } catch (const std::exception& e) {
        fprintf(stderr, "Reset device failed: %s\n\n", e.what());
        return 1;
    }
    
    try {
        if (args.cmd == PixStreamCmd)               pixStream(args, device);
        else if (args.cmd == LEDSetCmd)             ledSet(args, device);
        else if (args.cmd == TestResetStream)       testResetStream(args, device);
        else if (args.cmd == TestResetStreamInc)    testResetStreamInc(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    
    return 0;
}

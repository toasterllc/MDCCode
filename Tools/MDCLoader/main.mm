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
#import "MDCLoaderDevice.h"

using namespace STLoader;

using Cmd = std::string;
const Cmd LEDSetCmd = "ledset";
const Cmd STLoadCmd = "stload";
const Cmd ICELoadCmd = "iceload";

void printUsage() {
    using namespace std;
    cout << "MDCLoader commands:\n";
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

static void ledSet(const Args& args, MDCLoaderDevice& device) {
    device.ledSet(args.ledSet.idx, args.ledSet.on);
}

static void stLoad(const Args& args, MDCLoaderDevice& device) {
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
            STStatus status = device.stGetStatus();
            if (status == STStatus::Idle) break;
        }
        
        device.stWriteData(dataAddr, data, dataLen);
    }
    
    // Reset the device, triggering it to load the program we just wrote
    printf("Resetting device\n");
    device.stReset(entryPointAddr);
    printf("Done\n");
}

static void iceLoad(const Args& args, MDCLoaderDevice& device) {
    Mmap mmap(args.filePath.c_str());
    
    // Start ICE40 configuration
    printf("Starting configuration\n");
    device.iceStart(mmap.len());
    
    // Send ICE40 binary
    printf("Writing %ju bytes\n", (uintmax_t)mmap.len());
    device.iceDataOutPipe.write(mmap.data(), mmap.len());
    
    // Wait for interface to be idle
    // Without this, the next 'Finish' command would interupt the SPI configuration process
    for (;;) {
        ICEStatus status = device.iceGetStatus();
        if (status == ICEStatus::Idle) break;
    }
    
    // Finish ICE40 configuration
    printf("Finishing configuration\n");
    device.iceFinish();
    
    // Request status
    ICEStatus status = device.iceGetStatus();
    printf("%s\n", (status==ICEStatus::Done ? "Success" : "Failed"));
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
    
    std::vector<MDCLoaderDevice> devices;
    try {
        devices = MDCLoaderDevice::FindDevices();
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to find MDC loader devices: %s\n\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC loader devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC loader devices\n\n");
        return 1;
    }
    
    MDCLoaderDevice& device = devices[0];
    try {
        if (args.cmd == LEDSetCmd)          ledSet(args, device);
        else if (args.cmd == STLoadCmd)     stLoad(args, device);
        else if (args.cmd == ICELoadCmd)    iceLoad(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

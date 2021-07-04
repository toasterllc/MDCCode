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

using CmdStr = std::string;
const CmdStr LEDSetCmd = "ledset";
const CmdStr STLoadCmd = "stload";
const CmdStr ICELoadCmd = "iceload";
const CmdStr MSPLoadCmd = "mspload";

void printUsage() {
    using namespace std;
    cout << "MDCLoader commands:\n";
    cout << "  " << LEDSetCmd    << " <idx> <0/1>\n";
    cout << "  " << STLoadCmd    << " <file>\n";
    cout << "  " << ICELoadCmd   << " <file>\n";
    cout << "  " << MSPLoadCmd   << " <file>\n";
    cout << "\n";
}

struct Args {
    CmdStr cmd;
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
    
    } else if (args.cmd == MSPLoadCmd) {
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
        
        printf("STLoad: Writing %s @ 0x%jx [length: 0x%jx]\n", s.name.c_str(), (uintmax_t)dataAddr, (uintmax_t)dataLen);
        device.stWrite(dataAddr, data, dataLen);
    }
    
    // Reset the device, triggering it to load the program we just wrote
    printf("STLoad: Resetting device\n");
    device.stReset(entryPointAddr);
}

static void iceLoad(const Args& args, MDCLoaderDevice& device) {
    Mmap mmap(args.filePath.c_str());
    
    // Send the ICE40 binary
    printf("ICELoad: Writing %ju bytes\n", (uintmax_t)mmap.len());
    device.iceWrite(mmap.data(), mmap.len());
}

static void mspLoad(const Args& args, MDCLoaderDevice& device) {
    ELF32Binary bin(args.filePath.c_str());
    auto sections = bin.sections();
    
    device.mspConnect();
    
    for (const auto& s : sections) {
        // Ignore NOBITS sections (NOBITS = "occupies no space in the file"),
        if (s.type == ELF32Binary::SectionTypes::NOBITS) continue;
        // Ignore non-ALLOC sections (ALLOC = "occupies memory during process execution")
        if (!(s.flags & ELF32Binary::SectionFlags::ALLOC)) continue;
        const void*const data = bin.sectionData(s);
        const size_t dataLen = s.size;
        const uint32_t dataAddr = s.addr;
        if (!dataLen) continue; // Ignore sections with zero length
        
        printf("MSPLoad: Writing %s @ 0x%jx [length: 0x%jx]\n", s.name.c_str(), (uintmax_t)dataAddr, (uintmax_t)dataLen);
        device.mspWrite(dataAddr, data, dataLen);
    }
    
    device.mspDisconnect();
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
        devices = MDCLoaderDevice::FindDevice();
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
        else if (args.cmd == MSPLoadCmd)    mspLoad(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

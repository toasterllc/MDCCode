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
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
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
    
    static uint8_t DebugBytes[256*1024];
    
    MDCLoaderDevice& device = devices[0];
    device.dataOutPipe.writeBuf(DebugBytes, 512);
    device.dataOutPipe.writeBuf(DebugBytes, 0);
    
//    MDCLoaderDevice& device = devices[0];
//    device.dataOutPipe.writeBuf(DebugBytes, 13);
    
    return 0;
}

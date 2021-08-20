#include <vector>
#include <string>
#include <iostream>
#include <optional>
#include "Toastbox/USBDevice.h"
#include "ELF32Binary.h"
#include "STAppTypes.h"
#include "MDCDevice.h"

using namespace STApp;

using CmdStr = std::string;
const CmdStr LEDSetCmd = "ledset";

void printUsage() {
    using namespace std;
    cout << "MDCThroughputTest commands:\n";
    cout << "  " << LEDSetCmd    << " <idx> <0/1>\n";
    cout << "\n";
}

struct Args {
    CmdStr cmd = {};
    struct {
        uint8_t idx = 0;
        uint8_t on = 0;
    } ledSet = {};
    std::string filePath = {};
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
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void ledSet(const Args& args, MDCDevice& device) {
    device.ledSet(args.ledSet.idx, args.ledSet.on);
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
        devices = MDCDevice::GetDevices();
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get MDC devices: %s\n\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC devices\n\n");
        return 1;
    }
    
    MDCDevice& device = devices[0];
    try {
        if (args.cmd == LEDSetCmd)          ledSet(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

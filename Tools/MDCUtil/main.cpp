#include <vector>
#include <iostream>
#include <fstream>
#include <algorithm>
#include "STAppTypes.h"
#include "MDCDevice.h"
#include "MDCTypes.h"
#include "Toastbox/RuntimeError.h"

using CmdStr = std::string;
const CmdStr ImgReadCmd = "ImgRead";
const CmdStr LEDSetCmd = "LEDSet";

void printUsage() {
    using namespace std;
    cout << "MDCUtil commands:\n";
    cout << "  " << ImgReadCmd  << " <idx> <output.cfa>\n";
    cout << "  " << LEDSetCmd   << " <idx> <0/1>\n";
    cout << "\n";
}

struct Args {
    CmdStr cmd = "";
    
    struct {
        uint8_t idx = 0;
        std::string filePath;
    } imgRead = {};
    
    struct {
        uint8_t idx = 0;
        uint8_t on = 0;
    } ledSet = {};
};

static std::string lower(const std::string& str) {
    std::string r = str;
    std::transform(r.begin(), r.end(), r.begin(), ::tolower);
    return r;
}

static Args parseArgs(int argc, const char* argv[]) {
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = lower(strs[0]);
    
    if (args.cmd == lower(ImgReadCmd)) {
        if (strs.size() < 3) throw std::runtime_error("index/file path not specified");
        args.imgRead.idx = std::stoi(strs[1]);
        args.imgRead.filePath = strs[2];
    
    } else if (args.cmd == lower(LEDSetCmd)) {
        if (strs.size() < 3) throw std::runtime_error("LED index/state not specified");
        args.ledSet.idx = std::stoi(strs[1]);
        args.ledSet.on = std::stoi(strs[2]);
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static uint32_t checksumFletcher32(const void* data, size_t len) {
    // TODO: optimize so we don't perform a division each iteration
    assert(!(len % sizeof(uint16_t)));
    const uint16_t* words = (const uint16_t*)data;
    const size_t wordCount = len/sizeof(uint16_t);
    uint32_t a = 0;
    uint32_t b = 0;
    for (size_t i=0; i<wordCount; i++) {
        a = (a+words[i]) % UINT16_MAX;
        b = (b+a) % UINT16_MAX;
    }
    return (b<<16) | a;
}

static void imgRead(const Args& args, MDCDevice& device) {
    printf("Sending SDRead command...\n");
    device.sdRead(0);
    printf("-> OK\n\n");
    
    constexpr size_t BufCap = 8*1024*1024;
    static_assert(BufCap >= MDC::ImgLen);
    std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
    
    printf("Reading image...\n");
    const size_t len = device.usbDevice().read(STApp::Endpoints::DataIn, buf.get(), BufCap);
    if (len < MDC::ImgLen) {
        throw RuntimeError("expected at least 0x%jx bytes, but only got 0x%jx bytes", (uintmax_t)MDC::ImgLen, (uintmax_t)len);
    }
    
    // Validate checksum
    {
        const uint32_t checksumExpected = checksumFletcher32(buf.get(), MDC::ImgNoChecksumLen);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, (uint8_t*)buf.get()+MDC::ImgNoChecksumLen, sizeof(checksumGot));
        printf("-> Checksum: expected:0x%08x got:0x%08x\n", checksumExpected, checksumGot);
    }
    
    // Write image
    {
        std::ofstream f;
        f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
        f.open(args.imgRead.filePath.c_str());
        f.write((char*)buf.get(), MDC::ImgLen);
        printf("-> Wrote %ju bytes\n", (uintmax_t)MDC::ImgLen);
    }
}

static void ledSet(const Args& args, MDCDevice& device) {
    device.ledSet(args.ledSet.idx, args.ledSet.on);
}

int main(int argc, const char* argv[]) {
//    const uint8_t chars[] = {'a', 'b', 'c', 'd', 'e', 0};             // 0xf04fc729
////    const uint8_t chars[] = {'a', 'b', 'c', 'd', 'e', 'f'};           // 0x56502d2a
////    const uint8_t chars[] = {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'}; // 0xebe19591
//    const uint32_t checksum = checksumFletcher32(chars, sizeof(chars));
//    printf("checksum: 0x%08x\n", checksum);
//    return 0;
    
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
        fprintf(stderr, "Failed to get MDC loader devices: %s\n\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC loader devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC loader devices\n\n");
        return 1;
    }
    
    MDCDevice& device = devices[0];
    try {
        if (args.cmd == lower(ImgReadCmd))     imgRead(args, device);
        else if (args.cmd == lower(LEDSetCmd)) ledSet(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

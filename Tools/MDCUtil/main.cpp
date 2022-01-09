#include <vector>
#include <iostream>
#include <fstream>
#include <algorithm>
#include <cstring>
#include "STM.h"
#include "MDCDevice.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/IntForStr.h"
#include "ChecksumFletcher32.h"
#include "Img.h"
#include "SD.h"
#include "ELF32Binary.h"

using CmdStr = std::string;

// Common Commands
const CmdStr LEDSetCmd              = "LEDSet";

// STMLoader Commands
const CmdStr STMWriteCmd            = "STMWrite";
const CmdStr ICEWriteCmd            = "ICEWrite";
const CmdStr MSPReadCmd             = "MSPRead";
const CmdStr MSPWriteCmd            = "MSPWrite";

// STMApp Commands
const CmdStr SDImgReadCmd           = "SDImgRead";
const CmdStr ImgCaptureCmd          = "ImgCapture";

static void printUsage() {
    using namespace std;
    cout << "MDCUtil commands:\n";
    
    cout << "  " << LEDSetCmd       << " <idx> <0/1>\n";
    
    cout << "  " << STMWriteCmd     << " <file>\n";
    cout << "  " << ICEWriteCmd     << " <file>\n";
    
    cout << "  " << MSPReadCmd      << " <addr> <len>\n";
    cout << "  " << MSPWriteCmd     << " <file>\n";
    
    cout << "  " << SDImgReadCmd    << " <idx> <output.cfa>\n";
    cout << "  " << ImgCaptureCmd   << " <output.cfa>\n";
    
    cout << "\n";
}

struct Args {
    CmdStr cmd = "";
    
    struct {
        uint8_t idx = 0;
        uint8_t on = 0;
    } LEDSet = {};
    
    struct {
        std::string filePath;
    } STMWrite = {};
    
    struct {
        std::string filePath;
    } ICEWrite = {};
    
    struct {
        uintptr_t addr = 0;
        size_t len = 0;
    } MSPRead = {};
    
    struct {
        std::string filePath;
    } MSPWrite = {};
    
    struct {
        uint32_t idx = 0;
        std::string filePath;
    } SDImgRead = {};
    
    struct {
        std::string filePath;
    } ImgCapture = {};
};

static std::string lower(const std::string& str) {
    std::string r = str;
    std::transform(r.begin(), r.end(), r.begin(), ::tolower);
    return r;
}

static Args parseArgs(int argc, const char* argv[]) {
    using namespace Toastbox;
    
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = lower(strs[0]);
    
    if (args.cmd == lower(LEDSetCmd)) {
        if (strs.size() < 3) throw std::runtime_error("LED index/state not specified");
        IntForStr(args.LEDSet.idx, strs[1]);
        IntForStr(args.LEDSet.on, strs[2]);
    
    } else if (args.cmd == lower(STMWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.STMWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(ICEWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.ICEWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(MSPReadCmd)) {
        if (strs.size() < 3) throw std::runtime_error("address/length not specified");
        IntForStr(args.MSPRead.addr, strs[1]);
        IntForStr(args.MSPRead.len, strs[2]);
    
    } else if (args.cmd == lower(MSPWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.MSPWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(SDImgReadCmd)) {
        if (strs.size() < 3) throw std::runtime_error("index/file path not specified");
        IntForStr(args.SDImgRead.idx, strs[1]);
        args.SDImgRead.filePath = strs[2];
    
    } else if (args.cmd == lower(ImgCaptureCmd)) {
        if (strs.size() < 2) throw std::runtime_error("index/file path not specified");
        args.ImgCapture.filePath = strs[1];
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void LEDSet(const Args& args, MDCDevice& device) {
    device.ledSet(args.LEDSet.idx, args.LEDSet.on);
}

static void STMWrite(const Args& args, MDCDevice& device) {
    ELF32Binary elf(args.STMWrite.filePath.c_str());
    
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("STMWrite: Writing %12s @ 0x%08jx    size: 0x%08jx    vaddr: 0x%08jx\n",
            name, (uintmax_t)paddr, (uintmax_t)size, (uintmax_t)vaddr);
        
        device.stmWrite(paddr, data, size);
    });
    
    // Reset the device, triggering it to load the program we just wrote
    printf("STMWrite: Resetting device\n");
    device.stmReset(elf.entryPointAddr());
}

static void ICEWrite(const Args& args, MDCDevice& device) {
    Mmap mmap(args.ICEWrite.filePath.c_str());
    
    // Send the ICE40 binary
    printf("ICEWrite: Writing %ju bytes\n", (uintmax_t)mmap.len());
    device.iceWrite(mmap.data(), mmap.len());
}

static void MSPRead(const Args& args, MDCDevice& device) {
    device.mspConnect();
    
    printf("Reading [0x%08jx,0x%08jx):\n",
        (uintmax_t)args.MSPRead.addr,
        (uintmax_t)(args.MSPRead.addr+args.MSPRead.len)
    );
    
    auto buf = std::make_unique<uint8_t[]>(args.MSPRead.len);
    device.mspRead(args.MSPRead.addr, buf.get(), args.MSPRead.len);
    
    for (size_t i=0; i<args.MSPRead.len; i++) {
        printf("%02jx ", (uintmax_t)buf[i]);
    }
    
    printf("\n");
    
    device.mspDisconnect();
}

static void MSPWrite(const Args& args, MDCDevice& device) {
    ELF32Binary elf(args.MSPWrite.filePath.c_str());
    
    device.mspConnect();
    
    // Write the data
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("MSPWrite: Writing %22s @ 0x%04jx    size: 0x%04jx    vaddr: 0x%04jx\n",
            name, (uintmax_t)paddr, (uintmax_t)size, (uintmax_t)vaddr);
        
        device.mspWrite(paddr, data, size);
    });
    
    // Read back data and compare with what we expect
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("MSPWrite: Verifying %s @ 0x%jx [size: 0x%jx]\n",
            name, (uintmax_t)paddr, (uintmax_t)size);
        
        auto buf = std::make_unique<uint8_t[]>(size);
        device.mspRead(paddr, buf.get(), size);
        
        if (memcmp(data, buf.get(), size)) {
            throw Toastbox::RuntimeError("section doesn't match: %s", name);
        }
    });
    
    device.mspDisconnect();
}

static void SDImgRead(const Args& args, MDCDevice& device) {
    printf("Sending SDRead command...\n");
    device.sdRead(args.SDImgRead.idx*Img::PaddedLen);
    printf("-> OK\n\n");
    
    printf("Reading image...\n");
    auto img = device.imgReadout();
    printf("-> OK\n\n");
    
    // Write image
    printf("Writing image...\n");
    std::ofstream f;
    f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
    f.open(args.SDImgRead.filePath.c_str());
    f.write((char*)img.get(), Img::Len);
    printf("-> Wrote %ju bytes\n", (uintmax_t)Img::Len);
}

static void ImgCapture(const Args& args, MDCDevice& device) {
    printf("Sending ImgCapture command...\n");
    STM::ImgCaptureStats stats = device.imgCapture(0, 0);
    printf("-> OK (len: %ju)\n\n", (uintmax_t)stats.len);
    
    printf("Reading image...\n");
    auto img = device.imgReadout();
    printf("-> OK\n\n");
    
    // Write image
    printf("Writing image...\n");
    std::ofstream f;
    f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
    f.open(args.ImgCapture.filePath.c_str());
    f.write((char*)img.get(), Img::Len);
    printf("-> Wrote (len: %ju)\n", (uintmax_t)Img::Len);
}

int main(int argc, const char* argv[]) {
//    const uint8_t data[] = {
//        0x42,0x42,0x00,0x09,0x10,0x05,0x00,0x00,0xbe,0xba,0xfe,0xca,0x00,0x00,0x00,0x00,0xef,0xbe,0xad,0xde,0x00,0x00,0x00,0x00,0x11,0x11,0x22,0x22,0x00,0x00,0x00,0x00,0xff,0x0f,0xfe,0x0f,0xfd,0x0f,0xfc,0x0f,0xfb,0x0f,0xfa,0x0f,0xf9,0x0f,0xf8,0x0f,0xf7,0x0f,0xf6,0x0f,0xf5,0x0f,0xf4,0x0f,0xf3,0x0f,0xf2,0x0f,0xf1,0x0f,0xf0,0x0f,0xef,0x0f,0xee,0x0f,0xed,0x0f,0xec,0x0f,0xeb,0x0f,0xea,0x0f,0xe9,0x0f,0xe8,0x0f,0xe7,0x0f,0xe6,0x0f,0xe5,0x0f,0xe4,0x0f,0xe3,0x0f,0xe2,0x0f,0xe1,0x0f,0xe0,0x0f,0xdf,0x0f,0xde,0x0f,0xdd,0x0f,0xdc,0x0f,0xdb,0x0f,0xda,0x0f,0xd9,0x0f,0xd8,0x0f,0xd7,0x0f,0xd6,0x0f,0xd5,0x0f,0xd4,0x0f,0xd3,0x0f,0xd2,0x0f,0xd1,0x0f,0xd0,0x0f,0xcf,0x0f,0xce,0x0f,0xcd,0x0f,0xcc,0x0f,0xcb,0x0f,0xca,0x0f,0xc9,0x0f,0xc8,0x0f,0xc7,0x0f,0xc6,0x0f,0xc5,0x0f,0xc4,0x0f,0xc3,0x0f,0xc2,0x0f,0xc1,0x0f,0xc0,0x0f,0xbf,0x0f,0xbe,0x0f,0xbd,0x0f,0xbc,0x0f,0xbb,0x0f,0xba,0x0f,0xb9,0x0f,0xb8,0x0f,0xb7,0x0f,0xb6,0x0f,0xb5,0x0f,0xb4,0x0f,0xb3,0x0f,0xb2,0x0f,0xb1,0x0f,0xb0,0x0f,0xaf,0x0f,0xae,0x0f,0xad,0x0f,0xac,0x0f,0xab,0x0f,0xaa,0x0f,0xa9,0x0f,0xa8,0x0f,0xa7,0x0f,0xa6,0x0f,0xa5,0x0f,0xa4,0x0f,0xa3,0x0f,0xa2,0x0f,0xa1,0x0f,0xa0,0x0f,0x9f,0x0f,0x9e,0x0f,0x9d,0x0f,0x9c,0x0f,0x9b,0x0f,0x9a,0x0f,0x99,0x0f,0x98,0x0f,0x97,0x0f,0x96,0x0f,0x95,0x0f,0x94,0x0f,0x93,0x0f,0x92,0x0f,0x91,0x0f,0x90,0x0f,0x8f,0x0f,0x8e,0x0f,0x8d,0x0f,0x8c,0x0f,0x8b,0x0f,0x8a,0x0f,0x89,0x0f,0x88,0x0f,0x87,0x0f,0x86,0x0f,0x85,0x0f,0x84,0x0f,0x83,0x0f,0x82,0x0f,0x81,0x0f,0x80,0x0f,0x7f,0x0f,0x7e,0x0f,0x7d,0x0f,0x7c,0x0f,0x7b,0x0f,0x7a,0x0f,0x79,0x0f,0x78,0x0f,0x77,0x0f,0x76,0x0f,0x75,0x0f,0x74,0x0f,0x73,0x0f,0x72,0x0f,0x71,0x0f,0x70,0x0f,0x6f,0x0f,0x6e,0x0f,0x6d,0x0f,0x6c,0x0f,0x6b,0x0f,0x6a,0x0f,0x69,0x0f,0x68,0x0f,0x67,0x0f,0x66,0x0f,0x65,0x0f,0x64,0x0f,0x63,0x0f,0x62,0x0f,0x61,0x0f,0x60,0x0f,0x5f,0x0f,0x5e,0x0f,0x5d,0x0f,0x5c,0x0f,0x5b,0x0f,0x5a,0x0f,0x59,0x0f,0x58,0x0f,0x57,0x0f,0x56,0x0f,0x55,0x0f,0x54,0x0f,0x53,0x0f,0x52,0x0f,0x51,0x0f,0x50,0x0f,0x4f,0x0f,0x4e,0x0f,0x4d,0x0f,0x4c,0x0f,0x4b,0x0f,0x4a,0x0f,0x49,0x0f,0x48,0x0f,0x47,0x0f,0x46,0x0f,0x45,0x0f,0x44,0x0f,0x43,0x0f,0x42,0x0f,0x41,0x0f,0x40,0x0f,0x3f,0x0f,0x3e,0x0f,0x3d,0x0f,0x3c,0x0f,0x3b,0x0f,0x3a,0x0f,0x39,0x0f,0x38,0x0f,0x37,0x0f,0x36,0x0f,0x35,0x0f,0x34,0x0f,0x33,0x0f,0x32,0x0f,0x31,0x0f,0x30,0x0f,0x2f,0x0f,0x2e,0x0f,0x2d,0x0f,0x2c,0x0f,0x2b,0x0f,0x2a,0x0f,0x29,0x0f,0x28,0x0f,0x27,0x0f,0x26,0x0f,0x25,0x0f,0x24,0x0f,0x23,0x0f,0x22,0x0f,0x21,0x0f,0x20,0x0f,0x1f,0x0f,0x1e,0x0f,0x1d,0x0f,0x1c,0x0f,0x1b,0x0f,0x1a,0x0f,0x19,0x0f,0x18,0x0f,0x17,0x0f,0x16,0x0f,0x15,0x0f,0x14,0x0f,0x13,0x0f,0x12,0x0f,0x11,0x0f,0x10,0x0f,
//        0x0f,0x0f,0x0e,0x0f,0x0d,0x0f,0x0c,0x0f,0x0b,0x0f,0x0a,0x0f,0x09,0x0f,0x08,0x0f,0x07,0x0f,0x06,0x0f,0x05,0x0f,0x04,0x0f,0x03,0x0f,0x02,0x0f,0x01,0x0f,0x00,0x0f,0xff,0x0e,0xfe,0x0e,0xfd,0x0e,0xfc,0x0e,0xfb,0x0e,0xfa,0x0e,0xf9,0x0e,0xf8,0x0e,0xf7,0x0e,0xf6,0x0e,0xf5,0x0e,0xf4,0x0e,0xf3,0x0e,0xf2,0x0e,0xf1,0x0e,0xf0,0x0e,0xef,0x0e,0xee,0x0e,0xed,0x0e,0xec,0x0e,0xeb,0x0e,0xea,0x0e,0xe9,0x0e,0xe8,0x0e,0xe7,0x0e,0xe6,0x0e,0xe5,0x0e,0xe4,0x0e,0xe3,0x0e,0xe2,0x0e,0xe1,0x0e,0xe0,0x0e,0xdf,0x0e,0xde,0x0e,0xdd,0x0e,0xdc,0x0e,0xdb,0x0e,0xda,0x0e,0xd9,0x0e,0xd8,0x0e,0xd7,0x0e,0xd6,0x0e,0xd5,0x0e,0xd4,0x0e,0xd3,0x0e,0xd2,0x0e,0xd1,0x0e,0xd0,0x0e,0xcf,0x0e,0xce,0x0e,0xcd,0x0e,0xcc,0x0e,0xcb,0x0e,0xca,0x0e,0xc9,0x0e,0xc8,0x0e,0xc7,0x0e,0xc6,0x0e,0xc5,0x0e,0xc4,0x0e,0xc3,0x0e,0xc2,0x0e,0xc1,0x0e,0xc0,0x0e,0xbf,0x0e,0xbe,0x0e,0xbd,0x0e,0xbc,0x0e,0xbb,0x0e,0xba,0x0e,0xb9,0x0e,0xb8,0x0e,0xb7,0x0e,0xb6,0x0e,0xb5,0x0e,0xb4,0x0e,0xb3,0x0e,0xb2,0x0e,0xb1,0x0e,0xb0,0x0e,0xaf,0x0e,0xae,0x0e,0xad,0x0e,0xac,0x0e,0xab,0x0e,0xaa,0x0e,0xa9,0x0e,0xa8,0x0e,0xa7,0x0e,0xa6,0x0e,0xa5,0x0e,0xa4,0x0e,0xa3,0x0e,0xa2,0x0e,0xa1,0x0e,0xa0,0x0e,0x9f,0x0e,0x9e,0x0e,0x9d,0x0e,0x9c,0x0e,0x9b,0x0e,0x9a,0x0e,0x99,0x0e,0x98,0x0e,0x97,0x0e,0x96,0x0e,0x95,0x0e,0x94,0x0e,0x93,0x0e,0x92,0x0e,0x91,0x0e,0x90,0x0e,0x8f,0x0e,0x8e,0x0e,0x8d,0x0e,0x8c,0x0e,0x8b,0x0e,0x8a,0x0e,0x89,0x0e,0x88,0x0e,0x87,0x0e,0x86,0x0e,0x85,0x0e,0x84,0x0e,0x83,0x0e,0x82,0x0e,0x81,0x0e,0x80,0x0e,0x7f,0x0e,0x7e,0x0e,0x7d,0x0e,0x7c,0x0e,0x7b,0x0e,0x7a,0x0e,0x79,0x0e,0x78,0x0e,0x77,0x0e,0x76,0x0e,0x75,0x0e,0x74,0x0e,0x73,0x0e,0x72,0x0e,0x71,0x0e,0x70,0x0e,0x6f,0x0e,0x6e,0x0e,0x6d,0x0e,0x6c,0x0e,0x6b,0x0e,0x6a,0x0e,0x69,0x0e,0x68,0x0e,0x67,0x0e,0x66,0x0e,0x65,0x0e,0x64,0x0e,0x63,0x0e,0x62,0x0e,0x61,0x0e,0x60,0x0e,0x5f,0x0e,0x5e,0x0e,0x5d,0x0e,0x5c,0x0e,0x5b,0x0e,0x5a,0x0e,0x59,0x0e,0x58,0x0e,0x57,0x0e,0x56,0x0e,0x55,0x0e,0x54,0x0e,0x53,0x0e,0x52,0x0e,0x51,0x0e,0x50,0x0e,0x4f,0x0e,0x4e,0x0e,0x4d,0x0e,0x4c,0x0e,0x4b,0x0e,0x4a,0x0e,0x49,0x0e,0x48,0x0e,0x47,0x0e,0x46,0x0e,0x45,0x0e,0x44,0x0e,0x43,0x0e,0x42,0x0e,0x41,0x0e,0x40,0x0e,0x3f,0x0e,0x3e,0x0e,0x3d,0x0e,0x3c,0x0e,0x3b,0x0e,0x3a,0x0e,0x39,0x0e,0x38,0x0e,0x37,0x0e,0x36,0x0e,0x35,0x0e,0x34,0x0e,0x33,0x0e,0x32,0x0e,0x31,0x0e,0x30,0x0e,0x2f,0x0e,0x2e,0x0e,0x2d,0x0e,0x2c,0x0e,0x2b,0x0e,0x2a,0x0e,0x29,0x0e,0x28,0x0e,0x27,0x0e,0x26,0x0e,0x25,0x0e,0x24,0x0e,0x23,0x0e,0x22,0x0e,0x21,0x0e,0x20,0x0e,0x1f,0x0e,0x1e,0x0e,0x1d,0x0e,0x1c,0x0e,0x1b,0x0e,0x1a,0x0e,0x19,0x0e,0x18,0x0e,0x17,0x0e,0x16,0x0e,0x15,0x0e,0x14,0x0e,0x13,0x0e,0x12,0x0e,0x11,0x0e,0x10,0x0e,
//        0x0f,0x0e,0x0e,0x0e,0x0d,0x0e,0x0c,0x0e,0x0b,0x0e,0x0a,0x0e,0x09,0x0e,0x08,0x0e,0x07,0x0e,0x06,0x0e,0x05,0x0e,0x04,0x0e,0x03,0x0e,0x02,0x0e,0x01,0x0e,0x00,0x0e,0xff,0x0d,0xfe,0x0d,0xfd,0x0d,0xfc,0x0d,0xfb,0x0d,0xfa,0x0d,0xf9,0x0d,0xf8,0x0d,0xf7,0x0d,0xf6,0x0d,0xf5,0x0d,0xf4,0x0d,0xf3,0x0d,0xf2,0x0d,0xf1,0x0d,0xf0,0x0d,0xef,0x0d,0xee,0x0d,0xed,0x0d,0xec,0x0d,0xeb,0x0d,0xea,0x0d,0xe9,0x0d,0xe8,0x0d,0xe7,0x0d,0xe6,0x0d,0xe5,0x0d,0xe4,0x0d,0xe3,0x0d,0xe2,0x0d,0xe1,0x0d,0xe0,0x0d,0xdf,0x0d,0xde,0x0d,0xdd,0x0d,0xdc,0x0d,0xdb,0x0d,0xda,0x0d,0xd9,0x0d,0xd8,0x0d,0xd7,0x0d,0xd6,0x0d,0xd5,0x0d,0xd4,0x0d,0xd3,0x0d,0xd2,0x0d,0xd1,0x0d,0xd0,0x0d,0xcf,0x0d,0xce,0x0d,0xcd,0x0d,0xcc,0x0d,0xcb,0x0d,0xca,0x0d,0xc9,0x0d,0xc8,0x0d,0xc7,0x0d,0xc6,0x0d,0xc5,0x0d,0xc4,0x0d,0xc3,0x0d,0xc2,0x0d,0xc1,0x0d,0xc0,0x0d,0xbf,0x0d,0xbe,0x0d,0xbd,0x0d,0xbc,0x0d,0xbb,0x0d,0xba,0x0d,0xb9,0x0d,0xb8,0x0d,0xb7,0x0d,0xb6,0x0d,0xb5,0x0d,0xb4,0x0d,0xb3,0x0d,0xb2,0x0d,0xb1,0x0d,0xb0,0x0d,0xaf,0x0d,0xae,0x0d,0xad,0x0d,0xac,0x0d,0xab,0x0d,0xaa,0x0d,0xa9,0x0d,0xa8,0x0d,0xa7,0x0d,0xa6,0x0d,0xa5,0x0d,0xa4,0x0d,0xa3,0x0d,0xa2,0x0d,0xa1,0x0d,0xa0,0x0d,0x9f,0x0d,0x9e,0x0d,0x9d,0x0d,0x9c,0x0d,0x9b,0x0d,0x9a,0x0d,0x99,0x0d,0x98,0x0d,0x97,0x0d,0x96,0x0d,0x95,0x0d,0x94,0x0d,0x93,0x0d,0x92,0x0d,0x91,0x0d,0x90,0x0d,0x8f,0x0d,0x8e,0x0d,0x8d,0x0d,0x8c,0x0d,0x8b,0x0d,0x8a,0x0d,0x89,0x0d,0x88,0x0d,0x87,0x0d,0x86,0x0d,0x85,0x0d,0x84,0x0d,0x83,0x0d,0x82,0x0d,0x81,0x0d,0x80,0x0d,0x7f,0x0d,0x7e,0x0d,0x7d,0x0d,0x7c,0x0d,0x7b,0x0d,0x7a,0x0d,0x79,0x0d,0x78,0x0d,0x77,0x0d,0x76,0x0d,0x75,0x0d,0x74,0x0d,0x73,0x0d,0x72,0x0d,0x71,0x0d,0x70,0x0d,0x6f,0x0d,0x6e,0x0d,0x6d,0x0d,0x6c,0x0d,0x6b,0x0d,0x6a,0x0d,0x69,0x0d,0x68,0x0d,0x67,0x0d,0x66,0x0d,0x65,0x0d,0x64,0x0d,0x63,0x0d,0x62,0x0d,0x61,0x0d,0x60,0x0d,0x5f,0x0d,0x5e,0x0d,0x5d,0x0d,0x5c,0x0d,0x5b,0x0d,0x5a,0x0d,0x59,0x0d,0x58,0x0d,0x57,0x0d,0x56,0x0d,0x55,0x0d,0x54,0x0d,0x53,0x0d,0x52,0x0d,0x51,0x0d,0x50,0x0d,0x4f,0x0d,0x4e,0x0d,0x4d,0x0d,0x4c,0x0d,0x4b,0x0d,0x4a,0x0d,0x49,0x0d,0x48,0x0d,0x47,0x0d,0x46,0x0d,0x45,0x0d,0x44,0x0d,0x43,0x0d,0x42,0x0d,0x41,0x0d,0x40,0x0d,0x3f,0x0d,0x3e,0x0d,0x3d,0x0d,0x3c,0x0d,0x3b,0x0d,0x3a,0x0d,0x39,0x0d,0x38,0x0d,0x37,0x0d,0x36,0x0d,0x35,0x0d,0x34,0x0d,0x33,0x0d,0x32,0x0d,0x31,0x0d,0x30,0x0d,0x2f,0x0d,0x2e,0x0d,0x2d,0x0d,0x2c,0x0d,0x2b,0x0d,0x2a,0x0d,0x29,0x0d,0x28,0x0d,0x27,0x0d,0x26,0x0d,0x25,0x0d,0x24,0x0d,0x23,0x0d,0x22,0x0d,0x21,0x0d,0x20,0x0d,0x1f,0x0d,0x1e,0x0d,0x1d,0x0d,0x1c,0x0d,0x1b,0x0d,0x1a,0x0d,0x19,0x0d,0x18,0x0d,0x17,0x0d,0x16,0x0d,0x15,0x0d,0x14,0x0d,0x13,0x0d,0x12,0x0d,0x11,0x0d,0x10,0x0d,
//        0x0f,0x0d,0x0e,0x0d,0x0d,0x0d,0x0c,0x0d,0x0b,0x0d,0x0a,0x0d,0x09,0x0d,0x08,0x0d,0x07,0x0d,0x06,0x0d,0x05,0x0d,0x04,0x0d,0x03,0x0d,0x02,0x0d,0x01,0x0d,0x00,0x0d,0xff,0x0c,0xfe,0x0c,0xfd,0x0c,0xfc,0x0c,0xfb,0x0c,0xfa,0x0c,0xf9,0x0c,0xf8,0x0c,0xf7,0x0c,0xf6,0x0c,0xf5,0x0c,0xf4,0x0c,0xf3,0x0c,0xf2,0x0c,0xf1,0x0c,0xf0,0x0c,0xef,0x0c,0xee,0x0c,0xed,0x0c,0xec,0x0c,0xeb,0x0c,0xea,0x0c,0xe9,0x0c,0xe8,0x0c,0xe7,0x0c,0xe6,0x0c,0xe5,0x0c,0xe4,0x0c,0xe3,0x0c,0xe2,0x0c,0xe1,0x0c,0xe0,0x0c,0xdf,0x0c,0xde,0x0c,0xdd,0x0c,0xdc,0x0c,0xdb,0x0c,0xda,0x0c,0xd9,0x0c,0xd8,0x0c,0xd7,0x0c,0xd6,0x0c,0xd5,0x0c,0xd4,0x0c,0xd3,0x0c,0xd2,0x0c,0xd1,0x0c,0xd0,0x0c,0xcf,0x0c,0xce,0x0c,0xcd,0x0c,0xcc,0x0c,0xcb,0x0c,0xca,0x0c,0xc9,0x0c,0xc8,0x0c,0xc7,0x0c,0xc6,0x0c,0xc5,0x0c,0xc4,0x0c,0xc3,0x0c,0xc2,0x0c,0xc1,0x0c,0xc0,0x0c,0xbf,0x0c,0xbe,0x0c,0xbd,0x0c,0xbc,0x0c,0xbb,0x0c,0xba,0x0c,0xb9,0x0c,0xb8,0x0c,0xb7,0x0c,0xb6,0x0c,0xb5,0x0c,0xb4,0x0c,0xb3,0x0c,0xb2,0x0c,0xb1,0x0c,0xb0,0x0c,0xaf,0x0c,0xae,0x0c,0xad,0x0c,0xac,0x0c,0xab,0x0c,0xaa,0x0c,0xa9,0x0c,0xa8,0x0c,0xa7,0x0c,0xa6,0x0c,0xa5,0x0c,0xa4,0x0c,0xa3,0x0c,0xa2,0x0c,0xa1,0x0c,0xa0,0x0c,0x9f,0x0c,0x9e,0x0c,0x9d,0x0c,0x9c,0x0c,0x9b,0x0c,0x9a,0x0c,0x99,0x0c,0x98,0x0c,0x97,0x0c,0x96,0x0c,0x95,0x0c,0x94,0x0c,0x93,0x0c,0x92,0x0c,0x91,0x0c,0x90,0x0c,0x8f,0x0c,0x8e,0x0c,0x8d,0x0c,0x8c,0x0c,0x8b,0x0c,0x8a,0x0c,0x89,0x0c,0x88,0x0c,0x87,0x0c,0x86,0x0c,0x85,0x0c,0x84,0x0c,0x83,0x0c,0x82,0x0c,0x81,0x0c,0x80,0x0c,0x7f,0x0c,0x7e,0x0c,0x7d,0x0c,0x7c,0x0c,0x7b,0x0c,0x7a,0x0c,0x79,0x0c,0x78,0x0c,0x77,0x0c,0x76,0x0c,0x75,0x0c,0x74,0x0c,0x73,0x0c,0x72,0x0c,0x71,0x0c,0x70,0x0c,0x6f,0x0c,0x6e,0x0c,0x6d,0x0c,0x6c,0x0c,0x6b,0x0c,0x6a,0x0c,0x69,0x0c,0x68,0x0c,0x67,0x0c,0x66,0x0c,0x65,0x0c,0x64,0x0c,0x63,0x0c,0x62,0x0c,0x61,0x0c,0x60,0x0c,0x5f,0x0c,0x5e,0x0c,0x5d,0x0c,0x5c,0x0c,0x5b,0x0c,0x5a,0x0c,0x59,0x0c,0x58,0x0c,0x57,0x0c,0x56,0x0c,0x55,0x0c,0x54,0x0c,0x53,0x0c,0x52,0x0c,0x51,0x0c,0x50,0x0c,0x4f,0x0c,0x4e,0x0c,0x4d,0x0c,0x4c,0x0c,0x4b,0x0c,0x4a,0x0c,0x49,0x0c,0x48,0x0c,0x47,0x0c,0x46,0x0c,0x45,0x0c,0x44,0x0c,0x43,0x0c,0x42,0x0c,0x41,0x0c,0x40,0x0c,0x3f,0x0c,0x3e,0x0c,0x3d,0x0c,0x3c,0x0c,0x3b,0x0c,0x3a,0x0c,0x39,0x0c,0x38,0x0c,0x37,0x0c,0x36,0x0c,0x35,0x0c,0x34,0x0c,0x33,0x0c,0x32,0x0c,0x31,0x0c,0x30,0x0c,0x2f,0x0c,0x2e,0x0c,0x2d,0x0c,0x2c,0x0c,0x2b,0x0c,0x2a,0x0c,0x29,0x0c,0x28,0x0c,0x27,0x0c,0x26,0x0c,0x25,0x0c,0x24,0x0c,0x23,0x0c,0x22,0x0c,0x21,0x0c,0x20,0x0c,0x1f,0x0c,0x1e,0x0c,0x1d,0x0c,0x1c,0x0c,0x1b,0x0c,0x1a,0x0c,0x19,0x0c,0x18,0x0c,0x17,0x0c,0x16,0x0c,0x15,0x0c,0x14,0x0c,0x13,0x0c,0x12,0x0c,0x11,0x0c,0x10,0x0c,
//        0x0f,0x0c,0x0e,0x0c,0x0d,0x0c,0x0c,0x0c,0x0b,0x0c,0x0a,0x0c,0x09,0x0c,0x08,0x0c,0x07,0x0c,0x06,0x0c,0x05,0x0c,0x04,0x0c,0x03,0x0c,0x02,0x0c,0x01,0x0c,0x00,0x0c,0xff,0x0b,0xfe,0x0b,0xfd,0x0b,0xfc,0x0b,0xfb,0x0b,0xfa,0x0b,0xf9,0x0b,0xf8,0x0b,0xf7,0x0b,0xf6,0x0b,0xf5,0x0b,0xf4,0x0b,0xf3,0x0b,0xf2,0x0b,0xf1,0x0b,0xf0,0x0b,0xef,0x0b,0xee,0x0b,0xed,0x0b,0xec,0x0b,0xeb,0x0b,0xea,0x0b,0xe9,0x0b,0xe8,0x0b,0xe7,0x0b,0xe6,0x0b,0xe5,0x0b,0xe4,0x0b,0xe3,0x0b,0xe2,0x0b,0xe1,0x0b,0xe0,0x0b,0xdf,0x0b,0xde,0x0b,0xdd,0x0b,0xdc,0x0b,0xdb,0x0b,0xda,0x0b,0xd9,0x0b,0xd8,0x0b,0xd7,0x0b,0xd6,0x0b,0xd5,0x0b,0xd4,0x0b,0xd3,0x0b,0xd2,0x0b,0xd1,0x0b,0xd0,0x0b,0xcf,0x0b,0xce,0x0b,0xcd,0x0b,0xcc,0x0b,0xcb,0x0b,0xca,0x0b,0xc9,0x0b,0xc8,0x0b,0xc7,0x0b,0xc6,0x0b,0xc5,0x0b,0xc4,0x0b,0xc3,0x0b,0xc2,0x0b,0xc1,0x0b,0xc0,0x0b,0xbf,0x0b,0xbe,0x0b,0xbd,0x0b,0xbc,0x0b,0xbb,0x0b,0xba,0x0b,0xb9,0x0b,0xb8,0x0b,0xb7,0x0b,0xb6,0x0b,0xb5,0x0b,0xb4,0x0b,0xb3,0x0b,0xb2,0x0b,0xb1,0x0b,0xb0,0x0b,0xaf,0x0b,0xae,0x0b,0xad,0x0b,0xac,0x0b,0xab,0x0b,0xaa,0x0b,0xa9,0x0b,0xa8,0x0b,0xa7,0x0b,0xa6,0x0b,0xa5,0x0b,0xa4,0x0b,0xa3,0x0b,0xa2,0x0b,0xa1,0x0b,0xa0,0x0b,0x9f,0x0b,0x9e,0x0b,0x9d,0x0b,0x9c,0x0b,0x9b,0x0b,0x9a,0x0b,0x99,0x0b,0x98,0x0b,0x97,0x0b,0x96,0x0b,0x95,0x0b,0x94,0x0b,0x93,0x0b,0x92,0x0b,0x91,0x0b,0x90,0x0b,0x8f,0x0b,0x8e,0x0b,0x8d,0x0b,0x8c,0x0b,0x8b,0x0b,0x8a,0x0b,0x89,0x0b,0x88,0x0b,0x87,0x0b,0x86,0x0b,0x85,0x0b,0x84,0x0b,0x83,0x0b,0x82,0x0b,0x81,0x0b,0x80,0x0b,0x7f,0x0b,0x7e,0x0b,0x7d,0x0b,0x7c,0x0b,0x7b,0x0b,0x7a,0x0b,0x79,0x0b,0x78,0x0b,0x77,0x0b,0x76,0x0b,0x75,0x0b,0x74,0x0b,0x73,0x0b,0x72,0x0b,0x71,0x0b,0x70,0x0b,0x6f,0x0b,0x6e,0x0b,0x6d,0x0b,0x6c,0x0b,0x6b,0x0b,0x6a,0x0b,0x69,0x0b,0x68,0x0b,0x67,0x0b,0x66,0x0b,0x65,0x0b,0x64,0x0b,0x63,0x0b,0x62,0x0b,0x61,0x0b,0x60,0x0b,0x5f,0x0b,0x5e,0x0b,0x5d,0x0b,0x5c,0x0b,0x5b,0x0b,0x5a,0x0b,0x59,0x0b,0x58,0x0b,0x57,0x0b,0x56,0x0b,0x55,0x0b,0x54,0x0b,0x53,0x0b,0x52,0x0b,0x51,0x0b,0x50,0x0b,0x4f,0x0b,0x4e,0x0b,0x4d,0x0b,0x4c,0x0b,0x4b,0x0b,0x4a,0x0b,0x49,0x0b,0x48,0x0b,0x47,0x0b,0x46,0x0b,0x45,0x0b,0x44,0x0b,0x43,0x0b,0x42,0x0b,0x41,0x0b,0x40,0x0b,0x3f,0x0b,0x3e,0x0b,0x3d,0x0b,0x3c,0x0b,0x3b,0x0b,0x3a,0x0b,0x39,0x0b,0x38,0x0b,0x37,0x0b,0x36,0x0b,0x35,0x0b,0x34,0x0b,0x33,0x0b,0x32,0x0b,0x31,0x0b,0x30,0x0b,0x2f,0x0b,0x2e,0x0b,0x2d,0x0b,0x2c,0x0b,0x2b,0x0b,0x2a,0x0b,0x29,0x0b,0x28,0x0b,0x27,0x0b,0x26,0x0b,0x25,0x0b,0x24,0x0b,0x23,0x0b,0x22,0x0b,0x21,0x0b,0x20,0x0b,0x1f,0x0b,0x1e,0x0b,0x1d,0x0b,0x1c,0x0b,0x1b,0x0b,0x1a,0x0b,0x19,0x0b,0x18,0x0b,0x17,0x0b,0x16,0x0b,0x15,0x0b,0x14,0x0b,0x13,0x0b,0x12,0x0b,0x11,0x0b,0x10,0x0b,
//        0x0f,0x0b,0x0e,0x0b,0x0d,0x0b,0x0c,0x0b,0x0b,0x0b,0x0a,0x0b,0x09,0x0b,0x08,0x0b,0x07,0x0b,0x06,0x0b,0x05,0x0b,0x04,0x0b,0x03,0x0b,0x02,0x0b,0x01,0x0b,0x00,0x0b,0xff,0x0a,0xfe,0x0a,0xfd,0x0a,0xfc,0x0a,0xfb,0x0a,0xfa,0x0a,0xf9,0x0a,0xf8,0x0a,0xf7,0x0a,0xf6,0x0a,0xf5,0x0a,0xf4,0x0a,0xf3,0x0a,0xf2,0x0a,0xf1,0x0a,0xf0,0x0a,0xef,0x0a,0xee,0x0a,0xed,0x0a,0xec,0x0a,0xeb,0x0a,0xea,0x0a,0xe9,0x0a,0xe8,0x0a,0xe7,0x0a,0xe6,0x0a,0xe5,0x0a,0xe4,0x0a,0xe3,0x0a,0xe2,0x0a,0xe1,0x0a,0xe0,0x0a,0xdf,0x0a,0xde,0x0a,0xdd,0x0a,0xdc,0x0a,0xdb,0x0a,0xda,0x0a,0xd9,0x0a,0xd8,0x0a,0xd7,0x0a,0xd6,0x0a,0xd5,0x0a,0xd4,0x0a,0xd3,0x0a,0xd2,0x0a,0xd1,0x0a,0xd0,0x0a,0xcf,0x0a,0xce,0x0a,0xcd,0x0a,0xcc,0x0a,0xcb,0x0a,0xca,0x0a,0xc9,0x0a,0xc8,0x0a,0xc7,0x0a,0xc6,0x0a,0xc5,0x0a,0xc4,0x0a,0xc3,0x0a,0xc2,0x0a,0xc1,0x0a,0xc0,0x0a,0xbf,0x0a,0xbe,0x0a,0xbd,0x0a,0xbc,0x0a,0xbb,0x0a,0xba,0x0a,0xb9,0x0a,0xb8,0x0a,0xb7,0x0a,0xb6,0x0a,0xb5,0x0a,0xb4,0x0a,0xb3,0x0a,0xb2,0x0a,0xb1,0x0a,0xb0,0x0a,0xaf,0x0a,0xae,0x0a,0xad,0x0a,0xac,0x0a,0xab,0x0a,0xaa,0x0a,0xa9,0x0a,0xa8,0x0a,0xa7,0x0a,0xa6,0x0a,0xa5,0x0a,0xa4,0x0a,0xa3,0x0a,0xa2,0x0a,0xa1,0x0a,0xa0,0x0a,0x9f,0x0a,0x9e,0x0a,0x9d,0x0a,0x9c,0x0a,0x9b,0x0a,0x9a,0x0a,0x99,0x0a,0x98,0x0a,0x97,0x0a,0x96,0x0a,0x95,0x0a,0x94,0x0a,0x93,0x0a,0x92,0x0a,0x91,0x0a,0x90,0x0a,0x8f,0x0a,0x8e,0x0a,0x8d,0x0a,0x8c,0x0a,0x8b,0x0a,0x8a,0x0a,0x89,0x0a,0x88,0x0a,0x87,0x0a,0x86,0x0a,0x85,0x0a,0x84,0x0a,0x83,0x0a,0x82,0x0a,0x81,0x0a,0x80,0x0a,0x7f,0x0a,0x7e,0x0a,0x7d,0x0a,0x7c,0x0a,0x7b,0x0a,0x7a,0x0a,0x79,0x0a,0x78,0x0a,0x77,0x0a,0x76,0x0a,0x75,0x0a,0x74,0x0a,0x73,0x0a,0x72,0x0a,0x71,0x0a,0x70,0x0a,0x6f,0x0a,0x6e,0x0a,0x6d,0x0a,0x6c,0x0a,0x6b,0x0a,0x6a,0x0a,0x69,0x0a,0x68,0x0a,0x67,0x0a,0x66,0x0a,0x65,0x0a,0x64,0x0a,0x63,0x0a,0x62,0x0a,0x61,0x0a,0x60,0x0a,0x5f,0x0a,0x5e,0x0a,0x5d,0x0a,0x5c,0x0a,0x5b,0x0a,0x5a,0x0a,0x59,0x0a,0x58,0x0a,0x57,0x0a,0x56,0x0a,0x55,0x0a,0x54,0x0a,0x53,0x0a,0x52,0x0a,0x51,0x0a,0x50,0x0a,0x4f,0x0a,0x4e,0x0a,0x4d,0x0a,0x4c,0x0a,0x4b,0x0a,0x4a,0x0a,0x49,0x0a,0x48,0x0a,0x47,0x0a,0x46,0x0a,0x45,0x0a,0x44,0x0a,0x43,0x0a,0x42,0x0a,0x41,0x0a,0x40,0x0a,0x3f,0x0a,0x3e,0x0a,0x3d,0x0a,0x3c,0x0a,0x3b,0x0a,0x3a,0x0a,0x39,0x0a,0x38,0x0a,0x37,0x0a,0x36,0x0a,0x35,0x0a,0x34,0x0a,0x33,0x0a,0x32,0x0a,0x31,0x0a,0x30,0x0a,0x2f,0x0a,0x2e,0x0a,0x2d,0x0a,0x2c,0x0a,0x2b,0x0a,0x2a,0x0a,0x29,0x0a,0x28,0x0a,0x27,0x0a,0x26,0x0a,0x25,0x0a,0x24,0x0a,0x23,0x0a,0x22,0x0a,0x21,0x0a,0x20,0x0a,0x1f,0x0a,0x1e,0x0a,0x1d,0x0a,0x1c,0x0a,0x1b,0x0a,0x1a,0x0a,0x19,0x0a,0x18,0x0a,0x17,0x0a,0x16,0x0a,0x15,0x0a,0x14,0x0a,0x13,0x0a,0x12,0x0a,0x11,0x0a,0x10,0x0a,
//        0x0f,0x0a,0x0e,0x0a,0x0d,0x0a,0x0c,0x0a,0x0b,0x0a,0x0a,0x0a,0x09,0x0a,0x08,0x0a,0x07,0x0a,0x06,0x0a,0x05,0x0a,0x04,0x0a,0x03,0x0a,0x02,0x0a,0x01,0x0a,0x00,0x0a,0xff,0x09,0xfe,0x09,0xfd,0x09,0xfc,0x09,0xfb,0x09,0xfa,0x09,0xf9,0x09,0xf8,0x09,0xf7,0x09,0xf6,0x09,0xf5,0x09,0xf4,0x09,0xf3,0x09,0xf2,0x09,0xf1,0x09,0xf0,0x09,0xef,0x09,0xee,0x09,0xed,0x09,0xec,0x09,0xeb,0x09,0xea,0x09,0xe9,0x09,0xe8,0x09,0xe7,0x09,0xe6,0x09,0xe5,0x09,0xe4,0x09,0xe3,0x09,0xe2,0x09,0xe1,0x09,0xe0,0x09,0xdf,0x09,0xde,0x09,0xdd,0x09,0xdc,0x09,0xdb,0x09,0xda,0x09,0xd9,0x09,0xd8,0x09,0xd7,0x09,0xd6,0x09,0xd5,0x09,0xd4,0x09,0xd3,0x09,0xd2,0x09,0xd1,0x09,0xd0,0x09,0xcf,0x09,0xce,0x09,0xcd,0x09,0xcc,0x09,0xcb,0x09,0xca,0x09,0xc9,0x09,0xc8,0x09,0xc7,0x09,0xc6,0x09,0xc5,0x09,0xc4,0x09,0xc3,0x09,0xc2,0x09,0xc1,0x09,0xc0,0x09,0xbf,0x09,0xbe,0x09,0xbd,0x09,0xbc,0x09,0xbb,0x09,0xba,0x09,0xb9,0x09,0xb8,0x09,0xb7,0x09,0xb6,0x09,0xb5,0x09,0xb4,0x09,0xb3,0x09,0xb2,0x09,0xb1,0x09,0xb0,0x09,0xaf,0x09,0xae,0x09,0xad,0x09,0xac,0x09,0xab,0x09,0xaa,0x09,0xa9,0x09,0xa8,0x09,0xa7,0x09,0xa6,0x09,0xa5,0x09,0xa4,0x09,0xa3,0x09,0xa2,0x09,0xa1,0x09,0xa0,0x09,0x9f,0x09,0x9e,0x09,0x9d,0x09,0x9c,0x09,0x9b,0x09,0x9a,0x09,0x99,0x09,0x98,0x09,0x97,0x09,0x96,0x09,0x95,0x09,0x94,0x09,0x93,0x09,0x92,0x09,0x91,0x09,0x90,0x09,0x8f,0x09,0x8e,0x09,0x8d,0x09,0x8c,0x09,0x8b,0x09,0x8a,0x09,0x89,0x09,0x88,0x09,0x87,0x09,0x86,0x09,0x85,0x09,0x84,0x09,0x83,0x09,0x82,0x09,0x81,0x09,0x80,0x09,0x7f,0x09,0x7e,0x09,0x7d,0x09,0x7c,0x09,0x7b,0x09,0x7a,0x09,0x79,0x09,0x78,0x09,0x77,0x09,0x76,0x09,0x75,0x09,0x74,0x09,0x73,0x09,0x72,0x09,0x71,0x09,0x70,0x09,0x6f,0x09,0x6e,0x09,0x6d,0x09,0x6c,0x09,0x6b,0x09,0x6a,0x09,0x69,0x09,0x68,0x09,0x67,0x09,0x66,0x09,0x65,0x09,0x64,0x09,0x63,0x09,0x62,0x09,0x61,0x09,0x60,0x09,0x5f,0x09,0x5e,0x09,0x5d,0x09,0x5c,0x09,0x5b,0x09,0x5a,0x09,0x59,0x09,0x58,0x09,0x57,0x09,0x56,0x09,0x55,0x09,0x54,0x09,0x53,0x09,0x52,0x09,0x51,0x09,0x50,0x09,0x4f,0x09,0x4e,0x09,0x4d,0x09,0x4c,0x09,0x4b,0x09,0x4a,0x09,0x49,0x09,0x48,0x09,0x47,0x09,0x46,0x09,0x45,0x09,0x44,0x09,0x43,0x09,0x42,0x09,0x41,0x09,0x40,0x09,0x3f,0x09,0x3e,0x09,0x3d,0x09,0x3c,0x09,0x3b,0x09,0x3a,0x09,0x39,0x09,0x38,0x09,0x37,0x09,0x36,0x09,0x35,0x09,0x34,0x09,0x33,0x09,0x32,0x09,0x31,0x09,0x30,0x09,0x2f,0x09,0x2e,0x09,0x2d,0x09,0x2c,0x09,0x2b,0x09,0x2a,0x09,0x29,0x09,0x28,0x09,0x27,0x09,0x26,0x09,0x25,0x09,0x24,0x09,0x23,0x09,0x22,0x09,0x21,0x09,0x20,0x09,0x1f,0x09,0x1e,0x09,0x1d,0x09,0x1c,0x09,0x1b,0x09,0x1a,0x09,0x19,0x09,0x18,0x09,0x17,0x09,0x16,0x09,0x15,0x09,0x14,0x09,0x13,0x09,0x12,0x09,0x11,0x09,0x10,0x09,
//        0x0f,0x09,0x0e,0x09,0x0d,0x09,0x0c,0x09,0x0b,0x09,0x0a,0x09,0x09,0x09,0x08,0x09,0x07,0x09,0x06,0x09,0x05,0x09,0x04,0x09,0x03,0x09,0x02,0x09,0x01,0x09,0x00,0x09,0xff,0x08,0xfe,0x08,0xfd,0x08,0xfc,0x08,0xfb,0x08,0xfa,0x08,0xf9,0x08,0xf8,0x08,0xf7,0x08,0xf6,0x08,0xf5,0x08,0xf4,0x08,0xf3,0x08,0xf2,0x08,0xf1,0x08,0xf0,0x08,0xef,0x08,0xee,0x08,0xed,0x08,0xec,0x08,0xeb,0x08,0xea,0x08,0xe9,0x08,0xe8,0x08,0xe7,0x08,0xe6,0x08,0xe5,0x08,0xe4,0x08,0xe3,0x08,0xe2,0x08,0xe1,0x08,0xe0,0x08,0xdf,0x08,0xde,0x08,0xdd,0x08,0xdc,0x08,0xdb,0x08,0xda,0x08,0xd9,0x08,0xd8,0x08,0xd7,0x08,0xd6,0x08,0xd5,0x08,0xd4,0x08,0xd3,0x08,0xd2,0x08,0xd1,0x08,0xd0,0x08,0xcf,0x08,0xce,0x08,0xcd,0x08,0xcc,0x08,0xcb,0x08,0xca,0x08,0xc9,0x08,0xc8,0x08,0xc7,0x08,0xc6,0x08,0xc5,0x08,0xc4,0x08,0xc3,0x08,0xc2,0x08,0xc1,0x08,0xc0,0x08,0xbf,0x08,0xbe,0x08,0xbd,0x08,0xbc,0x08,0xbb,0x08,0xba,0x08,0xb9,0x08,0xb8,0x08,0xb7,0x08,0xb6,0x08,0xb5,0x08,0xb4,0x08,0xb3,0x08,0xb2,0x08,0xb1,0x08,0xb0,0x08,0xaf,0x08,0xae,0x08,0xad,0x08,0xac,0x08,0xab,0x08,0xaa,0x08,0xa9,0x08,0xa8,0x08,0xa7,0x08,0xa6,0x08,0xa5,0x08,0xa4,0x08,0xa3,0x08,0xa2,0x08,0xa1,0x08,0xa0,0x08,0x9f,0x08,0x9e,0x08,0x9d,0x08,0x9c,0x08,0x9b,0x08,0x9a,0x08,0x99,0x08,0x98,0x08,0x97,0x08,0x96,0x08,0x95,0x08,0x94,0x08,0x93,0x08,0x92,0x08,0x91,0x08,0x90,0x08,0x8f,0x08,0x8e,0x08,0x8d,0x08,0x8c,0x08,0x8b,0x08,0x8a,0x08,0x89,0x08,0x88,0x08,0x87,0x08,0x86,0x08,0x85,0x08,0x84,0x08,0x83,0x08,0x82,0x08,0x81,0x08,0x80,0x08,0x7f,0x08,0x7e,0x08,0x7d,0x08,0x7c,0x08,0x7b,0x08,0x7a,0x08,0x79,0x08,0x78,0x08,0x77,0x08,0x76,0x08,0x75,0x08,0x74,0x08,0x73,0x08,0x72,0x08,0x71,0x08,0x70,0x08,0x6f,0x08,0x6e,0x08,0x6d,0x08,0x6c,0x08,0x6b,0x08,0x6a,0x08,0x69,0x08,0x68,0x08,0x67,0x08,0x66,0x08,0x65,0x08,0x64,0x08,0x63,0x08,0x62,0x08,0x61,0x08,0x60,0x08,0x5f,0x08,0x5e,0x08,0x5d,0x08,0x5c,0x08,0x5b,0x08,0x5a,0x08,0x59,0x08,0x58,0x08,0x57,0x08,0x56,0x08,0x55,0x08,0x54,0x08,0x53,0x08,0x52,0x08,0x51,0x08,0x50,0x08,0x4f,0x08,0x4e,0x08,0x4d,0x08,0x4c,0x08,0x4b,0x08,0x4a,0x08,0x49,0x08,0x48,0x08,0x47,0x08,0x46,0x08,0x45,0x08,0x44,0x08,0x43,0x08,0x42,0x08,0x41,0x08,0x40,0x08,0x3f,0x08,0x3e,0x08,0x3d,0x08,0x3c,0x08,0x3b,0x08,0x3a,0x08,0x39,0x08,0x38,0x08,0x37,0x08,0x36,0x08,0x35,0x08,0x34,0x08,0x33,0x08,0x32,0x08,0x31,0x08,0x30,0x08,0x2f,0x08,0x2e,0x08,0x2d,0x08,0x2c,0x08,0x2b,0x08,0x2a,0x08,0x29,0x08,0x28,0x08,0x27,0x08,0x26,0x08,0x25,0x08,0x24,0x08,0x23,0x08,0x22,0x08,0x21,0x08,0x20,0x08,0x1f,0x08,0x1e,0x08,0x1d,0x08,0x1c,0x08,0x1b,0x08,0x1a,0x08,0x19,0x08,0x18,0x08,0x17,0x08,0x16,0x08,0x15,0x08,0x14,0x08,0x13,0x08,0x12,0x08,0x11,0x08,0x10,0x08,
//        0x0f,0x08,0x0e,0x08,0x0d,0x08,0x0c,0x08,0x0b,0x08,0x0a,0x08,0x09,0x08,0x08,0x08,0x07,0x08,0x06,0x08,0x05,0x08,0x04,0x08,0x03,0x08,0x02,0x08,0x01,0x08,0x00,0x08,0x40,0xa3,0xd5,0x7c,
//    };
//    const uint32_t checksumExpected = ChecksumFletcher32(data, sizeof(data)-4);
//    uint32_t checksumGot = 0;
//    memcpy(&checksumGot, data+sizeof(data)-4, sizeof(checksumGot));
//    printf("checksumExpected:0x%08x checksumGot:0x%08x\n", checksumExpected, checksumGot);
//    return 0;
    
//    const uint8_t chars[] = {'a', 'b', 'c', 'd', 'e', 0};             // 0xf04fc729
////    const uint8_t chars[] = {'a', 'b', 'c', 'd', 'e', 'f'};           // 0x56502d2a
////    const uint8_t chars[] = {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'}; // 0xebe19591
//    const uint32_t checksum = ChecksumFletcher32(chars, sizeof(chars));
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
        fprintf(stderr, "No matching MDC devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC devices\n\n");
        return 1;
    }
    
    MDCDevice& device = devices[0];
    try {
        device.endpointsFlush();
        if (args.cmd == lower(LEDSetCmd))           LEDSet(args, device);
        else if (args.cmd == lower(STMWriteCmd))    STMWrite(args, device);
        else if (args.cmd == lower(ICEWriteCmd))    ICEWrite(args, device);
        else if (args.cmd == lower(MSPReadCmd))     MSPRead(args, device);
        else if (args.cmd == lower(MSPWriteCmd))    MSPWrite(args, device);
        else if (args.cmd == lower(SDImgReadCmd))   SDImgRead(args, device);
        else if (args.cmd == lower(ImgCaptureCmd))  ImgCapture(args, device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

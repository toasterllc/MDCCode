#include <stdio.h>
#include <assert.h>
#include <vector>
#include <queue>
#include <algorithm>
#include <unistd.h>
#include <string.h>
#include <libftdi1/ftdi.h>
#include <optional>
#include <memory>
#include <chrono>
#include <sstream>
#include <iomanip>
#include <iostream>
#include <inttypes.h>
#include <fstream>
#include "MDCDevice.h"

using TimeInstant = std::chrono::steady_clock::time_point;

static TimeInstant CurrentTime() {
    return std::chrono::steady_clock::now();
}

static uint64_t TimeDurationNs(TimeInstant t1, TimeInstant t2) {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(t2-t1).count();
}

static uint64_t TimeDurationMs(TimeInstant t1, TimeInstant t2) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(t2-t1).count();
}

static void PrintMsg(const MDCDevice::ReadMemMsg& msg) {
    std::cout << msg.desc();
}

using Cmd = std::string;
const Cmd SetLEDCmd = "setled";
const Cmd ReadMemCmd = "readmem";
const Cmd VerifyMemCmd = "verifymem";
const Cmd PixReg8Cmd = "pixreg8";
const Cmd PixReg16Cmd = "pixreg16";
const Cmd PixCaptureCmd = "pixcapture";

void printUsage() {
    using namespace std;
    cout << "MDCDebugger commands:\n";
    cout << " " << SetLEDCmd        << " <0/1>\n";
    cout << " " << ReadMemCmd       << " <file>\n";
    cout << " " << VerifyMemCmd     << "\n";
    cout << " " << PixReg8Cmd       << " <addr>\n";
    cout << " " << PixReg8Cmd       << " <addr>=<val8>\n";
    cout << " " << PixReg16Cmd      << " <addr>\n";
    cout << " " << PixReg16Cmd      << " <addr>=<val16>\n";
    cout << " " << PixCaptureCmd    << " <file>\n";
    cout << "\n";
}

struct RegOp {
    bool write = false;
    uint16_t addr = 0;
    uint16_t val = 0;
};

struct Args {
    Cmd cmd;
    bool on = false;
    std::string filePath;
    RegOp regOp;
};

static RegOp parseRegOp(const std::string str) {
    std::stringstream ss(str);
    std::string part;
    std::vector<std::string> parts;
    while (std::getline(ss, part, '=')) parts.push_back(part);
    
    RegOp regOp;
    
    uintmax_t addr = strtoumax(parts[0].c_str(), nullptr, 0);
    if (addr > UINT16_MAX) throw std::runtime_error("invalid register address");
    regOp.addr = addr;
    
    if (parts.size() > 1) {
        uintmax_t val = strtoumax(parts[1].c_str(), nullptr, 0);
        if (val > UINT16_MAX) throw std::runtime_error("invalid register value");
        regOp.write = true;
        regOp.val = val;
    }
    
    return regOp;
}

static Args parseArgs(int argc, const char* argv[]) {
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = strs[0];
    
    if (args.cmd == SetLEDCmd) {
        if (strs.size() < 2) throw std::runtime_error("on/off state not specified");
        args.on = atoi(strs[1].c_str());
    
    } else if (args.cmd == ReadMemCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else if (args.cmd == VerifyMemCmd) {
    
    } else if (args.cmd == PixReg8Cmd) {
        if (strs.size() < 2) throw std::runtime_error("no register specified");
        args.regOp = parseRegOp(strs[1]);
        
        // Verify that the register value is a valid uint8
        if (args.regOp.val > UINT8_MAX) throw std::runtime_error("invalid register value");
    
    } else if (args.cmd == PixReg16Cmd) {
        if (strs.size() < 2) throw std::runtime_error("no register specified");
        args.regOp = parseRegOp(strs[1]);
    
    } else if (args.cmd == PixCaptureCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void setLED(const Args& args, MDCDevice& device) {
    using SetLEDMsg = MDCDevice::SetLEDMsg;
    using Msg = MDCDevice::Msg;
    device.write(SetLEDMsg{.on = args.on});
    for (;;) {
        if (auto msgPtr = Msg::Cast<SetLEDMsg>(device.read())) {
            return;
        }
    }
}

const size_t RAMWordCount = 0x2000000;
const size_t RAMWordSize = 2;
const size_t RAMSize = RAMWordCount*RAMWordSize;
const size_t ImagePixelCount = 2304*1296;
const size_t ImagePixelSize = 2;
const size_t ImageSize = ImagePixelCount*ImagePixelSize;

static void readMem(const Args& args, MDCDevice& device) {
    using ReadMemMsg = MDCDevice::ReadMemMsg;
    using Msg = MDCDevice::Msg;
    
    std::ofstream outputFile(args.filePath.c_str(), std::ofstream::out|std::ofstream::binary|std::ofstream::trunc);
    if (!outputFile) {
        throw std::runtime_error("failed to open output file: " + args.filePath);
    }
    
    device.write(ReadMemMsg{});
    size_t dataLen = 0;
    for (size_t msgCount=0; dataLen<RAMSize;) {
        if (auto msgPtr = Msg::Cast<ReadMemMsg>(device.read())) {
            const auto& msg = *msgPtr;
            // Cap `chunkLen` to prevent going past RAMSize.
            // Currently the device sends data in it 127-word chunks without bounds-checks,
            // so there will be trailing data if it didn't fall on a 127-word boundary.
            const size_t chunkLen = std::min((size_t)msg.hdr.len, RAMSize-dataLen);
            outputFile.write((char*)msg.mem, chunkLen);
            if (!outputFile) throw std::runtime_error("failed to write to output file");
            
            dataLen += chunkLen;
            
            msgCount++;
            if (!(msgCount % 1000)) {
                printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)dataLen);
            }
        }
    }
    
//    if (dataLen != RAMSize) {
//        throw std::runtime_error("data length mismatch: expected "
//            + std::to_string(RAMSize) + ", got " + std::to_string(dataLen));
//    }
}

static void verifyMem(const Args& args, MDCDevice& device) {
    using ReadMemMsg = MDCDevice::ReadMemMsg;
    using Msg = MDCDevice::Msg;
    device.write(ReadMemMsg{});
    
    auto startTime = CurrentTime();
    uintmax_t errorCount = 0;
    size_t dataLen = 0;
    std::optional<uint16_t> lastVal;
    for (size_t msgCount=0; dataLen<RAMSize; msgCount++) {
        if (auto msgPtr = Msg::Cast<ReadMemMsg>(device.read())) {
            const auto& msg = *msgPtr;
            if (!(msg.hdr.len % 2)) {
                // Cap `chunkLen` to prevent going past RAMSize.
                // Currently the device sends data in it 127-word chunks without bounds-checks,
                // so there will be trailing data if it didn't fall on a 127-word boundary.
                const size_t chunkLen = std::min((size_t)msg.hdr.len, RAMSize-dataLen);
                for (size_t i=0; i<chunkLen; i+=2) {
                    uint16_t val;
                    memcpy(&val, msg.mem+i, sizeof(val));
                    if (lastVal) {
                        uint16_t expected = (uint16_t)(*lastVal+1);
                        if (val != expected) {
                            fprintf(stderr, "Error: value mismatch: expected 0x%jx, got 0x%jx\n", (uintmax_t)expected, (uintmax_t)val);
                            errorCount++;
                        }
                    }
                    lastVal = val;
                }
                
                dataLen += chunkLen;
                if (!(msgCount % 1000)) {
                    printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)dataLen);
                }
            } else {
                fprintf(stderr, "Error: payload length invalid: expected even, got odd (0x%ju)\n", (uintmax_t)msg.hdr.len);
                errorCount++;
                break;
            }
        }
    }
    auto stopTime = CurrentTime();
    
    if (dataLen != RAMSize) {
        fprintf(stderr, "Error: data length mismatch: expected 0x%jx, got 0x%jx\n",
            (uintmax_t)RAMSize, (uintmax_t)dataLen);
        errorCount++;
    }
    
    printf("Memory verification finished\n");
    printf("  errors: %ju\n", (uintmax_t)errorCount);
    printf("  data length: %ju bytes\n", (uintmax_t)dataLen);
    printf("  duration: %ju ms\n", (uintmax_t)TimeDurationMs(startTime, stopTime));
    
    if (errorCount) throw std::runtime_error("memory verification failed");
}

static void pixReg8(const Args& args, MDCDevice& device) {
    using PixReg8Msg = MDCDevice::PixReg8Msg;
    using Msg = MDCDevice::Msg;
    
    device.write(PixReg8Msg{
        .write = args.regOp.write,
        .addr = args.regOp.addr,
        .val = (uint8_t)args.regOp.val,
    });
    
    if (auto msgPtr = Msg::Cast<PixReg8Msg>(device.read())) {
        const auto& msg = *msgPtr;
        if (msg.ok) {
            if (!args.regOp.write) {
                printf("0x%04x = 0x%02x\n", msg.addr, msg.val);
            }
        } else {
            throw std::runtime_error("i2c transaction failed");
        }
        return;
    }
}

static void pixReg16(const Args& args, MDCDevice& device) {
    using PixReg16Msg = MDCDevice::PixReg16Msg;
    using Msg = MDCDevice::Msg;
    
    device.write(PixReg16Msg{
        .write = args.regOp.write,
        .addr = args.regOp.addr,
        .val = args.regOp.val,
    });
    
    if (auto msgPtr = Msg::Cast<PixReg16Msg>(device.read())) {
        const auto& msg = *msgPtr;
        if (msg.ok) {
            if (!args.regOp.write) {
                printf("0x%04x = 0x%04x\n", msg.addr, msg.val);
            }
        } else {
            throw std::runtime_error("i2c transaction failed");
        }
        return;
    }
}

static void pixCapture(const Args& args, MDCDevice& device) {
    using PixCaptureMsg = MDCDevice::PixCaptureMsg;
    using Msg = MDCDevice::Msg;
    
    std::ofstream outputFile(args.filePath.c_str(), std::ofstream::out|std::ofstream::binary|std::ofstream::trunc);
    if (!outputFile) {
        throw std::runtime_error("failed to open output file: " + args.filePath);
    }
    
    device.write(PixCaptureMsg{});
    size_t dataLen = 0;
    for (size_t msgCount=0; dataLen<ImageSize;) {
        if (auto msgPtr = Msg::Cast<PixCaptureMsg>(device.read())) {
            const auto& msg = *msgPtr;
            // Cap `chunkLen` to prevent going past ImageSize.
            // Currently the device sends data in it 127-word chunks without bounds-checks,
            // so there will be trailing data if it didn't fall on a 127-word boundary.
            const size_t chunkLen = std::min((size_t)msg.hdr.len, ImageSize-dataLen);
            outputFile.write((char*)msg.mem, chunkLen);
            if (!outputFile) throw std::runtime_error("failed to write to output file");
            
            dataLen += chunkLen;
            
            msgCount++;
            if (!(msgCount % 1000)) {
                printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)dataLen);
            }
        }
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
    
    auto device = std::make_unique<MDCDevice>();
    
    try {
        if (args.cmd == SetLEDCmd)          setLED(args, *device);
        else if (args.cmd == ReadMemCmd)    readMem(args, *device);
        else if (args.cmd == VerifyMemCmd)  verifyMem(args, *device);
        else if (args.cmd == PixReg8Cmd)    pixReg8(args, *device);
        else if (args.cmd == PixReg16Cmd)   pixReg16(args, *device);
        else if (args.cmd == PixCaptureCmd) pixCapture(args, *device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

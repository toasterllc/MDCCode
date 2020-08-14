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

static void PrintMsg(const MDCDevice::MemDataMsg& msg) {
    std::cout << msg.desc();
}

using Cmd = std::string;
const Cmd LEDSetCmd = "ledset";
const Cmd MemReadCmd = "memread";
const Cmd MemVerifyCmd = "memverify";
const Cmd PixReg8Cmd = "pixreg8";
const Cmd PixReg16Cmd = "pixreg16";
const Cmd PixCaptureCmd = "pixcapture";
const Cmd SDCmdCmd = "sdcmd";

void printUsage() {
    using namespace std;
    cout << "MDCDebugger commands:\n";
    cout << " " << LEDSetCmd        << " <0/1>\n";
    cout << " " << MemReadCmd       << " <file>\n";
    cout << " " << MemVerifyCmd     << "\n";
    cout << " " << PixReg8Cmd       << " <addr>\n";
    cout << " " << PixReg8Cmd       << " <addr>=<val8>\n";
    cout << " " << PixReg16Cmd      << " <addr>\n";
    cout << " " << PixReg16Cmd      << " <addr>=<val16>\n";
    cout << " " << PixCaptureCmd    << " <file>\n";
    cout << " " << SDCmdCmd         << " <cmd> <arg32>\n";
    cout << "\n";
}

struct RegOp {
    bool write = false;
    uint16_t addr = 0;
    uint16_t val = 0;
};

struct SDCmd {
    uint8_t cmd = 0;
    uint8_t arg[4] = {};
};

struct Args {
    Cmd cmd;
    bool on = false;
    std::string filePath;
    RegOp regOp;
    SDCmd sdCmd;
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
    
    if (args.cmd == LEDSetCmd) {
        if (strs.size() < 2) throw std::runtime_error("on/off state not specified");
        args.on = atoi(strs[1].c_str());
    
    } else if (args.cmd == MemReadCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else if (args.cmd == MemVerifyCmd) {
    
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
    
    } else if (args.cmd == SDCmdCmd) {
        if (strs.size() < 3) throw std::runtime_error("cmd/arg not specified");
        args.sdCmd.cmd = atoi(strs[1].c_str());
        
        uint32_t sdCmdArg = (uint32_t)strtoumax(strs[2].c_str(), nullptr, 0);
        args.sdCmd.arg[0] = (uint8_t)((sdCmdArg&0xFF000000)>>24);
        args.sdCmd.arg[1] = (uint8_t)((sdCmdArg&0x00FF0000)>>16);
        args.sdCmd.arg[2] = (uint8_t)((sdCmdArg&0x0000FF00)>>8);
        args.sdCmd.arg[3] = (uint8_t)((sdCmdArg&0x000000FF)>>0);
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void ledSet(const Args& args, MDCDevice& device) {
    using LEDSetMsg = MDCDevice::LEDSetMsg;
    using Msg = MDCDevice::Msg;
    device.write(LEDSetMsg{.on = args.on});
    for (;;) {
        if (auto msgPtr = Msg::Cast<LEDSetMsg>(device.read())) {
            return;
        }
    }
}

const size_t RAMWordCount = 0x2000000;
const size_t RAMWordSize = 2;
const size_t RAMSize = RAMWordCount*RAMWordSize;

static void memRead(const Args& args, MDCDevice& device) {
    using MemReadMsg = MDCDevice::MemReadMsg;
    using MemDataMsg = MDCDevice::MemDataMsg;
    using Msg = MDCDevice::Msg;
    
    std::ofstream outputFile(args.filePath.c_str(), std::ofstream::out|std::ofstream::binary|std::ofstream::trunc);
    if (!outputFile) {
        throw std::runtime_error("failed to open output file: " + args.filePath);
    }
    
    device.write(MemReadMsg{});
    size_t dataLen = 0;
    for (size_t msgCount=0; dataLen<RAMSize;) {
        if (auto msgPtr = Msg::Cast<MemDataMsg>(device.read())) {
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

static void memVerify(const Args& args, MDCDevice& device) {
    using MemReadMsg = MDCDevice::MemReadMsg;
    using MemDataMsg = MDCDevice::MemDataMsg;
    using Msg = MDCDevice::Msg;
    device.write(MemReadMsg{});
    
    auto startTime = CurrentTime();
    uintmax_t errorCount = 0;
    size_t dataLen = 0;
    std::optional<uint16_t> lastVal;
    for (size_t msgCount=0; dataLen<RAMSize; msgCount++) {
        if (auto msgPtr = Msg::Cast<MemDataMsg>(device.read())) {
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

const size_t ImagePixelSize = 2;

static void pixCapture(const Args& args, MDCDevice& device) {
    using PixCaptureMsg = MDCDevice::PixCaptureMsg;
    using PixSizeMsg = MDCDevice::PixSizeMsg;
    using PixDataMsg = MDCDevice::PixDataMsg;
    using Msg = MDCDevice::Msg;
    
    std::ofstream outputFile(args.filePath.c_str(), std::ofstream::out|std::ofstream::binary|std::ofstream::trunc);
    if (!outputFile) {
        throw std::runtime_error("failed to open output file: " + args.filePath);
    }
    
    device.write(PixCaptureMsg{});
    
    // Get the image size
    uint32_t imageWidth = 0;
    uint32_t imageHeight = 0;
    if (auto msgPtr = Msg::Cast<PixSizeMsg>(device.read())) {
        const auto& msg = *msgPtr;
        imageWidth = msg.width;
        imageHeight = msg.height;
    
    } else abort();
    
    const uint32_t ImagePixelCount = imageWidth*imageHeight;
    const size_t ImageSize = ImagePixelCount*ImagePixelSize;
    
    printf("Image stats:\n");
    printf("  Width: %ju\n", (uintmax_t)imageWidth);
    printf("  Height: %ju\n", (uintmax_t)imageHeight);
    printf("  Size: %ju bytes\n", (uintmax_t)ImageSize);
    printf("\n");
    
    size_t dataLen = 0;
    for (size_t msgCount=0; dataLen<ImageSize;) {
        if (auto msgPtr = Msg::Cast<PixDataMsg>(device.read())) {
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

static void sdCmd(const Args& args, MDCDevice& device) {
    using SDCmdMsg = MDCDevice::SDCmdMsg;
    using SDRespMsg = MDCDevice::SDRespMsg;
    using Msg = MDCDevice::Msg;
    
    device.write(SDCmdMsg{
        .cmd = args.sdCmd.cmd,
        .arg = {args.sdCmd.arg[0], args.sdCmd.arg[1], args.sdCmd.arg[2], args.sdCmd.arg[3]},
    });
    
    if (auto msgPtr = Msg::Cast<SDRespMsg>(device.read())) {
        const auto& msg = *msgPtr;
        if (msg.ok) {
            printf("SD card response:\n");
            for (size_t i=0; i<sizeof(msg.resp)/sizeof(*msg.resp); i++) {
                printf("%jx ", (uintmax_t)msg.resp[i]);
            }
            printf("\n");
        
        } else {
            throw std::runtime_error("SD command failed");
        }
        return;
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
        if (args.cmd == LEDSetCmd)          ledSet(args, *device);
        else if (args.cmd == MemReadCmd)    memRead(args, *device);
        else if (args.cmd == MemVerifyCmd)  memVerify(args, *device);
        else if (args.cmd == PixReg8Cmd)    pixReg8(args, *device);
        else if (args.cmd == PixReg16Cmd)   pixReg16(args, *device);
        else if (args.cmd == PixCaptureCmd) pixCapture(args, *device);
        else if (args.cmd == SDCmdCmd)      sdCmd(args, *device);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

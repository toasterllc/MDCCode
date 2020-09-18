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
#include <string>
#include "MDCDevice.h"

using Cmd = std::string;
const Cmd EchoCmd = "echo";

void printUsage() {
    using namespace std;
    cout << "MDCDebugger commands:\n";
    cout << "  " << EchoCmd        << " <string>\n";
    cout << "\n";
}

struct Args {
    Cmd cmd;
    std::string str;
};

static Args parseArgs(int argc, const char* argv[]) {
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) {
        std::string str = argv[i];
        std::transform(str.begin(), str.end(), str.begin(), ::tolower);
        strs.push_back(str);
    }
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = strs[0];
    
    if (args.cmd == EchoCmd) {
        if (strs.size() < 2) throw std::runtime_error("string not specified");
        args.str = strs[1];
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void echo(const Args& args, MDCDevice& device) {
    using Msg = MDCDevice::Msg;
    using Resp = MDCDevice::Resp;
    
    Msg msg{.type = 0};
    memcpy(msg.payload, args.str.c_str(), std::min(sizeof(msg.payload), args.str.length()));
    msg.payload[sizeof(msg.payload)-1] = 0; // Ensure that string is null-terminated
    device.write(msg);
    
    Resp resp = device.read();
    resp.payload[sizeof(resp.payload)-1] = 0; // Ensure that response string is null-terminated
    printf("Response: %s\n", resp.payload);
}

int main(int argc, const char* argv[]) {
    using Msg = MDCDevice::Msg;
    using Resp = MDCDevice::Resp;
    auto devicePtr = std::make_unique<MDCDevice>();
    MDCDevice& device = *devicePtr;
    
    // SD clock = 400 kHz
    {
        Msg msg{.type=1, .payload={0,0,0,0,0,0,1}};
        device.write(msg);
    }
    
    // Issue SD CMD0
    {
        printf("Sending SD CMD0\n");
        {
            Msg msg{.type=2, .payload={0, 0x40,0x00,0x00,0x00,0x00,0x01}};
            device.write(msg);
        }
        
        // Wait for command to be sent
        printf("  -> Waiting for SD command to be sent...\n");
        for (;;) {
            Msg msg{.type=3, .payload={}};
            device.write(msg);
            Resp resp = device.read();
            bool sdCommandSent = getBits(resp.payload, sizeof(resp.payload), 50, 50);
            bool sdRespReady = getBits(resp.payload, sizeof(resp.payload), 49, 49);
            bool sdRespCRCOK = getBits(resp.payload, sizeof(resp.payload), 48, 48);
            printf("sdCommandSent:%d sdRespReady:%d sdRespCRCOK:%d\n", sdCommandSent, sdRespReady, sdRespCRCOK);
            if (sdCommandSent) break;
        }
        printf("  -> Done\n");
    }
    
    // Issue SD CMD8
    {
        printf("Sending SD CMD8\n");
        {
            Msg msg{.type=2, .payload={0, 0x48,0x00,0x00,0x01,0xAA,0x01}};
            device.write(msg);
        }
        
        // Wait for command to be sent
        printf("  -> Waiting for SD response...\n");
        for (;;) {
            Msg msg{.type=3, .payload={}};
            device.write(msg);
            Resp resp = device.read();
            bool sdCommandSent = getBits(resp.payload, sizeof(resp.payload), 50, 50);
            bool sdRespReady = getBits(resp.payload, sizeof(resp.payload), 49, 49);
            bool sdRespCRCOK = getBits(resp.payload, sizeof(resp.payload), 48, 48);
            uint64_t sdResp = getBits(resp.payload, sizeof(resp.payload), 47, 0);
            printf("sdCommandSent:%d sdRespReady:%d sdRespCRCOK:%d sdResp:%012jx\n", sdCommandSent, sdRespReady, sdRespCRCOK, (uintmax_t)sdResp);
            if (sdRespReady) break;
        }
        printf("  -> Done...\n");
    }
    
    return 0;
    
//    Args args;
//    try {
//        args = parseArgs(argc-1, argv+1);
//    
//    } catch (const std::exception& e) {
//        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
//        printUsage();
//        return 1;
//    }
//    
//    auto device = std::make_unique<MDCDevice>();
//    
//    try {
//        if (args.cmd == EchoCmd)            echo(args, *device);
//    
//    } catch (const std::exception& e) {
//        fprintf(stderr, "Failed: %s\n", e.what());
//        return 1;
//    }
//    
//    return 0;
}

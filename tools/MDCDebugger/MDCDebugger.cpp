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
    using MDC = MDCDevice;
    using EchoMsg = MDC::EchoMsg;
    using EchoResp = MDC::EchoResp;
    
    device.write(EchoMsg(args.str.c_str()));
    
    auto resp = device.read<EchoResp>();
    printf("Response: %s\n", resp.msg());
}

static void sendSDCmd(MDCDevice& d, uint8_t sdCmd, uint32_t sdArg) {
    using MDC = MDCDevice;
    using SDSendCmdMsg = MDC::SDSendCmdMsg;
    using SDGetStatusMsg = MDC::SDGetStatusMsg;
    using SDGetStatusResp = MDC::SDGetStatusResp;
    d.write(SDSendCmdMsg(sdCmd, sdArg));
    
    // Wait for command to be sent
    for (;;) {
        d.write(SDGetStatusMsg());
        auto resp = d.read<SDGetStatusResp>();
        if (resp.sdCommandSent()) break;
    }
}

static MDCDevice::SDGetStatusResp getSDStatus(MDCDevice& d) {
    using MDC = MDCDevice;
    using SDGetStatusMsg = MDC::SDGetStatusMsg;
    using SDGetStatusResp = MDC::SDGetStatusResp;
    d.write(SDGetStatusMsg());
    return d.read<SDGetStatusResp>();
}

static MDCDevice::SDGetStatusResp getSDResp(MDCDevice& d) {
    for (;;) {
        auto status = getSDStatus(d);
        if (status.sdRespRecv()) return status;
    }
}

int main(int argc, const char* argv[]) {
    using MDC = MDCDevice;
    using SDSetClkSrcMsg = MDC::SDSetClkSrcMsg;
    using SDSendCmdMsg = MDC::SDSendCmdMsg;
    using SDGetStatusMsg = MDC::SDGetStatusMsg;
    using SDGetStatusResp = MDC::SDGetStatusResp;
    using Resp = MDC::Resp;
    auto devicePtr = std::make_unique<MDCDevice>();
    MDCDevice& device = *devicePtr;
    
    // Enable SD slow clock
    {
        printf("Enabling SD slow clock\n");
        device.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::Slow));
        printf("-> Done\n\n");
    }
    
    // Issue SD CMD0
    {
        printf("Sending SD CMD0\n");
        sendSDCmd(device, 0, 0);
        printf("-> Done\n\n");
    }
    
    // Issue SD CMD8
    {
        printf("Sending SD CMD8\n");
        sendSDCmd(device, 8, 0x000001AA);
        auto resp = getSDResp(device);
        assert(!resp.sdRespCRCErr());
        assert(resp.getBits(15,8) == 0xAA); // Verify the response pattern is what we sent
        printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
    }
    
    // Issue SD ACMD41
    {
        for (;;) {
            printf("Sending SD ACMD41\n");
            // CMD55
            {
                sendSDCmd(device, 55, 0x00000000);
                auto resp = getSDResp(device);
                assert(!resp.sdRespCRCErr());
            }
            
            // CMD41
            {
                sendSDCmd(device, 41, 0x51008000);
                auto resp = getSDResp(device);
                // Don't check CRC with .sdRespCRCOK() (the CRC response to ACMD41 is all 1's)
                assert(resp.getBits(45,40) == 0x3F); // Command should be 6'b111111
                assert(resp.getBits(7,1) == 0x7F); // CRC should be 7'b1111111
                // Check if card is ready. If it's not, retry ACMD41.
                if (!resp.getBits(39, 39)) {
                    printf("-> Card busy (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
                    continue;
                }
                assert(resp.getBits(32, 32)); // Verify that card can switch to 1.8V
                
                printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
                break;
            }
        }
    }
    
    // Issue SD CMD11
    {
        printf("Sending SD CMD11\n");
        sendSDCmd(device, 11, 0x00000000);
        auto resp = getSDResp(device);
        assert(!resp.sdRespCRCErr());
        printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
    }
    
    // Disable SD clock for 5ms (SD clock source = none)
    {
        printf("Disabling SD clock for 5ms\n");
        device.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::None));
        usleep(5000);
        printf("-> Done\n\n");
    }
    
    // Re-enable the SD clock
    {
        printf("Enabling SD slow clock\n");
        device.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::Slow));
        printf("-> Done\n\n");
    }
    
    // Wait for SD card to release DAT[0] line to indicate it's ready
    {
        printf("Waiting for SD card to be ready...\n");
        for (;;) {
            auto status = getSDStatus(device);
            if (status.sdDat() & 0x1) break;
            printf("-> Busy...\n\n");
        }
        printf("-> Ready\n\n");
    }
    
    // Issue SD CMD2
    {
        printf("Sending SD CMD2\n");
        sendSDCmd(device, 2, 0x00000000);
        auto resp = getSDResp(device);
        // Wait 1000us extra to allow the SD card to finish responding.
        // The SD card response to CMD2 is 136 bits (instead of the typical 48 bits),
        // so the SD card will still be responding at the time that the ice40 thinks
        // that the response is complete.
        usleep(1000);
        printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
    }
    
    // Issue SD CMD3
    uint16_t rca = 0;
    {
        printf("Sending SD CMD3\n");
        sendSDCmd(device, 3, 0x00000000);
        auto resp = getSDResp(device);
        assert(!resp.sdRespCRCErr());
        // Get the card's RCA from the response
        rca = resp.getBits(39, 24);
        printf("-> Done (response: 0x%012jx, rca: %04jx)\n\n", (uintmax_t)resp.sdResp(), (uintmax_t)rca);
    }
    
    // Issue SD CMD7
    {
        printf("Sending SD CMD7\n");
        sendSDCmd(device, 7, ((uint32_t)rca)<<16);
        auto resp = getSDResp(device);
        assert(!resp.sdRespCRCErr());
        printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
    }
    
    // Issue SD ACMD6
    {
        printf("Sending SD ACMD6\n");
        
        // CMD55
        {
            sendSDCmd(device, 55, ((uint32_t)rca)<<16);
            auto resp = getSDResp(device);
            assert(!resp.sdRespCRCErr());
        }
        
        // CMD6
        {
            sendSDCmd(device, 6, 0x00000002);
            auto resp = getSDResp(device);
            assert(!resp.sdRespCRCErr());
            printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
        }
    }
    
    
    
    
    
    // Issue SD CMD6
    {
        // TODO: we need to check that the 'Access Mode' was successfully changed
        //       by looking at the function group 1 of the DAT response
        printf("Sending SD CMD6\n");
        sendSDCmd(device, 6, 0x80FFFFF3);
        auto resp = getSDResp(device);
        assert(!resp.sdRespCRCErr());
        // Wait 1000us to allow the SD card to finish writing the 512-bit status on the DAT lines
        // 512 bits / 4 DAT lines = 128 bits per DAT line -> 128 bits * (1/350kHz) = 366us.
        usleep(1000);
        printf("-> Done (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
    }
    
    // Disable SD clock
    {
        printf("Disabling SD clock\n");
        device.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::None));
        printf("-> Done\n\n");
    }
    
    // Enable SD fast clock
    {
        printf("Enabling SD fast clock\n");
        device.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::Fast));
        printf("-> Done\n\n");
    }
    
    
    
    // Issue SD ACMD23
    {
        printf("Sending SD ACMD23\n");
        
        // CMD55
        {
            sendSDCmd(device, 55, ((uint32_t)rca)<<16);
            auto resp = getSDResp(device);
            assert(!resp.sdRespCRCErr());
        }
        
        // CMD23
        {
            sendSDCmd(device, 23, 0x00000001);
            auto resp = getSDResp(device);
            assert(!resp.sdRespCRCErr());
        }
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

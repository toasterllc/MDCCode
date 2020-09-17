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
    device.write(Msg{.type=0, .payload={1,2,3}});
    Resp resp = device.read();
    printf("Response: %d %d %d %d\n", resp.payload[0], resp.payload[1], resp.payload[2], resp.payload[3]);
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
        if (args.cmd == EchoCmd)            echo(args, *device);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

//
//// Left shift array of bytes of `n` bits
//#include <unistd.h>
//#include <stdint.h>
//#include <assert.h>
//#include <stdio.h>
//
//// Left shift array of bytes by `n` bits
//static void lshift(uint8_t* bytes, size_t len, uint8_t n) {
//    assert(n <= 8);
//    const uint8_t mask = ~((1<<(8-n))-1);
//    uint8_t l = 0;
//    for (size_t i=len; i; i--) {
//        uint8_t& b = bytes[i-1];
//        // Remember the high bits that we're losing by left-shifting,
//        // which will become the next byte's low bits.
//        const uint8_t h = b&mask;
//        b <<= n;
//        b |= l;
//        l = h>>(8-n);
//    }
//}
//
//int main(int argc, const char* argv[]) {
//    uint8_t b[] = {1,2,3};
//    lshift(b, sizeof(b), 8);
//    for (const auto& x : b) {
//        printf("%02x ", x);
//    }
//    printf("\n");
////    lshift
//    return 0;
//}

//
//#include <unistd.h>
//#include <stdint.h>
//#include <assert.h>
//#include <stdio.h>
//#include <strings.h>
//
//int main(int argc, const char* argv[]) {
//    printf("%d\n", 8-fls(~0xFF));
//    return 0;
//}

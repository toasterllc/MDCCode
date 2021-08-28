#include <vector>
#include <string>
#include <iostream>
#include <optional>
#include "Toastbox/USBDevice.h"
#include "ELF32Binary.h"
#include "STAppTypes.h"
#include "MDCDevice.h"

using namespace STApp;

int main(int argc, const char* argv[]) {
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
    
    try {
        MDCDevice& device = devices[0];
        auto& usbDevice = device.usbDevice();
        
        STApp::Cmd cmd = {
            .op = Op::SDRead,
        };
        usbDevice.write(STApp::Endpoints::CmdOut, cmd);
        
//        constexpr size_t BufCap = 512;
//        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
//        printf("Reading...\n");
//        usbDevice.read(STApp::Endpoints::DataIn, buf.get(), BufCap);
//        printf("Done\n");
//        const uint32_t* buf32 = (const uint32_t*)buf.get();
//        std::optional<uint32_t> last;
//        for (size_t i=0; i<BufCap/sizeof(uint32_t); i++) {
//            const uint32_t cur = buf32[i];
//            printf("%jx\n", (uintmax_t)(buf32[i]));
////            if (last) assert(cur == *last+1);
////            last = cur;
//        }
        
//        STApp::Status s = {};
//        usbDevice.read(STApp::Endpoints::DataIn, s);
//        if (s != STApp::Status::OK) abort();
        
        printf("Started\n");
        
        constexpr size_t BufCap = 128*1024*1024;
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
        for (;;) {
            TimeInstant start;
            usbDevice.read(STApp::Endpoints::DataIn, buf.get(), BufCap);
            
            for (int i=0; i<1000; i++) {
                printf("%x\n", buf[i]);
            }
            
            const uintmax_t bits = BufCap*8;
            const uintmax_t throughput_bitsPerSec = (1000*bits)/start.durationMs();
            const uintmax_t throughput_MbitsPerSec = throughput_bitsPerSec/UINTMAX_C(1000000);
            printf("Throughput: %ju Mbits/sec\n", throughput_MbitsPerSec);
        }
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    
    return 0;
}

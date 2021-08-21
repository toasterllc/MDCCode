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
        
//        STApp::Cmd cmd = {
//            .op = Op::SDRead,
//        };
//        usbDevice.write(STApp::Endpoints::CmdOut, cmd);
        
        constexpr size_t BufCap = 16*1024;
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
        printf("Reading...\n");
        usbDevice.read(STApp::Endpoints::DataIn, buf.get(), BufCap);
        printf("Done\n");
        
//        STApp::Status s = {};
//        usbDevice.read(STApp::Endpoints::DataIn, s);
//        if (s != STApp::Status::OK) abort();
        
//        printf("OK\n");
        
//        constexpr size_t BufCap = 128*1024*1024;
//        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
//        for (;;) {
//            TimeInstant start;
//            usbDevice.read(STApp::Endpoints::DataIn, buf.get(), BufCap);
//            
//            const uintmax_t bits = BufCap*8;
//            const uintmax_t throughput_bitsPerSec = (1000*bits)/start.durationMs();
//            const uintmax_t throughput_MbitsPerSec = throughput_bitsPerSec/UINTMAX_C(1000000);
//            printf("Throughput: %ju Mbits/sec\n", throughput_MbitsPerSec);
//        }
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    
    return 0;
}

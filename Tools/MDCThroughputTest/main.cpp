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
        
//        printf("Sending SDRead command...\n");
//        Cmd cmd = {
//            .op = Op::SDRead,
//        };
//        usbDevice.write(Endpoints::CmdOut, cmd);
//        printf("-> Done\n\n");
//        exit(0);
        
        printf("Resetting...\n");
        device.reset();
        printf("-> OK\n\n");
        
        printf("Sending SDRead command...\n");
        device.sdRead(0);
        printf("-> OK\n\n");
        
        printf("Profiling...\n");
        constexpr size_t BufCap = 128*1024*1024;
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
        for (;;) {
            auto startTime = std::chrono::steady_clock::now();
            usbDevice.read(Endpoints::DataIn, buf.get(), BufCap);
            
//            for (int i=0; i<1000; i++) {
//                printf("%x\n", buf[i]);
//            }
            
            const uintmax_t bits = BufCap*8;
            const uintmax_t durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now()-startTime).count();
            
            const uintmax_t throughput_bitsPerSec = (1000*bits)/durationMs;
            const uintmax_t throughput_MbitsPerSec = throughput_bitsPerSec/UINTMAX_C(1000000);
            
//            printf("Validating data...\n");
//            for (size_t i=1; i<BufCap; i++) {
//                if (buf[i] != (((buf[i-1])+1)&0xFF)) {
//                    printf("-> Invalid sequence: buf[%zu]=%d, buf[%zu]=%d\n", i-1, buf[i-1], i, buf[i]);
//                    break;
//                }
//            }
            
            printf("Throughput: %ju Mbits/sec\n\n", throughput_MbitsPerSec);
        }
        
        
        
//        // Profile command
//        printf("Profiling...\n");
//        for (;;) {
//            auto start = std::chrono::steady_clock::now();
//            const size_t IterCount = 1000;
//            for (size_t i=0; i<IterCount; i++) {
//                Cmd cmd = { .op = Op::SDRead, };
//                usbDevice.vendorRequestOut(CtrlReqs::CmdExec, cmd);
//                
//                // Read packet
//                uint8_t packet[512];
//                usbDevice.read(Endpoints::DataIn, packet);
//            }
//            
//            size_t durationUs = std::chrono::duration_cast<std::chrono::microseconds>(
//                std::chrono::steady_clock::now()-start).count();
//            
//            printf("Time per iteration: %ju us\n", durationUs/IterCount);
//        }
//        
////        printf("Reading response...\n");
////        uint8_t buf2[512];
////        usbDevice.read(0, buf2, sizeof(buf2));
//        
//        printf("HALLO\n");
//        exit(0);
//        
////        printf("Sending SDRead command...\n");
////        Cmd cmd = {
////            .op = Op::SDRead,
////        };
////        usbDevice.write(Endpoints::CmdOut, cmd);
////        printf("-> Done\n\n");
//        
////        constexpr size_t BufCap = 512;
////        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
////        printf("Reading...\n");
////        usbDevice.read(Endpoints::DataIn, buf.get(), BufCap);
////        printf("Done\n");
////        const uint32_t* buf32 = (const uint32_t*)buf.get();
////        std::optional<uint32_t> last;
////        for (size_t i=0; i<BufCap/sizeof(uint32_t); i++) {
////            const uint32_t cur = buf32[i];
////            printf("%jx\n", (uintmax_t)(buf32[i]));
//////            if (last) assert(cur == *last+1);
//////            last = cur;
////        }
//        
////        Status s = {};
////        usbDevice.read(Endpoints::DataIn, s);
////        if (s != Status::OK) abort();
//        
////        constexpr size_t BufCap = 128*1024*1024;
////        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(BufCap);
////        for (;;) {
////            printf("Reading data...\n");
////            
////            TimeInstant start;
////            usbDevice.read(Endpoints::DataIn, buf.get(), BufCap);
////            
////            for (int i=0; i<1000; i++) {
////                printf("%x\n", buf[i]);
////            }
////            
////            const uintmax_t bits = BufCap*8;
////            const uintmax_t throughput_bitsPerSec = (1000*bits)/start.durationMs();
////            const uintmax_t throughput_MbitsPerSec = throughput_bitsPerSec/UINTMAX_C(1000000);
////            
////            printf("Validating data...\n");
////            for (size_t i=1; i<BufCap; i++) {
////                if (buf[i] != (((buf[i-1])+1)&0xFF)) {
////                    printf("-> Invalid sequence: buf[%zu]=%d, buf[%zu]=%d\n", i-1, buf[i-1], i, buf[i]);
////                    break;
////                }
////            }
////            
////            printf("Throughput: %ju Mbits/sec\n\n", throughput_MbitsPerSec);
////        }
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    
    return 0;
}

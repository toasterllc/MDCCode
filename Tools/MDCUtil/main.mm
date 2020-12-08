#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <vector>
#import <string>
#import <iostream>
#import <optional>
#import <inttypes.h>
#import "ELF32Binary.h"
#import "SendRight.h"
#import "USBDevice.h"
#import "USBInterface.h"
#import "USBPipe.h"
#import "STAppTypes.h"
#import "MyTime.h"
#import "RuntimeError.h"
#import "MDCDevice.h"
#import "MDCUtil.h"

int main(int argc, const char* argv[]) {
    MDCUtil::Args args;
    try {
        std::vector<std::string> argStrs;
        for (int i=1; i<argc; i++) argStrs.push_back(argv[i]);
        args = MDCUtil::ParseArgs(argStrs);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
        MDCUtil::PrintUsage();
        return 1;
    }
    
    try {
        std::vector<MDCDevice> devices = MDCDevice::FindDevices();
        if (devices.empty()) throw RuntimeError("no matching MDC devices");
        if (devices.size() > 1) throw RuntimeError("Too many matching MDC devices");
        
        MDCUtil::Run(devices[0], args);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    
    return 0;
}

#import <Cocoa/Cocoa.h>
#import <filesystem>
#import "TmpDir.h"
#import "Code/Shared/TimeAdjustment.h"
#import "Code/Shared/TimeString.h"
#import <iostream>

int main(int argc, const char* argv[]) {
    // Make C++ APIs locale-aware
    std::locale::global(std::locale(""));
    
    MDCStudio::TmpDir::Cleanup();
    
//    auto now = Time::Clock::now();
//    auto lastWeek = now - std::chrono::hours(24*10);
//    MSP::TimeState x = {
//        .start = Time::Clock::TimeInstantFromTimePoint(lastWeek),
//        .time = Time::Clock::TimeInstantFromTimePoint(now + std::chrono::milliseconds(500)),
//    };
//    const MSP::TimeAdjustment adj = Time::TimeAdjustmentCalculate(x);
//    std::cout << Time::StringForTimeAdjustment(adj);
//    exit(0);
    
//    std::filesystem::remove_all("/Users/dave/Library/Containers/llc.toaster.photon-transfer/Data/Library/Application Support/llc.toaster.photon-transfer");
//    std::filesystem::remove_all("/Users/dave/Desktop/DemoImageSource");
    try {
        return NSApplicationMain(argc, argv);
    
    } catch (const std::exception& e) {
        printf("Unhandled exception: %s\n", e.what());
        return 1;
    }
}

#import <Cocoa/Cocoa.h>
#import <filesystem>
#import "TmpDir.h"

int main(int argc, const char* argv[]) {
    // Make C++ APIs locale-aware
    std::locale::global(std::locale(""));
    
    MDCStudio::TmpDir::Cleanup();
    
//    std::filesystem::remove_all("/Users/dave/Library/Containers/llc.toaster.photon-transfer/Data/Library/Application Support/llc.toaster.photon-transfer");
//    std::filesystem::remove_all("/Users/dave/Desktop/DemoImageSource");
    try {
        return NSApplicationMain(argc, argv);
    
    } catch (const std::exception& e) {
        printf("Unhandled exception: %s\n", e.what());
        return 1;
    }
}

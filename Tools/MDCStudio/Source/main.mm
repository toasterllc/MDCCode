#import <Cocoa/Cocoa.h>
#import <filesystem>
#import <string>
#import "Tools/MDCUtil/MDCUtil.h"
#import "TmpDir.h"

int main(int argc, const char* argv[]) {
    if (argc>=2 && std::string(argv[1])=="MDCUtil") {
        return MDCUtil(argc-1, argv+1);
    }
    
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

#import <Cocoa/Cocoa.h>
#import <filesystem>

int main(int argc, const char* argv[]) {
    // Make C++ APIs locale-aware
    std::locale::global(std::locale(""));
    
//    std::filesystem::remove_all("/Users/dave/Library/Application Support/llc.toaster.MDCStudio");
    return NSApplicationMain(argc, argv);
}

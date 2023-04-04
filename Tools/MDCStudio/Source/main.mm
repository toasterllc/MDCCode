#import <Cocoa/Cocoa.h>
#import <filesystem>

int main(int argc, const char* argv[]) {
//    std::filesystem::remove_all("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio");
    // Make C++ APIs locale-aware
    std::locale::global(std::locale(""));
    return NSApplicationMain(argc, argv);
}

#import <Cocoa/Cocoa.h>
#import <filesystem>

int main(int argc, const char* argv[]) {
    std::filesystem::remove_all("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio");
    return NSApplicationMain(argc, argv);
}

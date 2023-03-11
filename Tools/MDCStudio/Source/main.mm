#import <Cocoa/Cocoa.h>
#import <filesystem>

int main(int argc, const char* argv[]) {
    std::filesystem::remove_all("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio");
    std::filesystem::remove_all("/Users/dave/Desktop/ImageLibrary");
    return NSApplicationMain(argc, argv);
}

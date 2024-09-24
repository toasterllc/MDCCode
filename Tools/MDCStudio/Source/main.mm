#import <Cocoa/Cocoa.h>
#import <filesystem>
#import "TmpDir.h"
#import "MDCDevice.h"
#import "PrefsUtil.h"

int main(int argc, const char* argv[]) {
    using namespace MDCStudio;
    
    // Make C++ APIs locale-aware
    std::locale::global(std::locale(""));
    
    TmpDir::Cleanup();
    
    // Keep using "extra large" thumbnails if they were already being used by an
    // old version of MDCStudio.
    // Otherwise, use the default thumbnail size defined by PrefsUtil.
    if (!PrefsUtil::ImageLibraryDescriptorMigrated()) {
        PrefsUtil::ImageLibraryDescriptorMigrated(true);
        if (MDCDevice::DevicesExist()) {
            PrefsUtil::ImageLibraryDescriptor(ImageLibrary::Descriptors::ExtraLarge);
        }
    }
    
//    std::filesystem::remove_all("/Users/dave/Library/Containers/llc.toaster.photon-transfer/Data/Library/Application Support/llc.toaster.photon-transfer");
//    std::filesystem::remove_all("/Users/dave/Desktop/DemoImageSource");
    try {
        return NSApplicationMain(argc, argv);
    
    } catch (const std::exception& e) {
        printf("Unhandled exception: %s\n", e.what());
        return 1;
    }
}

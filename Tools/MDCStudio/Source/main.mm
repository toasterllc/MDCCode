#import <Cocoa/Cocoa.h>
#import <filesystem>
#import "TmpDir.h"
#import "MDCDevice.h"
#import "PrefsUtil.h"
#import "Code/Lib/Toastbox/Util.h"

int main(int argc, const char* argv[]) {
    using namespace MDCStudio;
    
    // Make C++ APIs locale-aware
    std::locale::global(std::locale(""));
    
    // Delete previous temporary directories
    TmpDir::Cleanup();
    
    // Bump up our open-file limit
    // This is necessary because we open/mmap a lot of files for our thumbnails.
    {
//        constexpr rlim_t MaxOpenFileCount = 128;
        constexpr rlim_t MaxOpenFileCount = 2048;
        const struct rlimit rlp = {
            .rlim_cur = MaxOpenFileCount,
            .rlim_max = RLIM_INFINITY,
        };
        int ir = setrlimit(RLIMIT_NOFILE, &rlp);
        if (ir) Toastbox::Bail("setrlimit failed: %s", strerror(errno));
    }
    
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

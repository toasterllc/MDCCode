#import <Cocoa/Cocoa.h>
#import <filesystem>
#import "TmpDir.h"
#import "Shared/MDCDeviceHard.h"
#import "Shared/PrefsUtil.h"
#import "Lib/Toastbox/Util.h"

static std::vector<uint8_t> _FileRead(const std::filesystem::path& path) {
    std::vector<uint8_t> data;
    Toastbox::Mmap mmap(path);
    data.resize(mmap.len());
    memcpy(data.data(), mmap.data(), mmap.len());
    return data;
}

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
    
    // Configure MDCDeviceHard
    std::vector<uint8_t> stmapp =
        _FileRead([[[NSBundle mainBundle] pathForResource:@"STMApp" ofType:@"elf"] UTF8String]);
    std::vector<uint8_t> iceapp =
        _FileRead([[[NSBundle mainBundle] pathForResource:@"ICEApp" ofType:@"bin"] UTF8String]);
    {
        MDCDeviceHard::Config(stmapp.data(), stmapp.size(), iceapp.data(), iceapp.size());
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

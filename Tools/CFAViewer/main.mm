#import <Cocoa/Cocoa.h>
#import "Shared/TmpDir.h"
#import "Shared/MDCDeviceHard.h"

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
    
    // Configure MDCDeviceHard
    std::vector<uint8_t> stmapp =
        _FileRead([[[NSBundle mainBundle] pathForResource:@"STMApp" ofType:@"elf"] UTF8String]);
    std::vector<uint8_t> iceapp =
        _FileRead([[[NSBundle mainBundle] pathForResource:@"ICEApp" ofType:@"bin"] UTF8String]);
    {
        MDCDeviceHard::Config(stmapp.data(), stmapp.size(), iceapp.data(), iceapp.size());
    }
    
    try {
        return NSApplicationMain(argc, argv);
    
    } catch (const std::exception& e) {
        printf("Unhandled exception: %s\n", e.what());
        return 1;
    }
}

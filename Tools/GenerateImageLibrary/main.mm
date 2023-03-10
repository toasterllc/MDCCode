#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "Renderer.h"
#import "Toastbox/Mmap.h"
#import "ImageLibrary.h"
#import "Tools/Shared/BC7Encoder.h"
#import "MockImageSource.h"
namespace fs = std::filesystem;
using namespace MDCStudio;
using namespace MDCTools;
using namespace Toastbox;

//const fs::path ImagesDirPath = "/Users/dave/Desktop/SourceImages";
const fs::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-5k";
//const fs::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-40k";

static bool _IsJPGFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".jpg";
}

//static uintptr_t _FloorToPageSize(uintptr_t x) {
//    const uintptr_t s = getpagesize();
//    return (x/s)*s;
//}
//
//static uintptr_t _CeilToPageSize(uintptr_t x) {
//    const uintptr_t s = getpagesize();
//    return ((x+s-1)/s)*s;
//}

//static void DebugShowThumb(size_t thumbIdx) {
//    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
//    id<MTLLibrary> lib = [dev newDefaultLibrary];
//    id<MTLCommandQueue> commandQueue = [dev newCommandQueue];
//    
//    ThumbFile thumbFile = ThumbFile(ThumbFilePath, MAP_PRIVATE);
//    
//    const size_t batchLen = 1;
//    const uintptr_t start = _FloorToPageSize(thumbIdx*ThumbLen);
//    const uintptr_t end = _CeilToPageSize((thumbIdx+batchLen)*ThumbLen);
//    
//    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//    id<MTLBuffer> thumbFileBuf = [dev newBufferWithBytesNoCopy:(void*)(thumbFile.data()+start) length:end-start options:BufOpts deallocator:nil];
//    assert(thumbFileBuf);
//    
//    Renderer renderer(dev, lib, commandQueue);
//    
//    const size_t off = (thumbIdx*ThumbLen) - start;
//    const RenderContext ctx = {
//        .thumbOff = (uint32_t)off,
//        .width = ThumbWidth,
//        .height = ThumbHeight,
//    };
//    
//    auto debugTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm, 256, 256);
//    renderer.render("ReadThumb", debugTxt,
//        // Buffer args
//        ctx,
//        thumbFileBuf
//    );
//    
//    renderer.debugShowTexture(debugTxt);
//}

int main(int argc, const char* argv[]) {
//    DebugShowThumb(40000-1);
//    return 0;
    
    std::vector<fs::path> paths;
    for (const fs::path& p : fs::directory_iterator(ImagesDirPath)) {
        if (_IsJPGFile(p)) {
            paths.push_back(p);
        }
    }
    
    ImageLibrary imgLib("/Users/dave/Desktop/ImageLibrary");
    try {
        imgLib.read();
    } catch (const std::exception& e) {
        printf("Recreating ImageLibrary, cause: %s\n", e.what());
    }
    
    imgLib.reserve(paths.size());
    imgLib.add();
    
    auto startTime = std::chrono::steady_clock::now();
    {
        std::vector<std::thread> workers;
        std::atomic<size_t> workIdx = 0;
        const uint32_t threadCount = std::max(1,(int)std::thread::hardware_concurrency());
        for (uint32_t i=0; i<threadCount; i++) {
            workers.emplace_back([&](){
                id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
                MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:dev];
                Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
                MockImageSource::ThumbCompressor compressor;
                std::unique_ptr<MockImageSource::TmpStorage> tmpStorage = std::make_unique<MockImageSource::TmpStorage>();
                
                for (;;) @autoreleasepool {
                    const size_t idx = workIdx.fetch_add(1);
                    if (idx >= paths.size()) break;
                    ImageRecord& rec = **(imgLib.begin()+idx);
                    const fs::path& path = paths.at(idx);
                    NSURL*const url = [NSURL fileURLWithPath:@(path.c_str())];
                    
                    MockImageSource::ThumbRender(renderer, txtLoader, compressor, *tmpStorage, url, rec);
                    
                    // Set ImageRecord.id
                    rec.info.id = idx;
                    rec.info.addr = IntForStr<uint64_t>(path.stem().c_str(), 10);
                }
            });
        }
        
        // Wait for workers to complete
        for (std::thread& t : workers) t.join();
    }
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Took %ju ms\n", (uintmax_t)durationMs);
    
//    // Remove 100 random images
//    for (int i=0; i<100; i++) {
//        imgStore.removeImage(rand() % imgStore.imageCount());
//    }
    
    imgLib.write();
    
    return 0;
}

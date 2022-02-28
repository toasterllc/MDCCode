#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "Renderer.h"
#import "Toastbox/Mmap.h"
#import "ImageLibrary.h"
namespace fs = std::filesystem;
using namespace MDCStudio;
using namespace MDCTools;
using namespace Toastbox;

const fs::path ImagesDirPath = "/Users/dave/Desktop/Old/2022:1:26/TestImages-5k";
//const fs::path ImagesDirPath = "/Users/dave/Desktop/Old/2022:1:26/TestImages-40k";

static bool _IsJPGFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".jpg";
}

static uintptr_t _FloorToPageSize(uintptr_t x) {
    const uintptr_t s = getpagesize();
    return (x/s)*s;
}

static uintptr_t _CeilToPageSize(uintptr_t x) {
    const uintptr_t s = getpagesize();
    return ((x+s-1)/s)*s;
}

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
    
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    id<MTLLibrary> lib = [dev newDefaultLibrary];
    id<MTLCommandQueue> commandQueue = [dev newCommandQueue];
    MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:dev];
    
    NSMutableArray* urls = [NSMutableArray new];
    for (const fs::path& p : fs::directory_iterator(ImagesDirPath)) {
        if (_IsJPGFile(p)) {
            [urls addObject:[NSURL fileURLWithPath:@(p.c_str())]];
        }
    }
    
    ImageLibrary imgLib("/Users/dave/Desktop/ImageLibrary");
    try {
        imgLib.read();
    } catch (const std::exception& e) {
        printf("Recreating ImageLibrary, cause: %s\n", e.what());
    }
    
    ImageId imageId = 0;
    auto startTime = std::chrono::steady_clock::now();
    {
        constexpr size_t MaxBatchLen = 512;
        for (size_t i=0; i<[urls count]; i+=MaxBatchLen) @autoreleasepool {
            Renderer renderer(dev, lib, commandQueue);
            
            const size_t batchLen = std::min((size_t)([urls count]-i), MaxBatchLen);
            NSArray* batchURLs = [urls subarrayWithRange:{i, batchLen}];
            
            printf("Loading %ju textures...\n", (uintmax_t)batchLen);
            NSArray<id<MTLTexture>>* txts = [txtLoader newTexturesWithContentsOfURLs:batchURLs options:nil error:nil];
            
            const size_t beginOff = imgLib.recordCount();
            imgLib.reserve([txts count]);
            imgLib.add();
            auto imageThumbIter = imgLib.begin()+beginOff;
            
            printf("Writing %ju thumbnails...\n", (uintmax_t)batchLen);
            for (id<MTLTexture> txt : txts) @autoreleasepool {
                ImageThumb* thumb = imgLib.recordGet(imageThumbIter);
                
                thumb->ref.id = imageId;
                imageId++;
                
                const uintptr_t start = _FloorToPageSize((uintptr_t)thumb);
                const uintptr_t end = _CeilToPageSize((uintptr_t)(thumb)+sizeof(ImageLibrary::Record));
                const size_t len = end-start;
                const size_t off = ((uintptr_t)thumb + offsetof(ImageLibrary::Record, thumb)) - start;
                
                constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
                id<MTLBuffer> thumbBuf = [dev newBufferWithBytesNoCopy:(void*)start length:len options:BufOpts deallocator:nil];
                assert(thumbBuf);
                
                renderer.render(ImageThumb::ThumbWidth, ImageThumb::ThumbHeight,
                    renderer.FragmentShader("RenderThumb",
                        // Buffer args
                        (uint32_t)off,
                        (uint32_t)ImageThumb::ThumbWidth,
                        thumbBuf,
                        // Texture args
                        txt
                    )
                );
                
                imageId++;
                imageThumbIter++;
            }
            
            renderer.commitAndWait();
        }
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

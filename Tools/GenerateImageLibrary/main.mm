#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "Renderer.h"
#import "Toastbox/Mmap.h"
#import "ImageLibrary.h"
#import "Tools/Shared/BC7Encoder.h"
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
    
    Img::Id imageId = 0;
    auto startTime = std::chrono::steady_clock::now();
    {
        constexpr size_t MaxBatchLen = 512;
        BC7Encoder<ImageThumb::ThumbWidth, ImageThumb::ThumbHeight> bc7;
        uint8_t tmp[ImageThumb::ThumbHeight][ImageThumb::ThumbWidth][4];
        
        for (size_t i=0; i<[urls count]; i+=MaxBatchLen) @autoreleasepool {
            id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
            MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:dev];
            id<MTLLibrary> lib = [dev newDefaultLibrary];
            Renderer renderer(dev, lib, [dev newCommandQueue]);
            
            const size_t batchLenCapped = std::min((size_t)([urls count]-i), MaxBatchLen);
            NSArray* batchURLs = [urls subarrayWithRange:{i, batchLenCapped}];
            printf("Loading %ju textures...\n", (uintmax_t)batchLenCapped);
            NSDictionary* opts = @{
                // Assume all images are sRGB. In some cases there may be a different profile attached,
                // but that should be the minority of cases compared to the cases where there's no profile
                MTKTextureLoaderOptionSRGB: @YES,
            };
            NSArray<id<MTLTexture>>* txtsSrc = [txtLoader newTexturesWithContentsOfURLs:batchURLs options:opts error:nil];
            const size_t txtCount = [txtsSrc count];
            
            std::vector<Renderer::Txt> txtsDst;
            txtsDst.reserve(txtCount);
            for (size_t i=0; i<txtCount; i++) {
                txtsDst.emplace_back(renderer.textureCreate(MTLPixelFormatRGBA8Unorm, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight));
            }
            
//            NSMutableArray* txts = [NSMutableArray new];
//            for (int i=0; i<MaxBatchLen; i++) {
//                [txts addObject:@0];
//            }
            
            const size_t beginOff = imgLib.recordCount();
            imgLib.reserve(txtCount);
            imgLib.add();
            
            auto batchStartTime = std::chrono::steady_clock::now();
            
            // Generate thumbnails in the necessary format (RGBA)
            {
//                printf("Generating RGBA thumbnails...\n", (uintmax_t)txtCount);
                
                auto startTime = std::chrono::steady_clock::now();
                for (size_t txtIdx=0; txtIdx<txtCount; txtIdx++) @autoreleasepool {
                    id<MTLTexture> txtSrc = txtsSrc[txtIdx];
                    Renderer::Txt& txtDst = txtsDst.at(txtIdx);
                    renderer.render(txtDst,
                        renderer.FragmentShader("SampleTexture",
                            // Buffer args
                            // Texture args
                            txtSrc
                        )
                    );
                    #warning TODO: figure out if we need this
                    renderer.sync(txtDst);
                }
                
                renderer.commitAndWait();
                
//                auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//                printf("-> took %ju ms\n", (uintmax_t)durationMs);
            }
            
            // Encode thumbnails with BC7
            {
                auto imgRecIt = imgLib.begin()+beginOff;
                for (size_t txtIdx=0; txtIdx<txtCount; txtIdx++) @autoreleasepool {
                    ImageRecord& rec = **imgRecIt;
                    NSURL* url = batchURLs[txtIdx];
                    NSString* filename = [[url URLByDeletingPathExtension] lastPathComponent];
                    
                    // Set ImageRecord.id
                    rec.info.id = imageId;
                    
                    // Load RGBA data into `tmp`
                    Renderer::Txt& txtDst = txtsDst.at(txtIdx);
                    [txtDst getBytes:tmp bytesPerRow:ImageThumb::ThumbWidth*4
                        fromRegion:MTLRegionMake2D(0, 0, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight) mipmapLevel:0];
                    
                    // Set ImageRecord.id
                    rec.info.id = imageId;
                    rec.info.addr = IntForStr<uint64_t>([filename UTF8String], 10);
                    
                    // Compress thumbnail data as BC7
                    bc7.encode(tmp, rec.thumb.data);
                    
                    imageId++;
                    imgRecIt++;
                    
//                    {
//                        NSString*const path = [NSString stringWithFormat:@"/Users/dave/Desktop/dds/debug-%zu.dds", txtIdx];
//                        static constexpr size_t pixel_format_bpp = 8;
//                        static constexpr DXGI_FORMAT fmt = DXGI_FORMAT_BC7_UNORM;
//                        static constexpr bool perceptual = true;
//                        bool br = utils::save_dds([path UTF8String], ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, rec.thumb.data,
//                            pixel_format_bpp, fmt, perceptual, false);
//                        assert(br);
//                    }
                }
            }
            
            auto batchDurationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-batchStartTime).count();
            printf("-> Batch took %ju ms\n", (uintmax_t)batchDurationMs);
            
//            break;
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

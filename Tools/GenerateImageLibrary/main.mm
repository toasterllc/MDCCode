#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "Renderer.h"
#import "Toastbox/Mmap.h"
#import "ImageLibrary.h"
#import "bc7e_ispc.h"
#import "rdo_bc_encoder.h"
namespace fs = std::filesystem;
using namespace MDCStudio;
using namespace MDCTools;
using namespace Toastbox;

//const fs::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-5k";
const fs::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-40k";

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
        for (size_t i=0; i<[urls count]; i+=MaxBatchLen) @autoreleasepool {
            id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
            MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:dev];
            id<MTLLibrary> lib = [dev newDefaultLibrary];
            Renderer renderer(dev, lib, [dev newCommandQueue]);
            
            const size_t batchLenCapped = std::min((size_t)([urls count]-i), MaxBatchLen);
            NSArray* batchURLs = [urls subarrayWithRange:{i, batchLenCapped}];
            printf("Loading %ju textures...\n", (uintmax_t)batchLenCapped);
            NSArray<id<MTLTexture>>* txtsSrc = [txtLoader newTexturesWithContentsOfURLs:batchURLs options:nil error:nil];
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
                constexpr size_t BytesPerRow = ImageThumb::ThumbWidth*4;
                constexpr size_t BytesPerImage = ImageThumb::ThumbWidth*ImageThumb::ThumbHeight*4;
                utils::image_u8 srcImg;
                
                struct bc7_block
                {
                    uint64_t m_vals[2];
                };
                using bc7_block_vec = std::vector<bc7_block>;
                
                // Initialize the BC7 compressor (only need to call once). 
                // If you don't call this function (say by accident), the compressor will always return all-0 blocks.
                ispc::bc7e_compress_block_init();

                // Now initialize the BC7 compressor's parameters.
                ispc::bc7e_compress_block_params pack_params;
                memset(&pack_params, 0, sizeof(pack_params));
                int uber_level = 0;
                bool perceptual = true;
                switch (uber_level)
                {
                case 0:
                    ispc::bc7e_compress_block_params_init_ultrafast(&pack_params, perceptual);
                    break;
                case 1:
                    ispc::bc7e_compress_block_params_init_veryfast(&pack_params, perceptual);
                    break;
                case 2:
                    ispc::bc7e_compress_block_params_init_fast(&pack_params, perceptual);
                    break;
                case 3:
                    ispc::bc7e_compress_block_params_init_basic(&pack_params, perceptual);
                    break;
                case 4:
                    ispc::bc7e_compress_block_params_init_slow(&pack_params, perceptual);
                    break;
                case 5:
                    ispc::bc7e_compress_block_params_init_veryslow(&pack_params, perceptual);
                    break;
                case 6:
                default:
                    ispc::bc7e_compress_block_params_init_slowest(&pack_params, perceptual);
                    break;
                }
                
                srcImg.init(ImageThumb::ThumbWidth, ImageThumb::ThumbHeight);
                
                const uint32_t blocks_x = srcImg.width() / 4;
                const uint32_t blocks_y = srcImg.height() / 4;
                bc7_block_vec blocks(blocks_x * blocks_y);
                
                auto imgRecIt = imgLib.begin()+beginOff;
                for (size_t txtIdx=0; txtIdx<txtCount; txtIdx++) @autoreleasepool {
                    Renderer::Txt& txtDst = txtsDst.at(txtIdx);
                    
                    [txtDst getBytes:srcImg.get_pixels().data() bytesPerRow:BytesPerRow
                        fromRegion:MTLRegionMake2D(0, 0, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight) mipmapLevel:0];
                    
                    for (int32_t by = 0; by < static_cast<int32_t>(blocks_y); by++)
                    {
                        // Process 64 blocks at a time, for efficient SIMD processing.
                        // Ideally, N >= 8 (or more) and (N % 8) == 0.
                        const int N = 64;
                        
                        for (uint32_t bx = 0; bx < blocks_x; bx += N)
                        {
                            const uint32_t num_blocks_to_process = std::min<uint32_t>(blocks_x - bx, N);

                            utils::color_quad_u8 pixels[16 * N];

                            // Extract num_blocks_to_process 4x4 pixel blocks from the source image and put them into the pixels[] array.
                            for (uint32_t b = 0; b < num_blocks_to_process; b++)
                                srcImg.get_block(bx + b, by, 4, 4, pixels + b * 16);
                            
                            // Compress the blocks to BC7.
                            // Note: If you've used Intel's ispc_texcomp, the input pixels are different. BC7E requires a pointer to an array of 16 pixels for each block.
                            bc7_block *pBlock = &blocks[bx + by * blocks_x];
                            ispc::bc7e_compress_blocks(num_blocks_to_process, reinterpret_cast<uint64_t *>(pBlock), reinterpret_cast<const uint32_t *>(pixels), &pack_params);
                        }
                    }
                    
                    ImageRecord& rec = **imgRecIt;
                    rec.info.id = imageId;
                    
                    const size_t blocksSize = blocks.size() * sizeof(*blocks.data());
                    memcpy(rec.thumb.data, blocks.data(), blocksSize);
                    
                    imageId++;
                    imgRecIt++;
                    
//                    {
//                        NSString*const path = [NSString stringWithFormat:@"/Users/dave/Desktop/dds/debug-%zu.dds", txtIdx];
//                        static constexpr size_t pixel_format_bpp = 8;
//                        static constexpr DXGI_FORMAT fmt = DXGI_FORMAT_BC7_UNORM;
//                        bool br = utils::save_dds([path UTF8String], srcImg.width(), srcImg.height(), &packed_image[0],
//                            pixel_format_bpp, fmt, perceptual, false);
//                        assert(br);
//                    }
                }
            }
            
            auto batchDurationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-batchStartTime).count();
            printf("-> Batch took %ju ms\n", (uintmax_t)batchDurationMs);
            
            break;
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

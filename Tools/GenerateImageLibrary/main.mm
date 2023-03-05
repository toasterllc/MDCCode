#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "Renderer.h"
#import "Toastbox/Mmap.h"
#import "ImageLibrary.h"
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
            auto it = imgLib.begin()+beginOff;
            
            printf("Writing %ju thumbnails...\n", (uintmax_t)txtCount);
            
            // Generate thumbnails in the necessary format (RGBA)
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
            
            // Encode thumbnails with BC7
            constexpr size_t BytesPerRow = ImageThumb::ThumbWidth*4;
            constexpr size_t BytesPerImage = ImageThumb::ThumbWidth*ImageThumb::ThumbHeight*4;
            utils::image_u8 srcImg;
            srcImg.init(ImageThumb::ThumbWidth, ImageThumb::ThumbHeight);
            
            rdo_bc::rdo_bc_params rp;
            rp.m_bc7_uber_level = 0;
            rp.m_bc7enc_max_partitions_to_scan = 64;
            rp.m_perceptual = false;
            rp.m_y_flip = false;
            rp.m_bc45_channel0 = 0;
            rp.m_bc45_channel1 = 1;
            rp.m_bc1_mode = rgbcx::bc1_approx_mode::cBC1Ideal;
            rp.m_use_bc1_3color_mode = true;
            rp.m_use_bc1_3color_mode_for_black = true;
            rp.m_bc1_quality_level = 18;
            rp.m_dxgi_format = DXGI_FORMAT_BC7_UNORM;
            rp.m_rdo_lambda = 0;
            rp.m_rdo_debug_output = false;
            rp.m_rdo_smooth_block_error_scale = 15;
            rp.m_custom_rdo_smooth_block_error_scale = false;
            rp.m_lookback_window_size = 128;
            rp.m_custom_lookback_window_size = false;
            rp.m_bc7enc_rdo_bc7_quant_mode6_endpoints = true;
            rp.m_bc7enc_rdo_bc7_weight_modes = true;
            rp.m_bc7enc_rdo_bc7_weight_low_frequency_partitions = true;
            rp.m_bc7enc_rdo_bc7_pbit1_weighting = true;
            rp.m_rdo_max_smooth_block_std_dev = 18;
            rp.m_rdo_allow_relative_movement = false;
            rp.m_rdo_try_2_matches = true;
            rp.m_rdo_ultrasmooth_block_handling = true;
            rp.m_use_hq_bc345 = true;
            rp.m_bc345_search_rad = 5;
            rp.m_bc345_mode_mask = 3;
            rp.m_bc7enc_mode6_only = false;
            rp.m_rdo_multithreading = true;
            rp.m_bc7enc_reduce_entropy = false;
            rp.m_use_bc7e = true;
            rp.m_status_output = false;
            rp.m_rdo_max_threads = 1;
            
            rdo_bc::rdo_bc_encoder encoder;
//            bool br = encoder.init(srcImg, rp);
//            assert(br);
            
            bool initDone = false;
            
            for (size_t txtIdx=0; txtIdx<txtCount; txtIdx++) @autoreleasepool {
                Renderer::Txt& txtDst = txtsDst.at(txtIdx);
                
//                renderer.debugShowTexture(txtDst);
//                
//                renderer.sync(txtDst);
//                auto startTime = std::chrono::steady_clock::now();
                [txtDst getBytes:srcImg.get_pixels().data() bytesPerRow:BytesPerRow
                    fromRegion:MTLRegionMake2D(0, 0, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight) mipmapLevel:0];
                
                if (!initDone) {
                    bool br = encoder.init(srcImg, rp);
                    assert(br);
                    initDone = true;
                } else {
                    encoder.clear();
                }
                
                encoder.init_source_image();
                
//                auto startTime = std::chrono::steady_clock::now();
                bool br = encoder.encode();
                assert(br);
                
                NSString*const path = [NSString stringWithFormat:@"/Users/dave/Desktop/dds/debug-%zu.dds", txtIdx];
                static constexpr size_t pixel_format_bpp = 8;
                br = utils::save_dds([path UTF8String], encoder.get_orig_width(), encoder.get_orig_height(), encoder.get_blocks(),
                    pixel_format_bpp, rp.m_dxgi_format, rp.m_perceptual, false);
                assert(br);
                
                
//                auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//                printf("Encode took %ju ms\n", (uintmax_t)durationMs);
                
                
//                auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//                printf("Iter took %ju ms\n", (uintmax_t)durationMs);
                
                
//                
//                id<MTLTexture> txtSrc = txtsSrc[txtIdx];
//                Renderer::Txt& txtDst = txtsDst.at(txtIdx);
//                renderer.render(txtDst,
//                    renderer.FragmentShader("SampleTexture",
//                        // Buffer args
//                        // Texture args
//                        txtSrc
//                    )
//                );
            }
            
            exit(0);
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

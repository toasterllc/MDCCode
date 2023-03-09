#import "ImageLibrary.h"
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/BC7Encoder.h"

class MockImageSource : public MDCStudio::ImageSource {
public:
    MockImageSource(const std::filesystem::path& path) : _path(path) {
        _il = std::make_shared<MDCTools::Lockable<MDCStudio::ImageLibrary>>(_path / "ImageLibrary");
        _ic = std::make_shared<MDCStudio::ImageCache>(_il, [] (uint64_t addr) { return nullptr; });
    }
    
    MockImageSource(MDCStudio::ImageLibraryPtr il, MDCStudio::ImageCachePtr ic) : _il(il), _ic(ic) {
        _renderThumbs.thread = std::thread([&] { _threadRenderThumbs(); });
    }
    
    ~MockImageSource() {
        // Signal thread and wait for it to exit
        {
            auto lock = std::unique_lock(_renderThumbs.lock);
            _renderThumbs.stop = true;
        }
        _renderThumbs.signal.notify_one();
        _renderThumbs.thread.join();
    }
    
    MDCStudio::ImageLibraryPtr imageLibrary() override {
        return _il;
    }
    
    MDCStudio::ImageCachePtr imageCache() override {
        return _ic;
    }
    
    void renderThumbs(MDCStudio::ImageRecordIter begin, MDCStudio::ImageRecordIter end) override {
        bool enqueued = false;
        {
            auto lock = std::unique_lock(_renderThumbs.lock);
            for (auto it=begin; it!=end; it++) {
                MDCStudio::ImageRecordPtr ref = *it;
                if (ref->options.thumb.render) {
                    _renderThumbs.recs.insert(ref);
                    enqueued = true;
                }
            }
        }
        if (enqueued) _renderThumbs.signal.notify_one();
    }
    
    static MDCTools::Renderer::Txt _ThumbRender(MDCTools::Renderer& renderer, id<MTLTexture> src, MTLPixelFormat dstFormat) {
        using namespace MDCStudio;
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        
        // Calculate transform to fit source image in thumbnail aspect ratio
        MPSScaleTransform transform;
        {
            const float srcAspect = (float)[src width] / [src height];
            const float dstAspect = (float)ImageThumb::ThumbWidth / ImageThumb::ThumbHeight;
            const float scale = (srcAspect<dstAspect ? ((float)ImageThumb::ThumbWidth / [src width]) : ((float)ImageThumb::ThumbHeight / [src height]));
            transform = {
                .scaleX = scale,
                .scaleY = scale,
                .translateX = 0,
                .translateY = 0,
            };
        }
        
        // Scale image
        constexpr MTLTextureUsage DstUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        Renderer::Txt dst = renderer.textureCreate(dstFormat, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, DstUsage);
        {
            MPSImageLanczosScale* filter = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
            [filter setScaleTransform:&transform];
            [filter encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:src destinationTexture:dst];
        }
        return dst;
    }
    
//    static MDCTools::Renderer::Txt _ThumbRender2(MDCTools::Renderer& renderer, NSURL* srcUrl, MTLPixelFormat dstFormat) {
//        using namespace MDCStudio;
//        using namespace MDCTools;
//        using namespace MDCTools::ImagePipeline;
//        
//        // Calculate transform to fit source image in thumbnail aspect ratio
//        MPSScaleTransform transform;
//        {
//            const float srcAspect = (float)[src width] / [src height];
//            const float dstAspect = (float)ImageThumb::ThumbWidth / ImageThumb::ThumbHeight;
//            const float scale = (srcAspect<dstAspect ? ((float)ImageThumb::ThumbWidth / [src width]) : ((float)ImageThumb::ThumbHeight / [src height]));
//            transform = {
//                .scaleX = scale,
//                .scaleY = scale,
//                .translateX = 0,
//                .translateY = 0,
//            };
//        }
//        
//        // Scale image
//        constexpr MTLTextureUsage DstUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
//        Renderer::Txt dst = renderer.textureCreate(dstFormat, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, DstUsage);
//        {
//            MPSImageLanczosScale* filter = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
//            [filter setScaleTransform:&transform];
//            [filter encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:src destinationTexture:dst];
//        }
//        return dst;
//    }
    
    
    
    
    void _threadRenderThumbs() {
        using namespace MDCStudio;
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:dev];
        Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
        BC7Encoder<ImageThumb::ThumbWidth, ImageThumb::ThumbHeight> compressor;
        auto thumbData = std::make_unique<uint8_t[]>(ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4);
        
        for (;;) @autoreleasepool {
            MDCStudio::ImageRecordPtr rec;
            {
                auto lock = std::unique_lock(_renderThumbs.lock);
                // Wait for data, or to be signalled to stop
                _renderThumbs.signal.wait(lock, [&] { return !_renderThumbs.recs.empty() || _renderThumbs.stop; });
                if (_renderThumbs.stop) return;
                const auto it = _renderThumbs.recs.begin();
                rec = *it;
                _renderThumbs.recs.erase(it);
            }
            
//            // Re-render thumbnail
//            
//            const Pipeline::Options pipelineOpts = {
////                    .illum = illum,
////                    .colorMatrix = colorMatrix,
////                    .reconstructHighlights  = { .en = true, },
//                .debayerLMMSE           = { .applyGamma = true, },
//            };
//            
//            constexpr MTLTextureUsage ThumbTxtUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
//            Renderer::Txt thumbTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm,
//                ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, ThumbTxtUsage);
//            
//            Pipeline::Result renderResult = Pipeline::Run(renderer, pipelineOpts, rawImage, thumbTxt);
//            renderer.sync(thumbTxt);
//            
//            
//            _ThumbCompressor compressor;
//            auto thumbData = std::make_unique<uint8_t[]>(ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4);
//            
//            for (;;) {
//                const size_t idx = workIdx.fetch_add(1);
//                if (idx >= imgCount) break;
//                
//                const auto recordRefIter = _imageLibrary->reservedBegin()+idx;
//                id<MTLTexture> thumbTxt = thumbTxts[idx];
//                ImageRecord& rec = **recordRefIter;
//                
//                [thumbTxt getBytes:thumbData.get() bytesPerRow:ImageThumb::ThumbWidth*4
//                    fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
//                
//                compressor.encode(thumbData.get(), rec.thumb.data);
//            }
            
            
            
            
            
//            // Render the thumbnail into rec.thumb
//            {
//                Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
//                    Img::Thumb::PixelWidth, Img::Thumb::PixelHeight, (ImagePixel*)(imgData+Img::PixelsOffset));
//                
//                Renderer::Txt rgbTxt = renderer.textureCreate(rawTxt, MTLPixelFormatRGBA32Float);
//                
//                const Pipeline::DebayerOptions debayerOpts = {
//                    .cfaDesc        = _CFADesc,
//                    .debayerLMMSE   = { .applyGamma = true, },
//                };
//                
//                const Pipeline::DebayerResult debayerResult = Pipeline::Debayer(renderer, debayerOpts, rawTxt, rgbTxt);
//                
//                constexpr MTLTextureUsage ThumbTxtUsage = MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
//                Renderer::Txt& thumbTxt = txts.emplace_back(renderer.textureCreate(MTLPixelFormatRGBA8Unorm,
//                    ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, ThumbTxtUsage));
//                thumbTxts[idx] = thumbTxt;
//                
//                const Pipeline::ProcessOptions processOpts = {
//                    .illum = debayerResult.illum,
//                };
//                
//                Pipeline::Process(renderer, processOpts, rgbTxt, thumbTxt);
//                renderer.sync(thumbTxt);
//                
//                // Populate the illuminant (ImageRecord.info.illumEst)
//                rec.info.illumEst[0] = debayerResult.illum[0];
//                rec.info.illumEst[1] = debayerResult.illum[1];
//                rec.info.illumEst[2] = debayerResult.illum[2];
//            }
//            
//            
//            
//            
//            
//            
//            
//            - (nullable id <MTLTexture>)newTextureWithContentsOfURL:(nonnull NSURL *)URL
//            options:(nullable NSDictionary <MTKTextureLoaderOption, id> *)options
//            error:(NSError *__nullable *__nullable)error;
            
            
            
            
//            const std::filesystem::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-5k";
//            ImagesDirPath / / ".jpg"
            
            // Load thumbnail, store in txtRgba32
            Renderer::Txt txtRgba32;
            {
                // Load thumbnail from disk
                id<MTLTexture> txtOrig = nil;
                {
                    const std::filesystem::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-5k";
//                    const std::filesystem::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-40k";
                    NSString*const path = [NSString stringWithFormat:@"%s/%012ju.jpg", ImagesDirPath.c_str(), (uintmax_t)rec->info.addr];
                    NSDictionary*const loadOpts = @{
                        MTKTextureLoaderOptionSRGB: @YES,
                    };
                    txtOrig = [txtLoader newTextureWithContentsOfURL:[NSURL fileURLWithPath:path] options:loadOpts error:nil];
                }
                
                txtRgba32 = _ThumbRender(renderer, txtOrig, MTLPixelFormatRGBA32Float);
            }
            
            // Process image, store in txtRgba8
            const Renderer::Txt txtRgba8 = renderer.textureCreate(txtRgba32, MTLPixelFormatRGBA8Unorm);
            {
                const ImageOptions& imageOpts = rec->options;
                // colorMatrix: converts colorspace from LSRGB.D65 -> ProPhotoRGB.D50, which the pipeline expects
                const Pipeline::ColorMatrix colorMatrix = {
                   0.5293458, 0.3300728, 0.1405813,
                   0.0983744, 0.8734610, 0.0281647,
                   0.0168832, 0.1176725, 0.8654443,
                };
                const Pipeline::ProcessOptions processOpts = {
                    .colorMatrix = colorMatrix,
                    .exposure = imageOpts.exposure,
                    .saturation = imageOpts.saturation,
                    .brightness = imageOpts.brightness,
                    .contrast = imageOpts.contrast,
                    .localContrast = {
                        .en = (imageOpts.localContrast.amount!=0 && imageOpts.localContrast.radius!=0),
                        .amount = imageOpts.localContrast.amount,
                        .radius = imageOpts.localContrast.radius,
                    },
                };
                
                Pipeline::Process(renderer, processOpts, txtRgba32, txtRgba8);
                renderer.sync(txtRgba8);
            }
            
            // Compress thumbnail, store in rec->thumb.data
            {
                renderer.commitAndWait();
                
                [txtRgba8 getBytes:thumbData.get() bytesPerRow:ImageThumb::ThumbWidth*4
                    fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
                
                compressor.encode(thumbData.get(), rec->thumb.data);
                
                rec->options.thumb.render = false;
                printf("Rendered %ju\n", (uintmax_t)rec->info.id);
            }
            
            // Notify image library that the image changed
            {
                auto lock = std::unique_lock(*_il);
                _il->notifyChange({ rec });
            }
            
//                    auto lock = std::unique_lock(*_imgLib);
//                    std::set<ImageRecordPtr> records;
//                    for (const ImageRecordPtr& x : _selection) records.insert(x);
//                    _imgLib->notifyChange(std::move(records));
            
            
        }
    }

private:
    static std::filesystem::path _ThumbDirPath(const std::filesystem::path& path) {
        return path / "Thumb";
    }
    
    std::filesystem::path _path;
    MDCStudio::ImageLibraryPtr _il;
    MDCStudio::ImageCachePtr _ic;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        std::thread thread;
        std::set<MDCStudio::ImageRecordPtr> recs;
        bool stop = false;
    } _renderThumbs;
};

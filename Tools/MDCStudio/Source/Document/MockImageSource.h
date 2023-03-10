#import "ImageLibrary.h"
#import <filesystem>
#import <array>
#import <MetalKit/MetalKit.h>
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/BC7Encoder.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "ImageSource.h"

namespace MDCStudio {

class MockImageSource : public ImageSource {
public:
    using ThumbCompressor = BC7Encoder<ImageThumb::ThumbWidth, ImageThumb::ThumbHeight>;
    
    MockImageSource(const std::filesystem::path& path) :
    _path(path),
    _imageLibrary(_path),
    _imageCache(_imageLibrary, _ImageProvider()) {
        _imageLibrary.read();
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
    
    ImageLibrary& imageLibrary() override {
        return _imageLibrary;
    }
    
    ImageCache& imageCache() override {
        return _imageCache;
    }
    
    void renderThumbs(ImageRecordIter begin, ImageRecordIter end) override {
        bool enqueued = false;
        {
            auto lock = std::unique_lock(_renderThumbs.lock);
            for (auto it=begin; it!=end; it++) {
                ImageRecordPtr ref = *it;
                if (ref->options.thumb.render) {
                    _renderThumbs.recs.insert(ref);
                    enqueued = true;
                }
            }
        }
        if (enqueued) _renderThumbs.signal.notify_one();
    }
    
    static constexpr size_t TmpStorageLen = ImageThumb::ThumbWidth * ImageThumb::ThumbWidth * 4;
    using TmpStorage = std::array<uint8_t, TmpStorageLen>;
    
    static void ThumbRender(MDCTools::Renderer& renderer, MTKTextureLoader* txtLoader,
        ThumbCompressor& compressor, TmpStorage& tmpStorage, NSURL* url, ImageRecord& rec) {
        
        using namespace MDCStudio;
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        
        // Load thumbnail from `url`, store in txtRgba32
        Renderer::Txt txtRgba32;
        {
            NSDictionary*const loadOpts = @{
                MTKTextureLoaderOptionSRGB: @YES,
            };
            id<MTLTexture> src = [txtLoader newTextureWithContentsOfURL:url options:loadOpts error:nil];
            
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
            txtRgba32 = renderer.textureCreate(MTLPixelFormatRGBA32Float, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight, DstUsage);
            {
                MPSImageLanczosScale* filter = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
                [filter setScaleTransform:&transform];
                [filter encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:src destinationTexture:txtRgba32];
            }
        }
        
        // Process image, store in txtRgba8
        const Renderer::Txt txtRgba8 = renderer.textureCreate(txtRgba32, MTLPixelFormatRGBA8Unorm);
        {
            const ImageOptions& imageOpts = rec.options;
            // colorMatrix: converts colorspace from LSRGB.D65 -> ProPhotoRGB.D50, which Pipeline::Process expects
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
        
        // Compress thumbnail, store in rec.thumb.data
        {
            renderer.commitAndWait();
            
            [txtRgba8 getBytes:tmpStorage.data() bytesPerRow:ImageThumb::ThumbWidth*4
                fromRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0];
            
            compressor.encode(tmpStorage.data(), rec.thumb.data);
        }
    }
    
    
    static ImageCache::ImageProvider _ImageProvider() {
        return [=] (uint64_t addr) -> ImagePtr {
            return nullptr;
        };
    }
    
    void _threadRenderThumbs() {
        using namespace MDCStudio;
        using namespace MDCTools;
        using namespace MDCTools::ImagePipeline;
        
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        MTKTextureLoader* txtLoader = [[MTKTextureLoader alloc] initWithDevice:dev];
        Renderer renderer(dev, [dev newDefaultLibrary], [dev newCommandQueue]);
        ThumbCompressor compressor;
        std::unique_ptr<TmpStorage> tmpStorage = std::make_unique<TmpStorage>();
        auto thumbData = std::make_unique<uint8_t[]>(ImageThumb::ThumbWidth * ImageThumb::ThumbHeight * 4);
        
        for (;;) @autoreleasepool {
            ImageRecordPtr rec;
            {
                auto lock = std::unique_lock(_renderThumbs.lock);
                // Wait for data, or to be signalled to stop
                _renderThumbs.signal.wait(lock, [&] { return !_renderThumbs.recs.empty() || _renderThumbs.stop; });
                if (_renderThumbs.stop) return;
                const auto it = _renderThumbs.recs.begin();
                rec = *it;
                _renderThumbs.recs.erase(it);
            }
            
            // Render thumb to `rec.thumb`
            {
                const std::filesystem::path ImagesDirPath = "/Users/dave/Desktop/Old/2022-1-26/TestImages-5k";
                NSURL* url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s/%012ju.jpg", ImagesDirPath.c_str(), (uintmax_t)rec->info.addr]];
                ThumbRender(renderer, txtLoader, compressor, *tmpStorage, url, *rec);
                rec->options.thumb.render = false;
            }
            
            // Notify image library that the image changed
            {
                auto lock = std::unique_lock(_imageLibrary);
                _imageLibrary.notifyChange({ rec });
            }
        }
    }

private:
    static std::filesystem::path _ThumbDirPath(const std::filesystem::path& path) {
        return path / "Thumb";
    }
    
    std::filesystem::path _path;
    ImageLibrary _imageLibrary;
    ImageCache _imageCache;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        std::thread thread;
        std::set<ImageRecordPtr> recs;
        bool stop = false;
    } _renderThumbs;
};

} // namespace MDCStudio

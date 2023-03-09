#import "ImageLibrary.h"
#import <filesystem>

class FakeImageSource : public MDCStudio::ImageSource {
public:
    FakeImageSource(const std::filesystem::path& path) : _path(path) {
        _il = std::make_shared<MDCTools::Lockable<MDCStudio::ImageLibrary>>(_path / "ImageLibrary");
        _ic = std::make_shared<MDCStudio::ImageCache>(_il, [] (uint64_t addr) { return nullptr; });
    }
    
    FakeImageSource(MDCStudio::ImageLibraryPtr il, MDCStudio::ImageCachePtr ic) : _il(il), _ic(ic) {
        _renderThumbs.thread = std::thread([&] { _threadRenderThumbs(); });
    }
    
    ~FakeImageSource() {
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
    
    void _threadRenderThumbs() {
        for (;;) {
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
            
            
            
            
            
            
            
            
            
            
            
            
            rec->options.thumb.render = false;
            printf("Rendered %ju\n", (uintmax_t)rec->info.id);
            
            if (rec->options.thumb.originalOnDisk) {
                
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

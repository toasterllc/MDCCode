#import "Document.h"
#import "MainView.h"
#import "SourceListView/SourceListView.h"
#import "ImageGridView/ImageGridView.h"
#import "ImageView/ImageView.h"
#import "FixedScrollView.h"
using namespace MDCStudio;

@interface Document () <SourceListViewDelegate, ImageGridViewDelegate, ImageViewDelegate>
@end

@implementation Document {
    IBOutlet MainView* _mainView;
    SourceListView* _sourceListView;
}

+ (BOOL)autosavesInPlace {
    return false;
}

- (void)awakeFromNib {
//    printf("sizeof(MSP::State): %zu\n", sizeof(MSP::State));
    _sourceListView = [_mainView sourceListView];
    [_sourceListView setDelegate:self];
    
    // Handle whatever is first selected
    [self sourceListViewSelectionChanged:_sourceListView];
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if ([item action] == @selector(saveDocument:)) {
        return false;
    }
    return true;
}

- (NSString*)windowNibName {
    return @"Document";
}

- (NSString*)displayName {
    return @"MDCStudio";
}




//static void _addImages(ImageLibraryPtr imgLib, MDCTools::Renderer& renderer, const uint8_t* data, size_t imgCount, SD::Block block) {
//    using namespace MDCTools;
//    using namespace MDCTools::ImagePipeline;
//    
//    ImageId imageId = 0;
//    {
//        auto lock = std::unique_lock(*imgLib);
//        
//        // Reserve space for `imgCount` additional images
//        imgLib->reserve(imgCount);
//        
//        // Load `imageId` by looking at the last record's image id +1, and reserve space
//        if (imgLib->recordCount()) {
//            imageId = imgLib->recordGet(imgLib->back())->ref.id+1;
//        }
//    }
//    
//    Img::Id deviceImgIdLast = 0;
//    for (size_t idx=0; idx<imgCount; idx++) {
//        const uint8_t* imgData = data+idx*ImgSD::ImagePaddedLen;
//        const Img::Header& imgHeader = *(const Img::Header*)imgData;
//        // Accessing `imgLib` without a lock because we're the only entity using the image library's reserved space
//        const auto recordRefIter = imgLib->reservedBegin()+idx;
//        ImageThumb& imageThumb = *imgLib->recordGet(recordRefIter);
//        ImageRef& imageRef = imageThumb.ref; // Safe without a lock because we're the only entity using the image library's reserved space
//        
//        // Validate checksum
//        const uint32_t checksumExpected = ChecksumFletcher32(imgData, Img::ChecksumOffset);
//        uint32_t checksumGot = 0;
//        memcpy(&checksumGot, imgData+Img::ChecksumOffset, Img::ChecksumLen);
//        if (checksumGot != checksumExpected) {
//            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
//        } else {
//            printf("Checksum OK\n");
//        }
//        
//        // Populate ImageRef fields
//        {
//            imageRef.id = imageId;
//            
//            // If the image has an absolute time, use it
//            // If the image has a relative time (ie time since device boot), drop it
//            if (imgHeader.timestamp & MSP::TimeAbsoluteBase) {
//                imageRef.timestamp = MSP::UnixTimeFromTime(imgHeader.timestamp);
//            }
//            
//            imageRef.addr           = block;
//            
//            imageRef.imageWidth     = imgHeader.imageWidth;
//            imageRef.imageHeight    = imgHeader.imageHeight;
//            
//            imageRef.coarseIntTime  = imgHeader.coarseIntTime;
//            imageRef.analogGain     = imgHeader.analogGain;
//            
//            imageId++;
//            block += ImgSD::Full::ImageBlockCount;
//        }
//        
//        // Render the thumbnail into imageRef.thumbData
//        {
//            constexpr CFADesc _CFADesc = {
//                CFAColor::Green, CFAColor::Red,
//                CFAColor::Blue, CFAColor::Green,
//            };
//            
//            const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
//            
//            Pipeline::RawImage rawImage = {
//                .cfaDesc = _CFADesc,
//                .width = Img::PixelWidth,
//                .height = Img::PixelHeight,
//                .pixels = (ImagePixel*)(imgData+Img::PixelsOffset),
//            };
//            
//            const Pipeline::Options pipelineOpts = {
//                .rawMode = false,
//                .reconstructHighlights  = { .en = true, },
//                .debayerLMMSE           = { .applyGamma = true, },
//            };
//            
//            Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
//            const size_t thumbDataOff = (uintptr_t)&imageThumb.thumb - (uintptr_t)chunk.mmap.data();
//            
//            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//            id<MTLBuffer> buf = [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data() length:chunk.mmap.len() options:BufOpts deallocator:nil];
//            
//            const RenderThumb::Options thumbOpts = {
//                .thumbWidth = ImageThumb::ThumbWidth,
//                .thumbHeight = ImageThumb::ThumbHeight,
//                .dataOff = thumbDataOff,
//            };
//            
//            RenderThumb::RGB3FromTexture(renderer, thumbOpts, renderResult.txt, buf);
//        }
//        
//        deviceImgIdLast = imgHeader.id;
//    }
//    
//    // Make sure all rendering is complete before adding the images to the library
//    renderer.commitAndWait();
//    
//    {
//        auto lock = std::unique_lock(*imgLib);
//        // Add the records that we previously reserved
//        imgLib->add();
//        // Update the device's image id 'end' == last image id that we've observed from the device +1
//        imgLib->setDeviceImgIdEnd(deviceImgIdLast+1);
//    }
//}







- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView {
//    {
//        class FakeImageSource : public ImageSource {
//        public:
//            ImageLibraryPtr imageLibrary() override {
//                return il;
//            }
//            
//            ImageCachePtr imageCache() override {
//                return ic;
//            }
//            
//            ImageLibraryPtr il;
//            ImageCachePtr ic;
//        };
//        
//        ImageLibraryPtr il = std::make_shared<MDCTools::Lockable<ImageLibrary>>(std::filesystem::path("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio/Devices/335E36593137/ImageLibrary"));
//        il->read();
//        
//        ImageCachePtr ic = std::make_shared<ImageCache>(il, [] (const ImageRef& imageRef) { return nullptr; });
//        
//        auto imageSource = std::make_shared<FakeImageSource>();
//        imageSource->il = il;
//        imageSource->ic = ic;
//        
//        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:imageSource];
//        [imageGridView setDelegate:self];
//        
//        ImageGridScrollView* sv = [[ImageGridScrollView alloc] initWithFixedDocument:imageGridView];
//        [_mainView setContentView:sv animation:MainViewAnimation::None];
//    }
    
    
    
    
    
    
    
    
    ImageSourcePtr selection = [_sourceListView selection];
    if (selection) {
        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:selection];
        [imageGridView setDelegate:self];
        
        ImageGridScrollView* sv = [[ImageGridScrollView alloc] initWithFixedDocument:imageGridView];
        [_mainView setContentView:sv animation:MainViewAnimation::None];
    
    } else {
        [_mainView setContentView:nil animation:MainViewAnimation::None];
    }
}

// _openImage: open a particular image id, or an image offset from a particular image id
- (bool)_openImage:(Img::Id)imageId delta:(ssize_t)delta {
    ImageSourcePtr imageSource = [_sourceListView selection];
    if (!imageSource) return false;
    
    ImageLibraryPtr imageLibrary = imageSource->imageLibrary();
    {
        auto lock = std::unique_lock(*imageLibrary);
        if (imageLibrary->empty()) return false;
        
        auto find = imageLibrary->find(imageId);
        if (find == imageLibrary->end()) return false;
        
        const ssize_t deltaMin = std::distance(find, imageLibrary->begin());
        const ssize_t deltaMax = std::distance(find, std::prev(imageLibrary->end()));
        if (delta<deltaMin || delta>deltaMax) return false;
        
        const ImageThumb& imageThumb = *imageLibrary->recordGet(find+delta);
        ImageView* imageView = [[ImageView alloc] initWithImageThumb:imageThumb imageSource:imageSource];
        [imageView setDelegate:self];
        
        ImageScrollView* sv = [[ImageScrollView alloc] initWithFixedDocument:imageView];
        [sv setMagnifyToFit:true animate:false];
        
        NSDate* date = [NSDate dateWithTimeIntervalSince1970:imageThumb.timestamp];
        printf("Showing image #%ju (timestamp: 0x%jx / %s)\n", (uintmax_t)imageThumb.ref.id,
            (uintmax_t)imageThumb.timestamp, [[date descriptionWithLocale:[NSLocale currentLocale]] UTF8String]);
        
//        if (delta) {
//            [_mainView setContentView:imageView animation:(delta>0 ? MainViewAnimation::SlideToLeft : MainViewAnimation::SlideToRight)];
//        } else {
//            [_mainView setContentView:imageView animation:MainViewAnimation::None];
//        }
        
        [_mainView setContentView:sv animation:MainViewAnimation::None];
        
        return true;
    }
}

// MARK: - ImageGridViewDelegate

- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView {
    const ImageGridViewImageIds& selectedImageIds = [imageGridView selectedImageIds];
    if (selectedImageIds.empty()) return;
    const Img::Id imageId = *selectedImageIds.begin();
    [self _openImage:imageId delta:0];
}

// MARK: - ImageViewDelegate

- (void)imageViewPreviousImage:(ImageView*)imageView {
    const bool ok = [self _openImage:[imageView imageThumb].ref.id delta:-1];
    if (!ok) NSBeep();
}

- (void)imageViewNextImage:(ImageView*)imageView {
    const bool ok = [self _openImage:[imageView imageThumb].ref.id delta:1];
    if (!ok) NSBeep();
}

@end

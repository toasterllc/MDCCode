#import "Document.h"
#import "MainView.h"
#import "SourceListView/SourceListView.h"
#import "ImageGridView/ImageGridView.h"
#import "ImageView/ImageView.h"
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

- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView {
//    auto selection = [_sourceListView selection];
//    if (selection.device) {
//        auto imgLib = selection.device->imageLibrary();
//        auto lock = std::unique_lock(*imgLib);
//        const ImageThumb& imageThumb = *imgLib->recordGet(imgLib->begin());
//        
//        ImageView* imageView = [[ImageView alloc] initWithImageThumb:imageThumb
//            imageCache:selection.device->imageCache()];
//        
//        [self setContentView:imageView];
//    
//    } else {
//        [self setContentView:nil];
//    }
    
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
//        ImageLibraryPtr il = std::make_shared<MDCTools::Lockable<ImageLibrary>>(std::filesystem::path("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio/Devices/337336593137") / "ImageLibrary");
//        il->read();
//        
//        ImageCachePtr ic = std::make_shared<ImageCache>(il, [] (const ImageRef& imageRef) { return nullptr; });
//        
//        auto imageSource = std::make_shared<FakeImageSource>();
//        imageSource->il = il;
//        imageSource->ic = ic;
//        
//        ImageView* imageView = [[ImageView alloc] initWithImageThumb:*il->recordGet(il->begin()) imageSource:imageSource];
//        [_mainView setContentView:imageView animation:MainViewAnimation::None];
//    }
    
    
    
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
//        ImageLibraryPtr il = std::make_shared<MDCTools::Lockable<ImageLibrary>>(std::filesystem::path("/Users/dave/Desktop/ImageLibrary"));
//        il->read();
//        
//        ImageCachePtr ic = std::make_shared<ImageCache>(il, [] (const ImageRef& imageRef) { return nullptr; });
//        
//        auto imageSource = std::make_shared<FakeImageSource>();
//        imageSource->il = il;
//        imageSource->ic = ic;
//        
//        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:imageSource];
//        [_mainView setContentView:imageGridView animation:MainViewAnimation::None];
//    }
    
    
    
//    {
//        auto imgLib = std::make_shared<MDCTools::Vendor<ImageLibrary>>(std::filesystem::path("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio/Devices/337336593137") / "ImageLibrary");
//        imgLib->vend()->read();
//        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageLibrary:imgLib];
//        [self setContentView:imageGridView];
//    }
    
    ImageSourcePtr selection = [_sourceListView selection];
    if (selection) {
        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:selection];
        [imageGridView setDelegate:self];
        [_mainView setContentView:imageGridView animation:MainViewAnimation::None];
    
    } else {
        [_mainView setContentView:nil animation:MainViewAnimation::None];
    }
}

// _openImage: open a particular image id, or an image offset from a particular image id
- (bool)_openImage:(ImageId)imageId delta:(ssize_t)delta {
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
        
        NSDate* date = [NSDate dateWithTimeIntervalSince1970:imageThumb.ref.timestamp];
        printf("Showing image #%ju (timestamp: 0x%jx / %s)\n", (uintmax_t)imageId, (uintmax_t)imageThumb.ref.timestamp, [[date descriptionWithLocale:[NSLocale currentLocale]] UTF8String]);
        
//        if (delta) {
//            [_mainView setContentView:imageView animation:(delta>0 ? MainViewAnimation::SlideToLeft : MainViewAnimation::SlideToRight)];
//        } else {
//            [_mainView setContentView:imageView animation:MainViewAnimation::None];
//        }
        
        [_mainView setContentView:imageView animation:MainViewAnimation::None];
        
        return true;
    }
}

// MARK: - ImageGridViewDelegate

- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView {
    const ImageGridViewImageIds& selectedImageIds = [imageGridView selectedImageIds];
    if (selectedImageIds.empty()) return;
    const ImageId imageId = *selectedImageIds.begin();
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

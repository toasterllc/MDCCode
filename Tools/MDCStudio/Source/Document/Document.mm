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
//        auto imgLibPtr = std::make_shared<MDCTools::Vendor<ImageLibrary>>(std::filesystem::path("/Users/dave/Library/Application Support/com.heytoaster.MDCStudio/Devices/337336593137") / "ImageLibrary");
//        auto imgLib = imgLibPtr->vend();
//        imgLib->read();
//        
//        const ImageRef& imageRef = imgLib->recordGet(imgLib->begin())->ref;
//        ImageView* imageView = [[ImageView alloc] initWithImageRef:imageRef cache:nullptr];
//        [self setContentView:imageView];
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
        [_mainView setContentView:imageGridView];
    
    } else {
        [_mainView setContentView:nil];
    }
}

// _openImage: open a particular image id, or an image offset from a particular image id
- (void)_openImage:(ImageId)imageId delta:(ssize_t)delta {
    ImageSourcePtr imageSource = [_sourceListView selection];
    if (!imageSource) return;
    
    ImageLibraryPtr imageLibrary = imageSource->imageLibrary();
    {
        auto lock = std::unique_lock(*imageLibrary);
        if (imageLibrary->empty()) return;
        
        auto find = imageLibrary->find(imageId);
        if (find == imageLibrary->end()) return;
        
        const ssize_t deltaMin = std::distance(find, imageLibrary->begin());
        const ssize_t deltaMax = std::distance(find, std::prev(imageLibrary->end()));
        delta = std::clamp(delta, deltaMin, deltaMax);
        
        const ImageThumb& imageThumb = *imageLibrary->recordGet(find+delta);
        ImageView* imageView = [[ImageView alloc] initWithImageThumb:imageThumb imageSource:imageSource];
        [imageView setDelegate:self];
        [_mainView setContentView:imageView];
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
    [self _openImage:[imageView imageThumb].ref.id delta:-1];
}

- (void)imageViewNextImage:(ImageView*)imageView {
    [self _openImage:[imageView imageThumb].ref.id delta:1];
}

@end

#import "ImageGridView.h"
#import "ImageGridLayer.h"
#import "Util.h"
using namespace MDCStudio;

@interface ImageGridDocumentView : NSView
@end

@implementation ImageGridDocumentView {
@public
    CALayer* rootLayer;
    ImageGridLayer* imageGridLayer;
    CALayer* selectionRectLayer;
}

//- (void)setFrameSize:(NSSize)size {
////    CGSize superSize = [[self superview] bounds].size;
////    size.width = superSize.width;
//    [imageGridLayer setContainerWidth:size.width];
//    [imageGridLayer recomputeGrid];
//    // Don't let our frame.height be smaller than our superview's height
//    // This is so `selectionRectLayer` doesn't get clipped by the bottom of our view
////    size.height = std::max(superSize.height, [imageGridLayer containerHeight]);
//    [super setFrameSize:size];
////    NSLog(@"setFrameSize: %@", NSStringFromSize(size));
//}

//- (void)viewWillStartLiveResize {
//    [super viewWillStartLiveResize];
//    [imageGridLayer setResizingUnderway:true];
//}
//
//- (void)viewDidEndLiveResize {
//    [super viewDidEndLiveResize];
//    [imageGridLayer setResizingUnderway:false];
//}

- (BOOL)isFlipped {
    return true;
}

@end

@implementation ImageGridView {
    IBOutlet LayerScrollView* _scrollView;
    IBOutlet ImageGridDocumentView* _documentView;
    IBOutlet NSLayoutConstraint* _documentHeight;
    ImageGridLayer* _imageGridLayer;
    ImageSourcePtr _imageSource;
    __weak id<ImageGridViewDelegate> _delegate;
}

// MARK: - Creation

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _imageSource = imageSource;
    
    // Load from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        [_scrollView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:_scrollView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_scrollView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
    }
    
    // Configure ImageGridDocumentView
//    {
//        CALayer* rootLayer = [CALayer new];
////        [rootLayer setBackgroundColor:[[NSColor redColor] CGColor]];
//        
//        ImageGridLayer* imageGridLayer = [[ImageGridLayer alloc] initWithImageLibrary:_imageSource->imageLibrary()];
//        [rootLayer addSublayer:imageGridLayer];
//        
//        CALayer* selectionRectLayer = [CALayer new];
//        [selectionRectLayer setActions:LayerNullActions];
//        [selectionRectLayer setBackgroundColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:.2] CGColor]];
//        [selectionRectLayer setBorderColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] CGColor]];
//        [selectionRectLayer setHidden:true];
//        [selectionRectLayer setBorderWidth:1];
//        [rootLayer addSublayer:selectionRectLayer];
//        
//        _documentView->rootLayer = rootLayer;
//        _documentView->imageGridLayer = imageGridLayer;
//        _documentView->selectionRectLayer = selectionRectLayer;
//        [_documentView setLayer:_documentView->rootLayer];
//        [_documentView setWantsLayer:true];
//        [self _handleImageLibraryChanged];
//    }
    
    {
        _imageGridLayer = [[ImageGridLayer alloc] initWithImageLibrary:_imageSource->imageLibrary()];
        _documentView->imageGridLayer = _imageGridLayer;
        [_scrollView setScrollLayer:_imageGridLayer];
        [self _handleImageLibraryChanged];
    }
    
    
    
    // Observe image library changes so that we update the image grid
    {
        __weak auto weakSelf = self;
        ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
        auto lock = std::unique_lock(*imageLibrary);
        imageLibrary->addObserver([=] {
            auto strongSelf = weakSelf;
            if (!strongSelf) return false;
            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
            return true;
        });
    }
    
    return self;
}

- (void)setResizingUnderway:(bool)resizing {
    [_documentView->imageGridLayer setResizingUnderway:resizing];
}

- (void)setDelegate:(id<ImageGridViewDelegate>)delegate {
    _delegate = delegate;
}

- (ImageSourcePtr)imageSource {
    return _imageSource;
}

- (const ImageGridViewImageIds&)selectedImageIds {
    return [_documentView->imageGridLayer selectedImageIds];
}

- (NSResponder*)initialFirstResponder {
    return [_scrollView documentView];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [_imageGridLayer setContainerWidth:size.width];
    [_imageGridLayer recomputeGrid];
    [_documentHeight setConstant:[_imageGridLayer containerHeight]];
}

- (void)_handleImageLibraryChanged {
    #warning TODO: how do we update the document view's frame size?
    // Update the frame because the library's image count likely changed, which affects the document view's height
//    [_documentView setFrame:[_documentView frame]];
//    _documentHeight
    
    [_documentView->imageGridLayer setNeedsDisplay];
}

// MARK: - Event Handling

static ImageGridLayerImageIds _XORImageIds(const ImageGridLayerImageIds& a, const ImageGridLayerImageIds& b) {
    ImageGridLayerImageIds r;
    for (ImageId x : a) {
        if (b.find(x) == b.end()) {
            r.insert(x);
        }
    }
    
    for (ImageId x : b) {
        if (a.find(x) == a.end()) {
            r.insert(x);
        }
    }
    
    return r;
}

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    auto imageGridLayer = _documentView->imageGridLayer;
    
    CALayer* rectLayer = _documentView->selectionRectLayer;
    NSWindow* win = [mouseDownEvent window];
    const CGPoint startPoint = [_documentView convertPoint:[mouseDownEvent locationInWindow] fromView:nil];
    [rectLayer setHidden:false];
    
    const bool extend = [[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    const ImageGridLayerImageIds oldSelection = [imageGridLayer selectedImageIds];
    TrackMouse(win, mouseDownEvent, [=] (NSEvent* event, bool done) {
        const CGPoint curPoint = [_documentView convertPoint:[event locationInWindow] fromView:nil];
        const CGRect rect = CGRectStandardize(CGRect{startPoint.x, startPoint.y, curPoint.x-startPoint.x, curPoint.y-startPoint.y});
        const ImageGridLayerImageIds newSelection = [imageGridLayer imageIdsForRect:rect];
        if (extend) {
            [imageGridLayer setSelectedImageIds:_XORImageIds(oldSelection, newSelection)];
        } else {
            [imageGridLayer setSelectedImageIds:newSelection];
        }
        [rectLayer setFrame:rect];
        
        [_documentView autoscroll:event];
//        NSLog(@"mouseDown:");
    });
    [rectLayer setHidden:true];
}

- (void)mouseUp:(NSEvent*)event {
    if ([event clickCount] == 2) {
        [_delegate imageGridViewOpenSelectedImage:self];
    }
}

struct SelectionDelta {
    int x = 0;
    int y = 0;
};

- (void)_moveSelection:(SelectionDelta)delta extend:(bool)extend {
    auto imageGridLayer = _documentView->imageGridLayer;
    ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
    auto lock = std::unique_lock(*imageLibrary);
    
    const size_t imgCount = imageLibrary->recordCount();
    if (!imgCount) return;
    
    ImageGridLayerImageIds selectedImageIds = [imageGridLayer selectedImageIds];
    ssize_t newIdx = 0;
    if (!selectedImageIds.empty()) {
        const ImageId lastSelectedImgId = *std::prev(selectedImageIds.end());
        const auto iter = imageLibrary->find(lastSelectedImgId);
        if (iter == imageLibrary->end()) {
            NSLog(@"Image no longer in library");
            return;
        }
        
        const size_t idx = std::distance(imageLibrary->begin(), iter);
        const size_t colCount = [imageGridLayer columnCount];
        const size_t rem = (imgCount % colCount);
        const size_t lastRowCount = (rem ? rem : colCount);
        const bool firstRow = (idx < colCount);
        const bool lastRow = (idx >= (imgCount-lastRowCount));
        const bool firstCol = !(idx % colCount);
        const bool lastCol = ((idx % colCount) == (colCount-1));
        const bool lastElm = (idx == (imgCount-1));
        
        newIdx = idx;
        if (delta.x > 0) {
            // Right
            if (lastCol || lastElm) return;
            newIdx += 1;
        
        } else if (delta.x < 0) {
            // Left
            if (firstCol) return;
            newIdx -= 1;
        
        } else if (delta.y > 0) {
            // Down
            if (lastRow) return;
            newIdx += colCount;
        
        } else if (delta.y < 0) {
            // Up
            if (firstRow) return;
            newIdx -= colCount;
        }
        
        newIdx = std::clamp(newIdx, (ssize_t)0, (ssize_t)imgCount-1);
    
    } else {
        if (delta.x>0 || delta.y>0) {
            // Select first element
            newIdx = 0;
        } else if (delta.x<0 || delta.y<0) {
            // Select last element
            newIdx = imgCount-1;
        } else {
            return;
        }
    }
    
//    const size_t newIdx = std::min(imgCount-1, idx+[imageGridLayer columnCount]);
    const ImageId newImgId = imageLibrary->recordGet(imageLibrary->begin()+newIdx)->ref.id;
    [_documentView scrollRectToVisible:[imageGridLayer rectForImageAtIndex:newIdx]];
    
    if (!extend) selectedImageIds.clear();
    selectedImageIds.insert(newImgId);
    [imageGridLayer setSelectedImageIds:selectedImageIds];
}

- (void)moveDown:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{0,1} extend:extend];
}

- (void)moveUp:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{0,-1} extend:extend];
}

- (void)moveLeft:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{-1,0} extend:extend];
}

- (void)moveRight:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{1,0} extend:extend];
}

- (void)selectAll:(id)sender {
    ImageGridLayer* imageGridLayer = _documentView->imageGridLayer;
    ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
    auto lock = std::unique_lock(*imageLibrary);
    ImageGridLayerImageIds ids;
    for (auto it=imageLibrary->begin(); it!=imageLibrary->end(); it++) {
        ids.insert(imageLibrary->recordGet(it)->ref.id);
    }
    [imageGridLayer setSelectedImageIds:ids];
}

@end

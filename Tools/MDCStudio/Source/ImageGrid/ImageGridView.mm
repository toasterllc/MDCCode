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

- (void)setFrame:(NSRect)frame {
    [imageGridLayer setContainerWidth:frame.size.width];
    [imageGridLayer recomputeGrid];
    frame.size.height = [imageGridLayer containerHeight];
    [super setFrame:frame];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [imageGridLayer setContentsScale:[[self window] backingScaleFactor]];
}

- (void)viewWillStartLiveResize {
    [super viewWillStartLiveResize];
    [imageGridLayer setResizingUnderway:true];
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [imageGridLayer setResizingUnderway:false];
}

- (BOOL)isFlipped {
    return true;
}

@end

@interface ImageGridScrollView : NSScrollView
@end

@implementation ImageGridScrollView

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    [((ImageGridDocumentView*)[self documentView])->imageGridLayer setFrame:[self documentVisibleRect]];
}

@end

@implementation ImageGridView {
    IBOutlet NSView* _nibView;
    IBOutlet ImageGridDocumentView* _documentView;
}

// MARK: - Creation

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imgLib {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    // Load from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:_nibView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    }
    
    // Configure ImageGridDocumentView
    {
        CALayer* rootLayer = [CALayer new];
        
        ImageGridLayer* imageGridLayer = [[ImageGridLayer alloc] initWithImageLibrary:nullptr];
        [rootLayer addSublayer:imageGridLayer];
        
        CALayer* selectionRectLayer = [CALayer new];
        [selectionRectLayer setActions:LayerNullActions];
        [selectionRectLayer setBackgroundColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:.2] CGColor]];
        [selectionRectLayer setBorderColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] CGColor]];
        [selectionRectLayer setHidden:true];
        [selectionRectLayer setBorderWidth:1];
        [rootLayer addSublayer:selectionRectLayer];
        
        _documentView->rootLayer = rootLayer;
        _documentView->imageGridLayer = imageGridLayer;
        _documentView->selectionRectLayer = selectionRectLayer;
        [_documentView setLayer:_documentView->rootLayer];
        [_documentView setWantsLayer:true];
        [self _handleImageLibraryChanged];
    }
    
//    // Observe image library changes so that we update the image grid
//    {
//        __weak auto weakSelf = self;
//        imgLib->vend()->addObserver([=] {
//            auto strongSelf = weakSelf;
//            if (!strongSelf) return false;
//            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
//            return true;
//        });
//    }
    
//    ImageGridLayerImageIds imageIds;
//    imageIds.insert(88);
//    [_documentView->imageGridLayer setSelectedImageIds:imageIds];
    
    return self;
}
//
//- (instancetype)initWithCoder:(NSCoder*)coder {
//    if (!(self = [super initWithCoder:coder])) return nil;
//    [self initCommon];
//    return self;
//}
//
//- (instancetype)initWithFrame:(NSRect)frame {
//    if (!(self = [super initWithFrame:frame])) return nil;
//    [self initCommon];
//    return self;
//}
//
//- (void)initCommon {
//    // Load from nib
//    [self setTranslatesAutoresizingMaskIntoConstraints:false];
//    
//    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
//    assert(br);
//    
//    [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
//    [self addSubview:_nibView];
//    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
//    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
//}

//- (void)setImageLibrary:(ImageLibraryPtr)imgLib {
//    [_documentView->_imageGridLayer setImageLibrary:imgLib];
//    [_documentView _updateFrame];
//    
//    __weak auto weakSelf = self;
//    imgLib->vend()->addObserver([=] {
//        auto strongSelf = weakSelf;
//        if (!strongSelf) return false;
//        dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
//        return true;
//    });
//}

- (void)setResizingUnderway:(bool)resizing {
    [_documentView->imageGridLayer setResizingUnderway:resizing];
}

- (void)_handleImageLibraryChanged {
    // Update the frame because the library's image count likely changed, which affects the document view's height
    [_documentView setFrame:[_documentView frame]];
    [_documentView->imageGridLayer setNeedsDisplay];
}

// MARK: - Event Handling

//- (BOOL)acceptsFirstResponder {
//    NSLog(@"acceptsFirstResponder");
//    return true;
//}
//
//- (BOOL)becomeFirstResponder {
//    NSLog(@"becomeFirstResponder");
//    return true;
//}

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
    
    CALayer* layer = _documentView->selectionRectLayer;
    NSWindow* win = [mouseDownEvent window];
    
    const CGPoint startPoint = [_documentView convertPoint:[mouseDownEvent locationInWindow] fromView:nil];
    [layer setHidden:false];
    TrackMouse(win, mouseDownEvent, [=] (NSEvent* event, bool done) {
        const CGPoint curPoint = [_documentView convertPoint:[event locationInWindow] fromView:nil];
        const CGRect rect = CGRectStandardize(CGRect{startPoint.x, startPoint.y, curPoint.x-startPoint.x, curPoint.y-startPoint.y});
        [_documentView->imageGridLayer setSelectedImageIds:[_documentView->imageGridLayer imageIdsForRect:rect]];
        [layer setFrame:rect];
//        NSLog(@"mouseDown:");
    });
    [layer setHidden:true];
}

@end

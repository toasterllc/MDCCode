#import "ImageGridView.h"
#import "ImageGridLayer.h"

@interface ImageGridDocumentView : NSView
@end

@implementation ImageGridDocumentView {
@public
    CALayer* _rootLayer;
    ImageGridLayer* _imageGridLayer;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (void)initCommon {
    _rootLayer = [CALayer new];
    [self setLayer:_rootLayer];
    [self setWantsLayer:true];
    
    _imageGridLayer = [ImageGridLayer new];
    [_rootLayer addSublayer:_imageGridLayer];
    
    [self _updateFrame];
}

- (void)setFrame:(NSRect)frame {
    [_imageGridLayer setContainerWidth:frame.size.width];
    frame.size.height = [_imageGridLayer containerHeight];
//    NSLog(@"setFrame: %@", NSStringFromRect(frame));
    [super setFrame:frame];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_imageGridLayer setContentsScale:[[self window] backingScaleFactor]];
}

- (BOOL)isFlipped {
    return true;
}

- (void)viewWillStartLiveResize {
    [_imageGridLayer setResizingUnderway:true];
}

- (void)viewDidEndLiveResize {
    [_imageGridLayer setResizingUnderway:false];
}

- (void)_updateFrame {
    [self setFrame:[self frame]];
}

- (void)_handleScroll {
    [_imageGridLayer setFrame:[[self enclosingScrollView] documentVisibleRect]];
}

@end

@interface ImageGridScrollView : NSScrollView
@end

@implementation ImageGridScrollView

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    [(ImageGridDocumentView*)[self documentView] _handleScroll];
}

@end




@implementation ImageGridView {
    IBOutlet NSView* _nibView;
    IBOutlet ImageGridDocumentView* _documentView;
}

// MARK: - Creation

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (void)initCommon {
    // Load from nib
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_nibView];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
}

- (void)setImageLibrary:(ImageLibraryPtr)imgLib {
    [_documentView->_imageGridLayer setImageLibrary:imgLib];
    [_documentView _updateFrame];
    
    __weak auto weakSelf = self;
    imgLib->vend()->addObserver([=] {
        auto strongSelf = weakSelf;
        if (!strongSelf) return false;
        dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
        return true;
    });
}

- (void)_handleImageLibraryChanged {
    [_documentView _updateFrame];
}

@end

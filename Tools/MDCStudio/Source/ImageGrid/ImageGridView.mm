#import "ImageGridView.h"
#import "ImageGridLayer.h"

@implementation ImageGridView {
    CALayer* _rootLayer;
    ImageGridLayer* _imageGridLayer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
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

- (ImageGridLayer*)imageGridLayer {
    return _imageGridLayer;
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

- (void)setImageLibrary:(ImageLibraryPtr)imgLib {
    [_imageGridLayer setImageLibrary:imgLib];
    [self _updateFrame];
    
    __weak auto weakSelf = self;
    imgLib->vend()->addObserver([=] {
        auto strongSelf = weakSelf;
        if (!strongSelf) return false;
        dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
        return true;
    });
}

- (void)_updateFrame {
    [self setFrame:[self frame]];
}

- (void)_handleScroll {
    [_imageGridLayer setFrame:[[self enclosingScrollView] documentVisibleRect]];
}

- (void)_handleImageLibraryChanged {
    [self _updateFrame];
}

@end



@interface ImageGridScrollView : NSScrollView
@end

@implementation ImageGridScrollView

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    [(ImageGridView*)[self documentView] _handleScroll];
}

@end

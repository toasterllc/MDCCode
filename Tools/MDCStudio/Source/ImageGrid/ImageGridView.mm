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
    
    [self setFrame:[self frame]];
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
}

@end



@interface ImageGridScrollView : NSScrollView
@end

@implementation ImageGridScrollView

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    
//    NSLog(@"reflectScrolledClipView: %@", NSStringFromRect([self documentVisibleRect]));
    
    const CGRect visibleRect = [self documentVisibleRect];
    ImageGridLayer*const imageGridLayer = [((ImageGridView*)[self documentView]) imageGridLayer];
    [imageGridLayer setFrame:visibleRect];
}

@end

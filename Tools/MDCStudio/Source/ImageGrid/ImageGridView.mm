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
    // Don't let our frame.height be smaller than our superview's height
    // This is so `selectionRectLayer` doesn't get clipped by the bottom of our view
    frame.size.height = std::max([[self superview] bounds].size.height, [imageGridLayer containerHeight]);
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
//        [rootLayer setBackgroundColor:[[NSColor redColor] CGColor]];
        
        ImageGridLayer* imageGridLayer = [[ImageGridLayer alloc] initWithImageLibrary:imgLib];
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
    
    // Observe image library changes so that we update the image grid
    {
        __weak auto weakSelf = self;
        imgLib->vend()->addObserver([=] {
            auto strongSelf = weakSelf;
            if (!strongSelf) return false;
            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
            return true;
        });
    }
    
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
    
    CALayer* rectLayer = _documentView->selectionRectLayer;
    NSWindow* win = [mouseDownEvent window];
    
    const CGPoint startPoint = [_documentView convertPoint:[mouseDownEvent locationInWindow] fromView:nil];
    [rectLayer setHidden:false];
    TrackMouse(win, mouseDownEvent, [=] (NSEvent* event, bool done) {
        const CGPoint curPoint = [_documentView convertPoint:[event locationInWindow] fromView:nil];
        const CGRect rect = CGRectStandardize(CGRect{startPoint.x, startPoint.y, curPoint.x-startPoint.x, curPoint.y-startPoint.y});
        [_documentView->imageGridLayer setSelectedImageIds:[_documentView->imageGridLayer imageIdsForRect:rect]];
        [rectLayer setFrame:rect];
//        NSLog(@"mouseDown:");
    });
    [rectLayer setHidden:true];
}

- (void)moveDown:(id)sender {
    
}

- (void)moveUp:(id)sender {
    
}

- (void)moveLeft:(id)sender {
    
}

- (void)moveRight:(id)sender {
    
}

//- (void)moveForward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveRight:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveBackward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveLeft:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveUp:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveDown:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordForward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordBackward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToBeginningOfLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToEndOfLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToBeginningOfParagraph:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToEndOfParagraph:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToEndOfDocument:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToBeginningOfDocument:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)pageDown:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)pageUp:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)centerSelectionInVisibleArea:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveBackwardAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveForwardAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordForwardAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordBackwardAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveUpAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveDownAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToBeginningOfLineAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToEndOfLineAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToBeginningOfParagraphAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToEndOfParagraphAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToEndOfDocumentAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToBeginningOfDocumentAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)pageDownAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)pageUpAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveParagraphForwardAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveParagraphBackwardAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordRight:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordLeft:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveRightAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveLeftAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordRightAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveWordLeftAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToLeftEndOfLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToRightEndOfLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToLeftEndOfLineAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)moveToRightEndOfLineAndModifySelection:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)scrollPageUp:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)scrollPageDown:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)scrollLineUp:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)scrollLineDown:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)scrollToBeginningOfDocument:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)scrollToEndOfDocument:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)transpose:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)transposeWords:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)selectAll:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)selectParagraph:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)selectLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)selectWord:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)indent:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertTab:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertBacktab:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertNewline:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertParagraphSeparator:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertNewlineIgnoringFieldEditor:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertTabIgnoringFieldEditor:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertLineBreak:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertContainerBreak:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertSingleQuoteIgnoringSubstitution:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)insertDoubleQuoteIgnoringSubstitution:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)changeCaseOfLetter:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)uppercaseWord:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)lowercaseWord:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)capitalizeWord:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteForward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteBackward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteBackwardByDecomposingPreviousCharacter:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteWordForward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteWordBackward:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteToBeginningOfLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteToEndOfLine:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteToBeginningOfParagraph:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteToEndOfParagraph:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)yank:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)complete:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)setMark:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)deleteToMark:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)selectToMark:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)swapWithMark:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)cancelOperation:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)makeBaseWritingDirectionNatural:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)makeBaseWritingDirectionLeftToRight:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)makeBaseWritingDirectionRightToLeft:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)makeTextWritingDirectionNatural:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)makeTextWritingDirectionLeftToRight:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)makeTextWritingDirectionRightToLeft:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }
//- (void)quickLookPreviewItems:(nullable id)sender { NSLog(@"%@", NSStringFromSelector(_cmd)); }


@end

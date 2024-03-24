#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// AnchoredScrollView: a scroll view that holds the document (supplied to -initWithAnchoredDocument:)
// anchored at the visible rect of the scroll view, but transmits the current
// translation/magnification to the anchored document via -anchoredTranslationChanged:magnification:.
//
// This allows:
//
//   - the document to implement scrolling/magnification itself by using its
//     own transformation math (necessary for scrollable/zoomable Metal rendering);
//
//   - the size of the anchored document to match the size of the viewport, instead of
//     the size of the full content (necessary for Metal rendering);
// 
//   - consistent NSScrollView behaviors (eg rubber-banding, momentum scrolling,
//     window titlebar underlay effects).

@protocol AnchoredScrollViewDocument
@required
// -anchoredTranslationChanged:magnification: called whenever the translation/magnification changes
- (void)anchoredTranslationChanged:(CGPoint)t magnification:(CGFloat)m;
- (bool)anchoredFlipped;

@optional
- (void)anchoredCreateConstraintsForContainer:(NSView*)container;
- (void)anchoredInteractionUnderway:(bool)underway;
@end

@interface AnchoredScrollView : NSScrollView

- (instancetype)initWithAnchoredDocument:(NSView<AnchoredScrollViewDocument>*)doc;

- (NSView<AnchoredScrollViewDocument>*)document;

- (void)setAnchorDuringResize:(bool)anchorDuringResize;
- (void)scrollToCenter;

- (bool)magnifyToFit;
- (void)setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate;

// -magnifySnapToFit: only performs the magnify if the content is already near the size
// of the container. To the user this appears as if the content 'snaps' to the size of the
// container, when the content is near the container size.
- (void)magnifySnapToFit;

// Menu actions
- (IBAction)magnifyToActualSize:(id)sender;
- (IBAction)magnifyToFit:(id)sender;
- (IBAction)magnifyIncrease:(id)sender;
- (IBAction)magnifyDecrease:(id)sender;

// Floating subviews (that work with content insets)
- (NSView*)floatingSubviewContainer;

@end

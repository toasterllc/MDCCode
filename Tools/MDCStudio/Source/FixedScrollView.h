#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// FixedScrollView: a scroll view that holds the document (supplied to -initWithFixedDocument:)
// fixed at the visible rect of the scroll view, but transmits the current
// translation/magnification to the fixed document via -fixedTranslationChanged:magnification:.
// This allows:
//
//   - the document to implement scrolling/magnification itself by using its
//     own transformation math (necessary for scrollable/zoomable Metal rendering);
//
//   - the size of the fixed document to match the size of the viewport, instead of
//     the size of the full content (necessary for Metal rendering);
// 
//   - consistent NSScrollView behaviors (eg rubber-banding, momentum scrolling,
//     window titlebar underlay effects).

@protocol FixedScrollViewDocument
@required
// -fixedTranslationChanged:magnification: called whenever the translation/magnification changes
- (void)fixedTranslationChanged:(CGPoint)t magnification:(CGFloat)m;
- (bool)fixedFlipped;

@optional
- (void)fixedCreateConstraintsForContainer:(NSView*)container;
- (void)fixedInteractionUnderway:(bool)underway;
@end

@interface FixedScrollView : NSScrollView

- (instancetype)initWithFixedDocument:(NSView<FixedScrollViewDocument>*)doc;

- (NSView<FixedScrollViewDocument>*)document;

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

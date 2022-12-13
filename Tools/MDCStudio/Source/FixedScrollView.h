#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// FixedScrollView: a scroll view that holds the document (set via -setFixedDocument:)
// fixed at the visible rect of the scroll view, but transmits the current
// translation/magnification to the fixed document via -setTranslation:magnification:.
// This allows the document to implement scrolling/magnification itself by using its
// own transformation math (necessary for scrollable/zoomable Metal rendering, for
// example), while retaining consistent NSScrollView behaviors (eg rubber-banding,
// content-snapping, momentum scroll, window titlebar content-blur).

@protocol FixedScrollViewDocument
// -fixedContentSize: the total size of the scrollable/zoomable content.
// (Ie, the size of the 'universe'.)
- (CGSize)fixedContentSize;

#warning TODO: not sure if we want this
//- (bool)fixedFlipped;

// -setFixedTranslation:magnification: called whenever the
// translation/magnification changes.
- (void)setFixedTranslation:(CGPoint)t magnification:(CGFloat)m;
@end

@interface FixedScrollView : NSScrollView

- (void)setFixedDocument:(NSView<FixedScrollViewDocument>*)doc;

- (bool)magnifyToFit;
- (void)setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate;

// -magnifySnapToFit: only performs the magnify if the content is already near the size
// of the container. To the user this appears as if the content 'snaps' to the size of the
// container, when the content is near the container size.
- (void)magnifySnapToFit;

// Menu actions
- (void)magnifyIncrease:(id)sender;
- (void)magnifyDecrease:(id)sender;
- (void)magnifyToFit:(id)sender;

@end

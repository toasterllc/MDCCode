#import "LayerScrollView.h"
#import <algorithm>

@implementation LayerScrollView {
    CALayer<LayerScrollViewLayer>* _layer;
    CGRect _layerFrame;
    CGFloat _layerMagnification;
    CGPoint _anchorPointDocument;
    CGPoint _anchorPointScreen;
}

// MARK: - Methods

- (void)setScrollLayer:(CALayer<LayerScrollViewLayer>*)layer {
    [_layer removeFromSuperlayer];
    
    _layer = layer;
    CALayer* rootLayer = [CALayer new];
    [rootLayer addSublayer:_layer];
//    [rootLayer setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.1] CGColor]];
    
    NSView* documentView = [self documentView];
    [documentView setLayer:rootLayer];
    [documentView setWantsLayer:true];
    
    NSWindow* win = [self window];
    if (win) [_layer setContentsScale:[win backingScaleFactor]];
}

- (void)tile {
    [super tile];
    if (_layer) {
        [[self documentView] setFrameSize:[_layer preferredFrameSize]];
    }
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    
    // Keep the content anchored
    // This keeps the content in place when resizing the containing window, which looks better
    NSWindow* win = [self window];
    NSView* doc = [self documentView];
    NSClipView* clip = [self contentView];
    
    const CGPoint anchorPointWant = _anchorPointDocument;
    const CGPoint anchorPointHave = [doc convertPoint:[win convertPointFromScreen:_anchorPointScreen] fromView:nil];
    const CGPoint delta = {
        anchorPointWant.x-anchorPointHave.x,
        anchorPointWant.y-anchorPointHave.y,
    };
    
    CGRect bounds = [clip bounds];
    bounds.origin.x += delta.x;
    bounds.origin.y += delta.y;
    bounds = [clip constrainBoundsRect:bounds];
    
    [super scrollClipView:clip toPoint:bounds.origin];
    [self reflectScrolledClipView:clip];
}

// MARK: - NSView Overrides

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:[[self window] backingScaleFactor]];
}

- (void)viewWillStartLiveResize {
    [super viewWillStartLiveResize];
    _anchorPointDocument = [self documentVisibleRect].origin;
    _anchorPointScreen = [[self window] convertPointToScreen:
        [[self documentView] convertPoint:_anchorPointDocument toView:nil]];
}

// MARK: - NSScrollView Overrides

- (void)scrollClipView:(NSClipView*)clipView toPoint:(NSPoint)point {
    // If we're live-resize is underway, prevent the scroll elasticity animation from scrolling,
    // otherwise we get a very jittery animation.
    // This doesn't fully fix the problem, because the live resize can end before the elasticity
    // animation ends, but it works well enough.
    if ([self inLiveResize]) return;
    [super scrollClipView:clipView toPoint:point];
}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    
    const CGFloat mag = [self magnification];
    const CGFloat heightExtra = 22/mag; // Expand the height to get the NSWindow titlebar mirror effect
    const CGRect visibleRect = [[self documentView] visibleRect];
    const CGRect frame = {visibleRect.origin, {visibleRect.size.width, visibleRect.size.height+heightExtra}};
    
    if (!CGRectEqualToRect(frame, _layerFrame) || mag!=_layerMagnification) {
        _layerFrame = frame;
        _layerMagnification = mag;
        [_layer setFrame:_layerFrame];
        [_layer setTranslation:_layerFrame.origin magnification:_layerMagnification];
        [_layer setNeedsDisplay];
    }
}

@end

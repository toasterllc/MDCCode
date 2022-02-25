#import "LayerScrollView.h"
#import <algorithm>

@implementation LayerScrollView {
    CALayer<LayerScrollViewLayer>* _layer;
    CGRect _layerFrame;
    CGFloat _layerMagnification;
    CGPoint _anchorPoint;
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
    const CGPoint anchorBefore = [[self window] convertPointToScreen:
        [[self documentView] convertPoint:[self documentVisibleRect].origin toView:nil]];
    [super setFrame:frame];
    const CGPoint anchorAfter = [[self window] convertPointToScreen:
        [[self documentView] convertPoint:[self documentVisibleRect].origin toView:nil]];
    
    if (!CGPointEqualToPoint(anchorBefore, anchorAfter)) {
        NSLog(@"anchorBefore: %@, anchorAfter: %@", NSStringFromPoint(anchorBefore), NSStringFromPoint(anchorAfter));
    }
    
    
    
    CGRect docRect = [self documentVisibleRect];
    [super scrollClipView:[self contentView] toPoint:[[self contentView] constrainScrollPoint:{_anchorPoint.x, _anchorPoint.y-docRect.size.height}]];
//    [[self contentView] scrollToPoint:{_anchorPoint.x, _anchorPoint.y-docRect.size.height}];
    [self reflectScrolledClipView:[self contentView]];
//    [self tile];
}

// MARK: - NSView Overrides

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:[[self window] backingScaleFactor]];
}

- (void)viewWillStartLiveResize {
    NSEvent* currentEvent = [NSApp currentEvent];
    NSLog(@"viewWillStartLiveResize %@", [NSApp currentEvent]);
    CGRect docRect = [self documentVisibleRect];
    _anchorPoint = docRect.origin;
    _anchorPoint.y += docRect.size.height;
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

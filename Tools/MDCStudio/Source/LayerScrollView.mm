#import "LayerScrollView.h"
#import <algorithm>
#import <cmath>
#import <optional>

@implementation LayerScrollView {
    CALayer<LayerScrollViewLayer>* _layer;
    CGRect _layerFrame;
    CGFloat _layerMagnification;
    CGPoint _anchorPointDocument;
    CGPoint _anchorPointScreen;
    bool _magnifyToFit;
    std::optional<CGFloat> _animatedMagnification;
}

static void _initCommon(LayerScrollView* self) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_liveMagnifyEnded)
        name:NSScrollViewDidEndLiveMagnifyNotification object:nil];
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _initCommon(self);
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _initCommon(self);
    return self;
}

// MARK: - Methods

- (void)setScrollLayer:(CALayer<LayerScrollViewLayer>*)layer {
    [_layer removeFromSuperlayer];
    
    _layer = layer;
    CALayer* rootLayer = [CALayer new];
    [rootLayer addSublayer:_layer];
    
    NSView* documentView = [self documentView];
    [documentView setTranslatesAutoresizingMaskIntoConstraints:false];
    [documentView setLayer:rootLayer];
    [documentView setWantsLayer:true];
    [documentView setFrameSize:[_layer preferredFrameSize]];
    
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
    [self _setMagnifyToFit:true animate:false];
}

- (void)magnifyToFit {
    [self _setMagnifyToFit:true animate:true];
}

- (void)magnifyToFitIfNeeded {
    NSView* doc = [self documentView];
    
    const CGSize contentSize = [self convertRect:[[self documentView] bounds] fromView:doc].size;
    const CGSize containerSize = [self bounds].size;
    
    const CGFloat contentAspect = contentSize.width/contentSize.height;
    const CGFloat containerAspect = containerSize.width/containerSize.height;
    
    constexpr CGFloat Thresh = 80;
    if (contentAspect > containerAspect) {
        if (std::abs(contentSize.width-containerSize.width) < Thresh) {
            [self _setMagnifyToFit:true animate:true];
        }
    } else {
        if (std::abs(contentSize.height-containerSize.height) < Thresh) {
            [self _setMagnifyToFit:true animate:true];
        }
    }
}

- (IBAction)zoomIn:(id)sender {
    const CGFloat curMag = _animatedMagnification.value_or([self magnification]);
    const CGFloat mag = std::clamp(std::pow(2, floor(std::log2(curMag)+1)), [self minMagnification], [self maxMagnification]);
    if (mag == curMag) { return; } // Short-circuit if the magnification hasn't changed
    [self _setAnimatedMagnification:mag];
}

- (IBAction)zoomOut:(id)sender {
    const CGFloat curMag = _animatedMagnification.value_or([self magnification]);
    const CGFloat mag = std::clamp(std::pow(2, ceil(std::log2(curMag)-1)), [self minMagnification], [self maxMagnification]);
    if (mag == curMag) { return; } // Short-circuit if the magnification hasn't changed
    [self _setAnimatedMagnification:mag];
}

- (IBAction)zoomToFit:(id)sender {
    [self _setMagnifyToFit:true animate:true];
}

- (void)_setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate {
    _magnifyToFit = magnifyToFit;
    [self setHasVerticalScroller:!_magnifyToFit];
    [self setHasHorizontalScroller:!_magnifyToFit];
    
    if (_magnifyToFit) {
        NSClipView* clip = [self contentView];
        NSView* doc = [self documentView];
        
        if (animate) {
            [[self animator] magnifyToFitRect:[clip convertRect:[doc bounds] fromView:doc]];
        } else {
            [self magnifyToFitRect:[clip convertRect:[doc bounds] fromView:doc]];
        }
    }
}

- (void)_setAnimatedMagnification:(CGFloat)mag {
    _animatedMagnification = mag;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
        [[self animator] setMagnification:mag];
    } completionHandler:^{
        if (!self->_animatedMagnification || self->_animatedMagnification!=mag) return;
        self->_animatedMagnification = std::nullopt;
    }];
}

- (void)_liveMagnifyEnded {
    [self magnifyToFitIfNeeded];
}

// MARK: - NSView Overrides

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
    
    [self scrollClipView:clip toPoint:bounds.origin];
    [self _setMagnifyToFit:_magnifyToFit animate:false];
    [self reflectScrolledClipView:clip];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

- (void)viewWillStartLiveResize {
    [super viewWillStartLiveResize];
    _anchorPointDocument = [self documentVisibleRect].origin;
    _anchorPointScreen = [[self window] convertPointToScreen:
        [[self documentView] convertPoint:_anchorPointDocument toView:nil]];
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [self magnifyToFitIfNeeded];
}

// MARK: - NSScrollView Overrides

- (void)setMagnification:(CGFloat)mag {
    [self _setMagnifyToFit:false animate:false];
    [super setMagnification:mag];
}

- (void)setMagnification:(CGFloat)mag centeredAtPoint:(NSPoint)point {
    [self _setMagnifyToFit:false animate:false];
    [super setMagnification:mag centeredAtPoint:point];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    [self _setMagnifyToFit:false animate:false];
    [super magnifyWithEvent:event];
}

- (void)smartMagnifyWithEvent:(NSEvent*)event {
    [self _setMagnifyToFit:false animate:false];
    [super smartMagnifyWithEvent:event];
}

// Disable NSScrollView legacy 'responsive scrolling' by merely overriding -scrollWheel
// We don't want this behavior because it causes strange flashes and artifacts when
// scroll quickly, especially when scrolling near the margin
- (void)scrollWheel:(NSEvent*)event {
    if (!([event modifierFlags]&NSEventModifierFlagCommand)) {
        [super scrollWheel:event];
        return;
    }
    
    const CGPoint anchor = [[self contentView] convertPoint:[event locationInWindow] fromView:nil];
    const CGFloat mag = [self magnification];
    [self setMagnification:mag*(1-[event scrollingDeltaY]/250) centeredAtPoint:anchor];
    
    if ([event phase] & (NSEventPhaseEnded|NSEventPhaseCancelled)) {
        [self magnifyToFitIfNeeded];
    }
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

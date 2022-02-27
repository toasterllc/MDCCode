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
    [self setMagnifyToFit:true animate:false];
}

- (bool)magnifyToFit {
    return _magnifyToFit;
}

- (CGFloat)_fitMagnification {
    const CGSize contentSize = [[self documentView] frame].size;
    const CGSize containerSize = [self bounds].size;
    
    const CGFloat contentAspect = contentSize.width/contentSize.height;
    const CGFloat containerAspect = containerSize.width/containerSize.height;
    
    const CGFloat contentAxisSize = (contentAspect>containerAspect ? contentSize.width : contentSize.height);
    const CGFloat containerAxisSize = (contentAspect>containerAspect ? containerSize.width : containerSize.height);
    
    const CGFloat fitMag = containerAxisSize/contentAxisSize;
    return fitMag;
}

- (void)setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate {
    _magnifyToFit = magnifyToFit;
    // Setting the alpha because -setHidden: has no effect
    [[self verticalScroller] setAlphaValue:(!magnifyToFit ? 1 : 0)];
    [[self horizontalScroller] setAlphaValue:(!magnifyToFit ? 1 : 0)];
    
    if (_magnifyToFit) {
        const CGFloat fitMag = [self _fitMagnification];
        // We're using -setMagnification: here, and not -magnifyToFitRect:, because a single mechanism
        // must be used set the magnification, because future animations must cancel previous ones. If
        // we mix -setMagnification: with -magnifyToFitRect:, the animations don't cancel each other,
        // so they run simultaneously and conflict, and the effects are clearly visible to the user.
        if (animate) {
            [self _setAnimatedMagnification:fitMag];
        } else {
            [self setMagnification:fitMag];
        }
    }
}

- (void)magnifySnapToFit {
    const CGFloat mag = [self magnification];
    const CGFloat fitMag = [self _fitMagnification];
    constexpr CGFloat Thresh = 0.15;
    const bool magnifyToFit = std::abs(1-(mag/fitMag)) < Thresh;
    [self setMagnifyToFit:magnifyToFit animate:true];
}

static CGFloat _NextMagnification(CGFloat mag, int direction) {
    // Thresh: if `mag` is within this threshold of the next magnification, we'll skip to the next-next magnification
    constexpr CGFloat Thresh = 0.25;
    if (direction > 0) {
        return std::pow(2, std::floor((std::ceil(std::log2(mag)/Thresh)*Thresh)+1));
    } else {
        return std::pow(2, std::ceil((std::floor(std::log2(mag)/Thresh)*Thresh)-1));
    }
}

- (IBAction)zoomIn:(id)sender {
    const CGFloat curMag = _animatedMagnification.value_or([self magnification]);
    const CGFloat nextMag = std::clamp(_NextMagnification(curMag, 1), [self minMagnification], [self maxMagnification]);
    if (nextMag == curMag) return; // Short-circuit if the magnification hasn't changed
    [self _setAnimatedMagnification:nextMag];
}

- (IBAction)zoomOut:(id)sender {
    const CGFloat curMag = _animatedMagnification.value_or([self magnification]);
    const CGFloat nextMag = std::clamp(_NextMagnification(curMag, -1), [self minMagnification], [self maxMagnification]);
    if (nextMag == curMag) return; // Short-circuit if the magnification hasn't changed
    [self _setAnimatedMagnification:nextMag];
}

- (IBAction)zoomToFit:(id)sender {
    [self setMagnifyToFit:true animate:true];
}

- (void)_setAnimatedMagnification:(CGFloat)mag {
    _animatedMagnification = mag;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
        [[self animator] setMagnification:mag];
    } completionHandler:^{
        if (!self->_animatedMagnification || self->_animatedMagnification!=mag) return;
        self->_animatedMagnification = std::nullopt;
        [self magnifySnapToFit];
    }];
}

- (void)_liveMagnifyEnded {
    [self magnifySnapToFit];
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
    [self setMagnifyToFit:_magnifyToFit animate:false];
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
    [self magnifySnapToFit];
}

// MARK: - NSScrollView Overrides

- (void)smartMagnifyWithEvent:(NSEvent*)event {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        [super smartMagnifyWithEvent:event];
    } completionHandler:^{
        [self magnifySnapToFit];
    }];
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
        [self magnifySnapToFit];
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

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
    std::optional<CGFloat> _modelMagnification;
    struct {
        NSTimer* magnifyToFitTimer;
        bool zoom;
    } _scrollWheel;
    id _documentViewFrameChangedObserver;
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
    [documentView setLayer:rootLayer];
    [documentView setWantsLayer:true];
    
    // Observe document frame changes so we can update our magnification if we're in magnify-to-fit mode
    __weak auto weakSelf = self;
    _documentViewFrameChangedObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
        object:documentView queue:nil usingBlock:^(NSNotification*) {
        [weakSelf _documentViewFrameChanged];
    }];
    
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
    [_layer setGeometryFlipped:[documentView isFlipped]];
    [self setMagnifyToFit:true animate:false];
}

- (bool)magnifyToFit {
    return _magnifyToFit;
}

static bool _ShouldSnapToFitMagnification(CGFloat mag, CGFloat fitMag) {
    constexpr CGFloat Thresh = 0.15;
    return std::abs(1-(mag/fitMag)) < Thresh;
}

static CGFloat _NextMagnification(CGFloat mag, CGFloat fitMag, int direction) {
    // Thresh: if `mag` is within this threshold of the next magnification, we'll skip to the next-next magnification
    constexpr CGFloat Thresh = 0.25;
    if (direction > 0) {
        mag = std::pow(2, std::floor((std::ceil(std::log2(mag)/Thresh)*Thresh)+1));
    } else {
        mag = std::pow(2, std::ceil((std::floor(std::log2(mag)/Thresh)*Thresh)-1));
    }
    
    if (_ShouldSnapToFitMagnification(mag, fitMag)) return fitMag;
    return mag;
}

- (void)setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate {
    if (![self allowsMagnification]) return;
    
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
            [self _setAnimatedMagnification:fitMag snapToFit:false];
        } else {
            [self setMagnification:fitMag];
        }
    }
}

- (void)magnifySnapToFit {
    if (![self allowsMagnification]) return;
    const CGFloat mag = [self _modelMagnification];
    const CGFloat fitMag = [self _fitMagnification];
    [self setMagnifyToFit:_ShouldSnapToFitMagnification(mag, fitMag) animate:true];
}

- (IBAction)zoomIn:(id)sender {
    if (![self allowsMagnification]) return;
    const CGFloat fitMag = [self _fitMagnification];
    const CGFloat curMag = [self _modelMagnification];
    const CGFloat nextMag = std::clamp(_NextMagnification(curMag, fitMag, 1), [self minMagnification], [self maxMagnification]);
    [self _setAnimatedMagnification:nextMag snapToFit:true];
}

- (IBAction)zoomOut:(id)sender {
    if (![self allowsMagnification]) return;
    const CGFloat fitMag = [self _fitMagnification];
    const CGFloat curMag = [self _modelMagnification];
    const CGFloat nextMag = std::clamp(_NextMagnification(curMag, fitMag, -1), [self minMagnification], [self maxMagnification]);
    [self _setAnimatedMagnification:nextMag snapToFit:true];
}

- (IBAction)zoomToFit:(id)sender {
    if (![self allowsMagnification]) return;
    [self setMagnifyToFit:true animate:true];
}

- (void)_setAnimatedMagnification:(CGFloat)mag snapToFit:(bool)snapToFit {
    const CGFloat curMag = [self _modelMagnification];
    if (mag == curMag) return;
    
    _modelMagnification = mag;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext*) {
        [[self animator] setMagnification:mag];
    } completionHandler:^{
        if (!self->_modelMagnification || self->_modelMagnification!=mag) return;
        self->_modelMagnification = std::nullopt;
        if (snapToFit) {
            [self magnifySnapToFit];
        }
    }];
}

- (void)_liveMagnifyEnded {
    [self magnifySnapToFit];
}

- (void)_documentViewFrameChanged {
    // Update our magnification if we're in magnify-to-fit mode
    [self setMagnifyToFit:_magnifyToFit animate:false];
}

- (CGFloat)_modelMagnification {
    return _modelMagnification.value_or([self magnification]);
}

- (CGFloat)_presentationMagnification {
    return [self magnification];
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

- (void)smartMagnifyWithEvent:(NSEvent*)event {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        [super smartMagnifyWithEvent:event];
    } completionHandler:^{
        [self magnifySnapToFit];
    }];
}

// MARK: - NSScrollView Overrides

// Disable NSScrollView legacy 'responsive scrolling' by merely overriding -scrollWheel
// We don't want this behavior because it causes strange flashes and artifacts when
// scroll quickly, especially when scrolling near the margin
- (void)scrollWheel:(NSEvent*)event {
    const NSEventPhase phase = [event phase];
    if ((phase & NSEventPhaseBegan) && [self allowsMagnification]) {
        _scrollWheel.zoom = [event modifierFlags] & NSEventModifierFlagCommand;
    }
    
    if (_scrollWheel.zoom) {
        [self _handleScrollWheelZoom:event];
    } else {
        [super scrollWheel:event];
    }
}

- (void)_handleScrollWheelZoom:(NSEvent*)event {
    [_scrollWheel.magnifyToFitTimer invalidate];
    _scrollWheel.magnifyToFitTimer = nil;
    
    const NSEventPhase phase = [event phase];
    const NSEventPhase momentumPhase = [event momentumPhase];
    const CGPoint anchor = [[self contentView] convertPoint:[event locationInWindow] fromView:nil];
    const CGFloat mag = [self _modelMagnification];
    [self setMagnification:mag*(1-[event scrollingDeltaY]/250) centeredAtPoint:anchor];
    
    if (momentumPhase != NSEventPhaseNone) {
        if (momentumPhase & (NSEventPhaseEnded|NSEventPhaseCancelled)) {
            [self magnifySnapToFit];
        }
    
    } else if (phase & (NSEventPhaseEnded|NSEventPhaseCancelled)) {
        // We need a timer because momentum-scroll events come after the regular scroll wheel phase ends,
        // so we only want to start the snap-to-fit animation if the momentum events aren't coming
        _scrollWheel.magnifyToFitTimer = [NSTimer scheduledTimerWithTimeInterval:.01 repeats:false block:^(NSTimer*) {
            [self magnifySnapToFit];
        }];
    }
}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    
    NSView* doc = [self documentView];
    const CGFloat mag = [self _presentationMagnification];
    const CGFloat heightExtra = 22/mag; // Expand the height to get the NSWindow titlebar mirror effect
    const CGRect visibleRect = [doc visibleRect];//[doc convertRectToLayer:[doc visibleRect]];
    
    CGRect frame = visibleRect;
    if ([doc isFlipped]) {
        frame.origin.y -= heightExtra;
        frame.size.height += heightExtra;
    } else {
        frame.size.height += heightExtra;
    }
    
    if (!CGRectEqualToRect(frame, _layerFrame) || mag!=_layerMagnification) {
        _layerFrame = frame;
        _layerMagnification = mag;
        [_layer setFrame:_layerFrame];
        [_layer setTranslation:_layerFrame.origin magnification:_layerMagnification];
        [_layer setNeedsDisplay];
    }
}

@end

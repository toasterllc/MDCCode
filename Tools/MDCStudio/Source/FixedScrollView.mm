#import "FixedScrollView.h"
#import <algorithm>
#import <cmath>
#import <optional>

@interface FixedScrollView_ClipView : NSClipView {
@public
    __weak FixedScrollView* fixedScrollView;
}
@end

@interface FixedScrollView_DocView : NSView {
@public
    __weak FixedScrollView* fixedScrollView;
}
@end

@implementation FixedScrollView {
@public
    NSView<FixedScrollViewDocument>* _doc;
    CGRect _docFrame;
    CGFloat _docMagnification;
    
    struct {
        bool enabled = true;
        bool liveResizeUnderway = false;
        CGPoint document = {};
        CGPoint screen = {};
    } _anchor;
    
    bool _magnifyToFit;
    std::optional<CGFloat> _modelMagnification;
    
    struct {
        struct {
            bool phase = false;
            bool momentumPhase = false;
        } scrollWheel;
        
        bool magnify = false;
    } _interactionUnderway;
    
    struct {
        NSTimer* magnifyToFitTimer = nil;
        bool magnify = false;
        bool pan = false;
    } _scrollWheel;
    id _docViewFrameChangedObserver;
}

- (instancetype)initWithFixedDocument:(NSView<FixedScrollViewDocument>*)doc {
    NSParameterAssert(doc);
    if (!(self = [super initWithFrame:{}])) return nil;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_liveMagnifyStarted)
        name:NSScrollViewDidEndLiveMagnifyNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_liveMagnifyEnded)
        name:NSScrollViewDidEndLiveMagnifyNotification object:nil];
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _doc = doc;
    
    FixedScrollView_ClipView* clipView = [[FixedScrollView_ClipView alloc] initWithFrame:{}];
    clipView->fixedScrollView = self;
    [self setContentView:clipView];
    
    FixedScrollView_DocView* docView = [[FixedScrollView_DocView alloc] initWithFrame:{}];
    docView->fixedScrollView = self;
    [self setDocumentView:docView];
    
    [docView addSubview:_doc];
    if ([_doc respondsToSelector:@selector(fixedCreateConstraintsForContainer:)]) {
        [_doc fixedCreateConstraintsForContainer:docView];
    }
    
    // Observe document frame changes so we can update our magnification if we're in magnify-to-fit mode
    __weak auto selfWeak = self;
    _docViewFrameChangedObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
        object:docView queue:nil usingBlock:^(NSNotification*) {
        [selfWeak _docViewFrameChanged];
    }];
    
    [self setScrollerStyle:NSScrollerStyleOverlay];
    [self setBorderType:NSNoBorder];
    [self setHasHorizontalScroller:true];
    [self setHasVerticalScroller:true];
    [self setAllowsMagnification:true];
    [self setMinMagnification:1./(1<<16)];
    [self setMaxMagnification:1<<16];
    [self setUsesPredominantAxisScrolling:false];
    
    return self;
}

// MARK: - Methods

static bool _ShouldSnapToFitMagnification(CGFloat mag, CGFloat fitMag) {
    constexpr CGFloat Thresh = 0.15;
    return std::abs(1-(mag/fitMag)) < Thresh;
}

static CGFloat _NextMagnification(CGFloat mag, CGFloat fitMag, CGFloat min, CGFloat max, int direction) {
    // Thresh: if `mag` is within this threshold of the next magnification, we'll skip to the next-next magnification
    constexpr CGFloat Thresh = 0.25;
    if (direction > 0) {
        mag = std::pow(2, std::floor((std::ceil(std::log2(mag)/Thresh)*Thresh)+1));
    } else {
        mag = std::pow(2, std::ceil((std::floor(std::log2(mag)/Thresh)*Thresh)-1));
    }
    
    mag = _ShouldSnapToFitMagnification(mag, fitMag) ? fitMag : mag;
    mag = std::clamp(mag, min, max);
    return mag;
}

- (NSView<FixedScrollViewDocument>*)document {
    return _doc;
}

- (void)setAnchorDuringResize:(bool)anchorDuringResize {
    _anchor.enabled = anchorDuringResize;
}

- (void)scrollToCenter {
    NSView*const dv = [self documentView];
    const CGSize scrollSize = [self bounds].size;
    const CGSize dvSize = [dv bounds].size;
    const CGPoint dvPoint = {
        dvSize.width/2 - scrollSize.width/2,
        dvSize.height/2 - scrollSize.height/2,
    };
    
    [dv scrollPoint:dvPoint];
}

- (bool)magnifyToFit {
    return _magnifyToFit;
}

- (void)setMagnifyToFit:(bool)magnifyToFit animate:(bool)animate {
    if (![self allowsMagnification]) return;
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
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
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
    const CGFloat mag = [self _modelMagnification];
    const CGFloat fitMag = [self _fitMagnification];
    [self setMagnifyToFit:_ShouldSnapToFitMagnification(mag, fitMag) animate:true];
}

- (IBAction)magnifyIncrease:(id)sender {
    if (![self allowsMagnification]) return;
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
    const CGFloat fitMag = [self _fitMagnification];
    const CGFloat curMag = [self _modelMagnification];
    const CGFloat nextMag = _NextMagnification(curMag, fitMag, [self minMagnification], [self maxMagnification], 1);
    [self _setAnimatedMagnification:nextMag snapToFit:true];
}

- (IBAction)magnifyDecrease:(id)sender {
    if (![self allowsMagnification]) return;
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
    const CGFloat fitMag = [self _fitMagnification];
    const CGFloat curMag = [self _modelMagnification];
    const CGFloat nextMag = _NextMagnification(curMag, fitMag, [self minMagnification], [self maxMagnification], -1);
    [self _setAnimatedMagnification:nextMag snapToFit:true];
}

- (IBAction)magnifyToFit:(id)sender {
    if (![self allowsMagnification]) return;
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
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

- (void)_updateMagnifyInteractionUnderway:(bool)magnify animatedMagnify:(bool)animatedMagnify {
    
}

- (void)_liveMagnifyStarted {
    printf("_liveMagnifyStarted\n");
    [self _updateMagnifyInteractionUnderway:true];
}

- (void)_liveMagnifyEnded {
    [self magnifySnapToFit];
}

- (void)_docViewFrameChanged {
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

- (bool)_interactionUnderway {
    return _interactionUnderway.scrollWheel.phase || _interactionUnderway.scrollWheel.momentumPhase;
}

std::optional<bool> _BoolOptionalForEventPhase(NSEventPhase x) {
    if (x & NSEventPhaseBegan) return true;
    else if (x & (NSEventPhaseEnded|NSEventPhaseCancelled)) return false;
    return std::nullopt;
}

- (void)_updateScrollWheelInteractionUnderway:(NSEventPhase)phase momentumPhase:(NSEventPhase)momentumPhase {
    bool interactionUnderwayPrev = [self _interactionUnderway];
    
    std::optional<bool> p = _BoolOptionalForEventPhase(phase);
    std::optional<bool> mp = _BoolOptionalForEventPhase(momentumPhase);
    
    if (p) _interactionUnderway.scrollWheel.phase = *p;
    if (mp) _interactionUnderway.scrollWheel.momentumPhase = *mp;
    
    if ([self _interactionUnderway] != interactionUnderwayPrev) {
        if ([_doc respondsToSelector:@selector(fixedInteractionUnderway:)]) {
            [_doc fixedInteractionUnderway:[self _interactionUnderway]];
        }
    }
    
//    if (phase || momentumPhase) {
//        
//    }
//    
//    if (phase & NSEventPhaseBegan)
//        _scrollWheelInteractionUnderway.phase = true;
//    else if (phase & (NSEventPhaseEnded|NSEventPhaseCancelled))
//        _scrollWheelInteractionUnderway.phase = false;
//    
//    bool x = plase
//    
//    _interactionUnderway 
//    
//    _interactionUnderway = x;
//    printf("_setInteractionUnderway = %d\n", _interactionUnderway);
//    if ([_doc respondsToSelector:@selector(fixedInteractionUnderway:)]) {
//        [_doc fixedInteractionUnderway:_interactionUnderway];
//    }
}

// MARK: - NSView Overrides

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    
    NSView*const dv = [self documentView];
    NSClipView*const cv = [self contentView];
    
    if (_anchor.enabled && _anchor.liveResizeUnderway) {
        // Keep the content anchored
        // This keeps the content in place when resizing the containing window, which looks better
        NSWindow* win = [self window];
        
        const CGPoint anchorPointWant = _anchor.document;
        const CGPoint anchorPointHave = [dv convertPoint:[win convertPointFromScreen:_anchor.screen] fromView:nil];
        const CGPoint delta = {
            anchorPointWant.x-anchorPointHave.x,
            anchorPointWant.y-anchorPointHave.y,
        };
        
        CGRect bounds = [cv bounds];
        bounds.origin.x += delta.x;
        bounds.origin.y += delta.y;
        bounds = [cv constrainBoundsRect:bounds];
        
        [self scrollClipView:cv toPoint:bounds.origin];
    }
    
    [self setMagnifyToFit:_magnifyToFit animate:false];
    [self reflectScrolledClipView:cv];
}

- (void)viewWillStartLiveResize {
    _anchor.liveResizeUnderway = true;
    [super viewWillStartLiveResize];
    _anchor.document = [self documentVisibleRect].origin;
    _anchor.screen = [[self window] convertPointToScreen:
        [[self documentView] convertPoint:_anchor.document toView:nil]];
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [self magnifySnapToFit];
    _anchor.liveResizeUnderway = false;
}

- (void)smartMagnifyWithEvent:(NSEvent*)event {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        [super smartMagnifyWithEvent:event];
    } completionHandler:^{
        [self magnifySnapToFit];
    }];
}

// MARK: - NSScrollView Overrides

//- (void)setMagnification:(CGFloat)mag centeredAtPoint:(NSPoint)point {
//    [super setMagnification:mag centeredAtPoint:point];
//    
//    _anchorPointDocument = [[self documentView] convertPoint:point fromView:[self contentView]];
//    _anchorPointScreen = [[self window] convertPointToScreen:
//        [[self documentView] convertPoint:_anchorPointDocument toView:nil]];
//    
//}

- (void)_scrollWheelReset {
    [_scrollWheel.magnifyToFitTimer invalidate];
    _scrollWheel = {};
}

// Disable NSScrollView legacy 'responsive scrolling' by merely overriding -scrollWheel:
// We don't want this behavior because it causes strange flashes and artifacts when
// scrolling quickly, especially when scrolling near the margin
- (void)scrollWheel:(NSEvent*)event {
    const NSEventPhase phase = [event phase];
//    printf("FixedScrollView scrollWheel:\n");
    if (phase & NSEventPhaseBegan) {
        [self _scrollWheelReset];
        
        if (([event modifierFlags]&NSEventModifierFlagCommand) && ([self allowsMagnification])) {
            _scrollWheel.magnify = true;
        } else {
            _scrollWheel.pan = true;
        }
    }
    
    if (_scrollWheel.magnify) {
        [self _scrollWheelMagnify:event];
    
    } else if (_scrollWheel.pan) {
        [super scrollWheel:event];
    }
    
    [self _updateScrollWheelInteractionUnderway:phase momentumPhase:[event momentumPhase]];
    
//    const NSEventPhase momentumPhase = [event momentumPhase];
//    if (momentumPhase != NSEventPhaseNone) {
//        if (momentumPhase & NSEventPhaseBegan) {
//            printf("momentumPhase BEGAN\n");
//        } else if (momentumPhase & (NSEventPhaseEnded|NSEventPhaseCancelled)) {
//            printf("momentumPhase ENDED\n");
//        }
//    
//    } else {
//        if (phase & NSEventPhaseBegan) {
//            printf("phase BEGAN\n");
//        } else if (momentumPhase & (NSEventPhaseEnded|NSEventPhaseCancelled)) {
//            printf("phase ENDED\n");
//        }
//    }
    
    
//    if (phase & NSEventPhaseBegan) {
//        [self _setInteractionUnderway:true];
//    } else if (phase & (NSEventPhaseEnded|NSEventPhaseCancelled)) {
//        [self _setInteractionUnderway:false];
//    }
}

- (void)_scrollWheelMagnify:(NSEvent*)event {
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
    // TODO: we need to determine the '22' dynamically, because window titlebar heights aren't always 22pt (eg when there's a toolbar it's ~150pt)
    const CGFloat heightExtra = 22/mag; // Expand the height to get the NSWindow titlebar mirror effect
    const CGRect visibleRect = [doc visibleRect];//[doc convertRectToLayer:[doc visibleRect]];
    
    CGRect docFrame = visibleRect;
    if ([doc isFlipped]) {
        docFrame.origin.y -= heightExtra;
        docFrame.size.height += heightExtra;
    } else {
        docFrame.size.height += heightExtra;
    }
    
    if (!CGRectEqualToRect(docFrame, _docFrame) || mag!=_docMagnification) {
        _docFrame = docFrame;
        _docMagnification = mag;
        [_doc setFrame:_docFrame];
        [_doc fixedTranslationChanged:_docFrame.origin magnification:_docMagnification];
    }
}

// _magnificationInflectionPoints: private NSScrollView method that controls
// the magnifications points where increased resistance occurs, such that
// crossing these points requires more effort.
// We don't like the feel of it so we disable this resistance here.
- (NSArray*)_magnificationInflectionPoints {
    return @[];
}

@end

@implementation FixedScrollView_ClipView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (NSRect)constrainBoundsRect:(NSRect)bounds {
    bounds = [super constrainBoundsRect:bounds];
    
    const CGSize docSize = [[self documentView] frame].size;
    if (bounds.size.width >= docSize.width) {
        bounds.origin.x = (docSize.width-bounds.size.width)/2;
    }
    if (bounds.size.height >= docSize.height) {
        bounds.origin.y = (docSize.height-bounds.size.height)/2;
    }
    return bounds;
}

@end


@implementation FixedScrollView_DocView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    FixedScrollView* sv = fixedScrollView;
    if (!sv) return {};
    return [sv->_doc rectForSmartMagnificationAtPoint:point inRect:rect];
}

//#warning TODO: not sure how we want to handle flipping. forward message to FixedScrollView._doc? always return flipped or not flipped?
//- (BOOL)isFlipped {
//    return true;
//}

- (BOOL)isFlipped {
    FixedScrollView* sv = fixedScrollView;
    assert(sv);
    assert(sv->_doc);
    return [sv->_doc fixedFlipped];
}

@end

#import "AnchoredScrollView.h"
#import <algorithm>
#import <cmath>
#import <optional>
#import "Tools/Shared/AssertionCounter.h"

@interface AnchoredScrollView_ClipView : NSClipView {
@public
    __weak AnchoredScrollView* anchoredScrollView;
}
@end

@interface AnchoredScrollView_DocView : NSView {
@public
    __weak AnchoredScrollView* anchoredScrollView;
}
@end

@implementation AnchoredScrollView {
@public
    NSView<AnchoredScrollViewDocument>* _doc;
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
        AssertionCounter counter;
        AssertionCounter::Assertion scrollWheelUnderway;
        AssertionCounter::Assertion momentumScrollWheelUnderway;
        AssertionCounter::Assertion magnifyUnderway;
    } _interactionUnderway;
    
    NSView* _floatingSubviewContainer;
    
    struct {
        NSTimer* magnifyToFitTimer = nil;
        bool magnify = false;
        bool pan = false;
    } _scrollWheel;
    id _docViewFrameChangedObserver;
}

static NSScroller* _FirstScroller(NSView* view) {
    for (NSView* view : [view subviews]) {
        if ([view isKindOfClass:[NSScroller class]]) {
            return (NSScroller*)view;
        }
    }
    abort();
}

- (instancetype)initWithAnchoredDocument:(NSView<AnchoredScrollViewDocument>*)doc {
    NSParameterAssert(doc);
    if (!(self = [super initWithFrame:{}])) return nil;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_liveMagnifyStarted)
        name:NSScrollViewWillStartLiveMagnifyNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_liveMagnifyEnded)
        name:NSScrollViewDidEndLiveMagnifyNotification object:nil];
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    [self setAutomaticallyAdjustsContentInsets:false];
    
    _doc = doc;
    
    if ([_doc respondsToSelector:@selector(anchoredInteractionUnderway:)]) {
        _interactionUnderway.counter = AssertionCounter([doc] (bool underway) {
            [doc anchoredInteractionUnderway:underway];
        });
    }
    
    AnchoredScrollView_ClipView* clipView = [[AnchoredScrollView_ClipView alloc] initWithFrame:{}];
    clipView->anchoredScrollView = self;
    [self setContentView:clipView];
    
    AnchoredScrollView_DocView* docView = [[AnchoredScrollView_DocView alloc] initWithFrame:{}];
    docView->anchoredScrollView = self;
    [self setDocumentView:docView];
    
    [docView addSubview:_doc];
    if ([_doc respondsToSelector:@selector(anchoredCreateConstraintsForContainer:)]) {
        [_doc anchoredCreateConstraintsForContainer:docView];
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
    
    _floatingSubviewContainer = [[NSView alloc] initWithFrame:{}];
    [self addSubview:_floatingSubviewContainer positioned:NSWindowBelow relativeTo:_FirstScroller(self)];
    
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

- (NSView<AnchoredScrollViewDocument>*)document {
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

- (IBAction)magnifyToActualSize:(id)sender {
    if (![self allowsMagnification]) return;
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
    [self _setAnimatedMagnification:1 snapToFit:false];
}

- (IBAction)magnifyToFit:(id)sender {
    if (![self allowsMagnification]) return;
    [self _scrollWheelReset]; // Prevent further momentum scrolls from affecting us (until the start of the next scroll)
    
    [self setMagnifyToFit:true animate:true];
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

- (void)_setAnimatedMagnification:(CGFloat)mag snapToFit:(bool)snapToFit {
    const CGFloat curMag = [self _modelMagnification];
    if (mag == curMag) return;
    
    _modelMagnification = mag;
    
    auto interaction = _interactionUnderway.counter.assertion();
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext*) {
        [[self animator] setMagnification:mag];
    
    } completionHandler:^{
        if (!self->_modelMagnification || self->_modelMagnification!=mag) return;
        self->_modelMagnification = std::nullopt;
        if (snapToFit) {
            [self magnifySnapToFit];
        }
        (void)interaction; // Ensure that block captures assertion
    }];
}

- (void)_liveMagnifyStarted {
    _interactionUnderway.magnifyUnderway = _interactionUnderway.counter.assertion();
}

- (void)_liveMagnifyEnded {
    [self magnifySnapToFit];
    _interactionUnderway.magnifyUnderway = nullptr;
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
    CGSize containerSize = [self bounds].size;
    const NSEdgeInsets contentInsets = [self contentInsets];
    containerSize.width -= contentInsets.left + contentInsets.right;
    containerSize.height -= contentInsets.top + contentInsets.bottom;
    
    const CGFloat contentAspect = contentSize.width/contentSize.height;
    const CGFloat containerAspect = containerSize.width/containerSize.height;
    
    const CGFloat contentAxisSize = (contentAspect>containerAspect ? contentSize.width : contentSize.height);
    const CGFloat containerAxisSize = (contentAspect>containerAspect ? containerSize.width : containerSize.height);
    
    const CGFloat fitMag = containerAxisSize/contentAxisSize;
    return fitMag;
}

static bool _EventPhaseChanged(NSEventPhase x) {
    if (x & (NSEventPhaseBegan|NSEventPhaseEnded|NSEventPhaseCancelled)) return true;
    return false;
}

- (void)_updateScrollWheelInteractionUnderway:(NSEventPhase)phase momentumPhase:(NSEventPhase)momentumPhase {
    if (_EventPhaseChanged(phase)) {
        if (phase & NSEventPhaseBegan) {
            _interactionUnderway.scrollWheelUnderway = _interactionUnderway.counter.assertion();
        } else {
            _interactionUnderway.scrollWheelUnderway = nullptr;
        }
    }
    
    if (_EventPhaseChanged(momentumPhase)) {
        if (momentumPhase & NSEventPhaseBegan) {
            _interactionUnderway.momentumScrollWheelUnderway = _interactionUnderway.counter.assertion();
        } else {
            _interactionUnderway.momentumScrollWheelUnderway = nullptr;
        }
    }
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
    auto interaction = _interactionUnderway.counter.assertion();
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        [super smartMagnifyWithEvent:event];
    } completionHandler:^{
        [self magnifySnapToFit];
        (void)interaction; // Ensure that block captures the assertion
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
//    printf("AnchoredScrollView scrollWheel:\n");
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

//- (void)setContentInsets:(NSEdgeInsets)x {
//    NSLog(@"MEOWMIX -setContentInsets");
//    [super setContentInsets:x];
//}

//static CGRect _CGRectInset(CGRect rect, NSEdgeInsets inset) {
//    // Left/right
//    rect.origin.x += inset.left;
//    rect.size.width -= inset.left + inset.right;
//    
//    // Top/bottom
//    rect.origin.y += inset.top;
//    rect.size.height -= inset.top + inset.bottom;
//    
//    return rect;
//}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    
    NSView* doc = [self documentView];
    const CGFloat mag = [self _presentationMagnification];
    // TODO: we need to determine the '22' dynamically, because window titlebar heights aren't always 22pt (eg when there's a toolbar it's ~150pt)
    const CGFloat heightExtra = 22/mag; // Expand the height to get the NSWindow titlebar mirror effect
    CGRect docFrame = [self documentVisibleRect];
    
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
        [_doc anchoredTranslationChanged:_docFrame.origin magnification:_docMagnification];
    }
}

- (void)setContentInsets:(NSEdgeInsets)x {
    [super setContentInsets:x];
    [super setScrollerInsets:{-x.top, -x.left, -x.bottom, -x.right}];
}

// _magnificationInflectionPoints: private NSScrollView method that controls
// the magnifications points where increased resistance occurs, such that
// crossing these points requires more effort.
// We don't like the feel of it so we disable this resistance here.
- (NSArray*)_magnificationInflectionPoints {
    return @[];
}

// MARK: - Floating Subviews

- (NSView*)floatingSubviewContainer {
    return _floatingSubviewContainer;
}

- (void)tile {
    [super tile];
    // NSScrollView apparently inhibits autolayout on its direct subviews, so we have
    // to set _floatingSubviewContainer's frame directly.
    [_floatingSubviewContainer setFrame:[self bounds]];
}

@end

@implementation AnchoredScrollView_ClipView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (NSRect)constrainBoundsRect:(NSRect)bounds {
    bounds = [super constrainBoundsRect:bounds];
    
    const bool flipped = [[self documentView] isFlipped];
    const CGSize docSize = [[self documentView] frame].size;
    const NSEdgeInsets contentInsets = [self contentInsets];
    const CGFloat xinset = contentInsets.left + contentInsets.right;
    const CGFloat yinset = contentInsets.top + contentInsets.bottom;
    const CGFloat xexcess = (bounds.size.width-xinset) - docSize.width;
    const CGFloat yexcess = (bounds.size.height-yinset) - docSize.height;
    
    if (xexcess > 0) bounds.origin.x = -(contentInsets.left + xexcess/2);
    
    if (flipped) {
        if (yexcess > 0) bounds.origin.y = -(contentInsets.top + yexcess/2);
    } else {
        if (yexcess > 0) bounds.origin.y = -(contentInsets.bottom + yexcess/2);
    }
    
    return bounds;
}

@end


@implementation AnchoredScrollView_DocView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    AnchoredScrollView* sv = anchoredScrollView;
    if (!sv) return {};
    return [sv->_doc rectForSmartMagnificationAtPoint:point inRect:rect];
}

- (BOOL)isFlipped {
    AnchoredScrollView* sv = anchoredScrollView;
    assert(sv);
    assert(sv->_doc);
    return [sv->_doc anchoredFlipped];
}

@end

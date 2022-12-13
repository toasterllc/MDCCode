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
    NSLayoutConstraint* _contentWidth;
    NSLayoutConstraint* _contentHeight;
    NSView<FixedScrollViewDocument>* _doc;
    CGRect _docFrame;
    CGFloat _docMagnification;
    CGPoint _anchorPointDocument;
    CGPoint _anchorPointScreen;
    bool _magnifyToFit;
    std::optional<CGFloat> _modelMagnification;
    struct {
        NSTimer* magnifyToFitTimer = nil;
        bool magnify = false;
        bool pan = false;
    } _scrollWheel;
    id _documentViewFrameChangedObserver;
}

static void _InitCommon(FixedScrollView* self) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_liveMagnifyEnded)
        name:NSScrollViewDidEndLiveMagnifyNotification object:nil];
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    FixedScrollView_ClipView* clipView = [[FixedScrollView_ClipView alloc] initWithFrame:{}];
    clipView->fixedScrollView = self;
    [self setContentView:clipView];
    
    FixedScrollView_DocView* docView = [[FixedScrollView_DocView alloc] initWithFrame:{}];
    docView->fixedScrollView = self;
    [self setDocumentView:docView];
    
    [self setScrollerStyle:NSScrollerStyleOverlay];
    [self setBorderType:NSNoBorder];
    [self setHasHorizontalScroller:true];
    [self setHasVerticalScroller:true];
    [self setAllowsMagnification:true];
    [self setMinMagnification:1./(2*2*2*2)];
    [self setMaxMagnification:2*2*2*2];
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _InitCommon(self);
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _InitCommon(self);
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

- (void)setFixedDocument:(NSView<FixedScrollViewDocument>*)doc {
    NSView* documentView = [self documentView];
    if (_contentWidth) {
        [documentView removeConstraint:_contentWidth];
        [documentView removeConstraint:_contentHeight];
        _contentWidth = nil;
        _contentHeight = nil;
    }
    
    [_doc removeFromSuperview];
    
    _doc = doc;
    if (!_doc) return;
    
    [documentView addSubview:_doc];
    
    const CGSize contentSize = [_doc fixedContentSize];
    _contentWidth = [NSLayoutConstraint constraintWithItem:documentView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:1 constant:contentSize.width];
    _contentHeight = [NSLayoutConstraint constraintWithItem:documentView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:1 constant:contentSize.height];
    [documentView addConstraint:_contentWidth];
    [documentView addConstraint:_contentHeight];
    
    // Observe document frame changes so we can update our magnification if we're in magnify-to-fit mode
    __weak auto weakSelf = self;
    _documentViewFrameChangedObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
        object:documentView queue:nil usingBlock:^(NSNotification*) {
        [weakSelf _documentViewFrameChanged];
    }];
    
    [self setMagnifyToFit:true animate:false];
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

- (void)_scrollWheelReset {
    [_scrollWheel.magnifyToFitTimer invalidate];
    _scrollWheel = {};
}

// Disable NSScrollView legacy 'responsive scrolling' by merely overriding -scrollWheel
// We don't want this behavior because it causes strange flashes and artifacts when
// scrolling quickly, especially when scrolling near the margin
- (void)scrollWheel:(NSEvent*)event {
    const NSEventPhase phase = [event phase];
    
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
    const CGFloat heightExtra = 22/mag; // Expand the height to get the NSWindow titlebar mirror effect
    const CGRect visibleRect = [doc visibleRect];//[doc convertRectToLayer:[doc visibleRect]];
    
    CGRect frame = visibleRect;
    if ([doc isFlipped]) {
        frame.origin.y -= heightExtra;
        frame.size.height += heightExtra;
    } else {
        frame.size.height += heightExtra;
    }
    
    if (!CGRectEqualToRect(frame, _docFrame) || mag!=_docMagnification) {
        _docFrame = frame;
        _docMagnification = mag;
        [_doc setFrame:_docFrame];
        [_doc setFixedTranslation:_docFrame.origin magnification:_docMagnification];
    }
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

#warning TODO: not sure how we want to handle flipping. forward message to FixedScrollView._doc? always return flipped or not flipped?
- (BOOL)isFlipped {
    return true;
}

//- (BOOL)isFlipped {
//    FixedScrollView* sv = fixedScrollView;
//    if (!sv) return false;
//    return [sv->_doc fixedFlipped];
//}

@end

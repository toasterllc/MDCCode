#import "LayerScrollView.h"
#import <algorithm>

@implementation LayerScrollView {
    CALayer<LayerScrollViewLayer>* _layer;
    CGRect _layerFrame;
    CGFloat _layerMagnification;
    CGPoint _anchorPointDocument;
    CGPoint _anchorPointScreen;
    bool _magnifyToFit;
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
//    [rootLayer setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.1] CGColor]];
    
    NSView* documentView = [self documentView];
    [documentView setTranslatesAutoresizingMaskIntoConstraints:false];
//    [documentView addConstraint:[NSLayoutConstraint constraintWithItem:documentView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:100]];
//    [documentView addConstraint:[NSLayoutConstraint constraintWithItem:documentView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:100]];
    [documentView setLayer:rootLayer];
    [documentView setWantsLayer:true];
    [documentView setFrameSize:[_layer preferredFrameSize]];
    
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
    [self magnifyToFit];
    
//    NSClipView* clip = [self contentView];
//    CGRect bounds = [clip bounds];
//    [super scrollClipView:clip toPoint:bounds.origin];
//    [self reflectScrolledClipView:clip];
//    
////    [self setFrame:[self frame]];
//    
////    [self tile];
////    [self setMagnification:.75];
////    [self setMagnification:1.5];
//    [self setMagnification:.75];
//    [self setFrame:[self frame]];
    
//    [self reflectScrolledClipView:[self contentView]];
//    [self scrollClipView:[self contentView] toPoint:{}];
    
//    [self magnifyToFit];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        [self magnifyToFit];
////        [self setMagnification:2];
//    }];
    
//    [[self contentView] scrollToPoint:{}];
//    [self setMagnification:2];
//    
//    [self sizeToFit];
//    [self magnifyToFit];
}

- (void)magnifyToFit {
    [self _setMagnifyToFit:true];
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

- (void)_setMagnifyToFit:(bool)magnifyToFit {
    [self _setMagnifyToFit:magnifyToFit animate:false];
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

- (void)_liveMagnifyEnded {
    [self magnifyToFitIfNeeded];
}

//- (void)_magnifyToFit {
//    NSClipView* clip = [self contentView];
//    NSView* doc = [self documentView];
////    NSLog(@"magnifyToFitRect: %@ ", NSStringFromRect([clip convertRect:[doc bounds] fromView:doc]));
//    [self magnifyToFitRect:[clip convertRect:[doc bounds] fromView:doc]];
//}

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
    
    [super scrollClipView:clip toPoint:bounds.origin];
    [self _setMagnifyToFit:_magnifyToFit];
    [self reflectScrolledClipView:clip];
}

//- (void)layout {
//    [super layout];
//    [[self documentView] setFrameSize:[_layer preferredFrameSize]];
////    NSLog(@"MEOWMIX LAYOUT");
//}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

//- (void)viewDidMoveToSuperview {
//    NSLog(@"viewDidMoveToSuperview");
//}
//
//- (void)viewDidMoveToWindow {
//    [self magnifyToFit];
//    NSLog(@"viewDidMoveToWindow");
//}

- (void)viewWillStartLiveResize {
    [super viewWillStartLiveResize];
    _anchorPointDocument = [self documentVisibleRect].origin;
    _anchorPointScreen = [[self window] convertPointToScreen:
        [[self documentView] convertPoint:_anchorPointDocument toView:nil]];
}

- (void)viewDidEndLiveResize {
    [self magnifyToFitIfNeeded];
}

// MARK: - NSScrollView Overrides

//- (void)tile {
//    [super tile];
//    if (_layer) {
//        const CGSize frameSize = [_layer preferredFrameSize];
//        if (frameSize.width>1 && frameSize.height>1) {
//            printf("MEOWMIX setFrameSize: %f %f\n", frameSize.width, frameSize.height);
//            [[self documentView] setFrameSize:frameSize];
//        }
//    }
//}

- (void)setMagnification:(CGFloat)mag {
    [self _setMagnifyToFit:false];
    [super setMagnification:mag];
}

- (void)setMagnification:(CGFloat)mag centeredAtPoint:(NSPoint)point {
    [self _setMagnifyToFit:false];
    [super setMagnification:mag centeredAtPoint:point];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    [self _setMagnifyToFit:false];
    [super magnifyWithEvent:event];
}

- (void)smartMagnifyWithEvent:(NSEvent*)event {
    [self _setMagnifyToFit:false];
    [super smartMagnifyWithEvent:event];
}

// Disable NSScrollView responsive scrolling by overriding -scrollWheel
- (void)scrollWheel:(NSEvent*)event {
    [super scrollWheel:event];
}

- (void)scrollClipView:(NSClipView*)clipView toPoint:(NSPoint)point {
    // If we're live-resize is underway, prevent the scroll elasticity animation from scrolling,
    // otherwise we get a very jittery animation.
    // This doesn't fully fix the problem, because the live resize can end before the elasticity
    // animation ends, but it works well enough.
    if ([self inLiveResize]) return;
    [super scrollClipView:clipView toPoint:point];
}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    NSLog(@"reflectScrolledClipView");
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

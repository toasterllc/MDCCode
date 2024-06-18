#import "MainView.h"
#import <vector>
#import <array>
#import "ImageLayer.h"
//#import "HistogramLayer.h"
#import "Util.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"

using namespace CFAViewer;

@interface MainView () <CALayoutManager, NSGestureRecognizerDelegate>
@end

@implementation MainView {
    CALayer* _viewLayer;
    CALayer* _rootLayer;
    CGPoint _rootLayerOffset;
    ImageLayer* _imageLayer;
    CALayer* _sampleLayer;
    
    CGFloat _colorCheckerCircleRadius;
    bool _colorCheckersEnabled;
    std::array<CAShapeLayer*,ColorChecker::Count> _colorCheckers;
    ColorCheckerPositions _colorCheckerPositions;
    
    id<MainViewDelegate> _delegate;
    
    CGFloat _zoomScale;
    struct {
        struct {
            CGFloat startZoomScale;
            CGFloat multiplier;
        } magnify;
        
        struct {
            bool pan;
        } panZoom;
    } _gesture;
}

- (void)commonInit {
    [super commonInit];
    _viewLayer = [self layer];
    
    _rootLayer = [CALayer new];
    [_rootLayer setActions:LayerNullActions()];
    [_viewLayer addSublayer:_rootLayer];
    [_viewLayer setLayoutManager:self];
    
    _colorCheckerCircleRadius = 1;
    _imageLayer = [ImageLayer new];
    [_imageLayer setMagnificationFilter:kCAFilterNearest];
    [_rootLayer addSublayer:_imageLayer];
    [_rootLayer setLayoutManager:self];
    
    _sampleLayer = [CALayer new];
    [_sampleLayer setActions:LayerNullActions()];
    [_sampleLayer setBorderColor:(CGColorRef)SRGBColor(1, 0, 0, 1)];
    [_sampleLayer setBorderWidth:1];
    [_imageLayer addSublayer:_sampleLayer];
    
    // Create our color checker circles if they don't exist yet
    size_t i = 0;
    for (const auto& c : ColorChecker::Colors) {
        CAShapeLayer* circle = [CAShapeLayer new];
        setCircleRadius(circle, _colorCheckerCircleRadius);
        [circle setFillColor:(CGColorRef)SRGBColor(c[0], c[1], c[2], 1)];
        [circle setActions:LayerNullActions()];
        [circle setHidden:!_colorCheckersEnabled];
        [_imageLayer addSublayer:circle];
        _colorCheckers[i] = circle;
        
        i++;
    }
    
    [self resetColorCheckerPositions];
    
    NSMagnificationGestureRecognizer* magnify = [[NSMagnificationGestureRecognizer alloc] initWithTarget:self
        action:@selector(_handleMagnify:)];
    [magnify setDelegate:self];
    [self addGestureRecognizer:magnify];
    
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    
    [self reset];
}

// MARK: - Public Methods

- (void)reset {
    [_sampleLayer setFrame:CGRectNull];
    [self _setZoomScale:[[NSScreen mainScreen] backingScaleFactor]*.75 anchor:{0,0}];
}

- (ImageLayer*)imageLayer {
    return _imageLayer;
}

- (void)setDelegate:(id<MainViewDelegate>)delegate {
    _delegate = delegate;
}

- (CGRect)sampleRect {
    const CGSize imageLayerSize = [_imageLayer bounds].size;
    CGRect r = [_sampleLayer frame];
    r.origin.x /= imageLayerSize.width;
    r.origin.y /= imageLayerSize.height;
    r.size.width /= imageLayerSize.width;
    r.size.height /= imageLayerSize.height;
    r.origin.y = 1-r.origin.y-r.size.height; // Flip Y so the origin is at the top-left
    return r;
}

- (const ColorCheckerPositions&)colorCheckerPositions {
    return _colorCheckerPositions;
}

- (void)setColorCheckerPositions:(const ColorCheckerPositions&)x {
    _colorCheckerPositions = x;
}

static ColorCheckerPositions _ColorCheckerPositionsDefault() {
    // indoor_night2_200.cfa
    return {
        CGPoint{ 0.83571870285304372, 0.78818759720487419 },
        CGPoint{ 0.84938996133631395, 0.78947454825661023 },
        CGPoint{ 0.86338489110272809, 0.78952227858407853 },
        CGPoint{ 0.87698007937659594, 0.79034872036524129 },
        CGPoint{ 0.89073895956633309, 0.79166653106380491 },
        CGPoint{ 0.90420675086084356, 0.79129537186002796 },
        CGPoint{ 0.83532045293323065, 0.813978768041828   },
        CGPoint{ 0.84919257654459634, 0.81429431854009027 },
        CGPoint{ 0.86342566075744064, 0.81588002608597932 },
        CGPoint{ 0.87703725633137553, 0.81600995864408721 },
        CGPoint{ 0.89067023111448895, 0.81624330691170965 },
        CGPoint{ 0.90464427886263587, 0.81645986117522296 },
        CGPoint{ 0.83499827322282016, 0.83954189398087808 },
        CGPoint{ 0.8499120117929978,  0.84054776643752338 },
        CGPoint{ 0.86379059888620813, 0.84136094979438958 },
        CGPoint{ 0.87715310181366812, 0.84156159394874674 },
        CGPoint{ 0.89120321977121763, 0.84132912957607741 },
        CGPoint{ 0.90458511314421153, 0.84126814082431245 },
        CGPoint{ 0.83514643611433614, 0.8672537685509516  },
        CGPoint{ 0.84932134899057832, 0.86678265254094122 },
        CGPoint{ 0.86373342193142844, 0.86688695214540878 },
        CGPoint{ 0.87737037424183084, 0.8672537685509516  },
        CGPoint{ 0.89144684331766988, 0.8664503080385697  },
        CGPoint{ 0.90475813558128393, 0.86654842037836555 },
    };
    
    // outdoor_5pm_78.cfa
    return {
        CGPoint{ 0.83120797838401839, 0.81579079598887339 },
        CGPoint{ 0.8445072520134923,  0.82021772861811726 },
        CGPoint{ 0.85811871133799478, 0.82424906301240741 },
        CGPoint{ 0.87244664905918201, 0.82846877751858017 },
        CGPoint{ 0.8869058188871568,  0.83359996195070862 },
        CGPoint{ 0.90144486912795885, 0.83825439979199545 },
        CGPoint{ 0.82783588381395623, 0.84146120892735277 },
        CGPoint{ 0.84152477823252603, 0.84561716401104225 },
        CGPoint{ 0.85571170257188567, 0.85127581275644226 },
        CGPoint{ 0.86964186844144364, 0.85431163071332139 },
        CGPoint{ 0.88388177468727025, 0.86023256253757352 },
        CGPoint{ 0.89816325135201724, 0.86504639893506885 },
        CGPoint{ 0.82415730929263886, 0.86581585923822058 },
        CGPoint{ 0.83821707705647763, 0.86982111023240383 },
        CGPoint{ 0.85304304469845482, 0.8760883716469634  },
        CGPoint{ 0.86603094773915335, 0.88148908454686258 },
        CGPoint{ 0.8802871561100467,  0.88569141011963082 },
        CGPoint{ 0.89444555173053941, 0.89045742695026353 },
        CGPoint{ 0.82131666399975356, 0.88816063866307815 },
        CGPoint{ 0.8349851807619898,  0.89529299951451446 },
        CGPoint{ 0.84887459131888087, 0.90029811417945992 },
        CGPoint{ 0.86284469739485247, 0.90557130823439225 },
        CGPoint{ 0.87659390967616923, 0.91129806363562682 },
        CGPoint{ 0.89101558461649033, 0.91726391687117403 },
    };

    
    const size_t ColorCheckerWidth = 6;
    const size_t ColorCheckerHeight = 4;
    const CGFloat ColorCheckerSpacingX = 30./2304;
    const CGFloat ColorCheckerSpacingY = 30./1296;
    ColorCheckerPositions r;
    size_t i = 0;
    for (size_t y=0; y<ColorCheckerHeight; y++) {
        for (size_t x=0; x<ColorCheckerWidth; x++, i++) {
            r[i] = CGPoint{
                .9 + x*ColorCheckerSpacingX,
                .8 + y*ColorCheckerSpacingY
            };
        }
    }
    return r;
}

- (void)resetColorCheckerPositions {
    _colorCheckerPositions = _ColorCheckerPositionsDefault();
    [_rootLayer setNeedsLayout];
}

static void setCircleRadius(CAShapeLayer* c, CGFloat r) {
    [c setPath:(CGPathRef)CFBridgingRelease(CGPathCreateWithEllipseInRect({0,0,r*2,r*2}, nil))];
    [c setBounds:{0,0,r*2,r*2}];
}

- (void)setColorCheckerCircleRadius:(CGFloat)r {
    _colorCheckerCircleRadius = r;
    for (CAShapeLayer* c : _colorCheckers) {
        setCircleRadius(c, _colorCheckerCircleRadius);
    }
}

- (void)setColorCheckersVisible:(bool)visible {
    _colorCheckersEnabled = visible;
    for (CAShapeLayer* circle : _colorCheckers) {
        [circle setHidden:!_colorCheckersEnabled];
    }
}

// MARK: - Private Methods

- (void)_setZoomScale:(CGFloat)zoomScale anchor:(CGPoint)anchor {
    const CGFloat MinScale = 0.015625;
    const CGFloat MaxScale = 200;
    
    _zoomScale = std::clamp(zoomScale, MinScale, MaxScale);
    
    CGPoint anchorBefore = [_viewLayer convertPoint:anchor fromLayer:_rootLayer];
    [_rootLayer setTransform:CATransform3DMakeScale(_zoomScale, _zoomScale, 1)];
    CGPoint anchorAfter = [_viewLayer convertPoint:anchor fromLayer:_rootLayer];
    
    // Adjust the position of `_rootLayer` so that the anchor point stays in the same position
    _rootLayerOffset = {_rootLayerOffset.x+anchorBefore.x-anchorAfter.x, _rootLayerOffset.y+anchorBefore.y-anchorAfter.y};
//    [rootLayer setNeedsLayout];
//    [_viewLayer layoutIfNeeded];
    [_viewLayer setNeedsLayout];
//    CGRect frame = [_rootLayer frame];
//    frame.origin.x -= anchorAfter.x-anchorBefore.x;
//    frame.origin.y -= anchorAfter.y-anchorBefore.y;
//    [_rootLayer setFrame:frame];
}

- (void)_handleMagnify:(NSMagnificationGestureRecognizer*)recognizer {
    if ([recognizer state] == NSGestureRecognizerStateBegan) {
        _gesture.magnify.startZoomScale = _zoomScale;
        _gesture.magnify.multiplier = .5;
        if ([recognizer magnification] > 0) {
            _gesture.magnify.multiplier *= 20;
        }
    }
    
    CGFloat k = 1+(_gesture.magnify.multiplier*[recognizer magnification]);
    CGPoint anchor = [_rootLayer convertPoint:[recognizer locationInView:self] fromLayer:_viewLayer];
    [self _setZoomScale:k*_gesture.magnify.startZoomScale anchor:anchor];
}

// `p` is in coordinates of _layer
- (std::optional<size_t>)_colorCheckerHitTest:(CGPoint)p {
    const CGSize imageLayerSize = [_imageLayer bounds].size;
    size_t i = 0;
    for (CGPoint cp : _colorCheckerPositions) {
        cp.x = cp.x*imageLayerSize.width;
        cp.y = (1-cp.y)*imageLayerSize.height;
        if (sqrt(pow(cp.x-p.x,2)+pow(cp.y-p.y,2)) < _colorCheckerCircleRadius) {
            return i;
        }
        i++;
    }
    return std::nullopt;
}

- (void)_colorChecker:(size_t)i setPosition:(CGPoint)p {
    const CGSize imageLayerSize = [_imageLayer bounds].size;
    [_colorCheckers[i] setPosition:p];
    _colorCheckerPositions.at(i) = CGPoint{p.x/imageLayerSize.width, 1-(p.y/imageLayerSize.height)};
}

// MARK: - Overrides

static CGPoint eventPositionInLayer(NSWindow* win, CALayer* layer, NSEvent* ev) {
    // The mouse appears to be offset by 1/2 a pixel, so adjust for that
    const CGPoint off = {
        -(1/(2*[win backingScaleFactor])),
        +(1/(2*[win backingScaleFactor]))
    };
    const CGPoint pt = [layer convertPoint:[ev locationInWindow]
        fromLayer:[[win contentView] layer]];
    return {pt.x+off.x, pt.y+off.y};
}

- (void)mouseDown:(NSEvent*)ev {
    NSWindow* win = [self window];
    const CGPoint p = eventPositionInLayer(win, _imageLayer, ev);
    
    // Handle circle being clicked
    if (_colorCheckersEnabled) {
        std::optional<size_t> colorCheckerIdx = [self _colorCheckerHitTest:p];
//        CAShapeLayer* circle = [self _findColorCheckerCircle:p];
        if (colorCheckerIdx) {
            TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
                const CGPoint p = eventPositionInLayer(win, _imageLayer, ev);
                [self _colorChecker:*colorCheckerIdx setPosition:p];
            });
            
            [_delegate mainViewColorCheckerPositionsChanged:self];
            return;
        }
    }
    
    // Otherwise, handle sampler functionality
    const CGPoint start = p;
    TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
        const CGPoint end = eventPositionInLayer(win, _imageLayer, ev);
        CGRect frame = {start, {end.x-start.x, end.y-start.y}};
        if ([ev modifierFlags] & NSEventModifierFlagShift) {
            frame.size.height = (frame.size.height >= 0 ? 1 : -1) * fabs(frame.size.width);
        }
        frame = CGRectStandardize(frame);
        [_sampleLayer setFrame:frame];
    });
    [_delegate mainViewSampleRectChanged:self];
}

- (void)scrollWheel:(NSEvent*)event {
    if ([event phase] & NSEventPhaseBegan) {
        _gesture.panZoom.pan = !([event modifierFlags]&NSEventModifierFlagCommand);
    }
    
    // Pan
    if (_gesture.panZoom.pan) {
        _rootLayerOffset = {_rootLayerOffset.x+[event scrollingDeltaX]/3, _rootLayerOffset.y-[event scrollingDeltaY]/3};
        [_viewLayer setNeedsLayout];
    
    // Zoom
    } else {
        CGPoint anchor = [_rootLayer convertPoint:[self convertPoint:[event locationInWindow] fromView:nil] fromLayer:_viewLayer];
        [self _setZoomScale:_zoomScale-[event scrollingDeltaY]/100 anchor:anchor];
    }
}

- (void)layoutSublayersOfLayer:(CALayer*)layer {
    if (layer == _viewLayer) {
        CGRect bounds = [_viewLayer bounds];
        [_rootLayer setBounds:bounds];
        
        CGPoint pos = {CGRectGetMidX(bounds), CGRectGetMidY(bounds)};
        [_rootLayer setPosition:{pos.x+_rootLayerOffset.x, pos.y+_rootLayerOffset.y}];
    
    } else if (layer == _rootLayer) {
        const CGSize rootLayerSize = [_rootLayer bounds].size;
        [_imageLayer setPosition:{rootLayerSize.width/2, rootLayerSize.height/2}];
        
        const CGSize imageLayerSize = [_imageLayer bounds].size;
        size_t i = 0;
        for (CAShapeLayer* circle : _colorCheckers) {
            CGPoint p = _colorCheckerPositions[i];
            p.x = p.x*imageLayerSize.width;
            p.y = (1-p.y)*imageLayerSize.height;
            [circle setPosition:p];
            i++;
        }
        
    }
}

// MARK: - Drag & Drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [_delegate mainViewDraggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [_delegate mainViewPerformDragOperation:sender];
}

@end

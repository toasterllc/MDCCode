#import "MainView.h"
#import <vector>
#import "ImageLayer.h"
//#import "HistogramLayer.h"
#import "Util.h"
#import "ColorChecker.h"
#import "MetalUtil.h"

using namespace CFAViewer;
using namespace MDCTools::MetalUtil;

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
    bool _colorCheckersPositioned;
    std::vector<CAShapeLayer*> _colorCheckers;
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
    [_sampleLayer setBorderWidth:.1];
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
        _colorCheckers.push_back(circle);
        
        i++;
    }
    
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
    const CGSize layerSize = [_imageLayer bounds].size;
    CGRect r = [_sampleLayer frame];
    r.origin.x /= layerSize.width;
    r.origin.y /= layerSize.height;
    r.size.width /= layerSize.width;
    r.size.height /= layerSize.height;
    r.origin.y = 1-r.origin.y-r.size.height; // Flip Y so the origin is at the top-left
    return r;
}

- (std::vector<CGPoint>)colorCheckerPositions {
    const CGSize layerSize = [_imageLayer bounds].size;
    std::vector<CGPoint> r;
    for (CALayer* l : _colorCheckers) {
        CGPoint p = [l position];
        p.x /= layerSize.width;
        p.y /= layerSize.height;
        p.y = 1-p.y; // Flip Y, so that the origin of our return value is the top-left
        r.push_back(p);
    }
    return r;
}

- (void)setColorCheckerPositions:(const std::vector<CGPoint>&)points {
    assert(points.size() == ColorChecker::Count);
    const CGSize layerSize = [_imageLayer bounds].size;
    size_t i = 0;
    for (CALayer* l : _colorCheckers) {
        CGPoint p = points[i];
        p.y = 1-p.y; // Flip Y, since the origin of the supplied points is the top-left
        p.x *= layerSize.width;
        p.y *= layerSize.height;
        [l setPosition:p];
        i++;
    }
    _colorCheckersPositioned = true;
}

- (void)resetColorCheckerPositions {
    const size_t ColorCheckerWidth = 6;
    const size_t ColorCheckerHeight = 4;
    const CGSize size = [_imageLayer bounds].size;
    size_t i = 0;
    for (size_t y=0; y<ColorCheckerHeight; y++) {
        for (size_t x=0; x<ColorCheckerWidth; x++, i++) {
            const CGPoint p = {
                .5*size.width  + x*(_colorCheckerCircleRadius+10),
                .5*size.height - y*(_colorCheckerCircleRadius+10)
            };
            CAShapeLayer* circle = _colorCheckers[i];
            [circle setPosition:p];
        }
    }
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
    
    // Apply the initial color checker positions, if they haven't been positioned yet
    if (!_colorCheckersPositioned) {
        [self resetColorCheckerPositions];
        _colorCheckersPositioned = true;
    }
    
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
- (CAShapeLayer*)_findColorCheckerCircle:(CGPoint)p {
    for (CAShapeLayer* c : _colorCheckers) {
        const CGPoint cp = [c position];
        if (sqrt(pow(cp.x-p.x,2)+pow(cp.y-p.y,2)) < _colorCheckerCircleRadius) {
            return c;
        }
    }
    return nil;
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
        CAShapeLayer* circle = [self _findColorCheckerCircle:p];
        if (circle) {
            TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
                const CGPoint p = eventPositionInLayer(win, _imageLayer, ev);
                [circle setPosition:p];
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
        CGSize layerSize = [_rootLayer bounds].size;
        [_imageLayer setPosition:{layerSize.width/2, layerSize.height/2}];
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

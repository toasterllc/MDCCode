#import "BaseView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import "ImageLayer.h"
#import "HistogramLayer.h"
#import "Mmap.h"
#import "Util.h"
#import "Mat.h"
#import "ColorUtil.h"
#import "MyTime.h"

using namespace CFAViewer;
using namespace MetalTypes;
using namespace ImageLayerTypes;
using namespace ColorUtil;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

@interface NSObject ()
- (void)sampleRectChanged;
- (void)colorCheckerPositionsChanged;
@end

constexpr size_t ColorCheckerCount = 24;
const Color_SRGB_D65 ColorCheckerColors[ColorCheckerCount] {
    // Row 0
    {   0x73/255.   ,   0x52/255.   ,   0x44/255.   },
    {   0xc2/255.   ,   0x96/255.   ,   0x82/255.   },
    {   0x62/255.   ,   0x7a/255.   ,   0x9d/255.   },
    {   0x57/255.   ,   0x6c/255.   ,   0x43/255.   },
    {   0x85/255.   ,   0x80/255.   ,   0xb1/255.   },
    {   0x67/255.   ,   0xbd/255.   ,   0xaa/255.   },
    
    // Row 1
    {   0xd6/255.   ,   0x7e/255.   ,   0x2c/255.   },
    {   0x50/255.   ,   0x5b/255.   ,   0xa6/255.   },
    {   0xc1/255.   ,   0x5a/255.   ,   0x63/255.   },
    {   0x5e/255.   ,   0x3c/255.   ,   0x6c/255.   },
    {   0x9d/255.   ,   0xbc/255.   ,   0x40/255.   },
    {   0xe0/255.   ,   0xa3/255.   ,   0x2e/255.   },
    
    // Row 2
    {   0x38/255.   ,   0x3d/255.   ,   0x96/255.   },
    {   0x46/255.   ,   0x94/255.   ,   0x49/255.   },
    {   0xaf/255.   ,   0x36/255.   ,   0x3c/255.   },
    {   0xe7/255.   ,   0xc7/255.   ,   0x1f/255.   },
    {   0xbb/255.   ,   0x56/255.   ,   0x95/255.   },
    {   0x08/255.   ,   0x85/255.   ,   0xa1/255.   },
    
    // Row 3
    {   0xf3/255.   ,   0xf3/255.   ,   0xf2/255.   },
    {   0xc8/255.   ,   0xc8/255.   ,   0xc8/255.   },
    {   0xa0/255.   ,   0xa0/255.   ,   0xa0/255.   },
    {   0x7a/255.   ,   0x7a/255.   ,   0x79/255.   },
    {   0x55/255.   ,   0x55/255.   ,   0x55/255.   },
    {   0x34/255.   ,   0x34/255.   ,   0x34/255.   },
};

@interface MainView : BaseView <CALayoutManager, NSGestureRecognizerDelegate>
@end

@implementation MainView {
    CALayer* _viewLayer;
    CALayer* _rootLayer;
    CGPoint _rootLayerOffset;
    ImageLayer* _imageLayer;
    CALayer* _sampleLayer;
    CGFloat _colorCheckerCircleRadius;
    bool _colorCheckerCirclesVisible;
    bool _colorCheckersPositioned;
    std::vector<CAShapeLayer*> _colorCheckerCircles;
    
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
    
    IBOutlet id _delegate;
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
    for (const Color_SRGB_D65& c : ColorCheckerColors) {
        CAShapeLayer* circle = [CAShapeLayer new];
        setCircleRadius(circle, _colorCheckerCircleRadius);
        [circle setFillColor:(CGColorRef)SRGBColor(c[0], c[1], c[2], 1)];
        [circle setActions:LayerNullActions()];
        [circle setHidden:!_colorCheckerCirclesVisible];
        [_imageLayer addSublayer:circle];
        _colorCheckerCircles.push_back(circle);
        
        i++;
    }
    
    _zoomScale = 1;
    NSMagnificationGestureRecognizer* magnify = [[NSMagnificationGestureRecognizer alloc] initWithTarget:self
        action:@selector(_handleMagnify:)];
    [magnify setDelegate:self];
    [self addGestureRecognizer:magnify];
}

- (void)_setZoomScale:(CGFloat)zoomScale anchor:(CGPoint)anchor {
    const CGFloat MinScale = .25;
    const CGFloat MaxScale = 20;
    
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


- (ImageLayer*)imageLayer {
    return _imageLayer;
}

// `p` is in coordinates of _layer
- (CAShapeLayer*)_findColorCheckerCircle:(CGPoint)p {
    for (CAShapeLayer* c : _colorCheckerCircles) {
        const CGPoint cp = [c position];
        if (sqrt(pow(cp.x-p.x,2)+pow(cp.y-p.y,2)) < _colorCheckerCircleRadius) {
            return c;
        }
    }
    return nil;
}

static void setCircleRadius(CAShapeLayer* c, CGFloat r) {
    [c setPath:(CGPathRef)CFBridgingRelease(CGPathCreateWithEllipseInRect({0,0,r*2,r*2}, nil))];
    [c setBounds:{0,0,r*2,r*2}];
}

- (void)setColorCheckerCirclesVisible:(bool)visible {
    _colorCheckerCirclesVisible = visible;
    
    // Apply the initial color checker positions, if they haven't been positioned yet
    if (!_colorCheckersPositioned) {
        [self resetColorCheckerPositions];
        _colorCheckersPositioned = true;
    }
    
    for (CAShapeLayer* circle : _colorCheckerCircles) {
        [circle setHidden:!_colorCheckerCirclesVisible];
    }
}

- (void)mouseDown:(NSEvent*)ev {
    NSWindow* win = [self window];
    const CGPoint p = [_imageLayer convertPoint:[ev locationInWindow]
        fromLayer:[[win contentView] layer]];
    
    // Handle circle being clicked
    if (_colorCheckerCirclesVisible) {
        CAShapeLayer* circle = [self _findColorCheckerCircle:p];
        if (circle) {
            TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
                const CGPoint p = [_imageLayer convertPoint:[ev locationInWindow]
                    fromLayer:[[win contentView] layer]];
                [circle setPosition:p];
            });
            
            [_delegate colorCheckerPositionsChanged];
            return;
        }
    }
    
    // Otherwise, handle sampler functionality
    const CGPoint start = p;
    TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
        const CGPoint end = [_imageLayer convertPoint:[ev locationInWindow]
            fromLayer:[[win contentView] layer]];
        CGRect frame = {start, {end.x-start.x, end.y-start.y}};
        if ([ev modifierFlags] & NSEventModifierFlagShift) {
            frame.size.height = (frame.size.height >= 0 ? 1 : -1) * fabs(frame.size.width);
        }
        frame = CGRectStandardize(frame);
        [_sampleLayer setFrame:frame];
    });
    [_delegate sampleRectChanged];
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
            CAShapeLayer* circle = _colorCheckerCircles[i];
            [circle setPosition:p];
        }
    }
}

- (std::vector<CGPoint>)colorCheckerPositions {
    const CGSize layerSize = [_imageLayer bounds].size;
    std::vector<CGPoint> r;
    for (CALayer* l : _colorCheckerCircles) {
        CGPoint p = [l position];
        p.x /= layerSize.width;
        p.y /= layerSize.height;
        p.y = 1-p.y; // Flip Y, so that the origin of our return value is the top-left
        r.push_back(p);
    }
    return r;
}

- (void)setColorCheckerPositions:(const std::vector<CGPoint>&)points {
    assert(points.size() == ColorCheckerCount);
    const CGSize layerSize = [_imageLayer bounds].size;
    size_t i = 0;
    for (CALayer* l : _colorCheckerCircles) {
        CGPoint p = points[i];
        p.y = 1-p.y; // Flip Y, since the origin of the supplied points is the top-left
        p.x *= layerSize.width;
        p.y *= layerSize.height;
        [l setPosition:p];
        i++;
    }
    _colorCheckersPositioned = true;
}

- (void)setColorCheckerCircleRadius:(CGFloat)r {
    _colorCheckerCircleRadius = r;
    for (CAShapeLayer* c : _colorCheckerCircles) {
        setCircleRadius(c, _colorCheckerCircleRadius);
    }
}

@end

@interface HistogramView : BaseView
@end

@implementation HistogramView {
    NSTextField* _label;
    NSTrackingArea* _trackingArea;
    HistogramLayer* _layer;
}
+ (Class)layerClass                 { return [HistogramLayer class];    }
- (HistogramLayer*)histogramLayer   { return _layer;                    }

- (void)commonInit {
    [super commonInit];
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _layer = (id)[self layer];
    
    _label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [_label setTranslatesAutoresizingMaskIntoConstraints:false];
    [_label setEditable:false];
    [_label setBordered:false];
    [_label setDrawsBackground:false];
    [_label setHidden:true];
    [self addSubview:_label];
    
    [[[_label trailingAnchor] constraintEqualToAnchor:[self trailingAnchor]
        constant:-20] setActive:true];
    [[[_label topAnchor] constraintEqualToAnchor:[self topAnchor]
        constant:20] setActive:true];
    [_label setTextColor:[NSColor redColor]];
    
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited|NSTrackingMouseMoved|
                NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent*)event {
    [self _updateLabel:[self convertPoint:[event locationInWindow] fromView:nil]];
    [_label setHidden:false];
}

- (void)mouseMoved:(NSEvent*)event {
    [self _updateLabel:[self convertPoint:[event locationInWindow] fromView:nil]];
    [_label setHidden:false];
}

- (void)mouseExited:(NSEvent*)event {
    [self _updateLabel:[self convertPoint:[event locationInWindow] fromView:nil]];
    [_label setHidden:true];
}

- (void)_updateLabel:(CGPoint)p {
    CGPoint val = [[self histogramLayer] valueFromPoint:p];
    [_label setStringValue:[NSString stringWithFormat:@"%.1f %.1f", val.x, val.y]];
}

@end


@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
    
    IBOutlet NSSwitch* _liveSwitch;
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
    IBOutlet NSTextField* _colorMatrixTextField;
    IBOutlet NSMenuItem* _showColorCheckerCirclesMenuItem;
    
    IBOutlet NSTextField* _colorText_cameraRaw;
    IBOutlet NSTextField* _colorText_XYZ_D50;
    IBOutlet NSTextField* _colorText_SRGB_D65;
    
    IBOutlet NSSlider*      _highlightFactorR0Slider;
    IBOutlet NSTextField*   _highlightFactorR0Label;
    IBOutlet NSSlider*      _highlightFactorR1Slider;
    IBOutlet NSTextField*   _highlightFactorR1Label;
    IBOutlet NSSlider*      _highlightFactorR2Slider;
    IBOutlet NSTextField*   _highlightFactorR2Label;
    
    IBOutlet NSSlider*      _highlightFactorG0Slider;
    IBOutlet NSTextField*   _highlightFactorG0Label;
    IBOutlet NSSlider*      _highlightFactorG1Slider;
    IBOutlet NSTextField*   _highlightFactorG1Label;
    IBOutlet NSSlider*      _highlightFactorG2Slider;
    IBOutlet NSTextField*   _highlightFactorG2Label;
    
    IBOutlet NSSlider*      _highlightFactorB0Slider;
    IBOutlet NSTextField*   _highlightFactorB0Label;
    IBOutlet NSSlider*      _highlightFactorB1Slider;
    IBOutlet NSTextField*   _highlightFactorB1Label;
    IBOutlet NSSlider*      _highlightFactorB2Slider;
    IBOutlet NSTextField*   _highlightFactorB2Label;
    
    bool _colorCheckerCirclesVisible;
    float _colorCheckerCircleRadius;
    
    struct {
        std::mutex lock; // Protects this struct
        
        ColorMatrix colorMatrix;
        Mmap imageData;
        Image image;
        
        Color_CamRaw_D50 sample_CamRaw_D50;
        Color_XYZ_D50 sample_XYZ_D50;
        Color_SRGB_D65 sample_SRGB_D65;
    } _state;
}

- (void)awakeFromNib {
    constexpr size_t ImageWidth = 2304;
    constexpr size_t ImageHeight = 1296;
    
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    auto lock = std::unique_lock(_state.lock);
        _state.colorMatrix = {1., 0., 0., 0., 1., 0., 0., 0., 1.};
        _state.imageData = Mmap("/Users/dave/repos/MotionDetectorCamera/Tools/CFAViewer/img.cfa");
        
        _state.image = {
            .width = ImageWidth,
            .height = ImageHeight,
            .pixels = (MetalTypes::ImagePixel*)_state.imageData.data(),
        };
        
        [[_mainView imageLayer] setImage:_state.image];
    lock.unlock();
    
    __weak auto weakSelf = self;
    [[_mainView imageLayer] setDataChangedHandler:^(ImageLayer*) {
        [weakSelf _updateHistograms];
        [weakSelf _updateSampleColors];
    }];
    
    [self _resetColorMatrix];
    
    auto points = [self prefsColorCheckerPositions];
    if (!points.empty()) {
        [_mainView setColorCheckerPositions:points];
    }
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer* timer) {
//        const uint32_t count = 100;
//        auto startTime = MyTime::Now();
//        for (int i=0; i<count; i++) {
//            [[self->_mainView imageLayer] display];
//        }
//        auto durationNs = MyTime::DurationNs(startTime);
//        printf("Duration: %f ms\n", ((double)durationNs/count)/1000000);
//    }];
}

- (IBAction)identityButtonPressed:(id)sender {
    [self _resetColorMatrix];
}

- (void)_resetColorMatrix {
    [self _updateColorMatrix:{1.,0.,0.,0.,1.,0.,0.,0.,1.}];
}

- (void)controlTextDidChange:(NSNotification*)note {
    if ([note object] == _colorMatrixTextField) {
        [self _updateColorMatrixFromString:[[_colorMatrixTextField stringValue] UTF8String]];
    }
}

- (void)_updateColorMatrixFromString:(const std::string&)str {
    const std::regex floatRegex("[-+]?[0-9]*\\.?[0-9]+");
    auto begin = std::sregex_iterator(str.begin(), str.end(), floatRegex);
    auto end = std::sregex_iterator();
    std::vector<double> vals;
    
    for (std::sregex_iterator i=begin; i!=end; i++) {
        vals.push_back(std::stod(i->str()));
    }
    
    if (vals.size() != 9) {
        NSLog(@"Failed to parse color matrix");
        return;
    }
    
    [self _updateColorMatrix:vals.data()];
}

- (void)_updateColorMatrix:(const ColorMatrix&)colorMatrix {
    auto lock = std::unique_lock(_state.lock);
    _state.colorMatrix = colorMatrix;
    
    [[_mainView imageLayer] setColorMatrix:colorMatrix];
    
    [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f\n"
        @"%f %f %f\n"
        @"%f %f %f\n",
        _state.colorMatrix[0], _state.colorMatrix[1], _state.colorMatrix[2],
        _state.colorMatrix[3], _state.colorMatrix[4], _state.colorMatrix[5],
        _state.colorMatrix[6], _state.colorMatrix[7], _state.colorMatrix[8]
    ]];
}

- (void)_updateHistograms {
    [[_inputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] inputHistogram]];
    [[_outputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] outputHistogram]];
}

- (void)_updateSampleColors {
    auto lock = std::unique_lock(_state.lock);
    _state.sample_CamRaw_D50 = [[_mainView imageLayer] sample_CamRaw_D50];
    _state.sample_XYZ_D50 = [[_mainView imageLayer] sample_XYZ_D50];
    _state.sample_SRGB_D65 = [[_mainView imageLayer] sample_SRGB_D65];
    
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        [self _updateSampleColorsText];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (void)_updateSampleColorsText {
    auto lock = std::unique_lock(_state.lock);
    [_colorText_cameraRaw setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _state.sample_CamRaw_D50[0], _state.sample_CamRaw_D50[1], _state.sample_CamRaw_D50[2]]];
    [_colorText_XYZ_D50 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _state.sample_XYZ_D50[0], _state.sample_XYZ_D50[1], _state.sample_XYZ_D50[2]]];
    [_colorText_SRGB_D65 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _state.sample_SRGB_D65[0], _state.sample_SRGB_D65[1], _state.sample_SRGB_D65[2]]];
}

//  Row0    G1  R  G1  R
//  Row1    B   G2 B   G2
//  Row2    G1  R  G1  R
//  Row3    B   G2 B   G2

static double px(Image& img, uint32_t x, int32_t dx, uint32_t y, int32_t dy) {
    int32_t xc = (int32_t)x + dx;
    int32_t yc = (int32_t)y + dy;
    xc = std::clamp(xc, (int32_t)0, (int32_t)img.width-1);
    yc = std::clamp(yc, (int32_t)0, (int32_t)img.height-1);
    return (double)img.pixels[(yc*img.width)+xc] / ImagePixelMax;
}

static double sampleR(Image& img, uint32_t x, uint32_t y) {
    if (y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want R
        // Sample @ y-1, y+1
        if (x % 2) return .5*px(img, x, 0, y, -1) + .5*px(img, x, 0, y, +1);
        
        // Have B
        // Want R
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*px(img, x, -1, y, -1) +
                    .25*px(img, x, -1, y, +1) +
                    .25*px(img, x, +1, y, -1) +
                    .25*px(img, x, +1, y, +1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want R
        // Sample @ this pixel
        if (x % 2) return px(img, x, 0, y, 0);
        
        // Have G
        // Want R
        // Sample @ x-1 and x+1
        else return .5*px(img, x, -1, y, 0) + .5*px(img, x, +1, y, 0);
    }
}

static double sampleG(Image& img, uint32_t x, uint32_t y) {
//    return px(img, x, 0, y, 0);
    
    if (y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (x % 2) return px(img, x, 0, y, 0);
        
        // Have B
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*px(img, x, -1, y, 0) +
                    .25*px(img, x, +1, y, 0) +
                    .25*px(img, x, 0, y, -1) +
                    .25*px(img, x, 0, y, +1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        if (x % 2) return   .25*px(img, x, -1, y, 0) +
                            .25*px(img, x, +1, y, 0) +
                            .25*px(img, x, 0, y, -1) +
                            .25*px(img, x, 0, y, +1) ;
        
        // Have G
        // Want G
        // Sample @ this pixel
        else return px(img, x, 0, y, 0);
    }
}

static double sampleB(Image& img, uint32_t x, uint32_t y) {
//    return px(img, x, 0, y, 0);
    
    if (y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want B
        // Sample @ x-1, x+1
        if (x % 2) return .5*px(img, x, -1, y, 0) + .5*px(img, x, +1, y, 0);
        
        // Have B
        // Want B
        // Sample @ this pixel
        else return px(img, x, 0, y, 0);
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want B
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        if (x % 2) return   .25*px(img, x, -1, y, -1) +
                            .25*px(img, x, -1, y, +1) +
                            .25*px(img, x, +1, y, -1) +
                            .25*px(img, x, +1, y, +1) ;
        
        // Have G
        // Want B
        // Sample @ y-1, y+1
        else return .5*px(img, x, 0, y, -1) + .5*px(img, x, 0, y, +1);
    }
}

static Color_CamRaw_D50 sampleImageCircle(Image& img, uint32_t x, uint32_t y, uint32_t radius) {
    uint32_t left = std::clamp((int32_t)x-(int32_t)radius, (int32_t)0, (int32_t)img.width-1);
    uint32_t right = std::clamp((int32_t)x+(int32_t)radius, (int32_t)0, (int32_t)img.width-1)+1;
    uint32_t bottom = std::clamp((int32_t)y-(int32_t)radius, (int32_t)0, (int32_t)img.height-1);
    uint32_t top = std::clamp((int32_t)y+(int32_t)radius, (int32_t)0, (int32_t)img.height-1)+1;
    
    Color_CamRaw_D50 c;
    uint32_t i = 0;
    for (uint32_t iy=bottom; iy<top; iy++) {
        for (uint32_t ix=left; ix<right; ix++) {
            if (sqrt(pow((double)ix-x,2) + pow((double)iy-y,2)) < (double)radius) {
                c[0] += sampleR(img, ix, iy);
                c[1] += sampleG(img, ix, iy);
                c[2] += sampleB(img, ix, iy);
                i++;
            }
        }
    }
    
    c[0] /= i;
    c[1] /= i;
    c[2] /= i;
    return c;
}

static double LSRGBFromSRGB(double x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.04045) return x/12.92;
    return pow((x+.055)/1.055, 2.4);
}

static Color_XYZ_D50 XYZFromSRGB(const Color_SRGB_D65& srgb_d65) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const ColorMatrix XYZD65_From_LSRGBD65(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    
    const ColorMatrix XYZD50_From_XYZD65(
        1.0478112,  0.0228866,  -0.0501270,
         0.0295424, 0.9904844,  -0.0170491,
        -0.0092345, 0.0150436,  0.7521316
    );
    
    // SRGB -> linear SRGB
    const Color3 lsrgb_d65(LSRGBFromSRGB(srgb_d65[0]), LSRGBFromSRGB(srgb_d65[1]), LSRGBFromSRGB(srgb_d65[2]));
    // Linear SRGB -> XYZ.D65 -> XYZ.D50
    return XYZD50_From_XYZD65 * XYZD65_From_LSRGBD65 * lsrgb_d65;
}

- (IBAction)liveSwitchToggled:(id)sender {
    NSLog(@"liveSwitchToggled");
}

- (IBAction)showHideColorCheckerCircles:(id)sender {
	_colorCheckerCirclesVisible = !_colorCheckerCirclesVisible;
    [_mainView setColorCheckerCirclesVisible:_colorCheckerCirclesVisible];
    [_showColorCheckerCirclesMenuItem setState:(_colorCheckerCirclesVisible ? NSControlStateValueOn : NSControlStateValueOff)];
    [self colorCheckerPositionsChanged];
}

- (IBAction)resetColorCheckerCircles:(id)sender {
    [_mainView resetColorCheckerPositions];
    [self colorCheckerPositionsChanged];
}

- (IBAction)highlightFactorSliderChanged:(id)sender {
    Mat<double,3,3> highlightFactor(
        [_highlightFactorR0Slider doubleValue],
        [_highlightFactorR1Slider doubleValue],
        [_highlightFactorR2Slider doubleValue],
        
        [_highlightFactorG0Slider doubleValue],
        [_highlightFactorG1Slider doubleValue],
        [_highlightFactorG2Slider doubleValue],
        
        [_highlightFactorB0Slider doubleValue],
        [_highlightFactorB1Slider doubleValue],
        [_highlightFactorB2Slider doubleValue]
    );
    
    [[_mainView imageLayer] setHighlightFactor:highlightFactor];
    [_highlightFactorR0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[0]]];
    [_highlightFactorR1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[1]]];
    [_highlightFactorR2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[2]]];
    [_highlightFactorG0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[3]]];
    [_highlightFactorG1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[4]]];
    [_highlightFactorG2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[5]]];
    [_highlightFactorB0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[6]]];
    [_highlightFactorB1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[7]]];
    [_highlightFactorB2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[8]]];
    [self sampleRectChanged];
}

- (void)sampleRectChanged {
    const CGRect sampleRect = [_mainView sampleRect];
    [[_mainView imageLayer] setSampleRect:sampleRect];
}

- (void)colorCheckerPositionsChanged {
    auto lock = std::unique_lock(_state.lock);
    
    auto points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorCheckerCount);
    
    Mat<double,ColorCheckerCount,3> A; // Colors that we have
    size_t i = 0;
    for (const CGPoint& p : points) {
        Color_CamRaw_D50 c = sampleImageCircle(_state.image,
            round(p.x*_state.image.width),
            round(p.y*_state.image.height),
            _colorCheckerCircleRadius);
        A[i+0] = c[0];
        A[i+1] = c[1];
        A[i+2] = c[2];
        i += 3;
    }
    
    Mat<double,ColorCheckerCount,3> b; // Colors that we want
    i = 0;
    for (Color_SRGB_D65 c : ColorCheckerColors) {
        // Convert the color from SRGB -> XYZ -> XYY
        Color_XYZ_D50 cxyy = ColorUtil::XYYFromXYZ(XYZFromSRGB(c));
//        cxyy[2] /= 3; // Adjust luminance
        
        const Color_XYZ_D50 cxyz = ColorUtil::XYZFromXYY(cxyy);
        b[i+0] = cxyz[0];
        b[i+1] = cxyz[1];
        b[i+2] = cxyz[2];
        i += 3;
    }
    
    // Calculate the color matrix (x = (At*A)^-1 * At * b)
    auto x = (A.pinv() * b).trans();
    [self _updateColorMatrix:x];
    [self prefsSetColorCheckerPositions:points];
    
//    NSMutableArray* nspoints = [NSMutableArray new];
//    for (const CGPoint& p : points) {
//        [nspoints addObject:[NSValue valueWithPoint:p]];
//    }
//    [[NSUserDefaults standardUserDefaults] setObject:nspoints forKey:ColorCheckerPositionsKey];
}

- (std::vector<CGPoint>)prefsColorCheckerPositions {
    NSArray* nspoints = [[NSUserDefaults standardUserDefaults] objectForKey:ColorCheckerPositionsKey];
    std::vector<CGPoint> points;
    if ([nspoints count] != ColorCheckerCount) return {};
    if (![nspoints isKindOfClass:[NSArray class]]) return {};
    for (NSArray* nspoint : nspoints) {
        if (![nspoint isKindOfClass:[NSArray class]]) return {};
        if ([nspoint count] != 2) return {};
        
        NSNumber* nsx = nspoint[0];
        NSNumber* nsy = nspoint[1];
        if (![nsx isKindOfClass:[NSNumber class]]) return {};
        if (![nsy isKindOfClass:[NSNumber class]]) return {};
        points.push_back({[nsx doubleValue], [nsy doubleValue]});
    }
    return points;
}

- (void)prefsSetColorCheckerPositions:(const std::vector<CGPoint>&)points {
    NSMutableArray* nspoints = [NSMutableArray new];
    for (const CGPoint& p : points) {
        [nspoints addObject:@[@(p.x), @(p.y)]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:nspoints forKey:ColorCheckerPositionsKey];
}

@end

#import "BaseView.h"
#import <Accelerate/Accelerate.h>
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import "ImageLayer.h"
#import "HistogramLayer.h"
#import "Mmap.h"
#import "Util.h"
#import "Mat.h"

using namespace CFAViewer;
using namespace MetalTypes;
using namespace ImageLayerTypes;

using ColorMatrix = Mat<double,3,3>;
using Color3 = Mat<double,3,1>;
using ColorXYYD65 = Color3;
using ColorXYZD65 = Color3;
using ColorSRGBD65 = Color3;
using ColorCameraRaw = Color3;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

@interface NSObject ()
- (void)eyeDropperRectChanged;
- (void)colorCheckerPositionsChanged;
@end

constexpr size_t ColorCheckerCount = 24;
const ColorSRGBD65 ColorCheckerColors[ColorCheckerCount] {
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

@interface MainView : BaseView <CALayoutManager>
@end

@implementation MainView {
    CALayer* _rootLayer;
    ImageLayer* _imageLayer;
    CALayer* _eyeDropperLayer;
    CGFloat _colorCheckerCircleRadius;
    bool _colorCheckerCirclesVisible;
    bool _colorCheckersPositioned;
    std::vector<CAShapeLayer*> _colorCheckerCircles;
    IBOutlet id _delegate;
}

- (void)commonInit {
    [super commonInit];
    _rootLayer = [self layer];
    _colorCheckerCircleRadius = 1;
    _imageLayer = [ImageLayer new];
    [_rootLayer addSublayer:_imageLayer];
    [_rootLayer setLayoutManager:self];
    [_imageLayer setAffineTransform:CGAffineTransformMakeScale(1, -1)];
    
    _eyeDropperLayer = [CALayer new];
    [_eyeDropperLayer setActions:LayerNullActions()];
    [_eyeDropperLayer setBorderColor:(CGColorRef)SRGBColor(1, 0, 0, 1)];
    [_eyeDropperLayer setBorderWidth:1];
    [_imageLayer addSublayer:_eyeDropperLayer];
    
    // Create our color checker circles if they don't exist yet
    size_t i = 0;
    for (const ColorSRGBD65& c : ColorCheckerColors) {
        CAShapeLayer* circle = [CAShapeLayer new];
        setCircleRadius(circle, _colorCheckerCircleRadius);
        [circle setFillColor:(CGColorRef)SRGBColor(c[0], c[1], c[2], 1)];
        [circle setActions:LayerNullActions()];
        [circle setHidden:!_colorCheckerCirclesVisible];
        [_imageLayer addSublayer:circle];
        _colorCheckerCircles.push_back(circle);
        
        i++;
    }
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
        const size_t ColorCheckerWidth = 6;
        const size_t ColorCheckerHeight = 4;
        const CGSize size = [_imageLayer bounds].size;
        size_t i = 0;
        for (size_t y=0; y<ColorCheckerHeight; y++) {
            for (size_t x=0; x<ColorCheckerWidth; x++, i++) {
                const CGPoint p = {
                    .5*size.width  + x*(_colorCheckerCircleRadius+10),
                    .5*size.height + y*(_colorCheckerCircleRadius+10)
                };
                CAShapeLayer* circle = _colorCheckerCircles[i];
                [circle setPosition:p];
            }
        }
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
    
    // Otherwise, handle eye dropper functionality
    {
        const CGPoint start = p;
        TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
            const CGPoint end = [_imageLayer convertPoint:[ev locationInWindow]
                fromLayer:[[win contentView] layer]];
            CGRect frame;
            frame.origin = start;
            frame.size = {end.x-start.x, end.y-start.y};
            [_eyeDropperLayer setFrame:frame];
            [_delegate eyeDropperRectChanged];
        });
    }
}

- (void)layoutSublayersOfLayer:(CALayer*)layer {
    if (layer == _rootLayer) {
        CGSize layerSize = [_rootLayer bounds].size;
        [_imageLayer setPosition:{layerSize.width/2, layerSize.height/2}];
    }
}

- (CGRect)eyeDropperRect {
    const CGSize layerSize = [_imageLayer bounds].size;
    CGRect r = [_eyeDropperLayer frame];
    r.origin.x /= layerSize.width;
    r.origin.y /= layerSize.height;
    r.size.width /= layerSize.width;
    r.size.height /= layerSize.height;
    return r;
}

- (std::vector<CGPoint>)colorCheckerPositions {
    const CGSize layerSize = [_imageLayer bounds].size;
    std::vector<CGPoint> r;
    for (CALayer* l : _colorCheckerCircles) {
        CGPoint p = [l position];
        p.x /= layerSize.width;
        p.y /= layerSize.height;
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
}
+ (Class)layerClass                 { return [HistogramLayer class];    }
- (HistogramLayer*)histogramLayer   { return (id)[self layer];          }

- (void)commonInit {
    [super commonInit];
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
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
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
    IBOutlet NSTextField* _colorMatrixTextField;
    IBOutlet NSMenuItem* _showColorCheckerCirclesMenuItem;
    
    IBOutlet NSTextField* _colorText_cameraRaw;
    IBOutlet NSTextField* _colorText_XYZ_d50;
    IBOutlet NSTextField* _colorText_SRGB_D65;
    
    bool _colorCheckerCirclesVisible;
    float _colorCheckerCircleRadius;
    
    ColorMatrix _colorMatrix;
    Mmap _imageData;
    Image _image;
}

- (void)awakeFromNib {
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    _colorMatrix = {1., 0., 0., 0., 1., 0., 0., 0., 1.};
    
    _imageData = Mmap("/Users/dave/repos/MotionDetectorCamera/Tools/CFAViewer/img.cfa");
    
    constexpr size_t ImageWidth = 2304;
    constexpr size_t ImageHeight = 1296;
    
    _image = {
        .width = ImageWidth,
        .height = ImageHeight,
        .pixels = (MetalTypes::ImagePixel*)_imageData.data(),
    };
    [[_mainView imageLayer] updateImage:_image];
    
    __weak auto weakSelf = self;
    [[_mainView imageLayer] setHistogramChangedHandler:^(ImageLayer*) {
        [weakSelf _updateHistograms];
    }];
    
    [self _resetColorMatrix];
    
    auto points = [self prefsColorCheckerPositions];
    if (!points.empty()) {
        [_mainView setColorCheckerPositions:points];
    }
    
    // XYZ.D65 -> XYZ.D50 -> LSRGB.D50
    
    // ## XYZ->RGB
    // "If the input XYZ color is not relative to the same reference
    // white as the RGB system, you must first apply a chromatic
    // adaptation transform to the XYZ color to convert it from its
    // own reference white to the reference white of the RGB system."
    
    // ## RGB->XYZ
    // "The XYZ values will be relative to the same reference white
    // as the RGB system. If you want XYZ relative to a different
    // reference white, you must apply a chromatic adaptation
    // transform to the XYZ color to convert it from the reference
    // white of the RGB system to the desired reference white."
    
    const ColorMatrix XYZ_D50_From_XYZ_D65(
        1.0478112,  0.0228866,  -0.0501270,
        0.0295424,  0.9904844,  -0.0170491,
        -0.0092345, 0.0150436,  0.7521316
    );
    
    const ColorMatrix XYZ_D65_From_XYZ_D50_Scaling(
        0.9857398,  0.0000000,  0.0000000,
        0.0000000,  1.0000000,  0.0000000,
        0.0000000,  0.0000000,  1.3194581
    );
    
    const ColorMatrix XYZ_D65_From_XYZ_D50_Bradford(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    );
    
    const ColorMatrix XYZ_D65_From_XYZ_D50_VonKries(
        0.9845002,  -0.0546158, 0.0676324,
        -0.0059992, 1.0047864,  0.0012095,
        0.0000000,  0.0000000,  1.3194581
    );
    
    const ColorMatrix XYZ_From_LSRGB(
        0.4124564,  0.3575761,  0.1804375,
        0.2126729,  0.7151522,  0.0721750,
        0.0193339,  0.1191920,  0.9503041
    );
    
    const ColorMatrix LSRGB_From_XYZ(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660, 1.8760108,  0.0415560,
        0.0556434,  -0.2040259, 1.0572252
    );
    
    {
        Mmap grayData("/Users/dave/repos/MotionDetectorCamera/Tools/CFAViewer/gray-16bit.cfa");
        ImagePixel* grayPixels = (ImagePixel*)grayData.data();
        
        printf(
            "Assuming raw values are XYZ.D50\n"
            "Chromatic adaptation: Bradford\n"
            "SRGB Gamma: complex\n"
        );
        
        Color3 color((double)grayPixels[0], (double)grayPixels[0], (double)grayPixels[0]);
        color = color/0xFFFF;
        Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_Bradford*color;
        Color3 color_srgb = Color3(
            SRGBFromLSRGB(color_linearSRGB[0]),
            SRGBFromLSRGB(color_linearSRGB[1]),
            SRGBFromLSRGB(color_linearSRGB[2])
        );
        printf("%s\n", color_srgb.str(3).c_str());
    }
}

- (IBAction)identityButtonPressed:(id)sender {
    [self _resetColorMatrix];
}

- (void)_resetColorMatrix {
    double ident[9] = {1,0,0,0,1,0,0,0,1};
    [self _updateColorMatrix:ident];
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
    _colorMatrix = colorMatrix;
    
    [[_mainView imageLayer] updateColorMatrix:simd::float3x3{
        simd::float3{(float)_colorMatrix[0], (float)_colorMatrix[3], (float)_colorMatrix[6]},
        simd::float3{(float)_colorMatrix[1], (float)_colorMatrix[4], (float)_colorMatrix[7]},
        simd::float3{(float)_colorMatrix[2], (float)_colorMatrix[5], (float)_colorMatrix[8]},
    }];
    
    [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f\n"
        @"%f %f %f\n"
        @"%f %f %f\n",
        _colorMatrix[0], _colorMatrix[1], _colorMatrix[2],
        _colorMatrix[3], _colorMatrix[4], _colorMatrix[5],
        _colorMatrix[6], _colorMatrix[7], _colorMatrix[8]
    ]];
}

- (void)_updateHistograms {
    [[_inputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] inputHistogram]];
    [[_outputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] outputHistogram]];
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

static ColorCameraRaw sampleImageRect(Image& img, uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
    uint32_t left = std::clamp((int32_t)x, (int32_t)0, (int32_t)img.width-1);
    uint32_t right = std::clamp((int32_t)x+(int32_t)width, (int32_t)0, (int32_t)img.width-1)+1;
    uint32_t bottom = std::clamp((int32_t)y, (int32_t)0, (int32_t)img.height-1);
    uint32_t top = std::clamp((int32_t)y+(int32_t)height, (int32_t)0, (int32_t)img.height-1)+1;
    
    ColorCameraRaw c;
    uint32_t i = 0;
    for (uint32_t iy=bottom; iy<top; iy++) {
        for (uint32_t ix=left; ix<right; ix++) {
            c[0] += sampleR(img, ix, iy);
            c[1] += sampleG(img, ix, iy);
            c[2] += sampleB(img, ix, iy);
            i++;
        }
    }
    
    c[0] /= i;
    c[1] /= i;
    c[2] /= i;
    return c;
}

static ColorCameraRaw sampleImageCircle(Image& img, uint32_t x, uint32_t y, uint32_t radius) {
    uint32_t left = std::clamp((int32_t)x-(int32_t)radius, (int32_t)0, (int32_t)img.width-1);
    uint32_t right = std::clamp((int32_t)x+(int32_t)radius, (int32_t)0, (int32_t)img.width-1)+1;
    uint32_t bottom = std::clamp((int32_t)y-(int32_t)radius, (int32_t)0, (int32_t)img.height-1);
    uint32_t top = std::clamp((int32_t)y+(int32_t)radius, (int32_t)0, (int32_t)img.height-1)+1;
    
    ColorCameraRaw c;
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

static double SRGBFromLSRGB(double x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4) - .055;
}

static double LSRGBFromSRGB(double x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.04045) return x/12.92;
    return pow((x+.055)/1.055, 2.4);
}

static ColorXYZD65 XYZFromSRGB(const ColorSRGBD65& srgb) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const ColorMatrix XYZFromLSRGB(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    
    // SRGB -> linear SRGB
    const Color3 lsrgb(LSRGBFromSRGB(srgb[0]), LSRGBFromSRGB(srgb[1]), LSRGBFromSRGB(srgb[2]));
    // Linear SRGB -> XYZ
    return XYZFromLSRGB*lsrgb;
}

static ColorSRGBD65 SRGBFromXYZ(const ColorXYZD65& xyz) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const ColorMatrix LSRGBFromXYZ(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660,  1.8760108,  0.0415560,
        0.0556434,  -0.2040259,  1.0572252
    );
    
    // XYZ -> linear SRGB
    const Color3 lsrgb = LSRGBFromXYZ*xyz;
    
    // Linear SRGB -> SRGB
    return ColorSRGBD65(
        SRGBFromLSRGB(lsrgb[0]),
        SRGBFromLSRGB(lsrgb[1]),
        SRGBFromLSRGB(lsrgb[2])
    );
}

static ColorXYYD65 XYYFromXYZ(const ColorXYZD65& xyz) {
    const double denom = xyz[0]+xyz[1]+xyz[2];
    const double x = xyz[0]/denom;
    const double y = xyz[1]/denom;
    const double Y = xyz[1];
    return {x, y, Y};
}

static ColorXYZD65 XYZFromXYY(const ColorXYYD65& xyy) {
    const double X = (xyy[0]*xyy[2])/xyy[1];
    const double Y = xyy[2];
    const double Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
    return {X, Y, Z};
}

- (IBAction)showHideColorCheckerCircles:(id)sender {
	_colorCheckerCirclesVisible = !_colorCheckerCirclesVisible;
    [_mainView setColorCheckerCirclesVisible:_colorCheckerCirclesVisible];
    [_showColorCheckerCirclesMenuItem setState:(_colorCheckerCirclesVisible ? NSControlStateValueOn : NSControlStateValueOff)];
    [self colorCheckerPositionsChanged];
}

- (void)eyeDropperRectChanged {
    const CGRect eyeDropperRect = [_mainView eyeDropperRect];
    const uint32_t x = round(eyeDropperRect.origin.x*_image.width);
    const uint32_t y = round(eyeDropperRect.origin.y*_image.height);
    const uint32_t width = round(eyeDropperRect.size.width*_image.width);
    const uint32_t height = round(eyeDropperRect.size.height*_image.height);
    const ColorCameraRaw color_cameraRaw = sampleImageRect(_image, x, y, width, height);
    const ColorXYZD65 color_XYZD65 = _colorMatrix*color_cameraRaw;
    const ColorSRGBD65 color_SRGBD65 = SRGBFromXYZ(color_XYZD65);
    
    [_colorText_cameraRaw setStringValue:
        [NSString stringWithFormat:@"%f %f %f", color_cameraRaw[0], color_cameraRaw[1], color_cameraRaw[2]]];
    [_colorText_XYZ_d50 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", color_XYZD65[0], color_XYZD65[1], color_XYZD65[2]]];
    [_colorText_SRGB_D65 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", color_SRGBD65[0], color_SRGBD65[1], color_SRGBD65[2]]];
}

- (void)colorCheckerPositionsChanged {
    auto points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorCheckerCount);
    
    Mat<double,ColorCheckerCount,3> A; // Colors that we have
    size_t i = 0;
    for (const CGPoint& p : points) {
        ColorCameraRaw c = sampleImageCircle(_image,
            round(p.x*_image.width),
            round(p.y*_image.height),
            _colorCheckerCircleRadius);
        A[i+0] = c[0];
        A[i+1] = c[1];
        A[i+2] = c[2];
        i += 3;
    }
    
    Mat<double,ColorCheckerCount,3> b; // Colors that we want
    i = 0;
    for (ColorSRGBD65 c : ColorCheckerColors) {
        // Convert the color from SRGB -> XYZ -> XYY
        ColorXYZD65 cxyy = XYYFromXYZ(XYZFromSRGB(c));
        cxyy[2] /= 3; // Adjust luminance
        
        const ColorXYZD65 cxyz = XYZFromXYY(cxyy);
        b[i+0] = cxyz[0];
        b[i+1] = cxyz[1];
        b[i+2] = cxyz[2];
        i += 3;
    }
    
    // Calculate the color matrix (x = (At*A)^-1 * At * b)
    auto x = (A.pinv() * b).trans();
    [self _updateColorMatrix:x];
    printf("Color matrix:\n%s\n", x.str().c_str());
    printf("Color matrix inverted:\n%s\n", x.inv().str().c_str());
    
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

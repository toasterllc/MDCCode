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

@interface NSObject ()
- (void)colorCheckerPointsChanged;
@end

using Color3 = Mat<double,3,1>;

constexpr size_t ColorCheckerCount = 24;
const Color3 ColorCheckerColors[ColorCheckerCount] {
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
    CALayer* _layer;
    ImageLayer* _imageLayer;
    CGFloat _colorCheckerCircleRadius;
    std::vector<CAShapeLayer*> _colorCheckerCircles;
    IBOutlet id _delegate;
}

- (void)commonInit {
    [super commonInit];
    _layer = [self layer];
    _colorCheckerCircleRadius = 1;
    _imageLayer = [ImageLayer new];
    [_layer addSublayer:_imageLayer];
    [_layer setLayoutManager:self];
    [_imageLayer setAffineTransform:CGAffineTransformMakeScale(1, -1)];
}

- (ImageLayer*)imageLayer {
    return _imageLayer;
}

// `p` is in coordinates of _layer
- (CAShapeLayer*)_findCircle:(CGPoint)p {
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

- (void)mouseDown:(NSEvent*)ev {
    NSWindow* win = [self window];
    const CGPoint p = [_imageLayer convertPoint:[ev locationInWindow]
        fromLayer:[[win contentView] layer]];
    
    CAShapeLayer* circle = [self _findCircle:p];
    if (!circle && _colorCheckerCircles.size()<ColorCheckerCount) {
        circle = [CAShapeLayer new];
        setCircleRadius(circle, _colorCheckerCircleRadius);
        
        auto rgb = ColorCheckerColors[_colorCheckerCircles.size()];
        [circle setFillColor:(CGColorRef)SRGBColor(rgb[0], rgb[1], rgb[2], 1)];
        [circle setActions:LayerNullActions()];
        
        [circle setPosition:p];
        [_imageLayer addSublayer:circle];
        _colorCheckerCircles.push_back(circle);
    }
    
    TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
        const CGPoint p = [_imageLayer convertPoint:[ev locationInWindow]
            fromLayer:[[win contentView] layer]];
        [circle setPosition:p];
    });
    
    [_delegate colorCheckerPointsChanged];
}

- (void)layoutSublayersOfLayer:(CALayer*)layer {
    if (layer == _layer) {
        CGSize layerSize = [_layer bounds].size;
        [_imageLayer setPosition:{layerSize.width/2, layerSize.height/2}];
    }
}

- (std::vector<CGPoint>)colorCheckerPoints {
    std::vector<CGPoint> r;
    CGSize layerSize = [_imageLayer bounds].size;
    for (CALayer* c : _colorCheckerCircles) {
        CGPoint p = [c position];
        p.x /= layerSize.width;
        p.y /= layerSize.height;
        r.push_back(p);
    }
    return r;
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
    
    float _colorCheckerCircleRadius;
    Mmap _imageData;
    Image _image;
}

static double srgbFromLinearSRGB(double x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4) - .055;
}

- (void)awakeFromNib {
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
  
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
    
    const Mat<double,3,3> XYZ_D50_From_XYZ_D65(
        1.0478112,  0.0228866,  -0.0501270,
        0.0295424,  0.9904844,  -0.0170491,
        -0.0092345, 0.0150436,  0.7521316
    );
    
    const Mat<double,3,3> XYZ_D65_From_XYZ_D50_Scaling(
        0.9857398,  0.0000000,  0.0000000,
        0.0000000,  1.0000000,  0.0000000,
        0.0000000,  0.0000000,  1.3194581
    );
    
    const Mat<double,3,3> XYZ_D65_From_XYZ_D50_Bradford(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    );
    
    const Mat<double,3,3> XYZ_D65_From_XYZ_D50_VonKries(
        0.9845002,  -0.0546158, 0.0676324,
        -0.0059992, 1.0047864,  0.0012095,
        0.0000000,  0.0000000,  1.3194581
    );
    
    const Mat<double,3,3> XYZ_From_LSRGB(
        0.4124564,  0.3575761,  0.1804375,
        0.2126729,  0.7151522,  0.0721750,
        0.0193339,  0.1191920,  0.9503041
    );
    
    const Mat<double,3,3> LSRGB_From_XYZ(
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
            srgbFromLinearSRGB(color_linearSRGB[0]),
            srgbFromLinearSRGB(color_linearSRGB[1]),
            srgbFromLinearSRGB(color_linearSRGB[2])
        );
        printf("%s\n", color_srgb.str(3).c_str());
    }
    
    
    
//    // TODO: try not applying srgb gamma
//    // TODO: try applying simple srgb gamma
//    
//    // SRGB gamma: complex
//    {
//        {
//            printf(
//                "Assuming raw values are XYZ.D65\n"
//                "Chromatic adaptation: none\n"
//                "SRGB Gamma: complex\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*color;
//            Color3 color_srgb = Color3(
//                srgbFromLinearSRGB(color_linearSRGB[0]),
//                srgbFromLinearSRGB(color_linearSRGB[1]),
//                srgbFromLinearSRGB(color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are XYZ.D50\n"
//                "Chromatic adaptation: XYZ scaling\n"
//                "SRGB Gamma: complex\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_Scaling*color;
//            Color3 color_srgb = Color3(
//                srgbFromLinearSRGB(color_linearSRGB[0]),
//                srgbFromLinearSRGB(color_linearSRGB[1]),
//                srgbFromLinearSRGB(color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are XYZ.D50\n"
//                "Chromatic adaptation: Bradford\n"
//                "SRGB Gamma: complex\n"
//            );
//            
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_Bradford*color;
//            Color3 color_srgb = Color3(
//                srgbFromLinearSRGB(color_linearSRGB[0]),
//                srgbFromLinearSRGB(color_linearSRGB[1]),
//                srgbFromLinearSRGB(color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are XYZ.D50\n"
//                "Chromatic adaptation: Von Kries\n"
//                "SRGB Gamma: complex\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_VonKries*color;
//            Color3 color_srgb = Color3(
//                srgbFromLinearSRGB(color_linearSRGB[0]),
//                srgbFromLinearSRGB(color_linearSRGB[1]),
//                srgbFromLinearSRGB(color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are SRGB.D65\n"
//                "Chromatic adaptation: none\n"
//                "SRGB Gamma: complex\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = color;
//            Color3 color_srgb = Color3(
//                srgbFromLinearSRGB(color_linearSRGB[0]),
//                srgbFromLinearSRGB(color_linearSRGB[1]),
//                srgbFromLinearSRGB(color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//    }
//    
//    
//    
//    // SRGB gamma: none
//    {
//        {
//            printf(
//                "Assuming raw values are XYZ.D65\n"
//                "Chromatic adaptation: none\n"
//                "SRGB Gamma: none\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*color;
//            Color3 color_srgb = Color3(
//                (color_linearSRGB[0]),
//                (color_linearSRGB[1]),
//                (color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are XYZ.D50\n"
//                "Chromatic adaptation: XYZ scaling\n"
//                "SRGB Gamma: none\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_Scaling*color;
//            Color3 color_srgb = Color3(
//                (color_linearSRGB[0]),
//                (color_linearSRGB[1]),
//                (color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are XYZ.D50\n"
//                "Chromatic adaptation: Bradford\n"
//                "SRGB Gamma: none\n"
//            );
//            
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_Bradford*color;
//            Color3 color_srgb = Color3(
//                (color_linearSRGB[0]),
//                (color_linearSRGB[1]),
//                (color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//        
//        {
//            printf(
//                "Assuming raw values are XYZ.D50\n"
//                "Chromatic adaptation: Von Kries\n"
//                "SRGB Gamma: none\n"
//            );
//            Color3 color((double)_image.pixels[0], (double)_image.pixels[0], (double)_image.pixels[0]);
//            color = color/0xFFFF;
//            Color3 color_linearSRGB = LSRGB_From_XYZ*XYZ_D65_From_XYZ_D50_VonKries*color;
//            Color3 color_srgb = Color3(
//                (color_linearSRGB[0]),
//                (color_linearSRGB[1]),
//                (color_linearSRGB[2])
//            );
//            printf("%s\n", color_srgb.str(3).c_str());
//        }
//    }
}

- (void)controlTextDidChange:(NSNotification*)note {
    if ([note object] == _colorMatrixTextField) {
        [self _updateColorMatrix];
    }
}

- (void)_updateColorMatrix {
    const std::string str([[_colorMatrixTextField stringValue] UTF8String]);
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

- (void)_updateColorMatrix:(double[])vals {
    const ColorMatrix cm{
        {(float)vals[0], (float)vals[3], (float)vals[6]},   // Column 0
        {(float)vals[1], (float)vals[4], (float)vals[7]},   // Column 1
        {(float)vals[2], (float)vals[5], (float)vals[8]}    // Column 2
    };
    [[_mainView imageLayer] updateColorMatrix:cm];
}

- (void)_updateHistograms {
    [[_inputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] inputHistogram]];
    [[_outputHistogramView histogramLayer] updateHistogram:[[_mainView imageLayer] outputHistogram]];
    
//    auto hist = [[_mainView imageLayer] outputHistogram];
//    size_t i = 0;
//    for (uint32_t& val : hist.r) {
//        if (!val) continue;
//        printf("[%ju]: %ju\n", (uintmax_t)i, (uintmax_t)val);
//        i++;
//    }
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

static Color3 sampleImage(Image& img, uint32_t x, uint32_t y, uint32_t radius) {
    uint32_t left = std::clamp((int32_t)x-(int32_t)radius, (int32_t)0, (int32_t)img.width-1);
    uint32_t right = std::clamp((int32_t)x+(int32_t)radius, (int32_t)0, (int32_t)img.width-1)+1;
    uint32_t bottom = std::clamp((int32_t)y-(int32_t)radius, (int32_t)0, (int32_t)img.height-1);
    uint32_t top = std::clamp((int32_t)y+(int32_t)radius, (int32_t)0, (int32_t)img.height-1)+1;
    
    Color3 c;
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

//static Color3 sampleImage(uint32_t x, uint32_t y, uint32_t win) {
//    
//    return {};
//}

static double linearSRGBFromSRGB(double x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.04045) return x/12.92;
    return pow((x+.055)/1.055, 2.4);
}

static Color3 xyzFromSRGB(const Color3 c) {
    // Calculate the linear SRGB value from the gamma-ified SRGB value
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const Color3 linearSRGB(
        linearSRGBFromSRGB(c[0]),
        linearSRGBFromSRGB(c[1]),
        linearSRGBFromSRGB(c[2])
    );
    // Calculate the XYZ values from the linear SRGB values
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const Mat<double,3,3> xyzFromLinearSRGB(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    return xyzFromLinearSRGB*linearSRGB;
}

- (void)colorCheckerPointsChanged {
    auto points = [_mainView colorCheckerPoints];
    // Short-circuit until we have all the color-checker points
    if (points.size() != ColorCheckerCount) return;
    
    Mat<double,ColorCheckerCount,3> A; // Colors that we have
    size_t i = 0;
    for (const CGPoint& p : points) {
        Color3 c = sampleImage(_image,
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
    for (Color3 c : ColorCheckerColors) {
        // Convert the color from SRGB -> XYZ
        c = xyzFromSRGB(c);
        b[i+0] = c[0];
        b[i+1] = c[1];
        b[i+2] = c[2];
        i += 3;
    }
    
    // Calculate the color matrix (x = (At*A)^-1 * At * b)
    auto x = (A.pinv() * b).trans();
    [self _updateColorMatrix:x.vals];
    printf("Color matrix:\n%s\n", x.str().c_str());
    printf("Color matrix inverted:\n%s\n", x.inv().str().c_str());
    
    [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f\n"
        @"%f %f %f\n"
        @"%f %f %f\n",
        x[0], x[1], x[2],
        x[3], x[4], x[5],
        x[6], x[7], x[8]
    ]];
    
//    printf("%.3f\t%.3f\t%.3f \n%.3f\t%.3f\t%.3f \n%.3f\t%.3f\t%.3f \n",
//        x[0], x[1], x[2],
//        x[3], x[4], x[5],
//        x[6], x[7], x[8]
//    );
}

@end

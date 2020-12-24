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
using namespace CFAViewer;
using namespace MetalTypes;
using namespace ImageLayerTypes;

@interface NSObject ()
- (void)colorCheckerPointsChanged;
@end

struct Color3 {
    float r = 0;
    float g = 0;
    float b = 0;
};

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
        [circle setFillColor:(CGColorRef)SRGBColor(rgb.r, rgb.g, rgb.b, 1)];
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

template <typename T, size_t M, size_t N>
class Mat {
public:
    Mat() {}
    
    // Copy constructor: use copy assignment operator
    Mat(const Mat& x) { *this = x; }
    // Copy assignment operator
    Mat& operator=(const Mat& x) {
        memcpy(vals, x.vals, sizeof(vals));
        return *this;
    }
    
    template <typename... Ts>
    Mat(Ts... vals) : vals{vals...} {
        static_assert(sizeof...(vals)==M*N, "invalid number of values");
    }
    
    Mat<T,N,M> trans() {
        Mat<T,N,M> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mtrans(vals, 1, r.vals, 1, N, M);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mtransD(vals, 1, r.vals, 1, N, M);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    Mat<T,M,N> inv() {
        static_assert(M==N, "not a square matrix");
        
        Mat<T,M,M> r;
        memcpy(r.vals, vals, sizeof(vals));
        
        __CLPK_integer m = M;
        __CLPK_integer err = 0;
        __CLPK_integer pivot[m];
        T tmp[m];
        if constexpr(std::is_same_v<T, float>) {
            sgetrf_(&m, &m, r.vals, &m, pivot, &err);
            if (err) throw std::runtime_error("dgetrf_ failed");
            
            sgetri_(&m, r.vals, &m, pivot, tmp, &m, &err);
            if (err) throw std::runtime_error("dgetri_ failed");
        
        } else if constexpr(std::is_same_v<T, double>) {
            dgetrf_(&m, &m, r.vals, &m, pivot, &err);
            if (err) throw std::runtime_error("dgetrf_ failed");
            
            dgetri_(&m, r.vals, &m, pivot, tmp, &m, &err);
            if (err) throw std::runtime_error("dgetri_ failed");
        
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Moore-Penrose inverse
    Mat<T,N,M> pinv() {
        return (trans()*(*this)).inv()*trans();
    }
    
    template <size_t P>
    Mat<T,M,P> operator*(const Mat<T,N,P>& x) {
        Mat<T,M,P> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mmul(vals, 1, x.vals, 1, r.vals, 1, M, P, N);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mmulD(vals, 1, x.vals, 1, r.vals, 1, M, P, N);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    T vals[M*N] = {};

private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
};


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

- (void)awakeFromNib {
    Mat<double,3,2> A(
        2., -1.,
        1.,  2.,
        1.,  1.
    );
    
    Mat<double,3,1> b(
        2.,
        1.,
        4.
    );
    
    auto x = A.pinv() * b;
    printf("AAA\n");
    
//    Mat<float,2,2> A(5.f, 6.f, 7.f, 8.f);
//    auto B = A.inverse();
//    printf("AAA\n");
//    Mat<float,2,2> A(1.f,2.f,2.f,2.f);
//    Mat<float,2,2> B(1.f,2.f,2.f,2.f);
//    A*B;
//    Mat<int,2,2> A(1.f,2.f,2.f,2.f);
//    A.transpose();
    
//    const size_t Ah = 3;
//    const size_t Aw = 2;
//    float A[Ah*Aw] = {
//        2, -1,
//        1,  2,
//        1,  1,
//    };
//    
//    float b[] = {
//        2,
//        1,
//        4,
//    };
//    
//    // Calculate A transpose
//    float At[Aw*Ah] = {};
//    vDSP_mtrans(A, 1, At, 1, Aw, Ah);
//    
//    // Calculate At*A
//    float AtA[Aw*Aw] = {};
//    vDSP_mmul(At, 1, A, 1, AtA, 1, Aw, Aw, Ah);
//    
//    // Calculate (At*A)^-1
//    float AtA[Aw*Aw] = {};
    
//    float min[] = {
//        1,0,0,  // Column 1
//        1,0,0,  // Column 2
//        1,0,0,  // Column 3
//    };
//    
//    float mout[std::size(min)] = {};
//    
//    vDSP_mtrans(min, 1, mout, 1, 3, 3);
    printf("AAA\n");
    return;
    
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    _imageData = Mmap("/Users/dave/Desktop/img.cfa");
    
//    Mmap imageData("/Users/dave/repos/ImageProcessing/PureColor.cfa");
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
    std::vector<float> floats;
    
    for (std::sregex_iterator i=begin; i!=end; i++) {
        floats.push_back(std::stod(i->str()));
    }
    
    if (floats.size() != 9) {
        NSLog(@"Failed to parse color matrix");
        return;
    }
    
    const ColorMatrix cm{
        {floats[0], floats[3], floats[6]},  // Column 0
        {floats[1], floats[4], floats[7]},  // Column 1
        {floats[2], floats[5], floats[8]}   // Column 2
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

static float px(Image& img, uint32_t x, int32_t dx, uint32_t y, int32_t dy) {
    int32_t xc = (int32_t)x + dx;
    int32_t yc = (int32_t)y + dy;
    xc = std::clamp(xc, (int32_t)0, (int32_t)img.width-1);
    yc = std::clamp(yc, (int32_t)0, (int32_t)img.height-1);
    return (float)img.pixels[(yc*img.width)+xc] / ImagePixelMax;
}

static float sampleR(Image& img, uint32_t x, uint32_t y) {
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

static float sampleG(Image& img, uint32_t x, uint32_t y) {
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

static float sampleB(Image& img, uint32_t x, uint32_t y) {
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
    
    printf("%ju %ju\n", (uintmax_t)x, (uintmax_t)y);
    
    Color3 c;
    uint32_t i = 0;
    for (uint32_t iy=bottom; iy<top; iy++) {
        for (uint32_t ix=left; ix<right; ix++) {
            if (sqrt(pow((double)ix-x,2) + pow((double)iy-y,2)) < (double)radius) {
                c.r += sampleR(img, ix, iy);
                c.g += sampleG(img, ix, iy);
                c.b += sampleB(img, ix, iy);
                i++;
            }
        }
    }
    
    c.r /= i;
    c.g /= i;
    c.b /= i;
    return c;
}

//static Color3 sampleImage(uint32_t x, uint32_t y, uint32_t win) {
//    
//    return {};
//}

- (void)colorCheckerPointsChanged {
    auto points = [_mainView colorCheckerPoints];
    // Short-circuit until we have all the color-checker points
    if (points.size() != ColorCheckerCount) return;
    
    Color3 colorCheckerColors[ColorCheckerCount];
    for (size_t i=0; i<ColorCheckerCount; i++) {
        CGPoint p = points[i];
        colorCheckerColors[i] = sampleImage(_image,
            round(p.x*_image.width),
            round(p.y*_image.height),
            _colorCheckerCircleRadius);
    }
    
    const auto& A = colorCheckerColors; // have
    const auto& b = ColorCheckerColors; // want
}

@end

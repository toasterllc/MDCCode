#import "BaseView.h"
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

@interface MainView : BaseView <CALayoutManager>
@end

@implementation MainView {
    CALayer* _layer;
    ImageLayer* _imageLayer;
    float _circleRadius;
    std::vector<CAShapeLayer*> _circles;
}

- (void)commonInit {
    [super commonInit];
    _layer = [self layer];
    _circleRadius = 10;
    _imageLayer = [ImageLayer new];
    [_layer addSublayer:_imageLayer];
    [_layer setLayoutManager:self];
}

- (ImageLayer*)imageLayer {
    return _imageLayer;
}

// `p` is in coordinates of _layer
- (CAShapeLayer*)_findCircle:(CGPoint)p {
    for (CAShapeLayer* c : _circles) {
        const CGPoint cp = [c position];
        if (sqrt(pow(cp.x-p.x,2)+pow(cp.y-p.y,2)) < _circleRadius) {
            return c;
        }
    }
    return nil;
}

struct RGB {
    float r;
    float g;
    float b;    
};

const RGB ColorCheckerColors[] {
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

- (void)mouseDown:(NSEvent*)ev {
    NSWindow* win = [self window];
    const CGPoint p = [_imageLayer convertPoint:[ev locationInWindow]
        fromLayer:[[win contentView] layer]];
    const size_t MaxCircleCount = std::size(ColorCheckerColors);
    
    CAShapeLayer* circle = [self _findCircle:p];
    if (!circle && _circles.size()<MaxCircleCount) {
        circle = [CAShapeLayer new];
        [circle setPath:
            (CGPathRef)CFBridgingRelease(CGPathCreateWithEllipseInRect({0,0,_circleRadius*2,_circleRadius*2}, nil))];
        [circle setBounds:{0,0,_circleRadius*2,_circleRadius*2}];
        
        auto rgb = ColorCheckerColors[_circles.size()];
        [circle setFillColor:(CGColorRef)SRGBColor(rgb.r, rgb.g, rgb.b, 1)];
        [circle setActions:LayerNullActions()];
        
        [circle setPosition:p];
        [_imageLayer addSublayer:circle];
        _circles.push_back(circle);
    }
    
    TrackMouse(win, ev, [&](NSEvent* ev, bool done) {
        const CGPoint p = [_imageLayer convertPoint:[ev locationInWindow]
            fromLayer:[[win contentView] layer]];
        [circle setPosition:p];
    });
}

- (void)layoutSublayersOfLayer:(CALayer*)layer {
    if (layer == _layer) {
        CGSize layerSize = [_layer bounds].size;
        [_imageLayer setPosition:{layerSize.width/2, layerSize.height/2}];
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
}

- (void)awakeFromNib {
    Mmap imageData("/Users/dave/Desktop/img.cfa");
//    Mmap imageData("/Users/dave/repos/ImageProcessing/PureColor.cfa");
    constexpr size_t ImageWidth = 2304;
    constexpr size_t ImageHeight = 1296;
    Image image = {
        .width = ImageWidth,
        .height = ImageHeight,
        .pixels = (MetalTypes::ImagePixel*)imageData.data(),
    };
    [[_mainView imageLayer] updateImage:image];
    
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

@end

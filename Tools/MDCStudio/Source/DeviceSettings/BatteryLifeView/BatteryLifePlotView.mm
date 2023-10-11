#import <QuartzCore/QuartzCore.h>
#import "BatteryLifePlotView.h"
#import "BatteryLifeSimulator.h"
#import "Code/Lib/Toastbox/Mac/Util.h"

using namespace MDCStudio;

//@interface BatteryLifePlotLayer : CAShapeLayer
//- (void)setPoints:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)points;
//@end
//
//@implementation BatteryLifePlotLayer {
//    std::vector<BatteryLifeSimulator::Point> _points;
//    CGFloat _widthFactor;
//}
//
//- (instancetype)init {
//    if (!(self = [super init])) return nil;
//    [self setNeedsDisplayOnBoundsChange:true];
//    [self setActions:Toastbox::LayerNullActions];
//    _widthFactor = 1;
//    return self;
//}
//
//- (const std::vector<BatteryLifeSimulator::Point>&)points {
//    return _points;
//}
//
//- (void)setPoints:(std::vector<BatteryLifeSimulator::Point>)points {
//    _points = std::move(points);
//    [self setNeedsDisplay];
//}
//
//- (CGFloat)widthFactor {
//    return _widthFactor;
//}
//
//- (void)setWidthFactor:(float)x {
//    _widthFactor = x;
//}
//
//- (void)display {
//    auto debugTimeStart = std::chrono::steady_clock::now();
//    
//    const CGSize size = [self frame].size;
//    id /* CGMutablePathRef */ path = CFBridgingRelease(CGPathCreateMutable());
//    CGPathMoveToPoint((CGMutablePathRef)path, nullptr, 0, 0);
//    CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, 0, size.height);
//    
//    if (!_points.empty()) {
//        const CGFloat duration = (_points.back().time - _points.front().time).count();
//        CGPoint p = {};
//        for (const BatteryLifeSimulator::Point& pt : _points) {
//            const CGFloat xnorm = (pt.time - _points.front().time).count() / duration;
//            p.x = xnorm * size.width * _widthFactor;
//            p.y = pt.batteryLevel * size.height;
//            CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, p.x, p.y);
//        }
//        CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, p.x, 0);
//    }
//    CGPathCloseSubpath((CGMutablePathRef)path);
//    
//    [self setPath:(CGPathRef)path];
//    
//    auto debugTimeEnd = std::chrono::steady_clock::now();
//    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(debugTimeEnd-debugTimeStart);
//    printf("PLOT TIME: %ju ms\n", (uintmax_t)durationMs.count());
//}
//
//@end


@interface BatteryLifePlotView () <CALayerDelegate>
@end

@implementation BatteryLifePlotView {
    CAShapeLayer* _layer;
    std::vector<BatteryLifeSimulator::Point> _points;
}

static void _Init(BatteryLifePlotView* self) {
    self->_layer = [CAShapeLayer new];
    [self->_layer setNeedsDisplayOnBoundsChange:true];
    [self->_layer setActions:Toastbox::LayerNullActions];
    [self->_layer setDelegate:self];
    [self setLayer:self->_layer];
    [self setWantsLayer:true];
    
//    self->_maxLayer = [BatteryLifePlotLayer new];
//    [self->_layer addSublayer:self->_maxLayer];
//    [self->_maxLayer setFillColor:[[NSColor colorWithSRGBRed:.184 green:.510 blue:.922 alpha:1] CGColor]];
//    
//    self->_minLayer = [BatteryLifePlotLayer new];
//    [self->_layer addSublayer:self->_minLayer];
//    [self->_minLayer setFillColor:[[[NSColor blackColor] colorWithAlphaComponent:.4] CGColor]];
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _Init(self);    
    return self;
}

- (void)displayLayer:(CALayer*)layer {
    // YMin: minimum y value when plotting
    constexpr CGFloat YMin = 0.5;
    
    assert(layer == _layer);
    
    auto debugTimeStart = std::chrono::steady_clock::now();
    
    const CGSize size = [self frame].size;
    id /* CGMutablePathRef */ path = CFBridgingRelease(CGPathCreateMutable());
    CGPathMoveToPoint((CGMutablePathRef)path, nullptr, 0, 0);
    CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, 0, size.height);
    
    if (!_points.empty()) {
        const CGFloat duration = (_points.back().time - _points.front().time).count();
        CGPoint p = {};
        for (const BatteryLifeSimulator::Point& pt : _points) {
            const CGFloat xnorm = (pt.time - _points.front().time).count() / duration;
            p.x = xnorm * size.width;
            p.y = std::max(YMin, pt.batteryLevel * size.height);
            CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, p.x, p.y);
        }
        CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, p.x, 0);
    }
    CGPathCloseSubpath((CGMutablePathRef)path);
    
    [_layer setPath:(CGPathRef)path];
    
    auto debugTimeEnd = std::chrono::steady_clock::now();
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(debugTimeEnd-debugTimeStart);
    printf("PLOT TIME: %ju ms\n", (uintmax_t)durationMs.count());
}

//- (void)layoutSublayersOfLayer:(CALayer*)layer {
//    assert(layer == _layer);
//    const CGRect frame = [_layer bounds];
//    [_minLayer setFrame:frame];
//    [_maxLayer setFrame:frame];
//}

- (void)setPoints:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)x {
    _points = std::move(x);
    [_layer setNeedsDisplay];
}

//- (void)_updateWidthFactor {
//    if ([_minLayer points].empty() || [_maxLayer points].empty()) return;
//    const CGFloat x = (CGFloat)[_minLayer points].back().time.count() / [_maxLayer points].back().time.count();
//    [_minLayer setWidthFactor:x];
//}
//
//- (CGFloat)minEndX {
//    return [_minLayer widthFactor] * [self frame].size.width;
//}

- (CAShapeLayer*)plotLayer {
    return _layer;
}

@end

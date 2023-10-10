#import <Cocoa/Cocoa.h>
#import "BatteryLifePlotLayer.h"
using namespace MDCStudio;

@implementation BatteryLifePlotLayer {
    std::vector<BatteryLifeSimulator::Point> _points;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [self setNeedsDisplayOnBoundsChange:true];
    [self setFillColor:[[NSColor redColor] CGColor]];
    return self;
}

- (void)setPoints:(std::vector<BatteryLifeSimulator::Point>)points {
    _points = std::move(points);
    [self setNeedsDisplay];
}

- (void)display {
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
            p.y = pt.batteryLevel * size.height;
            CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, p.x, p.y);
        }
        CGPathAddLineToPoint((CGMutablePathRef)path, nullptr, p.x, 0);
    }
    CGPathCloseSubpath((CGMutablePathRef)path);
    
    [self setPath:(CGPathRef)path];
    
    auto debugTimeEnd = std::chrono::steady_clock::now();
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(debugTimeEnd-debugTimeStart);
    printf("PLOT TIME: %ju ms\n", (uintmax_t)durationMs.count());
}

@end

#import "AnchoredMetalDocumentLayer.h"
#import <algorithm>
#import <cmath>
#import "Tools/Shared/Mat.h"

static Mat<float,4,4> _Scale(float x, float y, float z) {
    return {
        x,   0.f, 0.f, 0.f,
        0.f, y,   0.f, 0.f,
        0.f, 0.f, z,   0.f,
        0.f, 0.f, 0.f, 1.f,
    };
}

static Mat<float,4,4> _Translate(float x, float y, float z) {
    return {
        1.f, 0.f, 0.f, x,
        0.f, 1.f, 0.f, y,
        0.f, 0.f, 1.f, z,
        0.f, 0.f, 0.f, 1.f,
    };
}

static simd::float4x4 _SIMDForMat(const Mat<float,4,4>& m) {
    return {
        simd::float4{m.at(0,0), m.at(1,0), m.at(2,0), m.at(3,0)},
        simd::float4{m.at(0,1), m.at(1,1), m.at(2,1), m.at(3,1)},
        simd::float4{m.at(0,2), m.at(1,2), m.at(2,2), m.at(3,2)},
        simd::float4{m.at(0,3), m.at(1,3), m.at(2,3), m.at(3,3)},
    };
}

@implementation AnchoredMetalDocumentLayer {
@private
    CGPoint _translation;
    CGFloat _magnification;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [self setOpaque:true];
    [self setNeedsDisplayOnBoundsChange:true];
    [self setAllowsNextDrawableTimeout:false];
    [self setPresentsWithTransaction:true];
    return self;
}

- (void)display {
    const CGRect frame = [self frame];
    const CGFloat contentsScale = [self contentsScale];
    const size_t drawableWidth = std::max(1., std::round(frame.size.width*_magnification*contentsScale));
    const size_t drawableHeight = std::max(1., std::round(frame.size.height*_magnification*contentsScale));
    [self setDrawableSize:{(CGFloat)drawableWidth, (CGFloat)drawableHeight}];
}

- (CGPoint)anchoredTranslation {
    return _translation;
}

- (CGFloat)anchoredMagnification {
    return _magnification;
}

- (simd_float4x4)anchoredTransform {
    const CGRect frame = [self frame];
    // We expect our superlayer's size to be the full content size
    const CGSize contentSize = [[self superlayer] bounds].size;
    const int flip = [self isGeometryFlipped] ? -1 : 1;
    const Mat<float,4,4> transform =
        _Translate(-1, -1*flip, 1)                          *
        _Scale(2, 2*flip, 1)                                *
        _Scale(1/frame.size.width, 1/frame.size.height, 1)  *
        _Translate(-_translation.x, -_translation.y, 0)     *
        _Scale(contentSize.width, contentSize.height, 1)    ;
    
    return _SIMDForMat(transform);
}

// MARK: - CALayer Overrides

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

// Disable implicit animation
- (id<CAAction>)actionForKey:(NSString*)event {
    return nil;
}

// MARK: - AnchoredScrollViewDocument Protocol

- (void)anchoredTranslationChanged:(CGPoint)t magnification:(CGFloat)m {
    _translation = t;
    _magnification = m;
    [self setNeedsDisplay];
}

- (bool)anchoredFlipped {
    return false;
}

@end

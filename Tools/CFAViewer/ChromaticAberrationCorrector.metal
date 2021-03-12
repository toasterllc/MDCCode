#import <metal_stdlib>
#import "ImageLayerTypes.h"
#import "ImageLayerShaderTypes.h"
using namespace metal;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;

namespace Clamp {
    template <typename Pt>
    uint Edge(uint bound, Pt pt, int delta=0) {
        const int ptd = (int)pt+delta;
        if (ptd < 0) return 0;
        if (ptd >= (int)bound) return bound-1;
        return ptd;
    }

    template <typename Pt>
    uint2 Edge(uint2 bound, Pt pt, int2 delta=0) {
        return {
            Edge(bound.x, pt.x, delta.x),
            Edge(bound.y, pt.y, delta.y)
        };
    }
    
    template <typename Pt>
    uint Mirror(uint bound, Pt pt, int delta=0) {
        const int ptd = (int)pt+delta;
        if (ptd < 0) return -ptd;
        if (ptd >= (int)bound) return 2*((int)bound-1)-ptd;
        return ptd;
    }

    template <typename Pt>
    uint2 Mirror(uint2 bound, Pt pt, int2 delta=0) {
        return {
            Mirror(bound.x, pt.x, delta.x),
            Mirror(bound.y, pt.y, delta.y)
        };
    }
}

namespace Sample {
    float3 RGB(texture2d<float> txt, int2 pos, int2 delta=0) {
        return txt.sample(coord::pixel, float2(pos.x+delta.x+.5, pos.y+delta.y+.5)).rgb;
    }
    
    float R(texture2d<float> txt, int2 pos, int2 delta=0) {
        return RGB(txt, pos, delta).r;
    }
}

namespace ChromaticAberrationCorrector {

constant float Eps = 1e-5;


//template <typename Pt>
//uint edgeClamp(uint bound, Pt pt, int delta=0) {
//    const int ptd = (int)pt+delta;
//    if (ptd < 0) return 0;
//    if (ptd >= (int)bound) return bound-1;
//    return ptd;
//}
//
//template <typename Pt>
//uint2 edgeClamp(uint2 bound, Pt pt, int2 delta=0) {
//    return {
//        edgeClamp(bound.x, pt.x, delta.x),
//        edgeClamp(bound.y, pt.y, delta.y)
//    };
//}

constant float WhiteBalanceRed = 0.296587/0.203138;
constant float WhiteBalanceGreen = 0.296587/0.296587;
constant float WhiteBalanceBlue = 0.296587/0.161148;

fragment float WhiteBalanceForward(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    const float s = Sample::R(raw, pos);
    switch (c) {
    case CFAColor::Red:     return s*WhiteBalanceRed;
    case CFAColor::Green:   return s*WhiteBalanceGreen;
    case CFAColor::Blue:    return s*WhiteBalanceBlue;
    }
}

fragment float WhiteBalanceReverse(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    const float s = Sample::R(raw, pos);
    switch (c) {
    case CFAColor::Red:     return s/WhiteBalanceRed;
    case CFAColor::Green:   return s/WhiteBalanceGreen;
    case CFAColor::Blue:    return s/WhiteBalanceBlue;
    }
}

// Interpolate the G channel using a directional weighted average
fragment float InterpolateG(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    // Green pixel: pass-through
    if (c == CFAColor::Green) return Sample::R(raw, pos);
    
    // TODO: mirrorClamp values that are out of range of the image
    
    // Red/blue pixel: directional weighted average, preferring the direction with least change
#define PX(dx,dy) Sample::R(raw, pos, {(dx),(dy)})
    const float ku =
        1/(Eps+pow(
            abs(PX(  0 , +1 ) - PX( 0 , -1 )) +
            abs(PX(  0 ,  0 ) - PX( 0 , -2 )) +
            abs(PX(  0 , -1 ) - PX( 0 , -3 )) ,
        2));
    
    const float kd =
        1/(Eps+pow(
            abs(PX(  0 , -1 ) - PX( 0 , +1 )) +
            abs(PX(  0 ,  0 ) - PX( 0 , +2 )) +
            abs(PX(  0 , +1 ) - PX( 0 , +3 )) ,
        2));
    
    const float kl =
        1/(Eps+pow(
            abs(PX( +1 ,  0 ) - PX( -1 , 0 )) +
            abs(PX(  0 ,  0 ) - PX( -2 , 0 )) +
            abs(PX( -1 ,  0 ) - PX( -3 , 0 )) ,
        2));
    
    const float kr =
        1/(Eps+pow(
            abs(PX( -1 ,  0 ) - PX( +1 , 0 )) +
            abs(PX(  0 ,  0 ) - PX( +2 , 0 )) +
            abs(PX( +1 ,  0 ) - PX( +3 , 0 )) ,
        2));
    
    return (
        ku * PX(  0 , -1 ) +
        kd * PX(  0 , +1 ) +
        kl * PX( -1 ,  0 ) +
        kr * PX( +1 ,  0 )
    ) / (ku + kd + kl + kr);
    
#undef PX
}

fragment float CalcRBGDelta(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> gInterp [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(in.pos.x, in.pos.y);
    switch (ctx.cfaColor(pos)) {
    case CFAColor::Red:
    case CFAColor::Blue: {
        const float rb = Sample::R(raw, pos);
        const float g = Sample::R(gInterp, pos);
        return rb-g;
    }
    case CFAColor::Green: return 0;
    }
}

//fragment float CalcSlopeX(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos(in.pos.x, in.pos.y);
//    const uint2 bounds(txt.get_width(), txt.get_height());
//#define PX(dx,dy) Sample::R(txt, Clamp::Edge(bounds, pos, {(dx),(dy)}))
//    switch (ctx.cfaColor(pos)) {
//    case CFAColor::Red:
//    case CFAColor::Blue:
//        return
//            ( 3./16)*(PX(+1,+1) - PX(-1,+1)) +
//            (10./16)*(PX(+1, 0) - PX(-1, 0)) +
//            ( 3./16)*(PX(+1,-1) - PX(-1,-1)) ;
//    default:
//        return 0;
//    }
//#undef PX
//}
//
//fragment float CalcSlopeY(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
////    return floor(in.pos.x)/100 + floor(in.pos.y)/100;
//    const int2 pos(in.pos.x, in.pos.y);
////    if (pos.y>=10 && pos.y<600) return 1;
////    return 0;
//    const uint2 bounds(txt.get_width(), txt.get_height());
//#define PX(dx,dy) Sample::R(txt, Clamp::Edge(bounds, pos, {(dx),(dy)}))
//    switch (ctx.cfaColor(pos)) {
//    case CFAColor::Red:
//    case CFAColor::Blue:
//        return
//            ( 3./16)*(PX(+1,+1) - PX(+1,-1)) +
//            (10./16)*(PX( 0,+1) - PX( 0,-1)) +
//            ( 3./16)*(PX(-1,+1) - PX(-1,-1)) ;
//    default: return 0;
//    }
//#undef PX
//}

float gshift(texture2d<float> gInterp, float2 shift, int2 pos) {
    const sampler samplr(coord::pixel, filter::linear);
    return gInterp.sample(samplr, float2(pos.x+.5, pos.y+.5)+shift).r;
}

float grbdiff(texture2d<float> raw, texture2d<float> gInterp, float2 shift, int2 pos) {
    const float gShift = gshift(gInterp, shift, pos);
    const float rb = Sample::R(raw, pos);
    return gShift - rb;
}

fragment float ApplyCorrection(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> gInterp [[texture(1)]],
    texture2d<float> shiftsRedX [[texture(2)]],
    texture2d<float> shiftsRedY [[texture(3)]],
    texture2d<float> shiftsBlueX [[texture(4)]],
    texture2d<float> shiftsBlueY [[texture(5)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    
    float2 shift = 0;
    switch (c) {
    case CFAColor::Red:
        shift = {
            shiftsRedX.sample(filter::linear, in.posUnit).r,
            shiftsRedY.sample(filter::linear, in.posUnit).r
        };
        break;
    case CFAColor::Green:
        return Sample::R(raw, pos); // Green pixel: pass through
    case CFAColor::Blue:
        shift = {
            shiftsBlueX.sample(filter::linear, in.posUnit).r,
            shiftsBlueY.sample(filter::linear, in.posUnit).r
        };
        break;
    }
    
    constexpr float ShiftLimit = 4;
    constexpr float Alpha = .25;
    constexpr float Beta = .5;
    
    shift.x = clamp(shift.x, -ShiftLimit, ShiftLimit);
    shift.y = clamp(shift.y, -ShiftLimit, ShiftLimit);
    
    const sampler samplr(coord::pixel, filter::linear);
    const float g = Sample::R(gInterp, pos);
    const float rb = Sample::R(raw, pos);
    const float gShift = gshift(gInterp, shift, pos);
    const float gShiftRBDelta = gShift - rb;
    const float rbInterp = g - gShiftRBDelta;
    const float grbDelta = g - rb;
    
    float rbCorrected = rb;
    if (abs(rbInterp-rb) < Alpha*(rbInterp+rb)) {
        if (abs(gShiftRBDelta) < abs(grbDelta)) {
            rbCorrected = rbInterp;
        }
    } else {
        const int2 d = {
            shift.x >= 0 ? -2 : 2,
            shift.y >= 0 ? -2 : 2,
        };
        
        // TODO: we should mirror clamp gshift/grbdiff values that go out of range
        // Gradient weights using difference from G at CA shift points and G at grid points
        const float w00 = 1 / (Eps + abs(g - gshift(gInterp, shift, pos+int2{0  ,  0})));
        const float wx0 = 1 / (Eps + abs(g - gshift(gInterp, shift, pos+int2{d.x,  0})));
        const float w0y = 1 / (Eps + abs(g - gshift(gInterp, shift, pos+int2{0  ,d.y})));
        const float wxy = 1 / (Eps + abs(g - gshift(gInterp, shift, pos+int2{d.x,d.y})));
        const float numer =
            w00 * grbdiff(raw, gInterp, shift, pos+int2{0  ,  0}) +
            wx0 * grbdiff(raw, gInterp, shift, pos+int2{d.x,  0}) +
            w0y * grbdiff(raw, gInterp, shift, pos+int2{0  ,d.y}) +
            wxy * grbdiff(raw, gInterp, shift, pos+int2{d.x,d.y}) ;
        const float denom = w00+wx0+w0y+wxy;
        const float gShiftRBDelta = numer/denom;
        
        if (abs(gShiftRBDelta) < abs(grbDelta)) {
            rbCorrected = g - gShiftRBDelta;
        }
    }
    
    if (grbDelta*gShiftRBDelta < 0) {
        // The colour difference interpolation overshot the correction, just desaturate
        if (abs(gShiftRBDelta/grbDelta) < 5) {
            rbCorrected = g - Beta*(grbDelta+gShiftRBDelta);
        }
    }
    
    return rbCorrected;
}

} // namespace ChromaticAberrationCorrector

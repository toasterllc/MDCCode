#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImageLayerTypes.h"
using namespace metal;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;

namespace ChromaticAberrationCorrector {

constant float Eps = 1e-5;

constant float WhiteBalanceRed = 0.296587/0.203138;
constant float WhiteBalanceGreen = 0.296587/0.296587;
constant float WhiteBalanceBlue = 0.296587/0.161148;

fragment float WhiteBalanceForward(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
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
    const int2 pos = int2(in.pos.xy);
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
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = ctx.cfaColor(pos);
    // Green pixel: pass-through
    if (c == CFAColor::Green) return Sample::R(raw, pos);
    
    // Red/blue pixel: directional weighted average, preferring the direction with least change
#define PX(dx,dy) Sample::R(Sample::MirrorClamp, raw, pos+int2{(dx),(dy)})
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
    const int2 pos = int2(in.pos.xy);
    switch (ctx.cfaColor(pos)) {
    case CFAColor::Red:
    case CFAColor::Blue: {
        const float r = Sample::R(raw, pos);
        const float g = Sample::R(gInterp, pos);
        return r-g;
    }
    case CFAColor::Green: return 0;
    }
}

//fragment float CalcSlopeX(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
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
//    const int2 pos = int2(in.pos.xy);
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

float ḡ(texture2d<float> gInterp, float2 shift, int2 pos) {
    pos = Clamp::Mirror({gInterp.get_width(), gInterp.get_height()}, pos);
    return gInterp.sample({coord::pixel, filter::linear}, float2(pos)+shift+float2(.5,.5)).r;
}

//float ΔḡrCalc(texture2d<float> raw, texture2d<float> gInterp, float2 shift, int2 pos) {
//    const float ḡ = ḡ(gInterp, shift, pos);
//    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
//    return ḡ - r;
//}

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
    constexpr float ShiftLimit = 4;
    constexpr float α = 2;
    constexpr float β = .5;
    constexpr float γ = 5;
    
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = ctx.cfaColor(pos);
    
    float2 shift = 0;
    switch (c) {
    case CFAColor::Red:
        shift = {
            shiftsRedX.sample(filter::linear, in.posUnit).r,
            shiftsRedY.sample(filter::linear, in.posUnit).r
        };
        break;
    case CFAColor::Blue:
        shift = {
            shiftsBlueX.sample(filter::linear, in.posUnit).r,
            shiftsBlueY.sample(filter::linear, in.posUnit).r
        };
        break;
    case CFAColor::Green:
        return Sample::R(raw, pos); // Green pixel: pass through
    }
    
    shift.x = clamp(shift.x, -ShiftLimit, ShiftLimit);
    shift.y = clamp(shift.y, -ShiftLimit, ShiftLimit);
    
    const float g = Sample::R(gInterp, pos);
    const float r = Sample::R(raw, pos);
    const float Δgr = g - r;
    // Δḡr: correction factor; difference between ḡ (shifted g) and rb
    const float Δḡr = ḡ(gInterp, shift, pos) - r;
    // r̄: guess for rb using Δḡr (correction factor)
    const float r̄ = g - Δḡr;
    float rCorrected = r;
    
    // Only apply correction if the correction factor (Δḡr) is in the same direction
    // as the raw g-rb delta (Δgr), otherwise the correction factor overshot.
    if ((Δḡr>=0) == (Δgr>=0)) {
        // Only use r̄ if the average of it and the raw rb is greater than α times
        // the magnitude of their difference.
        if (.5*(r̄+r) > α*abs(r̄-r)) {
            // Only use r̄ if the magnitude of the correction factor (Δḡr) is
            // less than the magnitude of the raw g-rb delta (Δgr).
            if (abs(Δḡr) <= abs(Δgr)) {
                rCorrected = r̄;
            }
        
        // Otherwise, redefine Δḡr as the weighted average of
        } else {
            const int2 d = {
                shift.x>=0 ? -2 : 2,
                shift.y>=0 ? -2 : 2,
            };
            
            const float ḡxy = ḡ(gInterp, shift, pos+int2{0  ,  0});
            const float ḡx̄y = ḡ(gInterp, shift, pos+int2{d.x,  0});
            const float ḡxȳ = ḡ(gInterp, shift, pos+int2{0  ,d.y});
            const float ḡx̄ȳ = ḡ(gInterp, shift, pos+int2{d.x,d.y});
            
            const float rxy = Sample::R(Sample::MirrorClamp, raw, pos+int2{0  ,  0});
            const float rx̄y = Sample::R(Sample::MirrorClamp, raw, pos+int2{d.x,  0});
            const float rxȳ = Sample::R(Sample::MirrorClamp, raw, pos+int2{0  ,d.y});
            const float rx̄ȳ = Sample::R(Sample::MirrorClamp, raw, pos+int2{d.x,d.y});
            
            // Gradient weights using difference from G at CA shift points and G at grid points
            const float wxy = 1 / (Eps + abs(g - ḡ(gInterp, shift, pos+int2{0  ,  0})));
            const float wx̄y = 1 / (Eps + abs(g - ḡ(gInterp, shift, pos+int2{d.x,  0})));
            const float wxȳ = 1 / (Eps + abs(g - ḡ(gInterp, shift, pos+int2{0  ,d.y})));
            const float wx̄ȳ = 1 / (Eps + abs(g - ḡ(gInterp, shift, pos+int2{d.x,d.y})));
            const float Δḡr = (wxy * (ḡxy-rxy)  +
                               wx̄y * (ḡx̄y-rx̄y)  +
                               wxȳ * (ḡxȳ-rxȳ)  +
                               wx̄ȳ * (ḡx̄ȳ-rx̄ȳ)) /
                               (wxy+wx̄y+wxȳ+wx̄ȳ);
            
            if (abs(Δḡr) < abs(Δgr)) {
                rCorrected = g - Δḡr;
            }
        }
    
    // The correction factor (Δḡr) overshot, so use a weighted average of r̄ and r instead.
    } else {
        // The colour difference interpolation overshot the correction, just desaturate
        if (abs(Δḡr/Δgr) < γ) {
            rCorrected = β*r̄ + (1-β)*r;
        }
    }
    
    return rCorrected;
}

} // namespace ChromaticAberrationCorrector

#import <metal_stdlib>
#import "MetalShaderUtil.h"
#import "ImageFilterTypes.h"
#import "ImageLayerTypes.h"
#import "DefringeTypes.h"
using namespace metal;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageFilter;
using namespace CFAViewer::ImageLayerTypes;
using namespace CFAViewer::ImageFilter::DefringeTypes;

namespace CFAViewer {
namespace ImageFilter {
namespace Defringe {

constant float Eps = 1e-5;

constant float WhiteBalanceRed = 0.296587/0.203138;
constant float WhiteBalanceGreen = 0.296587/0.296587;
constant float WhiteBalanceBlue = 0.296587/0.161148;

fragment float WhiteBalanceForward(
    constant Options& opts [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = opts.cfaDesc.color(pos);
    const float s = Sample::R(raw, pos);
    switch (c) {
    case CFAColor::Red:     return s*WhiteBalanceRed;
    case CFAColor::Green:   return s*WhiteBalanceGreen;
    case CFAColor::Blue:    return s*WhiteBalanceBlue;
    }
}

fragment float WhiteBalanceReverse(
    constant Options& opts [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = opts.cfaDesc.color(pos);
    const float s = Sample::R(raw, pos);
    switch (c) {
    case CFAColor::Red:     return s/WhiteBalanceRed;
    case CFAColor::Green:   return s/WhiteBalanceGreen;
    case CFAColor::Blue:    return s/WhiteBalanceBlue;
    }
}

// Interpolate the G channel using a directional weighted average
fragment float InterpolateG(
    constant Options& opts [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = opts.cfaDesc.color(pos);
    // Green pixel: pass-through
    if (c == CFAColor::Green) return Sample::R(raw, pos);
    
    // Red/blue pixel: directional weighted average, preferring the direction with least change
#define PX(dx,dy) Sample::R(Sample::MirrorClamp, raw, pos+int2{(dx),(dy)})
    
    // Derivative in 4 directions
    const float4 δ(
        // Up
        abs(PX(  0 , +1 ) - PX( 0 , -1 )) +
        abs(PX(  0 ,  0 ) - PX( 0 , -2 )) +
        abs(PX(  0 , -1 ) - PX( 0 , -3 )) ,
        // Down
        abs(PX(  0 , -1 ) - PX( 0 , +1 )) +
        abs(PX(  0 ,  0 ) - PX( 0 , +2 )) +
        abs(PX(  0 , +1 ) - PX( 0 , +3 )) ,
        // Left
        abs(PX( +1 ,  0 ) - PX( -1 , 0 )) +
        abs(PX(  0 ,  0 ) - PX( -2 , 0 )) +
        abs(PX( -1 ,  0 ) - PX( -3 , 0 )) ,
        // Right
        abs(PX( -1 ,  0 ) - PX( +1 , 0 )) +
        abs(PX(  0 ,  0 ) - PX( +2 , 0 )) +
        abs(PX( +1 ,  0 ) - PX( +3 , 0 ))
    );
    
    const float4 r(
        PX(  0 , -1 ),
        PX(  0 , +1 ),
        PX( -1 ,  0 ),
        PX( +1 ,  0 )
    );
    
    // Weights: 1/δ^2
    const float4 w = 1/(Eps+pow(δ,2));
    // Result: apply weights to δ, sum them, and normalize
    // with combined weight.
    return dot(w*r,1) / dot(w,1);
#undef PX
}

fragment float CalcRBGDelta(
    constant Options& opts [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> gInterp [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    switch (opts.cfaDesc.color(pos)) {
    case CFAColor::Red:
    case CFAColor::Blue: {
        const float r = Sample::R(raw, pos);
        const float g = Sample::R(gInterp, pos);
        return r-g;
    }
    case CFAColor::Green: return 0;
    }
}

float ḡcalc(texture2d<float> gInterp, float2 shift, int2 pos) {
    pos = Clamp::Mirror({gInterp.get_width(), gInterp.get_height()}, pos);
    return gInterp.sample({coord::pixel, filter::linear}, float2(pos)+shift+float2(.5,.5)).r;
}

fragment float ApplyCorrection(
    constant Options& opts [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> gInterp [[texture(1)]],
    texture2d<float> shiftsRedX [[texture(2)]],
    texture2d<float> shiftsRedY [[texture(3)]],
    texture2d<float> shiftsBlueX [[texture(4)]],
    texture2d<float> shiftsBlueY [[texture(5)]],
    VertexOutput in [[stage_in]]
) {
    constexpr float ShiftLimit = 4;
    constexpr float αthresh = 2; // Threshold to allow α correction
    constexpr float γthresh = .2; // Threshold to allow γ correction
    constexpr float γfactor = .5; // Weight to apply to r̄ vs r when doing γ correction
    
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = opts.cfaDesc.color(pos);
    
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
    const float Δḡr = ḡcalc(gInterp, shift, pos) - r;
    // r̄: corrected rb using Δḡr (correction factor)
    const float r̄ = g - Δḡr;
    float rCorrected = r;
    
    // α/β correction: only allow if the correction factor (Δḡr) is in the same direction
    // as the raw g-rb delta (Δgr), otherwise the correction factor overshot.
    if ((Δḡr>=0) == (Δgr>=0)) {
        // α correction: only use if [average of r̄,r]/|r̄-r| is greater than a threshold.
        // In other words, prefer α correction for pixels whose raw and corrected
        // rb values closely match (denominator), especially if either is a bright
        // pixel (numerator).
        if ((.5*(r̄+r))/abs(r̄-r) >= αthresh) {
            // Only use r̄ if the magnitude of the correction factor (Δḡr) is
            // less than the magnitude of the raw g-rb delta (Δgr).
            if (abs(Δḡr) <= abs(Δgr)) {
                rCorrected = r̄;
            }
        
        // β correction: recompute Δḡr as the weighted average of ḡ-r at the four
        // points in the shift direction, where more weight is given to the
        // directions where ḡ and g match.
        } else {
            const int2 d = {
                shift.x>=0 ? -2 : 2,
                shift.y>=0 ? -2 : 2,
            };
            
            const float4 ḡ(
                ḡcalc(gInterp, shift, pos+int2{0  ,  0}),
                ḡcalc(gInterp, shift, pos+int2{d.x,  0}),
                ḡcalc(gInterp, shift, pos+int2{0  ,d.y}),
                ḡcalc(gInterp, shift, pos+int2{d.x,d.y})
            );
            
            const float4 r(
                Sample::R(Sample::MirrorClamp, raw, pos+int2{0  ,  0}),
                Sample::R(Sample::MirrorClamp, raw, pos+int2{d.x,  0}),
                Sample::R(Sample::MirrorClamp, raw, pos+int2{0  ,d.y}),
                Sample::R(Sample::MirrorClamp, raw, pos+int2{d.x,d.y})
            );
            
            // w: directional weights, where more weight is given to the
            // directions where ḡ and g match.
            const float4 w = 1 / (Eps + abs(ḡ-g));
            // Δḡr: correction factor; apply weights to ḡ-r, sum them,
            // and normalize with combined weight.
            const float Δḡr = dot(w*(ḡ-r),1) / dot(w,1); // ∑ w*(ḡ-r) / ∑ w
            const float r̄ = g - Δḡr;
            
            // Only use r̄ if the magnitude of the correction factor (Δḡr) is
            // less than the magnitude of the raw g-rb delta (Δgr).
            if (abs(Δḡr) < abs(Δgr)) {
                rCorrected = r̄;
            }
        }
    
    // γ correction: the correction factor (Δḡr) overshot;
    // use a weighted average of r̄ and r.
    } else {
        // To reduce artifacts, only allow γ correction if Δgr/Δḡr is above a threshold.
        if (abs(Δgr/Δḡr) >= γthresh) {
            rCorrected = γfactor*r̄ + (1-γfactor)*r;
        }
    }
    
    return rCorrected;
}

} // namespace Defringe
} // namespace ImageFilter
} // namespace CFAViewer

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
    template <typename T>
    float3 RGB(texture2d<float> txt, T pos) {
        return txt.sample(coord::pixel, float2(pos.x, pos.y)).rgb;
    }
    
    template <typename T>
    float R(texture2d<float> txt, T pos) {
        return RGB(txt, pos).r;
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
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    const float s = Sample::R(rawTxt, pos);
    switch (c) {
    case CFAColor::Red:     return s*WhiteBalanceRed;
    case CFAColor::Green:   return s*WhiteBalanceGreen;
    case CFAColor::Blue:    return s*WhiteBalanceBlue;
    default:                return 0;
    }
}

fragment float WhiteBalanceReverse(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    const float s = Sample::R(rawTxt, pos);
    switch (c) {
    case CFAColor::Red:     return s/WhiteBalanceRed;
    case CFAColor::Green:   return s/WhiteBalanceGreen;
    case CFAColor::Blue:    return s/WhiteBalanceBlue;
    default:                return 0;
    }
}

// Interpolate the G channel using a directional weighted average
fragment float InterpG(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos(in.pos.x, in.pos.y);
    const CFAColor c = ctx.cfaColor(pos);
    // Green pixel: pass-through
    if (c == CFAColor::Green) return Sample::R(rawTxt, pos);
    
    // Red/blue pixel: directional weighted average
    const uint2 bounds(rawTxt.get_width(), rawTxt.get_height());
    
#define PX(dx,dy) Sample::R(rawTxt, Clamp::Edge(bounds, pos, {(dx),(dy)}))
    
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
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> gInterp [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos(in.pos.x, in.pos.y);
    switch (ctx.cfaColor(pos)) {
    case CFAColor::Red:
    case CFAColor::Blue: {
        const float rb = Sample::R(rawTxt, pos);
        const float g = Sample::R(gInterp, pos);
        return rb-g;
    }
    default: return 0;
    }
}

//fragment float CalcSlopeX(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const uint2 pos(in.pos.x, in.pos.y);
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
//    const uint2 pos(in.pos.x, in.pos.y);
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

template<typename T>
constexpr T intp(T a, T b, T c)
{
    // calculate a * b + (1 - a) * c
    // following is valid:
    // intp(a, b+x, c+x) = intp(a, b, c) + x
    // intp(a, b*x, c*x) = intp(a, b, c) * x
    return a * (b - c) + c;
}

const float pxInterp(texture2d<float> txt, float x, float y) {
    const int2 posInt = {(int)x, (int)y};
    const float2 posFrac = {abs(x-posInt.x), abs(y-posInt.y)};
    const int2 posDelta = {(x>=0?1:-1), (y>=0?1:-1)};
    
    // Bilinear interpolation
    const float a = Sample::R(txt, int2{posInt.x,               posInt.y            });
    const float b = Sample::R(txt, int2{posInt.x+posDelta.x,    posInt.y            });
    const float c = Sample::R(txt, int2{posInt.x,               posInt.y+posDelta.y });
    const float d = Sample::R(txt, int2{posInt.x+posDelta.x,    posInt.y+posDelta.y });
    
    return  (1-posFrac.y)*(1-posFrac.x) * a +
            (1-posFrac.y)*(  posFrac.x) * b +
            (  posFrac.y)*(1-posFrac.x) * c +
            (  posFrac.y)*(  posFrac.x) * d ;
}

fragment float ApplyCorrection(
    constant RenderContext& ctx [[buffer(0)]],
    constant TileGrid& grid [[buffer(1)]],
    constant TileShifts& shiftsRX [[buffer(2)]],
    constant TileShifts& shiftsRY [[buffer(3)]],
    constant TileShifts& shiftsBX [[buffer(4)]],
    constant TileShifts& shiftsBY [[buffer(5)]],
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> gInterp [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos(in.pos.x, in.pos.y);
    const uint2 tidx(grid.x.tileIndex(pos.x), grid.y.tileIndex(pos.y));
    const CFAColor c = ctx.cfaColor(pos);
    
//    return ((float)tidx.x+(float)tidx.y)/(grid.x.tileCount+grid.y.tileCount);
    
    float2 shift;
    switch (c) {
    case CFAColor::Red:     shift = {shiftsRX(tidx.x,tidx.y), shiftsRY(tidx.x,tidx.y)}; break;
    case CFAColor::Green:   return Sample::R(rawTxt, pos); // Green pixel: pass through
    case CFAColor::Blue:    shift = {shiftsBX(tidx.x,tidx.y), shiftsBY(tidx.x,tidx.y)}; break;
    }
    
    const float shiftLimit = 4;
    const float alpha = .25;
    const float beta = .5;
    
//    shift.x = clamp(shift.x, -shiftLimit, shiftLimit);
//    shift.y = clamp(shift.y, -shiftLimit, shiftLimit);
//    
//    const float g_px = Sample::R(gInterp, pos);
//    const float rb_px = Sample::R(rawTxt, pos);
//    const float g_interp = gInterp.sample({coord::pixel, filter::linear}, float2(pos.x, pos.y)+shift).r;
//    const float grbdiff = g_interp - rb_px;
//    const float g_rb_diff_interp = grbdiff;
//    const float rb_interp = g_px - g_rb_diff_interp;
//    const float g_rb_diff = g_px - rb_px;
//    
//    float rbCorrected = rb_px;
//    if (abs(rb_interp-rb_px) < alpha*(rb_interp+rb_px)) {
//        if (abs(g_rb_diff_interp) < abs(g_rb_diff)) {
//            rbCorrected = g_px - g_rb_diff_interp;
//        }
//    }
//    
//    if (g_rb_diff*g_rb_diff_interp < 0) {
//        // The colour difference interpolation overshot the correction, just desaturate
//        if (abs(g_rb_diff_interp/g_rb_diff) < 5) {
//            rbCorrected = g_px - beta*(g_rb_diff+g_rb_diff_interp);
//        }
//    }
//    
//    return rbCorrected;
    
    const float g_px = Sample::R(gInterp, pos);
    const float rb_px = Sample::R(rawTxt, pos);
    
    // polynomial fit coefficients
    // residual CA shift amount within a tile
    float shifthfrac = {};
    float shiftvfrac = {};
    
    // Fill shiftvfloor/shiftvceil/...
    int shiftvfloor = 0;
    int shiftvceil = 0;
    int shifthfloor = 0;
    int shifthceil = 0;
    
    {
        // some parameters for the bilinear interpolation
        shiftvfloor = floor((float)shift.y);
        shiftvceil = ceil((float)shift.y);
        if (shift.y < 0.0) {
            float tmp = shiftvfloor;
            shiftvfloor = shiftvceil;
            shiftvceil = tmp;
        }
        shiftvfrac = abs(shift.y - shiftvfloor);
        
        shifthfloor = floor((float)shift.x);
        shifthceil = ceil((float)shift.x);
        if (shift.x < 0.0) {
            float tmp = shifthfloor;
            shifthfloor = shifthceil;
            shifthceil = tmp;
        }
        shifthfrac = abs(shift.x - shifthfloor);
    }
    
    float grbdiff = 0;
    {
        const int yf = pos.y + shiftvfloor;
        const int yc = pos.y + shiftvceil;
        const int xf = pos.x + shifthfloor;
        const int xc = pos.x + shifthceil;
        // Perform CA correction using colour ratios or colour differences
        const float g_interp_h_floor = intp(shifthfrac,
            Sample::R(gInterp,int2{xc,yf}),
            Sample::R(gInterp,int2{xf,yf})
        );
        const float g_interp_h_ceil = intp(shifthfrac,
            Sample::R(gInterp,int2{xc,yc}),
            Sample::R(gInterp,int2{xf,yc})
        );
        // g_int is bilinear interpolation of G at CA shift point
//        const float g_interp = intp(shiftvfrac, g_interp_h_ceil, g_interp_h_floor);
//        const float g_interp = pxInterp(gInterp, pos.x+shift.x, pos.y+shift.y);
        const float g_interp = gInterp.sample({coord::pixel, filter::linear}, float2(pos.x, pos.y)+shift).r;
//        const float g_interp = gInterp.sample({coord::pixel, filter::linear}, float2(pos.x, pos.y)+shift).r;
//        float2 pos2 = float2(pos.x, pos.y)+shift;
//        pos2.x = (int)pos2.x;
//        pos2.y = (int)pos2.y;
//        const float g_interp = gInterp.sample(sampler(coord::pixel, filter::linear), pos2).r;
//        return gInterp.sample({coord::pixel, filter::linear}, float2(pos.x, pos.y)+shift).r - intp(shiftvfrac, g_interp_h_ceil, g_interp_h_floor);
        // Determine R/B at grid points using colour differences at shift point plus
        // interpolated G value at grid point. But first we need to interpolate
        // GR/GB to grid points...
        grbdiff = g_interp - rb_px;
    }
    
    float g_rb_diff_interp = grbdiff;
    
    // Now determine R/B at grid points using interpolated colour differences and interpolated G value at grid point
    const float rb_interp = g_px - g_rb_diff_interp;
    const float g_rb_diff = g_px - rb_px;
    
    float rbCorrected = rb_px;
    if (abs(rb_interp-rb_px) < alpha*(rb_interp+rb_px)) {
        if (abs(g_rb_diff_interp) < abs(g_rb_diff)) {
            rbCorrected = g_px - g_rb_diff_interp;
        }
    }
    
    if (g_rb_diff*g_rb_diff_interp < 0) {
        // The colour difference interpolation overshot the correction, just desaturate
        if (abs(g_rb_diff_interp/g_rb_diff) < 5) {
            rbCorrected = g_px - beta*(g_rb_diff+g_rb_diff_interp);
        }
    }
    return rbCorrected;
}


}

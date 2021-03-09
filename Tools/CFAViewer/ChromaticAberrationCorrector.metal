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


// Interpolate the G channel using a directional weighted average
fragment float InterpG(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(in.pos.x, in.pos.y);
    const int x = pos.x;
    const int y = pos.y;
    const PxColor c = ctx.cfaColor(x, y);
    // Green pixel: pass-through
    if (c == PxColors::Green) return Sample::R(rawTxt, pos);
    
    // Red/blue pixel: directional weighted average
    const uint2 bounds(rawTxt.get_width(), rawTxt.get_height());
    
#define PX(dx,dy) Sample::R(rawTxt, Clamp::Edge(bounds, int2{x+(dx),y+(dy)}))
    
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

}

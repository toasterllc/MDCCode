#import <metal_stdlib>
#import "ImageGridLayerTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageGridLayerTypes;

namespace MDCStudio {
namespace ImageGridLayerShader {

template <typename... Ts>
static uint32_t _HashInts(Ts... ts) {
    // FNV-1 hash
    const uint32_t v[] = {(uint32_t)ts...};
    const thread uint8_t* b = (thread uint8_t*)&v;
    uint32_t hash = (uint32_t)0x811c9dc5;
    for (size_t i=0; i<sizeof(v); i++) {
        hash *= (uint32_t)0x1000193;
        hash ^= b[i];
    }
    return hash;
}

//static float3 _ColorFromInt(uint32_t x) {
//    const uint32_t hash = _HashInts(x);
//    const uint8_t r = (hash&0x0000FF)>> 0;
//    const uint8_t g = (hash&0x00FF00)>> 8;
//    const uint8_t b = (hash&0xFF0000)>>16;
//    return float3((float)r/255, (float)g/255, (float)b/255);
//}

//static int2 _GetVertex(const thread Grid::Rect& rect, uint vidx) {
//    int x = rect.point.x;
//    int y = rect.point.y;
//    int w = rect.size.x;
//    int h = rect.size.y;
//    switch (vidx) {
//    case 0:     return int2(x, y);
//    
//    case 1:
//    case 4:     return int2(x, y+h);
//    
//    case 2:
//    case 3:     return int2(x+w, y);
//    
//    case 5:
//    default:    return int2(x+w, y+h);
//    }
//}

//static float4 _GetVertex(const thread Grid::Rect& rect, uint vidx) {
//    int x = rect.point.x;
//    int y = rect.point.y;
//    int w = rect.size.x;
//    int h = rect.size.y;
//    switch (vidx) {
//    case 0:     return float4(x, y, 0, 1);
//    
//    case 1:
//    case 4:     return float4(x, y+h, 0, 1);
//    
//    case 2:
//    case 3:     return float4(x+w, y, 0, 1);
//    
//    case 5:
//    default:    return float4(x+w, y+h, 0, 1);
//    }
//}

static float4 blendOver(float4 a, float4 b) {
    const float oa = a.a + b.a*(1-a.a);
    const float3 oc = (a.rgb*a.a + b.rgb*b.a*(1-a.a)) / oa;
    return float4(oc, oa);
}

static float4 blendColorDodge(float4 a, float4 b) {
    if (a.a == 0) return b;
    return float4(b.rgb / (float3(1)-a.rgb), a.a);
}

static float4 blendMask(float mask, float4 a) {
    return float4(a.rgb, a.a*mask);
}

float SRGBGammaForward(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4)-.055;
}

float SRGBGammaReverse(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.04045) return x/12.92;
    return pow((x+.055)/1.055, 2.4);
}

static float4 blendOverPremul(float4 a, float4 b) {
    const float oa = (1.0)*a.a + (1-a.a)*b.a;
    const float3 oc = (1.0)*a.rgb + (1-a.a)*b.rgb;
    return float4(oc, oa);
}





struct VertexOutput {
    float4 posView [[position]];
//    float2 posPx;
//    uint32_t thumbOff;
};

static float4 _VertexOffsetForVertexIndex(uint vidx) {
    switch (vidx) {
    case 0:     return float4(-1, -1, 0, 1);
    
    case 1:
    case 4:     return float4(-1, 1, 0, 1);
    
    case 2:
    case 3:     return float4(1, -1, 0, 1);
    
    case 5:
    default:    return float4(1, 1, 0, 1);
    }
}
vertex VertexOutput VertexShader(
    uint vidx [[vertex_id]],
    uint iidx [[instance_id]]
) {
    return VertexOutput{
        .posView = _VertexOffsetForVertexIndex(vidx),
    };
}

fragment float4 FragmentShader(
    texture2d<float> topTxt [[texture(0)]],
    texture2d<float> bottomTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    if (in.posView.x>=topTxt.get_width() || in.posView.y>=topTxt.get_height()) return float4(0,0,0,1);
    float4 top = topTxt.sample(coord::pixel, float2(in.posView.x, in.posView.y));
    float4 bottom = bottomTxt.sample(coord::pixel, float2(in.posView.x, in.posView.y));
    return blendOver(float4(top.rgb, .6), bottom);
    
//    return bottom;
//    return float4(1,1,0,1);
}

} // namespace ImageGridLayerShader
} // namespace MDCStudio

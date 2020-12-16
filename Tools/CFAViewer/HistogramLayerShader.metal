#import <metal_stdlib>
#import "HistogramLayerTypes.h"
using namespace metal;
using namespace MetalTypes;
using namespace HistogramLayerTypes;

struct VertexOutput {
    float4 viewPosition [[position]];
    float2 pixelPosition;
};

vertex VertexOutput HistogramLayer_VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    const float4 unitPosition = SquareVert[SquareVertIdx[vidx]];
    const float2 pixelPosition = {
        ((unitPosition.x+1)/2)*(ctx.viewWidth),
        ((unitPosition.y+1)/2)*(ctx.viewHeight),
    };
    
    return VertexOutput{
        unitPosition,
        pixelPosition
    };
}


//template <size_t N>
//float sampleRange(float unitRange0, float unitRange1, const uint32_t(& bins)[N]) {
//    unitRange0 = std::max(0.f, unitRange0);
//    unitRange1 = std::min(1.f, unitRange1);
//    
//    const float range0 = unitRange0*N;
//    const float range1 = unitRange1*N;
//    const uint32_t rangeIdx0 = range0;
//    const uint32_t rangeIdx1 = (uint32_t)range1;
//    const float leftAmount = 1-(range0-floor(range0));
//    const float rightAmount = range1-floor(range1);
//    
//    float sample = 0;
//    for (uint i=rangeIdx0; i<=std::min((uint32_t)N-1, rangeIdx1); i++) {
//        if (i == rangeIdx0)         sample += leftAmount*bins[i];
//        else if (i == rangeIdx1)    sample += rightAmount*bins[i];
//        else                        sample += bins[i];
//    }
//    return sample;
//}



template <size_t N>
float sampleRange(float2 unitRange, device const uint32_t(& bins)[N]) {
    unitRange = {max(0., unitRange[0]), min(1., unitRange[1])};
    
    const float2 range = unitRange*N;
    const uint2 rangeIdx = {(uint)range[0], (uint)range[1]};
    const float leftAmount = 1-(range[0]-floor(range[0]));
    const float rightAmount = range[1]-floor(range[1]);
    
    float sample = 0;
    // Limit `i` to N-1 here to prevent reading beyond `bins`.
    // We don't limit `i` via `rangeIdx`, because our alg works with
    // closed-open intervals, where the open interval has rightAmount==0.
    // If we limited our iteration with `rangeIdx`, we'd need a special
    // case to set rightAmount=1, otherwise the last bin would get dropped.
    for (uint i=rangeIdx[0]; i<=min((uint32_t)N-1, rangeIdx[1]); i++) {
        if (i == rangeIdx[0])           sample += leftAmount*bins[i];
        else if (i == rangeIdx[1])      sample += rightAmount*bins[i];
        else                            sample += bins[i];
    }
    return sample;
}

fragment float4 HistogramLayer_FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    device Histogram& histogram [[buffer(1)]],
    VertexOutput interpolated [[stage_in]]
) {
    float2 unitRange = float2{
        floor(interpolated.pixelPosition.x),
        floor(interpolated.pixelPosition.x)+1
    }/ctx.viewWidth;
    
//    float2 unitRange = float2{
//        interpolated.pixelPosition.x-.5,
//        interpolated.pixelPosition.x+.5,
//    }/ctx.viewWidth;
    
    float height = sampleRange(unitRange, histogram.r);
    height /= ctx.maxVals[0];
    height *= ctx.viewHeight;
    
//    uint2 pos = {(uint)interpolated.pixelPosition.x, (uint)interpolated.pixelPosition.y};
//    uint2 binRange = uint2{pos.x, pos.x+1};
//    binRange *= ctx.binsPerPixel;
//    binRange[0] = min(Histogram::Count, binRange[0]);
//    binRange[1] = min(Histogram::Count, binRange[1]);
//    
//    // Sum all the bins that this pixel represents
//    float height = 0;
//    for (uint i=binRange[0]; i<binRange[1]; i++) {
//        height += histogram.r[i];
//    }
//    height = (height/ctx.maxVals[0]) * ctx.viewHeight;
//    // Min 1 pixel in height, if there's anything in this bin
//    if (height > 0) height = max(1., height);
//    
    return float4(max(0., height-interpolated.pixelPosition.y), 0, 0, 1);
}

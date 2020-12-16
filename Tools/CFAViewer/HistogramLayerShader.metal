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

fragment float4 HistogramLayer_FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    device HistogramFloat& histogram [[buffer(1)]],
    VertexOutput interpolated [[stage_in]]
) {
    uint x = interpolated.pixelPosition.x;
    float height = histogram.r[x];
    height /= ctx.maxVals[0];
    height *= ctx.viewHeight;
    return float4(max(0., height-interpolated.pixelPosition.y), 0, 0, 1);
}

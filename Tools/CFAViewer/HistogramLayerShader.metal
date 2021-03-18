#import <metal_stdlib>
#import "HistogramLayerTypes.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::HistogramLayerTypes;

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
    float3 height = {
        histogram.r[x],
        histogram.g[x],
        histogram.b[x],
    };
    height = log(height);
    height /= log(ctx.maxVal);
    height *= ctx.viewHeight;
    return float4(max(0., height-interpolated.pixelPosition.y), 1);
}

#import <metal_stdlib>
#import "RenderTypes.h"
using namespace metal;

static constexpr constant float2 _ViewCoords[6] = {
    {0, 0},
    {0, 1},
    {1, 0},
    {1, 0},
    {0, 1},
    {1, 1},
};

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

vertex VertexOutput VertexShader(
    constant float4x4& transform [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    VertexOutput r = {
        .pos = transform * float4(_ViewCoords[vidx], 0, 1),
        .posUnit = _ViewCoords[vidx],
    };
    return r;
}

fragment float4 FragmentShader(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
//    return txt.sample({}, {in.posUnit.x, 1-in.posUnit.y});
    return txt.sample({}, in.posUnit);
}

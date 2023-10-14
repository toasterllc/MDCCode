#import <metal_stdlib>
#import "ImageGridLayerTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageGridLayerTypes;

namespace MDCStudio {
namespace ImageGridLayerShader {

struct VertexOutput {
    uint idx;
    bool selected;
    float4 posView [[position]];
    float2 posNorm;
    float2 posPx;
};

static constexpr constant float2 _Verts[6] = {
    {0, 0},
    {0, 1},
    {1, 0},
    {1, 0},
    {0, 1},
    {1, 1},
};

vertex VertexOutput VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImageRecordRef* recs [[buffer(1)]],
    constant const bool* selectedImages [[buffer(2)]],
    uint vidx [[vertex_id]],
    uint iidx [[instance_id]]
) {
    // idxGrid: absolute index in grid
    const uint idxGrid = ctx.idx + iidx;
    // idxRec: absolute index in `recs` array
    const uint idxRec = (ctx.sortNewestFirst ? (ctx.grid.elementCount()-1)-idxGrid : idxGrid);
    // idxChunk: relative index in chunk
    const uint idxChunk = recs[idxRec].idx; // Index in chunk
    const Grid::Rect rect = ctx.grid.rectForCellIndex(idxGrid);
    const int2 voff = int2(rect.size.x, rect.size.y) * int2(_Verts[vidx]);
    const int2 vabs = int2(rect.point.x, rect.point.y) + voff;
    const float2 vnorm = float2(vabs) / ctx.viewSize;
    
    const bool selected = (
        ctx.selection.count && (
            idxRec>=ctx.selection.base &&
            idxRec<ctx.selection.base+ctx.selection.count &&
            selectedImages[idxRec-ctx.selection.base]
        )
    );
    
    return VertexOutput{
        .idx = idxChunk,
        .selected = selected,
        .posView = ctx.transform * float4(vnorm, 0, 1),
        .posNorm = _Verts[vidx],
        .posPx = float2(voff),
    };
}

static float4 blendColorDodge(float4 a, float4 b) {
    if (a.a == 0) return b;
    const float3 oc = min(float3(1), b.rgb / (float3(1)-a.rgb)); // min to prevent nan/infinity
    return float4(oc, a.a);
}

static float4 blendOver(float4 a, float4 b) {
    const float oa = a.a + b.a*(1-a.a);
    if (oa == 0) return 0;
    const float3 oc = (a.rgb*a.a + b.rgb*b.a*(1-a.a)) / oa;
    return float4(oc, oa);
}

fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant uint32_t* loadCounts [[buffer(1)]],
    texture2d_array<float> txt [[texture(0)]],
    texture2d<float> placeholderTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.posPx);
    if (!loadCounts[in.idx]) return placeholderTxt.sample({}, in.posNorm);
    const uint2 txtSize = { txt.get_width(), txt.get_height() };
    
    constexpr float4 SelectionBorderColor1 = float4(0,0.523,1,1);
    constexpr float4 SelectionBorderColor2 = float4(1,1,1,.175);
    constexpr uint SelectionBorderSize = 10;
    float3 c = txt.read(pos, in.idx).rgb;
    if (in.selected && (metal::any(pos < SelectionBorderSize) || metal::any(pos > (txtSize-SelectionBorderSize)))) {
        return blendColorDodge(SelectionBorderColor1, blendOver(SelectionBorderColor2, float4(c,1)));
    }
    return float4(c, 1);
}

} // namespace ImageGridLayerShader
} // namespace MDCStudio

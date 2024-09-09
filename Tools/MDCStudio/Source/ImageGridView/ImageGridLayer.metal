#import <metal_stdlib>
#import "ImageGridLayerTypes.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
using namespace metal;
using namespace Toastbox::MetalUtil;
using namespace MDCStudio::ImageGridLayerTypes;

namespace MDCStudio {
namespace ImageGridLayerShader {

struct VertexOutput {
    uint idx;
    bool selected;
    float4 posView [[position]];
    float2 posNorm;
    float2 posPx;
    float zoomOpacity;
    float zoomSelectionOpacity;
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
    const Toastbox::Grid::Rect rect = ctx.grid.rectForCellIndex(idxGrid);
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
    
    const float zoomOpacity = (idxRec!=ctx.zoom.focusIdx ? 1-ctx.zoom.progress : 1);
    const float zoomSelectionOpacity = 1-ctx.zoom.progress;
    
    return VertexOutput{
        .idx = idxChunk,
        .selected = selected,
        .posView = ctx.transform * float4(vnorm, 0, 1),
        .posNorm = _Verts[vidx],
        .posPx = float2(voff),
        .zoomOpacity = zoomOpacity,
        .zoomSelectionOpacity = zoomSelectionOpacity,
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

static float4 _Frag(
    constant RenderContext& ctx,
    constant uint32_t* loadCounts,
    texture2d_array<float> txt,
    texture2d<float> placeholderTxt,
    VertexOutput in
) {
    const uint2 pos = uint2(in.posPx);
    if (!loadCounts[in.idx]) {
        constexpr float PlaceholderAlpha = 0.05;
        const float4 c = placeholderTxt.sample({}, in.posNorm);
        return float4(c.rgb, PlaceholderAlpha*c.a);
    }
    constexpr float4 SelectionBorderColor1 = float4(0,0.523,1,1);
    constexpr float4 SelectionBorderColor2 = float4(1,1,1,.175);
    const uint32_t selectionBorderSize = ctx.selection.borderSize;
    const uint2 cellSize = { (uint)ctx.grid.cellSize().x, (uint)ctx.grid.cellSize().y };
    
    const float4 c = txt.sample({}, in.posNorm, in.idx);
    if (in.selected && (metal::any(pos < selectionBorderSize) || metal::any(pos >= (cellSize-selectionBorderSize)))) {
        const float4 selectionColor = blendColorDodge(SelectionBorderColor1, blendOver(SelectionBorderColor2, c));
        return blendOver(selectionColor*float4(1,1,1,in.zoomSelectionOpacity), c);
//        return selectionColor*float4(1,1,1,in.zoomSelectionOpacity) + c*float4(1,1,1,1-in.zoomSelectionOpacity);
    }
    return c;
}

fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant uint32_t* loadCounts [[buffer(1)]],
    texture2d_array<float> txt [[texture(0)]],
    texture2d<float> placeholderTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    return _Frag(ctx, loadCounts, txt, placeholderTxt, in) * float4(1,1,1,in.zoomOpacity);
}

} // namespace ImageGridLayerShader
} // namespace MDCStudio

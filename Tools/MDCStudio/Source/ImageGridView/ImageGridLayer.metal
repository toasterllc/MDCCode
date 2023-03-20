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
    const uint idxRec = (ctx.reverse ? (ctx.grid.elementCount()-1)-idxGrid : idxGrid);
    // idxChunk: relative index in chunk
    const uint idxChunk = recs[idxRec].idx; // Index in chunk
    const Grid::Rect rect = ctx.grid.rectForCellIndex(idxGrid);
    const int2 voff = int2(rect.size.x, rect.size.y) * int2(_Verts[vidx]);
    const int2 vabs = int2(rect.point.x, rect.point.y) + voff;
    const float2 vnorm = float2(vabs) / ctx.viewSize;
    
    const bool selected = (
        !ctx.selection.count || (
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



fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant bool* loaded [[buffer(1)]],
    texture2d_array<float> txt [[texture(0)]],
    texture2d<float> placeholderTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.posPx);
    if (!loaded[in.idx]) return placeholderTxt.sample({}, in.posNorm);
    
    float3 c = txt.read(pos, in.idx).rgb;
    if (!in.selected) c /= 32;
    return float4(c, 1);
    
//    
//    
////    return float4(1,1,1,0.003935939504);
////    return float4(1,1,1,.01/2);
//    float4 c = txt.read(pos, in.idx).rgb;
//    if (!in.selected) c /= 32;
//    
//    const float4 p = placeholderTxt.read(pos);
//    return (loaded[in.idx] ? c : p);
    
//    return placeholderTxt.sample({}, in.posNorm);
//    
//    return float4(placeholderTxt.sample({}, in.posNorm).rgb, 1);
//    return float4(.2,.5,.7,1);
//    const uint2 pos = uint2(in.posPx);
//    return float4(placeholderTxt.read(pos).rgb, 1);
////    float3 c = txt.read(pos, in.idx).rgb;
//    float3 c = placeholderTxt.read(pos, in.idx).rgb;
//    if (!in.selected) c /= 32;
//    return float4(c, 1);
}




//fragment float4 SampleTexture(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    constexpr sampler s(coord::pixel, filter::linear);
//    return txt.sample(s, in.pos.xy);
////    constexpr sampler s(coord::normalized, filter::linear);
////    return txt.sample(s, in.posUnit.xy);
//}

//fragment float4 FragmentShader(
//    constant RenderContext& ctx [[buffer(0)]],
//    device uint8_t* images [[buffer(1)]],
//    device bool* selectedImageIds [[buffer(2)]],
//    texture2d<float> maskTxt [[texture(0)]],
//    texture2d<float> outlineTxt [[texture(1)]],
//    texture2d<float> shadowTxt [[texture(2)]],
//    texture2d<float> selectionTxt [[texture(4)]],
//    VertexOutput in [[stage_in]]
//) {
//    #warning TODO: adding +.5 to the pixel coordinates supplied to shadowTxt.sample() causes incorrect results. does that mean that the Sample::RGBA() implementation is incorrect? or are we getting bad pixel coords via `VertexOutput in`?
//    
//    device uint8_t* imageBuf = images+ctx.imagesOff+(ctx.imageSize*in.idx);
//    const uint32_t imageId = *((device uint32_t*)(imageBuf+ctx.off.id));
//    device const ImageOptions& imageOpts = *((device const ImageOptions*)(imageBuf+ctx.off.options));
//    device uint8_t* thumbData = imageBuf+ctx.off.thumbData;
//    
//    const uint32_t thumbInset = (shadowTxt.get_width()-maskTxt.get_width())/2;
//    const int2 pos = int2(in.posPx)-int2(thumbInset);
//    const uint pxIdx = (pos.y*ctx.thumb.width + pos.x);
//    
//    const bool selected = (
//        imageId>=ctx.selection.first &&
//        imageId<ctx.selection.first+ctx.selection.count &&
//        selectedImageIds[imageId-ctx.selection.first]
//    );
//    
//    const int maskWidth = maskTxt.get_width();
//    const int maskHeight = maskTxt.get_height();
//    const int maskWidth2 = maskWidth/2;
//    const int maskHeight2 = maskHeight/2;
//    const int2 marginX = int2(maskWidth2, (ctx.thumb.width-maskWidth2));
//    const int2 marginY = int2(maskHeight2, (ctx.thumb.height-maskHeight2));
//    
//    const uint32_t pxOff = pxIdx*ctx.thumb.pxSize;
//    
//    float3 thumb = float3(
//        ((float)thumbData[pxOff+0] / 255),
//        ((float)thumbData[pxOff+1] / 255),
//        ((float)thumbData[pxOff+2] / 255)
//    );
//    
//    const bool inThumb = (pos.x>=0 && pos.y>=0 && pos.x<(int)ctx.thumb.width && pos.y<(int)ctx.thumb.height);
//    if (!inThumb) return 0;
//    return float4(thumb, 1);
//    
////    thumb = ColorAdjust(imageOpts, thumb);
////    
////    const bool inThumb = (pos.x>=0 && pos.y>=0 && pos.x<(int)ctx.thumb.width && pos.y<(int)ctx.thumb.height);
////    if (!inThumb) return 0;
////    return float4(ColorAdjust(imageOpts, thumb), 1);
//    
//    // Calculate mask value
//    float mask = 0;
//    if (inThumb) {
//        if (pos.x<=marginX[0] && pos.y<=marginY[0]) {
//            // Top left
//            mask = Sample::R(maskTxt, int2(pos.x, pos.y));
//        
//        } else if (pos.x>=marginX[1] && pos.y<=marginY[0]) {
//            // Top right
//            mask = Sample::R(maskTxt, int2(maskWidth2+(pos.x-marginX[1]), pos.y));
//        
//        } else if (pos.x<=marginX[0] && pos.y>=marginY[1]) {
//            // Bottom left
//            mask = Sample::R(maskTxt, int2(pos.x, maskHeight2+(pos.y-marginY[1])));
//        
//        } else if (pos.x>=marginX[1] & pos.y>=marginY[1]) {
//            // Bottom right
//            mask = Sample::R(maskTxt, int2(maskWidth2+(pos.x-marginX[1]), maskHeight2+(pos.y-marginY[1])));
//        
//        } else {
//            mask = 1;
//        }
//    }
//    
//    // Calculate outline colors
//    float4 outlineOver = 0;
//    float4 outlineColorDodge = 0;
//    if (inThumb) {
//        int2 outlinePos = pos;
//        if (pos.x <= marginX[0])        outlinePos.x = pos.x;
//        else if (pos.x >= marginX[1])   outlinePos.x = maskWidth2+(pos.x-marginX[1]);
//        else                            outlinePos.x = maskWidth2;
//        
//        if (pos.y <= marginY[0])        outlinePos.y = pos.y;
//        else if (pos.y >= marginY[1])   outlinePos.y = maskHeight2+(pos.y-marginY[1]);
//        else                            outlinePos.y = maskHeight2;
//        
//        const float outline = Sample::R(outlineTxt, outlinePos);
//        
//        if (!selected) {
//            outlineOver = float4(float3(1), .03*outline);
//            outlineColorDodge = float4(float3(.7*outline), 1);
//        
//        } else {
//            outlineOver = float4(float3(1), 0*outline);
//            outlineColorDodge = float4(float3(.5*outline), 1);
//        }
//    }
//    
//    // Calculate shadow value
//    float4 shadow = 0;
//    if (!selected) {
//        const int2 pos = int2(in.posPx);
//        
//        const int shadowWidth = shadowTxt.get_width();
//        const int shadowHeight = shadowTxt.get_height();
//        const int shadowWidth2 = shadowWidth/2;
//        const int shadowHeight2 = shadowHeight/2;
//        const int2 marginX = int2(shadowWidth2, (ctx.cellWidth-shadowWidth2));
//        const int2 marginY = int2(shadowHeight2, (ctx.cellHeight-shadowHeight2));
//        
//        int2 shadowPos = pos;
//        if (pos.x <= marginX[0])        shadowPos.x = pos.x;
//        else if (pos.x >= marginX[1])   shadowPos.x = shadowWidth2+(pos.x-marginX[1]);
//        else                            shadowPos.x = shadowWidth2;
//        
//        if (pos.y <= marginY[0])        shadowPos.y = pos.y;
//        else if (pos.y >= marginY[1])   shadowPos.y = shadowHeight2+(pos.y-marginY[1]);
//        else                            shadowPos.y = shadowHeight2;
//        
//        shadow = float4(0, 0, 0, shadowTxt.sample(coord::pixel, float2(shadowPos.x, shadowPos.y)).a);
//    }
//    
//    // Calculate selection value
//    float4 selection = 0;
//    if (selected) {
//        const int2 pos = int2(in.posPx);
//        
//        const int selectionWidth = selectionTxt.get_width();
//        const int selectionHeight = selectionTxt.get_height();
//        const int selectionWidth2 = selectionWidth/2;
//        const int selectionHeight2 = selectionHeight/2;
//        const int2 marginX = int2(selectionWidth2, (ctx.cellWidth-selectionWidth2));
//        const int2 marginY = int2(selectionHeight2, (ctx.cellHeight-selectionHeight2));
//        
//        int2 selectionPos = pos;
//        if (pos.x <= marginX[0])        selectionPos.x = pos.x;
//        else if (pos.x >= marginX[1])   selectionPos.x = selectionWidth2+(pos.x-marginX[1]);
//        else                            selectionPos.x = selectionWidth2;
//        
//        if (pos.y <= marginY[0])        selectionPos.y = pos.y;
//        else if (pos.y >= marginY[1])   selectionPos.y = selectionHeight2+(pos.y-marginY[1]);
//        else                            selectionPos.y = selectionHeight2;
//        
//        selection = selectionTxt.sample(coord::pixel, float2(selectionPos.x, selectionPos.y));
//    }
//    
//    return
//        blendOver(
//            blendOver(
//                blendMask(mask,
//                blendColorDodge(outlineColorDodge,
//                blendOver(outlineOver, float4(thumb, 1)
//            ))), shadow),
//        selection);
//}

} // namespace ImageGridLayerShader
} // namespace MDCStudio

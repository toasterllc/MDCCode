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

struct VertexOutput {
    uint idx;
    float4 posView [[position]];
    float2 posPx;
//    uint32_t thumbOff;
};

static int2 _VertexOffsetForVertexIndex(const thread Grid::Rect& rect, uint vidx) {
    int w = rect.size.x;
    int h = rect.size.y;
    switch (vidx) {
    case 0:     return int2(0, 0);
    
    case 1:
    case 4:     return int2(0, h);
    
    case 2:
    case 3:     return int2(w, 0);
    
    case 5:
    default:    return int2(w, h);
    }
}

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

vertex VertexOutput VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImageRecordRef* imageRecordRefs [[buffer(1)]],
    uint vidx [[vertex_id]],
    uint iidx [[instance_id]]
) {
//    const Grid::Rect rect = ctx.grid.rectForCellIndex(ctx.startIdx + iidx);
    
//    float px = 100;
//    
//    float4 pos = 0;
//    if (vidx == 0) {
//        pos = float4(px,0,0,1);
//    } else if (vidx == 1) {
//        pos = float4(0,px,0,1);
//    } else if (vidx == 2) {
//        pos = float4(0,0,0,1);
//    } else if (vidx == 3) {
//        pos = float4(px,px,0,1);
//    } else if (vidx == 4) {
//        pos = float4(0,px,0,1);
//    } else if (vidx == 5) {
//        pos = float4(px,0,0,1);
//    }
//    return VertexOutput{
//        .position = ctx.viewMatrix*pos,
//    };
//    
//    float x = 100;
//    float y = 100;
//    float w = 100;
//    float h = 100;
//    
//    float4 pos = 0;
//    if (vidx == 0) {
//        pos = float4(   x,   y,  0,  1);
//    } else if (vidx == 1) {
//        pos = float4(   x, y+h,  0,  1);
//    } else if (vidx == 2) {
//        pos = float4( x+w,   y,  0,  1);
//    }
    
    const uint relIdx = iidx; // Index within chunk
    const uint absIdx = ctx.idxOff + relIdx;
    
    // Ignore ImageRefs that aren't for our intended chunk
//    if (any(imageRef.chunk != ctx.chunk)) return Nan;
    
//    if (idx >= ctx.grid.elementCount()) return Nan;
    
    const Grid::Rect rect = ctx.grid.rectForCellIndex(absIdx);
    const int2 vorigin = int2(rect.point.x, rect.point.y);
    const int2 voff = _VertexOffsetForVertexIndex(rect, vidx);
    const int2 vabs = vorigin + voff + ctx.viewOffset;
    
    return VertexOutput{
        .idx = relIdx,
        .posView = ctx.viewMatrix * float4(vabs.x, vabs.y, 0, 1),
        .posPx = float2(voff),
//        .thumbOff = 0,
//        .color = _ColorFromInt(idx),
    };
}

static float4 blendOver(float4 a, float4 b) {
    const float oa = a.a + b.a*(1-a.a);
    const float3 oc = (a.rgb*a.a + b.rgb*b.a*(1-a.a)) / oa;
    return float4(oc, oa);
}

static float4 blendColorDodge(float4 a, float4 b) {
//    if (a.a == 0) return b;
    return float4(b.rgb / (float3(1)-a.rgb), a.a);
}

static float4 blendMask(float mask, float4 a) {
    return float4(a.rgb, a.a*mask);
}

fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    device uint8_t* images [[buffer(1)]],
    device bool* selectedImageIds [[buffer(2)]],
    texture2d<float> maskTxt [[texture(0)]],
    texture2d<float> outlineTxt [[texture(1)]],
    texture2d<float> shadowTxt [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
//    return float4(0,0,0,1);
    
    device uint8_t* imageBuf = images+ctx.imagesOff+(ctx.imageSize*in.idx);
    const uint32_t imageId = *((device uint32_t*)(imageBuf+ctx.off.id));
    device uint8_t* thumbData = imageBuf+ctx.off.thumbData;
    
    const uint32_t thumbInset = (shadowTxt.get_width()-maskTxt.get_width())/2;
    const int2 pos = int2(in.posPx)-int2(thumbInset);
    const uint pxIdx = (pos.y*ctx.thumb.width + pos.x);
    
    const bool selected = (
        imageId>=ctx.selection.first &&
        imageId<ctx.selection.first+ctx.selection.count &&
        selectedImageIds[imageId-ctx.selection.first]
    );
    
    if (selected) {
        return float4(0,0,1,1);
    }
    
    const int maskWidth = maskTxt.get_width();
    const int maskHeight = maskTxt.get_height();
    const int maskWidth2 = maskWidth/2;
    const int maskHeight2 = maskHeight/2;
    const int2 marginX = int2(maskWidth2, (ctx.thumb.width-maskWidth2));
    const int2 marginY = int2(maskHeight2, (ctx.thumb.height-maskHeight2));
    
    const uint32_t pxOff = pxIdx*ctx.thumb.pxSize;
    const float4 thumb = float4(
        ((float)thumbData[pxOff+0] / 255),
        ((float)thumbData[pxOff+1] / 255),
        ((float)thumbData[pxOff+2] / 255),
        1
    );
    
    const bool inThumb = (pos.x>=0 && pos.y>=0 && pos.x<(int)ctx.thumb.width && pos.y<(int)ctx.thumb.height);
    
    // Calculate mask value
    float mask = 0;
    if (inThumb) {
        if (pos.x<=marginX[0] && pos.y<=marginY[0]) {
            // Top left
            mask = Sample::R(maskTxt, int2(pos.x, pos.y));
        
        } else if (pos.x>=marginX[1] && pos.y<=marginY[0]) {
            // Top right
            mask = Sample::R(maskTxt, int2(maskWidth2+(pos.x-marginX[1]), pos.y));
        
        } else if (pos.x<=marginX[0] && pos.y>=marginY[1]) {
            // Bottom left
            mask = Sample::R(maskTxt, int2(pos.x, maskHeight2+(pos.y-marginY[1])));
        
        } else if (pos.x>=marginX[1] & pos.y>=marginY[1]) {
            // Bottom right
            mask = Sample::R(maskTxt, int2(maskWidth2+(pos.x-marginX[1]), maskHeight2+(pos.y-marginY[1])));
        
        } else {
            mask = 1;
        }
    }
    
    // Calculate outline colors
    float4 outlineOver = 0;
    float4 outlineColorDodge = 0;
    if (inThumb) {
        int2 outlinePos = pos;
        if (pos.x <= marginX[0])        outlinePos.x = pos.x;
        else if (pos.x >= marginX[1])   outlinePos.x = maskWidth2+(pos.x-marginX[1]);
        else                            outlinePos.x = maskWidth2;
        
        if (pos.y <= marginY[0])        outlinePos.y = pos.y;
        else if (pos.y >= marginY[1])   outlinePos.y = maskHeight2+(pos.y-marginY[1]);
        else                            outlinePos.y = maskHeight2;
        
        const float outline = Sample::RGBA(outlineTxt, outlinePos).a;
        outlineOver = float4(float3(1), (32./255)*outline);
        outlineColorDodge = float4(float3((128./255)*outline), 1);
    }
    
    // Calculate shadow value
    float4 shadow = 0;
    {
        const int2 pos = int2(in.posPx);
        
        const int shadowWidth = shadowTxt.get_width();
        const int shadowHeight = shadowTxt.get_height();
        const int shadowWidth2 = shadowWidth/2;
        const int shadowHeight2 = shadowHeight/2;
        const int2 marginX = int2(shadowWidth2, (ctx.cellWidth-shadowWidth2));
        const int2 marginY = int2(shadowHeight2, (ctx.cellHeight-shadowHeight2));
        
        int2 shadowPos = pos;
        if (pos.x <= marginX[0])        shadowPos.x = pos.x;
        else if (pos.x >= marginX[1])   shadowPos.x = shadowWidth2+(pos.x-marginX[1]);
        else                            shadowPos.x = shadowWidth2;
        
        if (pos.y <= marginY[0])        shadowPos.y = pos.y;
        else if (pos.y >= marginY[1])   shadowPos.y = shadowHeight2+(pos.y-marginY[1]);
        else                            shadowPos.y = shadowHeight2;
        
        shadow = Sample::RGBA(shadowTxt, shadowPos);
    }
    
    return
        blendOver(
            blendMask(mask,
            blendColorDodge(outlineColorDodge,
            blendOver(outlineOver, thumb
        ))), shadow);
}

} // namespace ImageGridLayerShader
} // namespace MDCStudio

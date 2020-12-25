#import <metal_stdlib>
#import "ImageLayerTypes.h"
using namespace metal;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;

struct VertexOutput {
    float4 viewPosition [[position]];
    float2 pixelPosition;
};

vertex VertexOutput ImageLayer_VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    const float4 unitPosition = SquareVert[SquareVertIdx[vidx]];
    const float2 pixelPosition = {
        ((unitPosition.x+1)/2)*(ctx.imageWidth),
        ((unitPosition.y+1)/2)*(ctx.imageHeight),
    };
    
    return VertexOutput{
        unitPosition,
        pixelPosition
    };
}

float px(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint x, int dx, uint y, int dy) {
    x += clamp(dx, -((int)x), (int)(ctx.imageWidth-1-x));
    y += clamp(dy, -((int)y), (int)(ctx.imageHeight-1-y));
    return (float)pxs[(y*ctx.imageWidth)+x] / ImagePixelMax;
}

float r(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint2 pos) {
//    return px(ctx, pxs, pos.x, 0, pos.y, 0);
    
    if (pos.y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want R
        // Sample @ y-1, y+1
        if (pos.x % 2) return .5*px(ctx, pxs, pos.x, 0, pos.y, -1) + .5*px(ctx, pxs, pos.x, 0, pos.y, +1);
        
        // Have B
        // Want R
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*px(ctx, pxs, pos.x, -1, pos.y, -1) +
                    .25*px(ctx, pxs, pos.x, -1, pos.y, +1) +
                    .25*px(ctx, pxs, pos.x, +1, pos.y, -1) +
                    .25*px(ctx, pxs, pos.x, +1, pos.y, +1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want R
        // Sample @ this pixel
        if (pos.x % 2) return px(ctx, pxs, pos.x, 0, pos.y, 0);
        
        // Have G
        // Want R
        // Sample @ x-1 and x+1
        else return .5*px(ctx, pxs, pos.x, -1, pos.y, 0) + .5*px(ctx, pxs, pos.x, +1, pos.y, 0);
    }
}

float g(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint2 pos) {
//    return px(ctx, pxs, pos.x, 0, pos.y, 0);
    
    if (pos.y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (pos.x % 2) return px(ctx, pxs, pos.x, 0, pos.y, 0);
        
        // Have B
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*px(ctx, pxs, pos.x, -1, pos.y, 0) +
                    .25*px(ctx, pxs, pos.x, +1, pos.y, 0) +
                    .25*px(ctx, pxs, pos.x, 0, pos.y, -1) +
                    .25*px(ctx, pxs, pos.x, 0, pos.y, +1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        if (pos.x % 2) return   .25*px(ctx, pxs, pos.x, -1, pos.y, 0) +
                                .25*px(ctx, pxs, pos.x, +1, pos.y, 0) +
                                .25*px(ctx, pxs, pos.x, 0, pos.y, -1) +
                                .25*px(ctx, pxs, pos.x, 0, pos.y, +1) ;
        
        // Have G
        // Want G
        // Sample @ this pixel
        else return px(ctx, pxs, pos.x, 0, pos.y, 0);
    }
}

float b(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint2 pos) {
//    return px(ctx, pxs, pos.x, 0, pos.y, 0);
    
    if (pos.y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want B
        // Sample @ x-1, x+1
        if (pos.x % 2) return .5*px(ctx, pxs, pos.x, -1, pos.y, 0) + .5*px(ctx, pxs, pos.x, +1, pos.y, 0);
        
        // Have B
        // Want B
        // Sample @ this pixel
        else return px(ctx, pxs, pos.x, 0, pos.y, 0);
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want B
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        if (pos.x % 2) return   .25*px(ctx, pxs, pos.x, -1, pos.y, -1) +
                                .25*px(ctx, pxs, pos.x, -1, pos.y, +1) +
                                .25*px(ctx, pxs, pos.x, +1, pos.y, -1) +
                                .25*px(ctx, pxs, pos.x, +1, pos.y, +1) ;
        
        // Have G
        // Want B
        // Sample @ y-1, y+1
        else return .5*px(ctx, pxs, pos.x, 0, pos.y, -1) + .5*px(ctx, pxs, pos.x, 0, pos.y, +1);
    }
}

uint3 binFromColor(float3 color) {
    const uint32_t maxBin = (uint32_t)(sizeof(Histogram::r)/sizeof(*Histogram::r))-1;
    return {
        clamp((uint32_t)round(color.r*maxBin), (uint32_t)0, maxBin),
        clamp((uint32_t)round(color.g*maxBin), (uint32_t)0, maxBin),
        clamp((uint32_t)round(color.b*maxBin), (uint32_t)0, maxBin),
    };
}

static float srgbFromLinearSRGB(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4) - .055;
}

fragment float4 ImageLayer_FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    device Histogram& inputHistogram [[buffer(2)]],
    device Histogram& outputHistogram [[buffer(3)]],
    VertexOutput interpolated [[stage_in]]
) {
    // Bayer pattern:
    //  Row0    G R G R
    //  Row1    B G B G
    //  Row2    G R G R
    //  Row3    B G B G
    uint2 pos = {(uint)interpolated.pixelPosition.x, (uint)interpolated.pixelPosition.y};
    float3 inputColor(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
    float3x3 colorMatrix(ctx.colorMatrix.c0, ctx.colorMatrix.c1, ctx.colorMatrix.c2);
    float3 outputColor_xyz = colorMatrix*inputColor;
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 LinearSRGBD65_From_XYZD65(
        3.2404542, -0.9692660, 0.0556434,
        -1.5371385, 1.8760108, -0.2040259,
        -0.4985314, 0.0415560, 1.0572252
    );
    float3 outputColor_linearSRGB = LinearSRGBD65_From_XYZD65*outputColor_xyz;
    float3 outputColor_srgb = float3{
        srgbFromLinearSRGB(outputColor_linearSRGB[0]),
        srgbFromLinearSRGB(outputColor_linearSRGB[1]),
        srgbFromLinearSRGB(outputColor_linearSRGB[2])
    };
    
    uint3 inputColorBin = binFromColor(inputColor);
    atomic_fetch_add_explicit((device atomic_uint*)&inputHistogram.r[inputColorBin.r], 1, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_uint*)&inputHistogram.g[inputColorBin.g], 1, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_uint*)&inputHistogram.b[inputColorBin.b], 1, memory_order_relaxed);
    
    uint3 outputColorBin = binFromColor(outputColor_srgb);
    atomic_fetch_add_explicit((device atomic_uint*)&outputHistogram.r[outputColorBin.r], 1, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_uint*)&outputHistogram.g[outputColorBin.g], 1, memory_order_relaxed);
    atomic_fetch_add_explicit((device atomic_uint*)&outputHistogram.b[outputColorBin.b], 1, memory_order_relaxed);
    
    return float4(outputColor_srgb, 1);
}

#import <metal_stdlib>
#import "MDCImageLayerTypes.h"
using namespace metal;
using namespace MDCImageLayerTypes;

static float4x4 scale(float x, float y, float z) {
    return {
        {x, 0, 0, 0}, // Column 0
        {0, y, 0, 0}, // Column 1
        {0, 0, z, 0}, // Column 2
        {0, 0, 0, 1}, // Column 3
    };
}

struct VertexOutput {
    float4 viewPosition [[position]];
    float2 pixelPosition;
};

vertex VertexOutput MDCImageLayer_VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    const float4x4 scaleTransform = scale(
        (float)ctx.imageWidth/ctx.viewWidth,
        -(float)ctx.imageHeight/ctx.viewHeight,
        1
    );
    const float4 unitPosition = ctx.v[ctx.vi[vidx]];
    const float4 position = scaleTransform * unitPosition;
    const float2 pixelPosition = {
        ((unitPosition.x+1)/2)*(ctx.imageWidth),
        ((unitPosition.y+1)/2)*(ctx.imageHeight),
    };
    
    return VertexOutput{
        position,
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

fragment float4 MDCImageLayer_FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    VertexOutput interpolated [[stage_in]]
) {
    // Bayer pattern:
    //  Row0    G R G R
    //  Row1    B G B G
    //  Row2    G R G R
    //  Row3    B G B G
    uint2 pos = {(uint)interpolated.pixelPosition.x, (uint)interpolated.pixelPosition.y};
    
//    float3x3 colorMatrix = {
//        {    26.14248486,   -0.34495861,      5.0718457},  // Column 0
//        {   -20.00693736,    9.11605476,    -31.09156744}, // Column 1
//        {    31.76553751,   29.68887885,    109.69564914}, // Column 2
//    };
    
//    float3x3 colorMatrix = {
//        26.14248486,-20.00693736,31.76553751,
//        -0.34495861,9.11605476,29.68887885,
//        5.0718457,-31.09156744,109.69564914,
//    };
    
//    float3x3 colorMatrix = {
//        26.14248486,-20.00693736,31.76553751,
//        -0.34495861,9.11605476,29.68887885,
//        5.0718457,-31.09156744,109.69564914,
//    };
    
//    float3x3 colorMatrix = {
//        26.14248486, -0.34495861,5.0718457,
//        -20.00693736,9.11605476,-31.09156744,
//        31.76553751,29.68887885,109.69564914,
//    };
    
//    float3x3 colorMatrix(
//        130.057567,     -10.19467154,   13.72267482,
//        -59.14664147,   64.46669665,    -84.29080328,
//        44.19696355,    30.37530181,    201.6987413
//    );

    
    
//    float3x3 colorMatrix(
//        26.14248486, -0.34495861, 5.0718457,    // Column 0
//        -20.00693736, 9.11605476, -31.09156744, // Column 1
//        31.76553751, 29.68887885, 109.69564914  // Column 2
//    );

    float3x3 colorMatrix(
        1,  0,  0,
        0,  1,  0,
        0,  0,  1
    );

//    float3x3 colorMatrix(
//        26.14248486,    -20.00693736,   31.76553751,
//        -0.34495861,    9.11605476,     29.68887885,
//        5.0718457,      -31.09156744,   109.69564914
//    );
    
//    float3x3 colorMatrix(
//        95.496633,-8.895581,12.708955,
//        -40.551059,44.143511,-53.883598,
//        33.547201,24.089959,149.957579
//    );
    
    float3 color(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
//    float3 color(1,0,0);
    return float4(colorMatrix*color, 1);
}

// unitToViewTransform -- transforms unit square coordinates -> view coordinates
// viewToImageTransform -- transforms view coordinates -> image coordinates

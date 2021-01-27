#import <metal_stdlib>
#import "ImageLayerTypes.h"
using namespace metal;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

vertex VertexOutput ImageLayer_VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    VertexOutput r = {
        .pos = SquareVert[SquareVertIdx[vidx]],
        .posUnit = SquareVert[SquareVertIdx[vidx]].xy,
    };
    
    r.posUnit += 1;
    r.posUnit /= 2;
    r.posUnit.y = 1-r.posUnit.y;
    return r;
}

#define SamplePtr constant ImagePixel*

int32_t symclamp(int32_t N, int32_t n) {
    if (n < 0)          return -n;
    else if (n >= N)    return 2*((int)N-1)-n;
    else                return n;
}

float sample(SamplePtr in, int32_t width, int32_t height, int x, int y) {
//    printf("sample(%d %d)\n", x, y);
    x = symclamp(width, x);
    y = symclamp(height, y);
    return (float)in[y*width+x]/ImagePixelMax;
}

float sampleFilteredH(SamplePtr in, int32_t width, int32_t height, int x, int y) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    const float coeff[5] = {-0.25f, 0.5f, 0.5f, 0.5f, -0.25f};
    float accum = 0;
    for (int i=0, ix=x-2; i<5; i++, ix++) {
        const float k = coeff[i];
        accum += k*sample(in, width, height, ix, y);
    }
    return accum;
}

float sampleFilteredV(SamplePtr in, int32_t width, int32_t height, int x, int y) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    const float coeff[] = {-0.25f, 0.5f, 0.5f, 0.5f, -0.25f};
    float accum = 0;
    for (int i=0, iy=y-2; i<5; i++, iy++) {
        const float k = coeff[i];
        accum += k*sample(in, width, height, x, iy);
    }
    return accum;
}

float sampleDiffH(SamplePtr in, int32_t width, int32_t height, int green, int x, int y) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    float r = sample(in, width, height, x, y) - sampleFilteredH(in, width, height, x, y);
    if (((x+y) & 1) != green) r *= -1;
    return r;
}

float sampleDiffV(SamplePtr in, int32_t width, int32_t height, int green, int x, int y) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    float r = sample(in, width, height, x, y) - sampleFilteredV(in, width, height, x, y);
    if (((x+y) & 1) != green) r *= -1;
    return r;
}

float sampleDiffHSmoothed(SamplePtr in, int32_t width, int32_t height, int green, int x, int y) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    const float coeff[] = {0.03125f, 0.0703125f, 0.1171875f,
                           0.1796875f, 0.203125f, 0.1796875f,
                           0.1171875f, 0.0703125f, 0.03125f
    };
    float accum = 0;
    for (int i=0, ix=x-4; i<9; i++, ix++) {
        const float k = coeff[i];
        accum += k*sampleDiffH(in, width, height, green, ix, y);
    }
    return accum;
}

float sampleDiffVSmoothed(SamplePtr in, int32_t width, int32_t height, int green, int x, int y) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    
    const float coeff[] = {0.03125f, 0.0703125f, 0.1171875f,
                           0.1796875f, 0.203125f, 0.1796875f,
                           0.1171875f, 0.0703125f, 0.03125f
    };
    float accum = 0;
    for (int i=0, iy=y-4; i<9; i++, iy++) {
        const float k = coeff[i];
        accum += k*sampleDiffV(in, width, height, green, x, iy);
    }
    return accum;
}

float sampleOutputGreen(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int x, int y
) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    
    // Window size for estimating LMMSE statistics
    const int M = 4;
    // Small value added in denominators to avoid divide-by-zero
    const float DivEpsilon = 0.1f/(255*255);
    
    if (((x+y) & 1) != green) {
        // (x,y) is a red or blue location
        // Adjust loop indices m = -M,...,M when necessary to
        // compensate for left and right boundaries.  We effectively
        // do zero-padded boundary handling.
        int m0 = (x >= M) ? -M : -x;
        int m1 = (x < width - M) ? M : (width - x - 1);
        
        // The following computes
        // ph = var FilteredH[i + m]
        //   m=-M,...,M
        // Rh = mean(FilteredH[i + m] - DiffH[i + m])^2
        //   m=-M,...,M
        // h = LMMSE estimate
        // H = LMMSE estimate accuracy (estimated variance of h)
        float mom1 = 0;
        float ph = 0;
        float Rh = 0;
        for (int m=m0; m<=m1; m++) {
            float Temp = sampleDiffHSmoothed(in, width, height, green, x+m, y);
            mom1 += Temp;
            ph += Temp*Temp;
            Temp -= sampleDiffH(in, width, height, green, x+m, y);
            Rh += Temp*Temp;
        }
        
        // useZhangCodeEst=0: Compute mh = mean_m FilteredH[i + m]
        // useZhangCodeEst=1: Compute mh as in Zhang's MATLAB code
        const float mh = (!useZhangCodeEst ? mom1/(2*M + 1) : sampleDiffHSmoothed(in, width, height, green, x, y));
        
        ph = ph/(2*M) - mom1*mom1/(2*M*(2*M + 1));
        Rh = Rh/(2*M + 1) + DivEpsilon;
        float h = mh + (ph/(ph + Rh))*(sampleDiffH(in, width, height, green, x, y) - mh);
        float H = ph - (ph/(ph + Rh))*ph + DivEpsilon;
        
        // Adjust loop indices for top and bottom boundaries.
        m0 = (y >= M) ? -M : -y;
        m1 = (y < height - M) ? M : (height - y - 1);
        
        // The following computes
        // pv = var FilteredV[i + m]
        //      m = -M,...,M
        // Rv = mean(FilteredV[i + m] - DiffV[i + m])^2
        //      m = -M,...,M
        // v = LMMSE estimate
        // V = LMMSE estimate accuracy (estimated variance of v)
        mom1 = 0;
        float pv = 0;
        float Rv = 0;
        for (int m=m0; m<=m1; m++) {
            float Temp = sampleDiffVSmoothed(in, width, height, green, x, y+m);
            mom1 += Temp;
            pv += Temp*Temp;
            Temp -= sampleDiffV(in, width, height, green, x, y+m);
            Rv += Temp*Temp;
        }
        
        // useZhangCodeEst=0: Compute mv = mean_m FilteredV[i + m]
        // useZhangCodeEst=1: Compute mv as in Zhang's MATLAB code
        const float mv = (!useZhangCodeEst ? mom1/(2*M + 1) : sampleDiffVSmoothed(in, width, height, green, x, y));
        
        pv = pv/(2*M) - mom1*mom1/(2*M*(2*M + 1));
        Rv = Rv/(2*M + 1) + DivEpsilon;
        float v = mv + (pv/(pv + Rv))*(sampleDiffV(in, width, height, green, x, y) - mv);
        float V = pv - (pv/(pv + Rv))*pv + DivEpsilon;
        
        // Fuse the directional estimates to obtain the green component
        return sample(in, width, height, x, y) + (V*h + H*v) / (H + V);
    
    } else {
        return sample(in, width, height, x, y);
    }
}

float sampleDiffGR(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    
    if (((x+y) & 1)!=green && (y&1)==redY) {
        return sampleOutputGreen(in, width, height, useZhangCodeEst, green, x, y) - sample(in, width, height, x, y);
    } else {
        return sampleDiffH(in, width, height, green, x, y);
    }
}

float sampleDiffGB(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    
    if (((x+y) & 1)!=green && (y&1)!=redY) {
        return sampleOutputGreen(in, width, height, useZhangCodeEst, green, x, y) - sample(in, width, height, x, y);
    } else {
        return sampleDiffV(in, width, height, green, x, y);
    }
}

float sampleDiagAvgDiffGR(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    
    assert(((x+y) & 1) != green);
    assert((y&1) != redY);
    
    const int32_t L = 0; // Left
    const int32_t R = 1; // Right
    
    // Down
    float d[] = {
        sampleDiffGR(in, width, height, useZhangCodeEst, green, redY, x-1, y+1),
        sampleDiffGR(in, width, height, useZhangCodeEst, green, redY, x+1, y+1)
    };
    
    // Up
    float u[] = {
        sampleDiffGR(in, width, height, useZhangCodeEst, green, redY, x-1, y-1),
        sampleDiffGR(in, width, height, useZhangCodeEst, green, redY, x+1, y-1)
    };
    
    if (y == 0) {
        if (x == 0)             return d[R];
        else if (x < width-1)   return (d[L] + d[R]) / 2;
        else                    return d[L];
    
    } else if (y < height-1) {
        if (x == 0)             return (u[R] + d[R]) / 2;
        else if (x < width-1)   return (u[L] + u[R] + d[L] + d[R]) / 4;
        else                    return (u[L] + d[L]) / 2;
    
    } else {
        if (x == 0)             return u[R];
        else if (x < width-1)   return (u[L] + u[R]) / 2;
        else                    return u[L];
    }
}

float sampleDiagAvgDiffGB(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    
    assert(((x+y) & 1) != green);
    assert((y&1) == redY);
    
    const int32_t L = 0; // Left
    const int32_t R = 1; // Right
    
    // Down
    float d[] = {
        sampleDiffGB(in, width, height, useZhangCodeEst, green, redY, x-1, y+1),
        sampleDiffGB(in, width, height, useZhangCodeEst, green, redY, x+1, y+1)
    };
    
    // Up
    float u[] = {
        sampleDiffGB(in, width, height, useZhangCodeEst, green, redY, x-1, y-1),
        sampleDiffGB(in, width, height, useZhangCodeEst, green, redY, x+1, y-1)
    };
    
    if (y == 0) {
        if (x == 0)             return d[R];
        else if (x < width-1)   return (d[L] + d[R]) / 2;
        else                    return d[L];
    
    } else if (y < height-1) {
        if (x == 0)             return (u[R] + d[R]) / 2;
        else if (x < width-1)   return (u[L] + u[R] + d[L] + d[R]) / 4;
        else                    return (u[L] + d[L]) / 2;
    
    } else {
        if (x == 0)             return u[R];
        else if (x < width-1)   return (u[L] + u[R]) / 2;
        else                    return u[L];
    }
}

float sampleDiagAvgDiffGR_OrDiffGR(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    assert(((x+y) & 1) != green);
    
    if ((y&1) != redY) {
        return sampleDiagAvgDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y);
    } else {
        return sampleDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y);
    }
}

float sampleDiagAvgDiffGB_OrDiffGB(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    x = symclamp(width, x);
    y = symclamp(height, y);
    assert(((x+y) & 1) != green);
    
    if ((y&1) == redY) {
        return sampleDiagAvgDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y);
    } else {
        return sampleDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y);
    }
}

float sampleAxialAvgDiffGR(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    assert(((x+y) & 1) == green);
    
    const float l = sampleDiagAvgDiffGR_OrDiffGR(in, width, height, useZhangCodeEst, green, redY, x-1, y);
    const float r = sampleDiagAvgDiffGR_OrDiffGR(in, width, height, useZhangCodeEst, green, redY, x+1, y);
    const float u = sampleDiagAvgDiffGR_OrDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y-1);
    const float d = sampleDiagAvgDiffGR_OrDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y+1);
    if (y == 0) {
        if (x == 0)             return (r + d) / 2;
        else if (x < width - 1) return (l + r + 2*d) / 4;
        else                    return (l + d) / 2;
    
    } else if (y < height - 1) {
        if (x == 0)             return (2*r + u + d) / 4;
        else if (x < width - 1) return (l + r + u + d) / 4;
        else                    return (2*l + u + d) / 4;
    
    } else {
        if (x == 0)             return (r + u)/2;
        else if (x < width - 1) return (l + r + 2*u) / 4;
        else                    return (l + u) / 2;
    }
}

float sampleAxialAvgDiffGB(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    assert(((x+y) & 1) == green);
    
    const float l = sampleDiagAvgDiffGB_OrDiffGB(in, width, height, useZhangCodeEst, green, redY, x-1, y);
    const float r = sampleDiagAvgDiffGB_OrDiffGB(in, width, height, useZhangCodeEst, green, redY, x+1, y);
    const float u = sampleDiagAvgDiffGB_OrDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y-1);
    const float d = sampleDiagAvgDiffGB_OrDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y+1);
    if (y == 0) {
        if (x == 0)             return (r + d) / 2;
        else if (x < width - 1) return (l + r + 2*d) / 4;
        else                    return (l + d) / 2;
    
    } else if (y < height - 1) {
        if (x == 0)             return (2*r + u + d) / 4;
        else if (x < width - 1) return (l + r + u + d) / 4;
        else                    return (2*l + u + d) / 4;
    
    } else {
        if (x == 0)             return (r + u)/2;
        else if (x < width - 1) return (l + r + 2*u) / 4;
        else                    return (l + u) / 2;
    }
}

float sampleDiffGR_Final(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    
    if (((x+y) & 1) == green) {
        return sampleAxialAvgDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y);
    
    } else if ((y&1) != redY) {
        return sampleDiagAvgDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y);
    
    } else {
        return sampleDiffGR(in, width, height, useZhangCodeEst, green, redY, x, y);
    }
}

float sampleDiffGB_Final(
    SamplePtr in,
    int width, int height,
    int useZhangCodeEst,
    int green, int redY,
    int x, int y
) {
    assert(x>=0 && x<width);
    assert(y>=0 && y<height);
    
    if (((x+y) & 1) == green) {
        return sampleAxialAvgDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y);
    
    } else if ((y&1) == redY) {
        return sampleDiagAvgDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y);
    
    } else {
        return sampleDiffGB(in, width, height, useZhangCodeEst, green, redY, x, y);
    }
}





float px(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint x, int dx, uint y, int dy) {
    x += clamp(dx, -((int)x), (int)(ctx.imageWidth-1-x));
    y += clamp(dy, -((int)y), (int)(ctx.imageHeight-1-y));
    return (float)pxs[(y*ctx.imageWidth)+x] / ImagePixelMax;
}

//float r(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint2 pos) {
////    return px(ctx, pxs, pos.x, 0, pos.y, 0);
//    
//    if (pos.y % 2) {
//        // ROW = B G B G ...
//        
//        // Have G
//        // Want R
//        // Sample @ y-1, y+1
//        if (pos.x % 2) return .5*px(ctx, pxs, pos.x, 0, pos.y, -1) + .5*px(ctx, pxs, pos.x, 0, pos.y, +1);
//        
//        // Have B
//        // Want R
//        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
//        else return .25*px(ctx, pxs, pos.x, -1, pos.y, -1) +
//                    .25*px(ctx, pxs, pos.x, -1, pos.y, +1) +
//                    .25*px(ctx, pxs, pos.x, +1, pos.y, -1) +
//                    .25*px(ctx, pxs, pos.x, +1, pos.y, +1) ;
//    
//    } else {
//        // ROW = G R G R ...
//        
//        // Have R
//        // Want R
//        // Sample @ this pixel
//        if (pos.x % 2) return px(ctx, pxs, pos.x, 0, pos.y, 0);
//        
//        // Have G
//        // Want R
//        // Sample @ x-1 and x+1
//        else return .5*px(ctx, pxs, pos.x, -1, pos.y, 0) + .5*px(ctx, pxs, pos.x, +1, pos.y, 0);
//    }
//}
//
//float g(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint2 pos) {
////    return px(ctx, pxs, pos.x, 0, pos.y, 0);
//    
//    if (pos.y % 2) {
//        // ROW = B G B G ...
//        
//        // Have G
//        // Want G
//        // Sample @ this pixel
//        if (pos.x % 2) return px(ctx, pxs, pos.x, 0, pos.y, 0);
//        
//        // Have B
//        // Want G
//        // Sample @ x-1, x+1, y-1, y+1
//        else return .25*px(ctx, pxs, pos.x, -1, pos.y, 0) +
//                    .25*px(ctx, pxs, pos.x, +1, pos.y, 0) +
//                    .25*px(ctx, pxs, pos.x, 0, pos.y, -1) +
//                    .25*px(ctx, pxs, pos.x, 0, pos.y, +1) ;
//    
//    } else {
//        // ROW = G R G R ...
//        
//        // Have R
//        // Want G
//        // Sample @ x-1, x+1, y-1, y+1
//        if (pos.x % 2) return   .25*px(ctx, pxs, pos.x, -1, pos.y, 0) +
//                                .25*px(ctx, pxs, pos.x, +1, pos.y, 0) +
//                                .25*px(ctx, pxs, pos.x, 0, pos.y, -1) +
//                                .25*px(ctx, pxs, pos.x, 0, pos.y, +1) ;
//        
//        // Have G
//        // Want G
//        // Sample @ this pixel
//        else return px(ctx, pxs, pos.x, 0, pos.y, 0);
//    }
//}
//
//float b(constant RenderContext& ctx [[buffer(0)]], constant ImagePixel* pxs, uint2 pos) {
////    return px(ctx, pxs, pos.x, 0, pos.y, 0);
//    
//    if (pos.y % 2) {
//        // ROW = B G B G ...
//        
//        // Have G
//        // Want B
//        // Sample @ x-1, x+1
//        if (pos.x % 2) return .5*px(ctx, pxs, pos.x, -1, pos.y, 0) + .5*px(ctx, pxs, pos.x, +1, pos.y, 0);
//        
//        // Have B
//        // Want B
//        // Sample @ this pixel
//        else return px(ctx, pxs, pos.x, 0, pos.y, 0);
//    
//    } else {
//        // ROW = G R G R ...
//        
//        // Have R
//        // Want B
//        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
//        if (pos.x % 2) return   .25*px(ctx, pxs, pos.x, -1, pos.y, -1) +
//                                .25*px(ctx, pxs, pos.x, -1, pos.y, +1) +
//                                .25*px(ctx, pxs, pos.x, +1, pos.y, -1) +
//                                .25*px(ctx, pxs, pos.x, +1, pos.y, +1) ;
//        
//        // Have G
//        // Want B
//        // Sample @ y-1, y+1
//        else return .5*px(ctx, pxs, pos.x, 0, pos.y, -1) + .5*px(ctx, pxs, pos.x, 0, pos.y, +1);
//    }
//}

uint3 binFromColor(float3 color) {
    const uint32_t maxBin = (uint32_t)(sizeof(Histogram::r)/sizeof(*Histogram::r))-1;
    return {
        clamp((uint32_t)round(color.r*maxBin), (uint32_t)0, maxBin),
        clamp((uint32_t)round(color.g*maxBin), (uint32_t)0, maxBin),
        clamp((uint32_t)round(color.b*maxBin), (uint32_t)0, maxBin),
    };
}

float3 XYYFromXYZ(const float3 xyz) {
    const float denom = xyz[0] + xyz[1] + xyz[2];
    return {xyz[0]/denom, xyz[1]/denom, xyz[1]};
}

float3 XYZFromXYY(const float3 xyy) {
    const float X = (xyy[0]*xyy[2])/xyy[1];
    const float Y = xyy[2];
    const float Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
    return {X, Y, Z};
}

fragment float ImageLayer_LoadRaw(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    device float3* samples [[buffer(2)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const float v = (float)pxs[ctx.imageWidth*pos.y + pos.x] / ImagePixelMax;
    if (pos.x >= ctx.sampleRect.left &&
        pos.x < ctx.sampleRect.right &&
        pos.y >= ctx.sampleRect.top &&
        pos.y < ctx.sampleRect.bottom) {
        const bool red = (!(pos.y%2) && (pos.x%2));
        const bool green = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
        const bool blue = ((pos.y%2) && !(pos.x%2));
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        const float3 sample = float3(red ? v : 0., green ? v : 0., blue ? v : 0.);
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = sample;
    }
    
    return v;
}



//static int mirrorClamp(uint N, int n) {
//    const int Ni = (int)N;
//    if (n < 0) return -n;
//    else if (n >= Ni) return 2*(Ni-1)-n;
//    else return n;
//}
//
//static int2 mirrorClamp(uint2 N, int2 n) {
//    return {mirrorClamp(N.x, n.x), mirrorClamp(N.y, n.y)};
//}

//float2 mirrorClampF(uint2 N, int2 n) {
//    return {(float)mirrorClamp(N.x, n.x), (float)mirrorClamp(N.y, n.y)};
//}


template <typename P>
uint mirrorClamp(uint bound, P pt, int delta=0) {
    const int ptd = (int)pt+delta;
    if (ptd < 0) return -ptd;
    if (ptd >= (int)bound) return 2*((int)bound-1)-ptd;
    return ptd;
}

template <typename P>
uint2 mirrorClamp2(uint2 bound, P pt, int2 delta=0) {
    return {
        mirrorClamp(bound.x, pt.x, delta.x),
        mirrorClamp(bound.y, pt.y, delta.y)
    };
}

template <typename T>
float3 sampleRGB(texture2d<float> txt, T pos, int2 delta=0) {
    const uint2 bounds(txt.get_width(), txt.get_height());
    return txt.sample(coord::pixel, float2(mirrorClamp2(bounds, pos.xy, delta))).rgb;
}

template <typename T>
float sampleR(texture2d<float> txt, T pos, int2 delta=0) {
    return sampleRGB(txt, pos, delta).r;
}

float SRGBGamma(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4)-.055;
}

float InverseSRGBGamma(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.04045) return x/12.92;
    return pow((x+.055)/1.055, 2.4);
}

fragment float ImageLayer_DebayerLMMSE_Gamma(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return SRGBGamma(sampleR(rawTxt, in.pos));
}

fragment float4 ImageLayer_DebayerLMMSE_Degamma(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = sampleRGB(txt, in.pos);
    return float4(InverseSRGBGamma(c.r), InverseSRGBGamma(c.g), InverseSRGBGamma(c.b), 1);
}

fragment float ImageLayer_DebayerLMMSE_Interp5(
    constant RenderContext& ctx [[buffer(0)]],
    constant bool& h [[buffer(1)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 dim(ctx.imageWidth, ctx.imageHeight);
    const int2 pos = int2(in.pos.xy);
    const sampler s = sampler(coord::pixel);
    return  -.25*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?-2:+0,!h?-2:+0)))).r    +
            +0.5*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?-1:+0,!h?-1:+0)))).r    +
            +0.5*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+0:+0,!h?+0:+0)))).r    +
            +0.5*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+1:+0,!h?+1:+0)))).r    +
            -.25*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+2:+0,!h?+2:+0)))).r    ;
}

fragment float ImageLayer_DebayerLMMSE_NoiseEst(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> filteredTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const sampler s;
    const bool green = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
    const float raw = rawTxt.sample(s, in.posUnit).r;
    const float filtered = filteredTxt.sample(s, in.posUnit).r;
    if (green)  return raw-filtered;
    else        return filtered-raw;
}

fragment float ImageLayer_DebayerLMMSE_Smooth9(
    constant RenderContext& ctx [[buffer(0)]],
    constant bool& h [[buffer(1)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 dim(ctx.imageWidth, ctx.imageHeight);
    const int2 pos = int2(in.pos.xy);
    const sampler s = sampler(coord::pixel);
    return  0.0312500*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?-4:+0,!h?-4:+0)))).r     +
            0.0703125*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?-3:+0,!h?-3:+0)))).r     +
            0.1171875*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?-2:+0,!h?-2:+0)))).r     +
            0.1796875*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?-1:+0,!h?-1:+0)))).r     +
            0.2031250*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+0:+0,!h?+0:+0)))).r     +
            0.1796875*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+1:+0,!h?+1:+0)))).r     +
            0.1171875*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+2:+0,!h?+2:+0)))).r     +
            0.0703125*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+3:+0,!h?+3:+0)))).r     +
            0.0312500*rawTxt.sample(s, float2(mirrorClamp2(dim, pos, int2(h?+4:+0,!h?+4:+0)))).r     ;
}

constant bool UseZhangCodeEst = false;

fragment float4 ImageLayer_DebayerLMMSE_CalcG(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> filteredHTxt [[texture(1)]],
    texture2d<float> diffHTxt [[texture(2)]],
    texture2d<float> filteredVTxt [[texture(3)]],
    texture2d<float> diffVTxt [[texture(4)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const bool red = (!(pos.y%2) && (pos.x%2));
    const bool blue = ((pos.y%2) && !(pos.x%2));
    const float raw = sampleR(rawTxt, pos);
    float g = 0;
    if (red || blue) {
        const int M = 4;
        const float DivEpsilon = 0.1/(255*255);
        
        // Adjust loop indices m = -M,...,M when necessary to
        // compensate for left and right boundaries.  We effectively
        // do zero-padded boundary handling.
        int m0 = (pos.x>=M ? -M : -pos.x);
        int m1 = (pos.x<(int)ctx.imageWidth-M ? M : (int)ctx.imageWidth-pos.x-1);
        
        // The following computes
        // ph =   var   FilteredH[i + m]
        //      m=-M,...,M
        // Rh =   mean  (FilteredH[i + m] - DiffH[i + m])^2
        //      m=-M,...,M
        // h = LMMSE estimate
        // H = LMMSE estimate accuracy (estimated variance of h)
        float mom1 = 0;
        float ph = 0;
        float Rh = 0;
        for (int m=m0; m <= m1; m++) {
            float Temp = 0;
            Temp = sampleR(filteredHTxt, pos, {m,0});
            mom1 += Temp;
            ph += Temp*Temp;
            Temp -= sampleR(diffHTxt, pos, {m,0});
            Rh += Temp*Temp;
        }
        
        float mh = 0;
        // Compute mh = mean_m FilteredH[i + m]
        if (!UseZhangCodeEst) mh = mom1/(2*M + 1);
        // Compute mh as in Zhang's MATLAB code
        else mh = sampleR(filteredHTxt, pos);
        
        ph = ph/(2*M) - mom1*mom1/(2*M*(2*M + 1));
        Rh = Rh/(2*M + 1) + DivEpsilon;
        float h = mh + (ph/(ph + Rh))*(sampleR(diffHTxt,pos)-mh);
        float H = ph - (ph/(ph + Rh))*ph + DivEpsilon;
        
        // Adjust loop indices for top and bottom boundaries
        m0 = (pos.y>=M ? -M : -pos.y);
        m1 = (pos.y<(int)ctx.imageHeight-M ? M : (int)ctx.imageHeight-pos.y-1);
        
        // The following computes
        // pv =   var   FilteredV[i + m]
        //      m=-M,...,M
        // Rv =   mean  (FilteredV[i + m] - DiffV[i + m])^2
        //      m=-M,...,M
        // v = LMMSE estimate
        // V = LMMSE estimate accuracy (estimated variance of v)
        mom1 = 0;
        float pv = 0;
        float Rv = 0;
        for (int m=m0; m<=m1; m++) {
            float Temp = 0;
            Temp = sampleR(filteredVTxt, pos, {0,m});
            mom1 += Temp;
            pv += Temp*Temp;
            Temp -= sampleR(diffVTxt, pos, {0,m});
            Rv += Temp*Temp;
        }
        
        float mv = 0;
        // Compute mv = mean_m FilteredV[i + m]
        if (!UseZhangCodeEst) mv = mom1/(2*M + 1);
        // Compute mv as in Zhang's MATLAB code
        else mv = sampleR(filteredVTxt, pos);
        
        pv = pv/(2*M) - mom1*mom1/(2*M*(2*M + 1));
        Rv = Rv/(2*M + 1) + DivEpsilon;
        float v = mv + (pv/(pv + Rv))*(sampleR(diffVTxt,pos)-mv);
        float V = pv - (pv/(pv + Rv))*pv + DivEpsilon;
        
        // Fuse the directional estimates to obtain the green component
        g = raw + (V*h + H*v) / (H + V);
    
    } else {
        // This is a green pixel -- return its value directly
        g = raw;
    }
    
    return float4(0, g, 0, 1);
}

fragment float ImageLayer_DebayerLMMSE_CalcDiffGRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant bool& modeGR [[buffer(1)]],
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> txt [[texture(1)]],
    texture2d<float> diffTxt [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const bool redPx = (!(pos.y%2) && (pos.x%2));
    const bool bluePx = ((pos.y%2) && !(pos.x%2));
    
    if ((modeGR && redPx) || (!modeGR && bluePx)) {
        const float raw = sampleR(rawTxt, pos);
        const float g = sampleRGB(txt, pos).g;
//        return g-raw;
        return g-raw;
    }
    
    // Pass-through
    return sampleR(diffTxt, pos);
}

float diagAvg(texture2d<float> txt, uint2 pos) {
    const int2 lu(-1,-1);
    const int2 ld(-1,+1);
    const int2 ru(+1,-1);
    const int2 rd(+1,+1);
    if (pos.y == 0) {
        if (pos.x == 0)
            return sampleR(txt,pos,rd);
        else if (pos.x < txt.get_width()-1)
            return (sampleR(txt,pos,ld)+sampleR(txt,pos,rd))/2;
        else
            return sampleR(txt,pos,ld);
    
    } else if (pos.y < txt.get_height()-1) {
        if (pos.x == 0)
            return (sampleR(txt,pos,ru)+sampleR(txt,pos,rd))/2;
        else if (pos.x < txt.get_width()-1)
            return (sampleR(txt,pos,lu)+sampleR(txt,pos,ru)+
                    sampleR(txt,pos,ld)+sampleR(txt,pos,rd))/4;
        else    
            return (sampleR(txt,pos,lu)+sampleR(txt,pos,ld))/2;
    
    } else {
        if (pos.x == 0)
            return sampleR(txt,pos,ru);
        else if (pos.x < txt.get_width()-1)
            return (sampleR(txt,pos,lu)+sampleR(txt,pos,ru))/2;
        else
            return sampleR(txt,pos,lu);
    }
}

fragment float ImageLayer_DebayerLMMSE_CalcDiagAvgDiffGRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant bool& modeGR [[buffer(1)]],
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> txt [[texture(1)]],
    texture2d<float> diffTxt [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const bool redPx = (!(pos.y%2) && (pos.x%2));
    const bool bluePx = ((pos.y%2) && !(pos.x%2));
    
    if ((modeGR && bluePx) || (!modeGR && redPx)) {
        return diagAvg(diffTxt, pos);
    }
    
    // Pass-through
    return sampleR(diffTxt, pos);
}

float axialAvg(texture2d<float> txt, uint2 pos) {
    const int2 l(-1,+0);
    const int2 r(+1,+0);
    const int2 u(+0,-1);
    const int2 d(+0,+1);
    if (pos.y == 0) {
        if (pos.x == 0)
            return (sampleR(txt,pos,r)+sampleR(txt,pos,d))/2;
        else if (pos.x < txt.get_width()-1)
            return (sampleR(txt,pos,l)+sampleR(txt,pos,r)+2*sampleR(txt,pos,d))/4;
        else
            return (sampleR(txt,pos,l)+sampleR(txt,pos,d))/2;
    
    } else if (pos.y < txt.get_height()-1) {
        if (pos.x == 0)
            return (2*sampleR(txt,pos,r)+sampleR(txt,pos,u)+sampleR(txt,pos,d))/4;
        else if (pos.x < txt.get_width()-1)
            return (sampleR(txt,pos,l)+sampleR(txt,pos,r)+
                    sampleR(txt,pos,u)+sampleR(txt,pos,d))/4;
        else
            return (2*sampleR(txt,pos,l)+sampleR(txt,pos,u)+sampleR(txt,pos,d))/4;
    
    } else {
        if (pos.x == 0)
            return (sampleR(txt,pos,r)+sampleR(txt,pos,u))/2;
        else if (pos.x < txt.get_width()-1)
            return (sampleR(txt,pos,l)+sampleR(txt,pos,r)+2*sampleR(txt,pos,u))/4;
        else
            return (sampleR(txt,pos,l)+sampleR(txt,pos,u))/2;
    }
}

fragment float ImageLayer_DebayerLMMSE_CalcAxialAvgDiffGRGB(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    texture2d<float> txt [[texture(1)]],
    texture2d<float> diffTxt [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const bool greenPx = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
    if (greenPx) {
        return axialAvg(diffTxt, pos);
    }
    
    // Pass-through
    return sampleR(diffTxt, pos);
}

fragment float4 ImageLayer_DebayerLMMSE_CalcRB(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    texture2d<float> diffGR [[texture(1)]],
    texture2d<float> diffGB [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const float g = sampleRGB(txt, pos).g;
    const float dgr = sampleR(diffGR, pos);
    const float dgb = sampleR(diffGB, pos);
    return float4(g-dgr, g, g-dgb, 1);
}



// This is just 2 passes of ImageLayer_NoiseEst combined into 1
// TODO: profile this again. remember though that the -nextDrawable/-waitUntilCompleted pattern will cause our minimum render time to be the display refresh rate (16ms). so instead, for each iteration, we should only count the time _after_ -nextDrawable completes to the time after -waitUntilCompleted completes
//fragment void ImageLayer_NoiseEst2(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> rawTxt [[texture(0)]],
//    texture2d<float> filteredHTxt [[texture(1)]],
//    texture2d<float> filteredVTxt [[texture(2)]],
//    texture2d<float, access::read_write> diffH [[texture(3)]],
//    texture2d<float, access::read_write> diffV [[texture(4)]],
//    VertexOutput in [[stage_in]]
//) {
//    const uint2 pos = uint2(in.pos.xy);
//    const sampler s;
//    const bool green = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
//    const float raw = rawTxt.sample(s, in.posUnit).r;
//    const float filteredH = filteredHTxt.sample(s, in.posUnit).r;
//    const float filteredV = filteredVTxt.sample(s, in.posUnit).r;
//    if (green) {
//        diffH.write(float4(raw-filteredH), pos);
//        diffV.write(float4(raw-filteredV), pos);
//    } else {
//        diffH.write(float4(filteredH-raw), pos);
//        diffV.write(float4(filteredV-raw), pos);
//    }
//}







float ImageLayer_DebayerBilinear_R(texture2d<float> rawTxt, uint2 pos) {
    if (pos.y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want R
        // Sample @ y-1, y+1
        if (pos.x % 2) return .5*sampleR(rawTxt, pos, {+0,-1}) + .5*sampleR(rawTxt, pos, {+0,+1});
        
        // Have B
        // Want R
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*sampleR(rawTxt, pos, {-1,-1}) +
                    .25*sampleR(rawTxt, pos, {-1,+1}) +
                    .25*sampleR(rawTxt, pos, {+1,-1}) +
                    .25*sampleR(rawTxt, pos, {+1,+1}) ;
        
        
        
        
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want R
        // Sample @ this pixel
        if (pos.x % 2) return sampleR(rawTxt, pos, {+0,+0});
        
        // Have G
        // Want R
        // Sample @ x-1 and x+1
        else return .5*sampleR(rawTxt, pos, {-1,+0}) + .5*sampleR(rawTxt, pos, {+1,+0});
    }
}

float ImageLayer_DebayerBilinear_G(texture2d<float> rawTxt, uint2 pos) {
    if (pos.y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (pos.x % 2) return sampleR(rawTxt, pos, {+0,+0});
        
        // Have B
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*sampleR(rawTxt, pos, {-1,+0}) +
                    .25*sampleR(rawTxt, pos, {+1,+0}) +
                    .25*sampleR(rawTxt, pos, {+0,-1}) +
                    .25*sampleR(rawTxt, pos, {+0,+1}) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        if (pos.x % 2) return   .25*sampleR(rawTxt, pos, {-1,+0}) +
                                .25*sampleR(rawTxt, pos, {+1,+0}) +
                                .25*sampleR(rawTxt, pos, {+0,-1}) +
                                .25*sampleR(rawTxt, pos, {+0,+1}) ;
        
        // Have G
        // Want G
        // Sample @ this pixel
        else return sampleR(rawTxt, pos, {+0,+0});
    }
}

float ImageLayer_DebayerBilinear_B(texture2d<float> rawTxt, uint2 pos) {
    if (pos.y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want B
        // Sample @ x-1, x+1
        if (pos.x % 2) return .5*sampleR(rawTxt, pos, {-1,+0}) + .5*sampleR(rawTxt, pos, {+1,+0});
        
        // Have B
        // Want B
        // Sample @ this pixel
        else return sampleR(rawTxt, pos, {+0,+0});
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want B
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        if (pos.x % 2) return   .25*sampleR(rawTxt, pos, {-1,-1}) +
                                .25*sampleR(rawTxt, pos, {-1,+1}) +
                                .25*sampleR(rawTxt, pos, {+1,-1}) +
                                .25*sampleR(rawTxt, pos, {+1,+1}) ;
        
        // Have G
        // Want B
        // Sample @ y-1, y+1
        else return .5*sampleR(rawTxt, pos, {+0,-1}) + .5*sampleR(rawTxt, pos, {+0,+1});
    }
}




fragment float4 ImageLayer_DebayerBilinear(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    return float4(
        ImageLayer_DebayerBilinear_R(rawTxt, pos),
        ImageLayer_DebayerBilinear_G(rawTxt, pos),
        ImageLayer_DebayerBilinear_B(rawTxt, pos),
        1
    );
}


















//fragment float4 ImageLayer_DebayerBilinear(
//    constant RenderContext& ctx [[buffer(0)]],
//    constant ImagePixel* pxs [[buffer(1)]],
//    device float3* samples [[buffer(2)]],
//    VertexOutput in [[stage_in]]
//) {
//    const uint2 pos = uint2(in.pos.xy);
//    float3 c(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
//    
//    if (pos.x >= ctx.sampleRect.left &&
//        pos.x < ctx.sampleRect.right &&
//        pos.y >= ctx.sampleRect.top &&
//        pos.y < ctx.sampleRect.bottom) {
//        const bool red = (!(pos.y%2) && (pos.x%2));
//        const bool green = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
//        const bool blue = ((pos.y%2) && !(pos.x%2));
//        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
//        const float3 sample = float3(red ? c.r : 0., green ? c.g : 0., blue ? c.b : 0.);
//        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = sample;
//    }
//    
////    const uint BlackX = 504;
////    const uint BlackWidth = 8;
////    if (pos.y >= BlackX && pos.y < BlackX+BlackWidth) {
////        c = float3(0,0,0);
////    }
//    
//    // ## Bilinear debayering
////    return float4(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos), 1);
//    return float4(c, 1);
////    return float4(1, 0, 0, 1);
//}

fragment float4 ImageLayer_Downsample(
    constant RenderContext& ctx [[buffer(0)]],
    constant uint8_t& downsampleFactor [[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float2 q(1./ctx.imageWidth, 1./ctx.imageHeight);
    const sampler s = sampler(address::mirrored_repeat);
    const float2 startPos = in.posUnit - q*((downsampleFactor-1)/2.);
    float2 pos = startPos;
    float4 c = 0;
    for (uint iy=0; iy<downsampleFactor; iy++) {
        pos.x = startPos.x;
        for (uint ix=0; ix<downsampleFactor; ix++) {
            c += texture.sample(s, pos);
            pos.x += q.x;
        }
        pos.y += q.y;
    }
    c /= (downsampleFactor*downsampleFactor);
    return c;
}

fragment float4 ImageLayer_DebayerLMMSE(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const int redX = 1;
    const int redY = 0;
    const int green = 1 - ((redX + redY) & 1);
    float3 c;
    c.g =       sampleOutputGreen(pxs, ctx.imageWidth, ctx.imageHeight, false, green, pos.x, pos.y);
    c.r = c.g - sampleDiffGR_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
    c.b = c.g - sampleDiffGB_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
    return float4(c, 1);
}

fragment float4 ImageLayer_XYZD50FromCameraRaw(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_cameraRaw = sampleRGB(txt, in.pos);
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
    float3 outputColor_XYZD50 = XYZD50_From_CameraRaw * inputColor_cameraRaw;
    return float4(outputColor_XYZD50, 1);
}

fragment float4 ImageLayer_XYYD50FromCameraRaw(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_cameraRaw = sampleRGB(txt, in.pos);
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
//    const float3x3 XYZD50_From_CameraRaw(1);
    const float3 c = XYYFromXYZ(XYZD50_From_CameraRaw * inputColor_cameraRaw);
    return float4(c, 1);
}

fragment float4 ImageLayer_Exposure(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& exposure [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = sampleRGB(txt, in.pos);
    c[2] *= exposure;
    return float4(c, 1);
}

float scurve(float x) {
    return 1/(1+exp(-2*((2*x)-1)));
}

float bellcurve(float x) {
    return exp(-pow(2.5*(x-.5), 4));
}

fragment float4 ImageLayer_Brightness(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& brightness [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    
//    float3 c = sampleRGB(txt, in.pos);
//    const float b = bellcurve(c[0]/100)*brightness;
//    c[0] = 100*b + c[0]*(1-b);
//    return float4(c, 1);
    
//    float3 c = sampleRGB(txt, in.pos);
//    const float b = bellcurve(c[0]/100)*brightness;
//    c[0] += 100*b;
//    return float4(c, 1);
    
    float3 c = sampleRGB(txt, in.pos);
    const float b = bellcurve(c[0]/100)*brightness;
    c[0] += 100*b;
    return float4(c, 1);
    
//    float3 c = sampleRGB(txt, in.pos);
//    const float b = scurve(c[0]/100)*brightness;
//    c[0] = 100*b + c[0]*(1-b);
//    return float4(c, 1);
}

fragment float4 ImageLayer_Contrast(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& contrast [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = sampleRGB(txt, in.pos);
    c[0] = (contrast*(c[0]-50))+50;
    return float4(c, 1);
}

fragment float4 ImageLayer_Saturation(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& contrast [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = sampleRGB(txt, in.pos);
    return float4(c, 1);
}

fragment float4 ImageLayer_XYYD50FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = sampleRGB(txt, in.pos);
    return float4(XYYFromXYZ(c), 1);
}

fragment float4 ImageLayer_XYZD50FromXYYD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = sampleRGB(txt, in.pos);
    return float4(XYZFromXYY(c), 1);
}

float LabfInv(float x) {
    // From https://en.wikipedia.org/wiki/CIELAB_color_space
    const float d = 6./29;
    if (x > d)  return pow(x, 3);
    else        return 3*d*d*(x - 4./29);
}

float3 XYZFromLab(float3 white_XYZ, float3 c_Lab) {
    // From https://en.wikipedia.org/wiki/CIELAB_color_space
    const float k = (c_Lab.x+16)/116;
    const float X = white_XYZ.x * LabfInv(k+c_Lab.y/500);
    const float Y = white_XYZ.y * LabfInv(k);
    const float Z = white_XYZ.z * LabfInv(k-c_Lab.z/200);
    return float3(X,Y,Z);
}

float Labf(float x) {
    const float d = 6./29;
    const float d3 = d*d*d;
    if (x > d3) return pow(x, 1./3);
    else        return (x/(3*d*d)) + 4./29;
}

float3 LabFromXYZ(float3 white_XYZ, float3 c_XYZ) {
    const float k = Labf(c_XYZ.y/white_XYZ.y);
    const float L = 116*k - 16;
    const float a = 500*(Labf(c_XYZ.x/white_XYZ.x) - k);
    const float b = 200*(k - Labf(c_XYZ.z/white_XYZ.z));
    return float3(L,a,b);
}

fragment float4 ImageLayer_LabD50FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return float4(LabFromXYZ(D50, sampleRGB(txt, in.pos)), 1);
}

fragment float4 ImageLayer_XYZD50FromLabD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return float4(XYZFromLab(D50, sampleRGB(txt, in.pos)), 1);
}

fragment float ImageLayer_ExtractL(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return sampleR(txt, in.pos);
}

fragment float4 ImageLayer_LocalContrast(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& amount [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    texture2d<float> blurredLTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const float blurredL = sampleR(blurredLTxt, in.pos);
    float3 Lab = sampleRGB(txt, in.pos);
    Lab[0] += (Lab[0]-blurredL)*amount;
    return float4(Lab, 1);
    
    
//    float bufval = (lab->L[y][x] - buf[y][x]) * a;
//    destination[y][x] = LIM(lab->L[y][x] + bufval, 0.0001f, 32767.f);
}

constant uint UIntNormalizeVal = 65535;
fragment float4 ImageLayer_NormalizeXYYLuminance(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsXYY[[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float maxY = (float)maxValsXYY.z/UIntNormalizeVal;
    float3 c = sampleRGB(txt, in.pos);
    c[2] /= maxY;
    return float4(c, 1);
}

fragment float4 ImageLayer_NormalizeRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsRGB[[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float denom = (float)max3(maxValsRGB.x, maxValsRGB.y, maxValsRGB.z)/UIntNormalizeVal;
    const float3 c = sampleRGB(txt, in.pos) / denom;
    return float4(c, 1);
}

fragment float4 ImageLayer_ClipRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsRGB[[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
//    const float m = .7;
    const float m = (float)min3(maxValsRGB.x, maxValsRGB.y, maxValsRGB.z)/UIntNormalizeVal;
    const float3 c = sampleRGB(txt, in.pos);
    return float4(min(m, c.r), min(m, c.g), min(m, c.b), 1);
}

fragment float4 ImageLayer_DecreaseLuminance(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c_XYYD50 = sampleRGB(txt, in.pos);
    c_XYYD50[2] /= 4.5;
    return float4(c_XYYD50, 1);
}

fragment float4 ImageLayer_DecreaseLuminanceXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c_XYZD50 = sampleRGB(txt, in.pos);
    float3 c_XYYD50 = XYYFromXYZ(c_XYZD50);
    c_XYYD50[2] /= 3;
    return float4(XYZFromXYY(c_XYYD50), 1);
}

fragment float4 ImageLayer_LSRGBD65FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    device float3* samples [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c_XYZD50 = sampleRGB(txt, in.pos);
    
    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
    const float3x3 XYZD65_From_XYZD50 = transpose(float3x3(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    ));
    
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 LSRGBD65_From_XYZD65 = transpose(float3x3(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660, 1.8760108,  0.0415560,
        0.0556434,  -0.2040259, 1.0572252
    ));
    
    const float3 c_LSRGBD65 = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * c_XYZD50;
    
    const uint2 pos = uint2(in.pos.xy);
    if (pos.x >= ctx.sampleRect.left &&
        pos.x < ctx.sampleRect.right &&
        pos.y >= ctx.sampleRect.top &&
        pos.y < ctx.sampleRect.bottom) {
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = c_XYZD50;
    }
    
    return float4(c_LSRGBD65, 1);
}

//fragment float4 ImageLayer_LSRGBD65FromXYYD50(
//    constant RenderContext& ctx [[buffer(0)]],
//    device float3* samples [[buffer(1)]],
//    texture2d<float> texture [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float3 inputColor_XYYD50 = texture.sample({}, in.posUnit).rgb;
//    
//    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
//    const float3x3 XYZD65_From_XYZD50 = transpose(float3x3(
//        0.9555766,  -0.0230393, 0.0631636,
//        -0.0282895, 1.0099416,  0.0210077,
//        0.0122982,  -0.0204830, 1.3299098
//    ));
//    
//    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
//    const float3x3 LSRGBD65_From_XYZD65 = transpose(float3x3(
//        3.2404542,  -1.5371385, -0.4985314,
//        -0.9692660, 1.8760108,  0.0415560,
//        0.0556434,  -0.2040259, 1.0572252
//    ));
//    
//    const float3 c_XYZD50 = XYZFromXYY(inputColor_XYYD50);
//    const float3 c_LSRGBD65 = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * c_XYZD50;
//    
//    const uint2 pos = {(uint)in.pos.x, (uint)in.pos.y};
//    if (pos.x >= ctx.sampleRect.left &&
//        pos.x < ctx.sampleRect.right &&
//        pos.y >= ctx.sampleRect.top &&
//        pos.y < ctx.sampleRect.bottom) {
//        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
//        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = c_XYZD50;
//    }
//    
//    return float4(c_LSRGBD65, 1);
//}




fragment float4 ImageLayer_ColorAdjust(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_cameraRaw = sampleRGB(txt, in.pos);
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
    
    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
    const float3x3 XYZD65_From_XYZD50 = transpose(float3x3(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    ));
    
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 LSRGBD65_From_XYZD65 = transpose(float3x3(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660, 1.8760108,  0.0415560,
        0.0556434,  -0.2040259, 1.0572252
    ));
    float3 outputColor_LSRGB = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * XYZD50_From_CameraRaw * inputColor_cameraRaw;
    return float4(outputColor_LSRGB, 1);
}

// Atomically sets the value at `dst` if `val` is greater than it
void setIfGreater(volatile device atomic_uint& dst, uint val) {
    uint current = (device uint&)dst;
    while (val > current) {
        if (atomic_compare_exchange_weak_explicit(&dst, &current, val,
            memory_order_relaxed, memory_order_relaxed)) break;
    }
}

fragment float4 ImageLayer_FindMaxVals(
    constant RenderContext& ctx [[buffer(0)]],
    device Vals3& highlights [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 lsrgbfloat = sampleRGB(txt, in.pos);
    uint3 lsrgb = uint3(lsrgbfloat * UIntNormalizeVal);
    
    setIfGreater((device atomic_uint&)highlights.x, lsrgb.r);
    setIfGreater((device atomic_uint&)highlights.y, lsrgb.g);
    setIfGreater((device atomic_uint&)highlights.z, lsrgb.b);
    
    return float4(lsrgbfloat, 1);
}



//fragment float4 ImageLayer_Debayer(
//    constant RenderContext& ctx [[buffer(0)]],
//    constant ImagePixel* pxs [[buffer(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    uint2 pos = {(uint)in.pos.x, (uint)in.pos.y};
//    //    if (pos.y == 5) return float4(1,0,0,1);
//    
//    // ## Bilinear debayering
////    return float4(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos), 1);
//    return float4(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos), 1);
////    return float4(1, 0, 0, 1);
//}

//fragment float4 ImageLayer_FixHighlights(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> texture [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    float3 c = texture.sample({}, in.posUnit).rgb;
//    
////    uint goodCount = 0;
////    if (c.r < 1) goodCount++;
////    if (c.g < 1) goodCount++;
////    if (c.b < 1) goodCount++;
////    
////    if (goodCount == 0) return float4(ctx.whitePoint_CamRaw_D50, 1);
//    
////    switch (goodCount) {
////    case 0: return float4(ctx.whitePoint_CamRaw_D50, 1);
////    
////    case 1: {
////        // Green+blue are saturated
////        if (c.r < 1)        return float4((c.r/ctx.greenBluePoint_CamRaw_D50)*ctx.greenBluePoint_CamRaw_D50, 1);
////        // Red+blue are saturated
////        else if (c.g < 1)   return float4((c.g/ctx.redBluePoint_CamRaw_D50)*ctx.redBluePoint_CamRaw_D50, 1);
////        // Red+green are saturated
////        else if (c.b < 1)   return float4((c.b/ctx.redGreenPoint_CamRaw_D50)*ctx.redGreenPoint_CamRaw_D50, 1);
////    }
////    
////    case 2: {
////        // Blue is saturated
////        if (c.r<1 && c.g<1)         return  float4(
////                                                .5*((c.r/ctx.bluePoint_CamRaw_D50)*ctx.bluePoint_CamRaw_D50) +
////                                                .5*((c.g/ctx.bluePoint_CamRaw_D50)*ctx.bluePoint_CamRaw_D50),
////                                            1);
////        // Green is saturated
////        else if (c.r<1 && c.b<1)    return  float4(
////                                                .5*((c.r/ctx.greenPoint_CamRaw_D50)*ctx.greenPoint_CamRaw_D50) +
////                                                .5*((c.b/ctx.greenPoint_CamRaw_D50)*ctx.greenPoint_CamRaw_D50),
////                                            1);
////        // Red is saturated
////        else if (c.g<1 && c.b<1)    return  float4(
////                                                .5*((c.g/ctx.redPoint_CamRaw_D50)*ctx.redPoint_CamRaw_D50) +
////                                                .5*((c.b/ctx.redPoint_CamRaw_D50)*ctx.redPoint_CamRaw_D50),
////                                            1);
////    }
////    
//////    case 1: {
//////        float factor = 0;
//////        if (c.r < 1)        factor = c.r / ctx.whitePoint_CamRaw_D50.r;
//////        else if (c.g < 1)   factor = c.g / ctx.whitePoint_CamRaw_D50.g;
//////        else if (c.b < 1)   factor = c.b / ctx.whitePoint_CamRaw_D50.b;
//////        return float4(factor*ctx.whitePoint_CamRaw_D50, 1);
//////    }
//////    
//////    case 2: {
//////        const float3 factors = float3(
//////            c.r/ctx.whitePoint_CamRaw_D50.r,
//////            c.g/ctx.whitePoint_CamRaw_D50.g,
//////            c.b/ctx.whitePoint_CamRaw_D50.b
//////        );
//////        float factor = 0;
//////        if (c.r<1 && c.g<1)         factor = (factors.r+factors.g)/2;
//////        else if (c.r<1 && c.b<1)    factor = (factors.r+factors.b)/2;
//////        else                        factor = (factors.g+factors.b)/2;
//////        return float4(factor*ctx.whitePoint_CamRaw_D50, 1);
//////    }
////    }
//    
////    if (c.r>=1 && c.g>=1 && c.b>=1) c = ctx.whitePoint_CamRaw_D50;
////    if (c.r>=1 || c.g>=1 || c.b>=1) c = ctx.whitePoint_CamRaw_D50;
//    
////    if (c.r >= 1) c.r = ctx.whitePoint_CamRaw_D50.r;
////    if (c.g >= 1) c.g = ctx.whitePoint_CamRaw_D50.g;
////    if (c.b >= 1) c.b = ctx.whitePoint_CamRaw_D50.b;
//    
//    
//    uint goodCount = 0;
//    if (c.r < 1) goodCount++;
//    if (c.g < 1) goodCount++;
//    if (c.b < 1) goodCount++;
//    
//    switch (goodCount) {
//    case 0: return float4(ctx.whitePoint_CamRaw_D50, 1);
//    
//    case 1: {
//        // Green+blue are saturated
//        if (c.r < 1)        return float4((c.r/ctx.whitePoint_CamRaw_D50.r)*ctx.whitePoint_CamRaw_D50, 1);
//        // Red+blue are saturated
//        else if (c.g < 1)   return float4((c.g/ctx.whitePoint_CamRaw_D50.g)*ctx.whitePoint_CamRaw_D50, 1);
//        // Red+green are saturated
//        else if (c.b < 1)   return float4((c.b/ctx.whitePoint_CamRaw_D50.b)*ctx.whitePoint_CamRaw_D50, 1);
//    }
//    
//    case 2: {
//        // Blue is saturated
//        if (c.r<1 && c.g<1)         return float4(
//                                        .5*((c.r/ctx.whitePoint_CamRaw_D50.r)*ctx.whitePoint_CamRaw_D50)+
//                                        .5*((c.g/ctx.whitePoint_CamRaw_D50.g)*ctx.whitePoint_CamRaw_D50),
//                                    1);
//        // Green is saturated
//        else if (c.r<1 && c.b<1)    return float4(
//                                        .5*((c.r/ctx.whitePoint_CamRaw_D50.r)*ctx.whitePoint_CamRaw_D50)+
//                                        .5*((c.b/ctx.whitePoint_CamRaw_D50.b)*ctx.whitePoint_CamRaw_D50),
//                                    1);
//        // Red is saturated
//        else if (c.g<1 && c.b<1)    return float4(
//                                        .5*((c.g/ctx.whitePoint_CamRaw_D50.g)*ctx.whitePoint_CamRaw_D50)+
//                                        .5*((c.b/ctx.whitePoint_CamRaw_D50.b)*ctx.whitePoint_CamRaw_D50),
//                                    1);
//    }}
//    
//    
//    
//    return float4(c, 1);
//    
////    if (c.r>=1 && c.g>=1 && c.b>=1) c = ctx.whitePoint_CamRaw_D50;
//    
////    if (max3(c.r, c.g, c.b) >= 1.) {
////        // For any pixel that has an over-exposed channel, replace that
////        // pixel with the whitepoint in raw camera space.
////        return float4(ctx.whitePoint_CamRaw_D50, 1);
////    }
//    
//}







//float Labf(float x) {
//    // From http://www.brucelindbloom.com/index.html?Eqn_XYZ_to_Lab.html
//    const float e = 216./24389.;
//    const float k = 24389./27.;
//    return (x>e ? pow(x, 1./3) : (k*x+16)/116);
//}
//
//float3 Labf(float3 xyz) {
//    return float3(Labf(xyz.x), Labf(xyz.y), Labf(xyz.z));
//}
//
//float3 LabFromXYZ(float3 white_XYZ, float3 c_XYZ) {
//    // From http://www.brucelindbloom.com/index.html?Eqn_XYZ_to_Lab.html
//    const float3 r = c_XYZ/white_XYZ;
//    const float3 f = Labf(r);
//    const float L = 116*f.y-16;
//    const float a = 500*(f.x-f.y);
//    const float b = 200*(f.y-f.z);
//    return float3(L,a,b);
//}




class Float3x3 {
public:
    Float3x3(texture2d<float> txt, uint2 pos) {
        _c[0] = sampleR(txt, pos, {-1,-1});
        _c[1] = sampleR(txt, pos, {+0,-1});
        _c[2] = sampleR(txt, pos, {+1,-1});
        
        _c[3] = sampleR(txt, pos, {-1,+0});
        _c[4] = sampleR(txt, pos, {+0,+0});
        _c[5] = sampleR(txt, pos, {+1,+0});
        
        _c[6] = sampleR(txt, pos, {-1,+1});
        _c[7] = sampleR(txt, pos, {+0,+1});
        _c[8] = sampleR(txt, pos, {+1,+1});
    }
    
    thread float& get(int x=0, int y=0) {
        return _c[((y+1)*3)+(x+1)];
    }
    
private:
    float _c[9];
};

//float cget(float3x3 cm, int2 pos) {
//    return cm[pos.y+1][pos.x+1];
//}
//
//float cset(float3x3 cm, int2 pos, float c) {
//    return cm[pos.y+1][pos.x+1] = c;
//}

fragment float ImageLayer_FixHighlightsRaw(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const uint2 pos = uint2(in.pos.xy);
    const bool red = (!(pos.y%2) && (pos.x%2));
    const bool greenr = (!(pos.y%2) && !(pos.x%2));
    const bool greenb = ((pos.y%2) && (pos.x%2));
    const bool blue = ((pos.y%2) && !(pos.x%2));
    Float3x3 c(rawTxt, pos);
    
    float thresh = 1;
    
    // Short-circuit if this pixel isn't saturated
    if (c.get() < thresh) return c.get();
    
//    // Patch up the saturated values in `c`
//    if (red) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G * G R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.b;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.g;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.b;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.g;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.r;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.g;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.b;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.g;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.b;
//    
//    } else if (greenr) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G R * R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.g;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.b;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.g;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.r;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.g;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.r;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.g;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.b;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.g;
//    
//    } else if (greenb) {
//        //  Row0    G R G R
//        //  Row1    B * B G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.g;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.r;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.g;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.b;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.g;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.b;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.g;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.r;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.g;
//    
//    } else if (blue) {
//        //  Row0    G R G R
//        //  Row1    B G * G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.r;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.g;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.r;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.g;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.b;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.g;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.r;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.g;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.r;
//    }
//    
//    if (red) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G * G R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorR.r * (c.get(+0,+0));
//        const float g = ctx.highlightFactorR.g * (c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1));
//        const float b = ctx.highlightFactorR.b * (c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        return (r+g+b)/9;
//    
//    } else if (greenr) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G R * R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorG.r * (c.get(-1,+0)+c.get(+1,+0));
//        const float g = ctx.highlightFactorG.g * (c.get(+0,+0)+c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        const float b = ctx.highlightFactorG.b * (c.get(+0,-1)+c.get(+0,+1));
//        return (r+g+b)/9;
//    
//    } else if (greenb) {
//        //  Row0    G R G R
//        //  Row1    B * B G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorG.r * (c.get(+0,-1)+c.get(+0,+1));
//        const float g = ctx.highlightFactorG.g * (c.get(+0,+0)+c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        const float b = ctx.highlightFactorG.b * (c.get(-1,+0)+c.get(+1,+0));
//        return (r+g+b)/9;
//    
//    } else if (blue) {
//        //  Row0    G R G R
//        //  Row1    B G * G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorB.r * (c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        const float g = ctx.highlightFactorB.g * (c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1));
//        const float b = ctx.highlightFactorB.b * (c.get(+0,+0));
//        return (r+g+b)/9;
//    }
//    
//    return 0;
    
    //  Row0    G R G R
    //  Row1    B G B G
    //  Row2    G R G R
    //  Row3    B G B G
    
    uint goodCount = 0;
    if (c.get(-1,+0) < thresh) goodCount++;
    if (c.get(+1,+0) < thresh) goodCount++;
    if (c.get(+0,-1) < thresh) goodCount++;
    if (c.get(+0,+1) < thresh) goodCount++;
    if (goodCount == 0) {
        if (red) {
            c.get() *= 1.1300929235;
        } else if (greenr || greenb) {
            c.get() *= 1.6132952108;
        } else if (blue) {
            c.get() *= 1;
        }
        
    } else {
        if (red) {
//            uint gcount = 0;
//            float g = 0;
//            if (c.get(-1,-1) < thresh) { g += c.get(-1,-1); gcount++; };
//            if (c.get(+1,-1) < thresh) { g += c.get(+1,-1); gcount++; };
//            if (c.get(-1,+1) < thresh) { g += c.get(-1,+1); gcount++; };
//            if (c.get(+1,+1) < thresh) { g += c.get(+1,+1); gcount++; };
//            g /= gcount;
//            
//            uint bcount = 0;
//            float b = 0;
//            if (c.get(-1,+0) < thresh) { g += c.get(-1,+0); bcount++; };
//            if (c.get(+1,+0) < thresh) { g += c.get(+1,+0); bcount++; };
//            if (c.get(+0,-1) < thresh) { g += c.get(+0,-1); bcount++; };
//            if (c.get(+0,+1) < thresh) { g += c.get(+0,+1); bcount++; };
//            b /= bcount;
//            
//            if (gcount && bcount) {
//                c.get() = (ctx.highlightFactorR.g*g) + (ctx.highlightFactorR.b*b);
//            } else if (gcount) {
//                c.get() = (ctx.highlightFactorR.g*g);
//            } else if (bcount) {
//                c.get() = (ctx.highlightFactorR.b*b);
//            }
            
//            c.get() =   ctx.highlightFactorR.r*(c.get(-1,-1)+c.get(+1,-1)+c.get(-1,+1)+c.get(+1,+1))/8 +
//                        ctx.highlightFactorR.g*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/8;
            c.get() = 1.051*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
        
        } else if (greenr) {
//            c.get() = ctx.highlightFactorR.g*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
            c.get() = 1.544*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
        
        } else if (greenb) {
//            c.get() = ctx.highlightFactorR.b*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
            c.get() = 1.544*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
        
        } else if (blue) {
//            c.get() = ctx.highlightFactorG.r*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
            c.get() = 1.195*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
        }
    }
    return c.get();
}






//fragment float ImageLayer_FixHighlightsRaw(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> rawTxt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    //  Row0    G R G R
//    //  Row1    B G B G
//    //  Row2    G R G R
//    //  Row3    B G B G
//    
//    const uint2 pos = uint2(in.pos.xy);
//    const bool red = (!(pos.y%2) && (pos.x%2));
//    const bool greenr = (!(pos.y%2) && !(pos.x%2));
//    const bool greenb = ((pos.y%2) && (pos.x%2));
//    const bool blue = ((pos.y%2) && !(pos.x%2));
//    const uint2 bounds(rawTxt.get_width(), rawTxt.get_height());
//    float craw      = sampleR(rawTxt, in.pos, {+0,+0});
//    float crawl     = sampleR(rawTxt, in.pos, {-1,+0});
//    float crawr     = sampleR(rawTxt, in.pos, {+1,+0});
//    float crawu     = sampleR(rawTxt, in.pos, {+0,-1});
//    float crawd     = sampleR(rawTxt, in.pos, {+0,+1});
//    float crawul    = sampleR(rawTxt, in.pos, {-1,-1});
//    float crawur    = sampleR(rawTxt, in.pos, {+1,-1});
//    float crawdl    = sampleR(rawTxt, in.pos, {-1,+1});
//    float crawdr    = sampleR(rawTxt, in.pos, {+1,+1});
//    float thresh = 1;
//    
//    if (craw>=thresh) {
////        if (crawl>=thresh && crawr>=thresh && crawu>=thresh && crawd>=thresh &&
////            crawul>=thresh && crawur>=thresh && crawdl>=thresh && crawdr>=thresh) {
////            
////            
////        }
//        
//        return (crawl+crawr+crawu+crawd+crawul+crawur+crawdl+crawdr)/20;
//        
////        return (crawl+crawr+crawu+crawd+crawul+crawur+crawdl+crawdr)/20;
//    }
//    
//    
//    // repros
////    if (craw>=thresh) {
////        if (crawl>=thresh && crawr>=thresh && crawu>=thresh && crawd>=thresh &&
////            crawul>=thresh && crawur>=thresh && crawdl>=thresh && crawdr>=thresh) {
////            
////            craw *= 0.9607;
////        
////        } else if (greenr || greenb) {
////            return 0;
////        }
////    }
//    
//    return 0;
//}

//fragment float4 ImageLayer_FixHighlights(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> rawTxt [[texture(0)]],
//    texture2d<float> txt [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float craw = sampleR(rawTxt, in.pos);
//    const float crawl = sampleR(rawTxt, in.pos, {-1,+0});
//    const float crawr = sampleR(rawTxt, in.pos, {+1,+0});
//    const float crawu = sampleR(rawTxt, in.pos, {+0,-1});
//    const float crawd = sampleR(rawTxt, in.pos, {+0,+1});
//    const float crawul = 0;//sampleR(rawTxt, in.pos, {-1,-1});
//    const float crawur = 0;//sampleR(rawTxt, in.pos, {+1,-1});
//    const float crawdl = 0;//sampleR(rawTxt, in.pos, {-1,+1});
//    const float crawdr = 0;//sampleR(rawTxt, in.pos, {+1,+1});
//    const float thresh = 1;
//    
//    float3 c_CamRaw = sampleRGB(txt, in.pos);
//    const float3 c_XYZ = ctx.colorMatrix*c_CamRaw;
//    const float3 highlight_XYZ = ctx.colorMatrix*float3(1);
//    const float3 D50_XYZ(0.96422, 1, 0.82521);
//    const float3 highlight_LAB = labFromXYZ(D50_XYZ, highlight_XYZ);
//    const float3 c_LAB = labFromXYZ(D50_XYZ, c_XYZ);
//    const float highlight_dist = distance(highlight_LAB, c_LAB);
//    
//    if (craw >= thresh      ||
//        crawl >= thresh     ||
//        crawr >= thresh     ||
//        crawu >= thresh     ||
//        crawd >= thresh     ||
//        crawul >= thresh    ||
//        crawur >= thresh    ||
//        crawdl >= thresh    ||
//        crawdr >= thresh    ) {
//        c_CamRaw = 0;
//    }
//    
//    return float4(c_CamRaw, 1);
//}

//fragment float4 ImageLayer_FixHighlights(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> rawTxt [[texture(0)]],
//    texture2d<float> txt [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float craw = sampleR(rawTxt, in.pos);
//    const float crawl = sampleR(rawTxt, in.pos, {-1,+0});
//    const float crawr = sampleR(rawTxt, in.pos, {+1,+0});
//    const float crawu = sampleR(rawTxt, in.pos, {+0,-1});
//    const float crawd = sampleR(rawTxt, in.pos, {+0,+1});
//    const float crawul = 0;//sampleR(rawTxt, in.pos, {-1,-1});
//    const float crawur = 0;//sampleR(rawTxt, in.pos, {+1,-1});
//    const float crawdl = 0;//sampleR(rawTxt, in.pos, {-1,+1});
//    const float crawdr = 0;//sampleR(rawTxt, in.pos, {+1,+1});
//    const float thresh = 1;
//    
//    float3 c_CamRaw = sampleRGB(txt, in.pos);
//    const float3 c_XYZ = ctx.colorMatrix*c_CamRaw;
//    const float3 highlight_XYZ = ctx.colorMatrix*float3(1);
//    const float3 D50_XYZ(0.96422, 1, 0.82521);
//    const float3 highlight_LAB = labFromXYZ(D50_XYZ, highlight_XYZ);
//    const float3 c_LAB = labFromXYZ(D50_XYZ, c_XYZ);
//    const float highlight_dist = distance(highlight_LAB, c_LAB);
//    
//    if (craw >= thresh      ||
//        crawl >= thresh     ||
//        crawr >= thresh     ||
//        crawu >= thresh     ||
//        crawd >= thresh     ||
//        crawul >= thresh    ||
//        crawur >= thresh    ||
//        crawdl >= thresh    ||
//        crawdr >= thresh    ) {
//        c_CamRaw = 0;
//    }
//    
//    return float4(c_CamRaw, 1);
//}





















//fragment float4 ImageLayer_FixHighlights(
//    constant RenderContext& ctx [[buffer(0)]],
//    constant ImagePixel* pxs [[buffer(1)]],
//    texture2d<float> texture [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
////    // LMMSE
////    const uint2 pos = {(uint)in.pos.x, (uint)in.pos.y};
////    const int redX = 1;
////    const int redY = 0;
////    const int green = 1 - ((redX + redY) & 1);
////    float3 craw;
////    craw.g =          sampleOutputGreen(pxs, ctx.imageWidth, ctx.imageHeight, false, green, pos.x, pos.y);
////    craw.r = craw.g - sampleDiffGR_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
////    craw.b = craw.g - sampleDiffGB_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
////    if (craw.r>=1 || craw.g>=1 || craw.b>=1) return float4(1, 1, 1, 1);
////    float3 c = texture.sample(sampler(coord::pixel), in.pos.xy).rgb;
////    return float4(c, 1);
//    
//    
//    // Bilinear debayer
//    const uint2 pos = {(uint)in.pos.x, (uint)in.pos.y};
//    const float3 craw = float3(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
//    float3 c = texture.sample(sampler(coord::pixel), in.pos.xy).rgb;
//    if (craw.r>=254./255 || craw.g>=254./255 || craw.b>=254./255) c = float3(1,1,1);
////    if (craw.r >= 250./255) c.r = 1;
////    if (craw.g >= 250./255) c.g = 1;
////    if (craw.b >= 250./255) c.b = 1;
//    return float4(c, 1);
//}

//fragment float4 ImageLayer_FixHighlightsPropagation(
//    constant RenderContext& ctx [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    texture2d<float> smallRaw [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    float3 c = sampleRGB(txt, in.pos);
////    return float4(c, 1);
//    
//    uint goodCount = 0;
//    if (c.r < 1) goodCount++;
//    if (c.g < 1) goodCount++;
//    if (c.b < 1) goodCount++;
//    
//    if (goodCount < 3) {
//        // Find a reference pixel
//        const float2 q(1./smallRaw.get_width(), 1./smallRaw.get_height());
//        const sampler s = sampler(address::mirrored_repeat);
//        float3 cref(0);
//        uint i = 0;
//        for (i=0; i<1000; i++) {
//            float2 d((i+1)*q.x, (i+1)*q.y);
//            // -1 -1
//            cref = smallRaw.sample(s, in.posUnit + float2(-1*d.x, -1*d.y)).rgb;
//            if (cref.r<1 && cref.g<1 && cref.b<1) break;
//            // -1 +1
//            cref = smallRaw.sample(s, in.posUnit + float2(-1*d.x, +1*d.y)).rgb;
//            if (cref.r<1 && cref.g<1 && cref.b<1) break;
//            // +1 -1
//            cref = smallRaw.sample(s, in.posUnit + float2(+1*d.x, -1*d.y)).rgb;
//            if (cref.r<1 && cref.g<1 && cref.b<1) break;
//            // +1 +1
//            cref = smallRaw.sample(s, in.posUnit + float2(+1*d.x, +1*d.y)).rgb;
//            if (cref.r<1 && cref.g<1 && cref.b<1) break;
//        }
//        
//        switch (goodCount) {
//        case 0: {
//            c = cref / min3(cref.r, cref.g, cref.b);
//            break;
//        }
//        
//        case 1: {
//            c = float3(0,0,0);
//            break;
//        }
//        
//        case 2: {
//            c = float3(0,0,0);
//            break;
//        }}
//    }
////    c = float3(0,0,0);
//    return float4(c, 1);
//    
////    if (c)
////    
////    const float2 q(1./downsampledTexture.get_width(), 1./downsampledTexture.get_height());
////    const sampler s = sampler(address::mirrored_repeat);
////    const float2 startPos = in.posUnit - q*((Factor-1)/2.);
////    float2 pos = startPos;
////    for (uint iy=0; iy<Factor; iy++) {
////        pos.x = startPos.x;
////        for (uint ix=0; ix<Factor; ix++) {
////            c += texture.sample(s, pos);
////            pos.x += q.x;
////        }
////        pos.y += q.y;
////    }
////    return c;
////    
////    
////    
////    if (smallRaw.) {
////    
////    }
////    uint i = 0;
////    for (i=0; i<10; i++) {
////        
////    }
////    
////    // Find a reference pixel
////    
//////    return texture.sample(sampler(), in.posUnit);
//}

fragment float4 ImageLayer_SRGBGamma(
    constant RenderContext& ctx [[buffer(0)]],
    device float3* samples [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c_LSRGB = sampleRGB(txt, in.pos);
    float3 c_SRGB = float3{
        SRGBGamma(c_LSRGB.r),
        SRGBGamma(c_LSRGB.g),
        SRGBGamma(c_LSRGB.b)
    };
    
    const uint2 pos = uint2(in.pos.xy);
    if (pos.x >= ctx.sampleRect.left &&
        pos.x < ctx.sampleRect.right &&
        pos.y >= ctx.sampleRect.top &&
        pos.y < ctx.sampleRect.bottom) {
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = c_SRGB;
    }
    
    return float4(c_SRGB, 1);
}

fragment float4 ImageLayer_Display(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = sampleRGB(txt, in.pos);
    return float4(c, 1);
}


//fragment float4 ImageLayer_FragmentShader(
//    constant RenderContext& ctx [[buffer(0)]],
//    constant ImagePixel* pxs [[buffer(1)]],
//    device Histogram& inputHistogram [[buffer(2)]],
//    device Histogram& outputHistogram [[buffer(3)]],
//    VertexOutput in [[stage_in]]
//) {
//    // Bayer pattern:
//    //  Row0    G R G R
//    //  Row1    B G B G
//    //  Row2    G R G R
//    //  Row3    B G B G
//    uint2 pos = {(uint)in.pos.x, (uint)in.pos.y};
//    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
//    
//    // ## Bilinear debayering
//    float3 inputColor_cameraRaw(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
//    
//    // ## LMMSE debayering
////    const int redX = 1;
////    const int redY = 0;
////    const int green = 1 - ((redX + redY) & 1);
////    float3 inputColor_cameraRaw;
////    inputColor_cameraRaw.g =
////        sampleOutputGreen(pxs, ctx.imageWidth, ctx.imageHeight, false, green, pos.x, pos.y);
////    inputColor_cameraRaw.r = inputColor_cameraRaw.g -
////        sampleDiffGR_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
////    inputColor_cameraRaw.b = inputColor_cameraRaw.g -
////        sampleDiffGB_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
//    
//    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
//    const float3x3 XYZD65_From_XYZD50 = transpose(float3x3(
//        0.9555766,  -0.0230393, 0.0631636,
//        -0.0282895, 1.0099416,  0.0210077,
//        0.0122982,  -0.0204830, 1.3299098
//    ));
//    
//    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
//    const float3x3 LSRGBD65_From_XYZD65 = transpose(float3x3(
//        3.2404542,  -1.5371385, -0.4985314,
//        -0.9692660, 1.8760108,  0.0415560,
//        0.0556434,  -0.2040259, 1.0572252
//    ));
//    float3 outputColor_LSRGB = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * XYZD50_From_CameraRaw * inputColor_cameraRaw;
//    float3 outputColor_SRGB = saturate(float3{
//        SRGBFromLSRGB(outputColor_LSRGB[0]),
//        SRGBFromLSRGB(outputColor_LSRGB[1]),
//        SRGBFromLSRGB(outputColor_LSRGB[2])
//    });
//    
//    const float thresh = 1;
//    if (inputColor_cameraRaw.r >= thresh) outputColor_SRGB.r = 1;
//    if (inputColor_cameraRaw.g >= thresh) outputColor_SRGB.g = 1;
//    if (inputColor_cameraRaw.b >= thresh) outputColor_SRGB.b = 1;
//    
//    uint3 inputColorBin = binFromColor(inputColor_cameraRaw);
//    atomic_fetch_add_explicit((device atomic_uint*)&inputHistogram.r[inputColorBin.r], 1, memory_order_relaxed);
//    atomic_fetch_add_explicit((device atomic_uint*)&inputHistogram.g[inputColorBin.g], 1, memory_order_relaxed);
//    atomic_fetch_add_explicit((device atomic_uint*)&inputHistogram.b[inputColorBin.b], 1, memory_order_relaxed);
//    
//    // If any of the input raw-camera-space channels was saturated, saturate the corresponding output channel
//    
////    if (inputColor_cameraRaw.r>=1 || inputColor_cameraRaw.g>=1 || inputColor_cameraRaw.b>=1) {
////        outputColor_SRGB.r = 1;
////        outputColor_SRGB.g = 0;
////        outputColor_SRGB.b = 0;
////    }
//    
////    if (inputColor_cameraRaw.r >= 1) outputColor_SRGB.r = 1;
////    if (inputColor_cameraRaw.g >= 1) outputColor_SRGB.g = 1;
////    if (inputColor_cameraRaw.b >= 1) outputColor_SRGB.b = 1;
//    
////    const float thresh = 254.5/255;
//    
////    if (pos.x==2133 && pos.y==350) {
////        if (inputColor_cameraRaw.g >= .9999) outputColor_SRGB.g = 1;
//////        outputColor_SRGB.r = 0;
//////        outputColor_SRGB.g = 1;
//////        outputColor_SRGB.b = 0;
//////        outputColor_SRGB = {0,0,0};
////    }
//    
//    uint3 outputColorBin = binFromColor(outputColor_SRGB);
//    atomic_fetch_add_explicit((device atomic_uint*)&outputHistogram.r[outputColorBin.r], 1, memory_order_relaxed);
//    atomic_fetch_add_explicit((device atomic_uint*)&outputHistogram.g[outputColorBin.g], 1, memory_order_relaxed);
//    atomic_fetch_add_explicit((device atomic_uint*)&outputHistogram.b[outputColorBin.b], 1, memory_order_relaxed);
//    
//    return float4(outputColor_SRGB, 1);
//}

#import <metal_stdlib>
#import "ImageLayerTypes.h"
using namespace metal;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;

struct VertexOutput {
    float4 pos [[position]];
//    float2 pixelPosition;
};

vertex VertexOutput ImageLayer_VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    return VertexOutput{SquareVert[SquareVertIdx[vidx]]};
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

float SRGBFromLSRGB(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4) - .055;
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

fragment float4 ImageLayer_DebayerBilinear(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    device float3* samples [[buffer(2)]],
    VertexOutput interpolated [[stage_in]]
) {
    const uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
    const float3 c(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
    
    if (pos.x >= ctx.sampleRect.left &&
        pos.x < ctx.sampleRect.right &&
        pos.y >= ctx.sampleRect.top &&
        pos.y < ctx.sampleRect.bottom) {
        const bool red = (!(pos.y%2) && (pos.x%2));
        const bool green = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
        const bool blue = ((pos.y%2) && !(pos.x%2));
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        const float3 sample = float3(red ? c.r : 0., green ? c.g : 0., blue ? c.b : 0.);
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = sample;
    }
    
    // ## Bilinear debayering
//    return float4(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos), 1);
    return float4(c, 1);
//    return float4(1, 0, 0, 1);
}

fragment float4 ImageLayer_DebayerLMMSE(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    VertexOutput interpolated [[stage_in]]
) {
    const uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
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
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 inputColor_cameraRaw = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
    float3 outputColor_XYZD50 = XYZD50_From_CameraRaw * inputColor_cameraRaw;
    return float4(outputColor_XYZD50, 1);
}

fragment float4 ImageLayer_XYYD50FromCameraRaw(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 inputColor_cameraRaw = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
    const float3 c = XYYFromXYZ(XYZD50_From_CameraRaw * inputColor_cameraRaw);
    return float4(c, 1);
}

fragment float4 ImageLayer_XYYD50FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    return float4(XYYFromXYZ(c), 1);
}

fragment float4 ImageLayer_XYZD50FromXYYD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    return float4(XYZFromXYY(c), 1);
}

constant uint UIntNormalizeVal = 65535;
fragment float4 ImageLayer_NormalizeXYYLuminance(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsXYY[[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float maxY = (float)maxValsXYY.z/UIntNormalizeVal;
    float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    c[2] /= maxY;
    return float4(c, 1);
}

fragment float4 ImageLayer_NormalizeRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsRGB[[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float denom = (float)max3(maxValsRGB.x, maxValsRGB.y, maxValsRGB.z)/UIntNormalizeVal;
    const float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb / denom;
    return float4(c, 1);
}

fragment float4 ImageLayer_ClipRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsRGB[[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
//    const float m = .7;
    const float m = (float)min3(maxValsRGB.x, maxValsRGB.y, maxValsRGB.z)/UIntNormalizeVal;
    const float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    return float4(min(m, c.r), min(m, c.g), min(m, c.b), 1);
}


fragment float4 ImageLayer_LSRGBD65FromXYYD50(
    constant RenderContext& ctx [[buffer(0)]],
    device float3* samples [[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 inputColor_XYYD50 = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    
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
    
    const float3 c_XYZD50 = XYZFromXYY(inputColor_XYYD50);
    const float3 c_LSRGBD65 = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * c_XYZD50;
    
    const uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
    if (pos.x >= ctx.sampleRect.left &&
        pos.x < ctx.sampleRect.right &&
        pos.y >= ctx.sampleRect.top &&
        pos.y < ctx.sampleRect.bottom) {
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = c_XYZD50;
    }
    
    return float4(c_LSRGBD65, 1);
}



fragment float4 ImageLayer_ColorAdjust(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 inputColor_cameraRaw = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
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
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 lsrgbfloat = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    uint3 lsrgb = uint3(lsrgbfloat * UIntNormalizeVal);
    
    setIfGreater((device atomic_uint&)highlights.x, lsrgb.r);
    setIfGreater((device atomic_uint&)highlights.y, lsrgb.g);
    setIfGreater((device atomic_uint&)highlights.z, lsrgb.b);
    
    return float4(lsrgbfloat, 1);
}



//fragment float4 ImageLayer_Debayer(
//    constant RenderContext& ctx [[buffer(0)]],
//    constant ImagePixel* pxs [[buffer(1)]],
//    VertexOutput interpolated [[stage_in]]
//) {
//    uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
//    //    if (pos.y == 5) return float4(1,0,0,1);
//    
//    // ## Bilinear debayering
////    return float4(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos), 1);
//    return float4(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos), 1);
////    return float4(1, 0, 0, 1);
//}

fragment float4 ImageLayer_FixHighlights(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    // LMMSE
    const uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
    const int redX = 1;
    const int redY = 0;
    const int green = 1 - ((redX + redY) & 1);
    float3 craw;
    craw.g =          sampleOutputGreen(pxs, ctx.imageWidth, ctx.imageHeight, false, green, pos.x, pos.y);
    craw.r = craw.g - sampleDiffGR_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
    craw.b = craw.g - sampleDiffGB_Final(pxs, ctx.imageWidth, ctx.imageHeight, false, green, redY, pos.x, pos.y);
    if (craw.r>=1 || craw.g>=1 || craw.b>=1) return float4(1, 1, 1, 1);
    float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    return float4(c, 1);
    
    
//    // Bilinear
//    const uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
//    const float3 craw = float3(r(ctx, pxs, pos), g(ctx, pxs, pos), b(ctx, pxs, pos));
//    float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
//    if (craw.r >= 1) c.r = 1;
//    if (craw.g >= 1) c.g = 1;
//    if (craw.b >= 1) c.b = 1;
//    return float4(c, 1);
}

fragment float4 ImageLayer_SRGBGamma(
    constant RenderContext& ctx [[buffer(0)]],
    device float3* samples [[buffer(1)]],
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 lsrgb = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    float3 c_SRGB = float3{
        SRGBFromLSRGB(lsrgb[0]),
        SRGBFromLSRGB(lsrgb[1]),
        SRGBFromLSRGB(lsrgb[2])
    };
    
    const uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
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
    texture2d<float> texture [[texture(0)]],
    VertexOutput interpolated [[stage_in]]
) {
    const float3 c = texture.sample(sampler(coord::pixel), interpolated.pos.xy).rgb;
    return float4(c, 1);
}


//fragment float4 ImageLayer_FragmentShader(
//    constant RenderContext& ctx [[buffer(0)]],
//    constant ImagePixel* pxs [[buffer(1)]],
//    device Histogram& inputHistogram [[buffer(2)]],
//    device Histogram& outputHistogram [[buffer(3)]],
//    VertexOutput interpolated [[stage_in]]
//) {
//    // Bayer pattern:
//    //  Row0    G R G R
//    //  Row1    B G B G
//    //  Row2    G R G R
//    //  Row3    B G B G
//    uint2 pos = {(uint)interpolated.pos.x, (uint)interpolated.pos.y};
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

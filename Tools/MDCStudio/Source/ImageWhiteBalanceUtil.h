#pragma once
#include <simd/simd.h>
#include "ImageWhiteBalance.h"

namespace MDCStudio {

struct _CCM {
    simd::float3 illum;
    simd::float3x3 matrix;
};

// Indoor, night
// Calculated from indoor_night2_200.cfa
const _CCM _CCM1 = {
    .illum = { 0.879884, 0.901580, 0.341031 },
    .matrix = {
        simd::float3{ 0.626076, -0.396581, -0.195309 },
        simd::float3{ 0.128755,  1.438671, -0.784350 },
        simd::float3{ 0.245169, -0.042090,  1.979659 },
    },
};

// Outdoor, 5pm
// Calculated from outdoor_5pm_78.cfa
const _CCM _CCM2 = {
    .illum = { 0.632708, 0.891153, 0.561737 },
    .matrix = {
        simd::float3{ 0.724397, -0.238233, -0.061917 },
        simd::float3{ 0.115398,  1.361934, -0.651388 },
        simd::float3{ 0.160204, -0.123701,  1.713306 },
    },
};

template <typename T, typename K>
T _Interp(const T& lo, const T& hi, K k) {
    return lo*(1-k) + hi*k;
}

// _CCMInterp(..., k): returns the linear interpolation between ccm1 and ccm2, controlled by `k`
static _CCM _CCMInterp(const _CCM& ccm1, const _CCM& ccm2, const float k) {
    return {
        .illum = _Interp(_CCM1.illum, _CCM2.illum, k),
        .matrix = _Interp(_CCM1.matrix, _CCM2.matrix, k),
    };
}

// _CCMInterp(..., illumRaw): projects illumRaw onto the line connecting ccm1.illum and ccm2.illum,
// which results in the closest point on that line to the given illumRaw. This point is then used
// to determine the amount of interpolation between ccm1 and ccm2, and passed to _CCMInterp(..., k).
static _CCM _CCMInterp(const _CCM& ccm1, const _CCM& ccm2, const simd::float3& illumRaw) {
    const simd::float3 a = ccm1.illum;
    const simd::float3 b = ccm2.illum;
    const simd::float3 c = illumRaw;
    
    const simd::float3 ab = (b-a);
    const simd::float3 ac = (c-a);
    const simd::float3 ad = simd::project(ac, ab);
    
    const float k = simd::length(ad) / simd::length(ab);
    return _CCMInterp(ccm1, ccm2, k);
}

inline void ImageWhiteBalanceSetAuto(ImageWhiteBalance& x, const simd::float3& illum) {
    x.automatic = true;
    
    static_assert(sizeof(x.illum) == sizeof(simd::float3));
    reinterpret_cast<simd::float3&>(x.illum) = illum;
    
    const _CCM ccm = _CCMInterp(_CCM1, _CCM2, illum);
    static_assert(sizeof(x.colorMatrix) == sizeof(simd::float3x3));
    reinterpret_cast<simd::float3x3&>(x.colorMatrix) = ccm.matrix;
}

inline void ImageWhiteBalanceSetManual(ImageWhiteBalance& x, float value) {
    x.automatic = false;
    x.value = value;
    
    const _CCM ccm = _CCMInterp(_CCM1, _CCM2, value);
    
    static_assert(sizeof(x.illum) == sizeof(simd::float3));
    reinterpret_cast<simd::float3&>(x.illum) = ccm.illum;
    
    static_assert(sizeof(x.colorMatrix) == sizeof(simd::float3x3));
    reinterpret_cast<simd::float3x3&>(x.colorMatrix) = ccm.matrix;
}

} // namespace MDCStudio

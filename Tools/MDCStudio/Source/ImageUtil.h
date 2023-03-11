#pragma once
#include <simd/simd.h>
#include <simd/packed.h>
#include "ImageOptions.h"
#include "Tools/Shared/Color.h"

namespace MDCStudio {

using ColorRaw = MDCTools::Color<MDCTools::ColorSpace::Raw>;
using ColorMatrix = Mat<double,3,3>;

struct CCM {
    ColorRaw illum;
    ColorMatrix matrix;
};

// Indoor, night
// Calculated from indoor_night2_200.cfa
const CCM _CCM1 = {
    .illum = { 0.879884, 0.901580, 0.341031 },
    .matrix = {
        +0.626076, +0.128755, +0.245169,
        -0.396581, +1.438671, -0.042090,
        -0.195309, -0.784350, +1.979659,
    },
};

// Outdoor, 5pm
// Calculated from outdoor_5pm_78.cfa
const CCM _CCM2 = {
    .illum = { 0.632708, 0.891153, 0.561737 },
    .matrix = {
        +0.724397, +0.115398, +0.160204,
        -0.238233, +1.361934, -0.123701,
        -0.061917, -0.651388, +1.713306,
    },
};

template <typename T, typename K>
T _Interp(const T& lo, const T& hi, K k) {
    return lo*(1-k) + hi*k;
}

// _CCMInterp(..., k): returns the linear interpolation between ccm1 and ccm2, controlled by `k`
static CCM _CCMInterp(const CCM& ccm1, const CCM& ccm2, const double k) {
    return {
        .illum = _Interp(_CCM1.illum.m, _CCM2.illum.m, k),
        .matrix = _Interp(_CCM1.matrix, _CCM2.matrix, k),
    };
}

// _CCMInterp(..., illum): projects illum onto the line connecting ccm1.illum and ccm2.illum,
// which results in the closest point on that line to the given illum. This point is then used
// to determine the amount of interpolation between ccm1 and ccm2, and passed to _CCMInterp(..., k).
static CCM _CCMInterp(const CCM& ccm1, const CCM& ccm2, const ColorRaw& illum) {
    const ColorRaw a = ccm1.illum;
    const ColorRaw b = ccm2.illum;
    const ColorRaw c = illum;
    
    const ColorRaw ab = b.m-a.m;
    const ColorRaw ac = c.m-a.m;
    const ColorRaw ad = ac.m.project(ab.m);
    
    const double k = ad.m.length() / ab.m.length();
    return _CCMInterp(ccm1, ccm2, k);
}

inline CCM ColorMatrixForIlluminant(const ColorRaw& illum) {
    return _CCMInterp(_CCM1, _CCM2, illum);
}

inline CCM ColorMatrixForInterpolation(double interpolation) {
    return _CCMInterp(_CCM1, _CCM2, interpolation);
}

//inline void ImageWhiteBalanceSetAuto(ImageWhiteBalance& x, const ColorRaw& illum) {
//    const _CCM ccm = _CCMInterp(_CCM1, _CCM2, illum);
//    
//    x.automatic = true;
//    
//    #warning TODO: add static_asserts to confirm that the source/dest have the same number of elements
//    std::copy(illum.m.begin(), illum.m.end(), std::begin(x.illum));
//    std::copy(ccm.matrix.begin(), ccm.matrix.end(), std::begin(x.colorMatrix));
//}
//
//inline void ImageWhiteBalanceSetManual(ImageWhiteBalance& x, double value) {
//    const _CCM ccm = _CCMInterp(_CCM1, _CCM2, value);
//    
//    x.automatic = false;
//    x.value = value;
//    
//    #warning TODO: add static_asserts to confirm that the source/dest have the same number of elements
//    std::copy(ccm.illum.m.begin(), ccm.illum.m.end(), std::begin(x.illum));
//    std::copy(ccm.matrix.begin(), ccm.matrix.end(), std::begin(x.colorMatrix));
//}

inline void ImageWhiteBalanceSet(ImageWhiteBalance& x, bool automatic, double value, const CCM& ccm) {
    x.automatic = automatic;
    x.value = value;
    
    #warning TODO: add static_asserts to confirm that the source/dest have the same number of elements
    std::copy(ccm.illum.m.begin(), ccm.illum.m.end(), std::begin(x.illum));
    std::copy(ccm.matrix.begin(), ccm.matrix.end(), std::begin(x.colorMatrix[0]));
}





} // namespace MDCStudio

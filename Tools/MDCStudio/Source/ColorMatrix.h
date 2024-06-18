#pragma once
#include "Tools/Shared/ImagePipeline/ImagePipeline.h"

namespace MDCStudio {

using ColorRaw = ImagePipeline::ColorRaw;
using ColorMatrix = ImagePipeline::ColorMatrix;

struct CCM {
    ColorRaw illum;
    ColorMatrix matrix;
};

// ### Color matrices
// ### Convert from raw camera colorspace -> XYZ.D50

// Indoor, night
// Calculated from indoor_night2_200.cfa
// We're assuming this is Standard A illuminant (incandescent / tungsten lighting)
// TODO: perform more rigorous collection; in the future, use real Standard A lighting to collect these values
const CCM _CCM1 = {
    .illum = { 0.880159, 0.902888, 0.340842 },
    .matrix = {
        +0.253550, +0.474052, +0.272397,
        -0.182395, +1.121929, +0.060466,
        -0.458151, -0.017908, +1.476060,
    },
};

// Outdoor, 5pm
// Calculated from outdoor_5pm_78.cfa
// We're assuming this is D50 illuminant ("horizon light")
// TODO: perform more rigorous collection; in the future, use D65 daylight (noon daylight) lighting to collect these values
const CCM _CCM2 = {
    .illum = { 0.638797, 0.900519, 0.567254 },
    .matrix = {
        +0.579444, +0.247106, +0.173450,
        +0.093154, +0.983335, -0.076489,
        -0.171737, -0.351732, +1.523468,
    },
};

template<typename T, typename K>
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

} // namespace MDCStudio

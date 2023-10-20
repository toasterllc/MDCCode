#pragma once
#import "ColorMatrix.h"

namespace MDCStudio {

inline void ImageWhiteBalanceSet(ImageWhiteBalance& x, bool automatic, double value, const CCM& ccm) {
    x.automatic = automatic;
    x.value = value;
    ccm.illum.m.get(x.illum);
    ccm.matrix.get(x.colorMatrix);
}

} // namespace MDCStudio

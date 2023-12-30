#pragma once
#import "ColorMatrix.h"

namespace MDCStudio {

inline void ImageWhiteBalanceSet(ImageWhiteBalance& x, bool automatic, const CCM& ccm) {
    x.automatic = automatic;
    ccm.illum.m.get(x.illum);
    ccm.matrix.get(x.colorMatrix);
}

} // namespace MDCStudio

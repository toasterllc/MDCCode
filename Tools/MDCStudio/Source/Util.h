#pragma once
#include "Tools/Shared/Color.h"

namespace MDCStudio {

inline struct {
    MDCTools::Color<MDCTools::ColorSpace::SRGB> srgb    = {.114, .125, .133};
    MDCTools::Color<MDCTools::ColorSpace::LSRGB> lsrgb  = srgb;
} WindowBackgroundColor;

} // namespace MDCStudio

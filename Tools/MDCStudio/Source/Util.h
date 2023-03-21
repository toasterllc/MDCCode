#pragma once
#include "Tools/Shared/Color.h"

namespace MDCStudio {

inline struct {
    MDCTools::Color<MDCTools::ColorSpace::SRGB> srgb    = {.118, .122, .129};
    MDCTools::Color<MDCTools::ColorSpace::LSRGB> lsrgb  = srgb;
} WindowBackgroundColor;

} // namespace MDCStudio

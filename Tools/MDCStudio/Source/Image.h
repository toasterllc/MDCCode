#pragma once
#include <memory>
#include "CFA.h"

namespace MDCStudio {

struct Image {
    size_t width = 0;
    size_t height = 0;
    CFADesc cfaDesc;
    std::unique_ptr<uint8_t[]> imageData;
};

using ImagePtr = std::shared_ptr<Image>;

} // namespace MDCStudio

#pragma once
#include <memory>
#import "Tools/Shared/CFA.h"

namespace MDCStudio {

struct Image {
    size_t width = 0;
    size_t height = 0;
    MDCTools::CFADesc cfaDesc;
    std::unique_ptr<uint8_t[]> data;
    size_t off = 0;
};

using ImagePtr = std::shared_ptr<Image>;

} // namespace MDCStudio

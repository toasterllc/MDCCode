#pragma once
#include "Toastbox/Math.h"
#include "Img.h"
#include "SD.h"

// ImgSD: constants that require information from both Img and SD
// We want to keep the Img and SD namespaces isolated (ie they shouldn't depend
// on each other), so constants that need information from both exist here.
namespace ImgSD {

namespace Full {
    // ImagePaddedLen: the length of the image padded to a multiple of 512 bytes
    constexpr uint32_t ImagePaddedLen = Toastbox::Ceil(SD::BlockLen, Img::Full::ImageLen);
    static_assert(ImagePaddedLen == 5972480); // Debug
    
    // ImageBlockCount: the length of an image in SD blocks
    constexpr uint32_t ImageBlockCount = ImagePaddedLen / SD::BlockLen;
    static_assert(ImageBlockCount == 11665); // Debug
}

namespace Thumb {
    constexpr uint32_t ImagePaddedLen = Toastbox::Ceil(SD::BlockLen, Img::Thumb::ImageLen);
    static_assert(ImagePaddedLen == 373760); // Debug
    
    constexpr uint32_t ImageBlockCount = ImagePaddedLen / SD::BlockLen;
    static_assert(ImageBlockCount == 730); // Debug
}

} // namespace ImgSD

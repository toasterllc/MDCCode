#pragma once
#include "Code/Shared/Img.h"
#include "Code/Shared/SD.h"

// ImgSD: constants that require information from both Img and SD
// We want to keep the Img and SD namespaces isolated (ie they shouldn't depend
// on each other), so constants that need information from both exist here.
namespace ImgSD {

    // ImgPaddedLen: the length of the image padded to a multiple of 512 bytes
    constexpr uint32_t ImgPaddedLen = Util::Ceil(Img::Len, SD::BlockLen);
    static_assert(ImgPaddedLen == 5972480); // Debug
    
    // ImgBlockCount: the length of an image in SD blocks
    constexpr uint32_t ImgBlockCount = ImgPaddedLen / SD::BlockLen;
    static_assert(ImgBlockCount == 11665); // Debug

} // namespace ImgSD

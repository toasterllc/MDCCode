#pragma once
#include "Img.h"
#include "SD.h"

// ImgSD: constants that require information from both Img and SD
// We want to keep the Img and SD namespaces isolated (ie they shouldn't depend
// on each other), so constants that need information from both exist here.
namespace ImgSD {

    namespace Full {
        // ImgPaddedLen: the length of the image padded to a multiple of 512 bytes
        constexpr uint32_t ImgPaddedLen = Util::Ceil(Img::Full::ImageLen, SD::BlockLen);
        static_assert(ImgPaddedLen == 5972480); // Debug
        
        // ImgBlockCount: the length of an image in SD blocks
        constexpr uint32_t ImgBlockCount = ImgPaddedLen / SD::BlockLen;
        static_assert(ImgBlockCount == 11665); // Debug
    }
    
    namespace Thumb {
        constexpr uint32_t ImgPaddedLen = Util::Ceil(Img::Thumb::ImageLen, SD::BlockLen);
        static_assert(ImgPaddedLen == 373760); // Debug
        
        constexpr uint32_t ImgBlockCount = ImgPaddedLen / SD::BlockLen;
        static_assert(ImgBlockCount == 730); // Debug
    }

} // namespace ImgSD

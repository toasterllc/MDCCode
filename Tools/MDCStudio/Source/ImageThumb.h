#pragma once
#import <Metal/Metal.h>

namespace MDCStudio {

struct [[gnu::packed]] ImageThumb {
//    static constexpr size_t ThumbWidth      = 288;
//    static constexpr size_t ThumbHeight     = 162;

//    static constexpr size_t ThumbWidth      = 400;
//    static constexpr size_t ThumbHeight     = 225;
    
//    static constexpr size_t ThumbWidth      = 432;
//    static constexpr size_t ThumbHeight     = 243;
    
//    static constexpr size_t ThumbWidth      = 480;
//    static constexpr size_t ThumbHeight     = 270;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    
#if defined(__aarch64__)
    static constexpr MTLPixelFormat PixelFormat = MTLPixelFormatASTC_4x4_LDR;
#elif defined(__x86_64__)
    static constexpr MTLPixelFormat PixelFormat = MTLPixelFormatBC7_RGBAUnorm;
#else
    #error Unknown platform
#endif
    
#pragma clang diagnostic pop
    
    static constexpr size_t ThumbWidth      = 512;
    static constexpr size_t ThumbHeight     = 288;
    
//    static constexpr size_t ThumbWidth      = 576;
//    static constexpr size_t ThumbHeight     = 324;
    
//    static constexpr size_t ThumbWidth      = 2304;
//    static constexpr size_t ThumbHeight     = 1296;
    
    alignas(16) // Must be aligned to the block size of the compressed thumb format (either ASTC or BC7)
    uint8_t data[ThumbHeight][ThumbWidth];
};

static_assert(!(sizeof(ImageThumb) % 8)); // Ensure that ImageThumb is a multiple of 8 bytes

} // namespace MDCStudio

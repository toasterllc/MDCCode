#pragma once

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
    
    static constexpr size_t ThumbWidth      = 512;
    static constexpr size_t ThumbHeight     = 288;
    
//    static constexpr size_t ThumbWidth      = 576;
//    static constexpr size_t ThumbHeight     = 324;
    
//    static constexpr size_t ThumbWidth      = 2304;
//    static constexpr size_t ThumbHeight     = 1296;
    
    bool render = false;
    uint8_t _pad[7];
    
    uint8_t data[ThumbHeight][ThumbWidth];
};

static_assert(!(sizeof(ImageThumb) % 8)); // Ensure that ImageThumb is a multiple of 8 bytes

} // namespace MDCStudio

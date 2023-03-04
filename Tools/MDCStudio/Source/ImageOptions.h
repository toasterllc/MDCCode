#pragma once
#include "ImageWhiteBalance.h"

namespace MDCStudio {

struct [[gnu::packed]] ImageOptions {
    enum class Rotation : uint8_t {
        Clockwise0,
        Clockwise90,
        Clockwise180,
        Clockwise270,
    };
    
    enum class Corner : uint8_t {
        BottomRight,
        BottomLeft,
        TopLeft,
        TopRight,
    };
    
    Rotation rotation = Rotation::Clockwise0;
    bool defringe = false;
    bool reconstructHighlights = false;
    struct [[gnu::packed]] {
        bool show = false;
        Corner corner = Corner::BottomRight;
    } timestamp;
    uint8_t _pad[3];
    
    ImageWhiteBalance whiteBalance;
    static_assert(!(sizeof(whiteBalance) % 8)); // Ensure that ImageOptions is a multiple of 8 bytes
    
    float exposure = 0;
    float saturation = 0;
    float brightness = 0;
    float contrast = 0;
    struct {
        float amount = 0;
        float radius = 0;
    } localContrast;
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[64];
};

static_assert(!(sizeof(ImageOptions) % 8)); // Ensure that ImageOptions is a multiple of 8 bytes

} // namespace MDCStudio

#pragma once
#include "Code/Lib/Toastbox/Util.h"

namespace MDCStudio {

struct [[gnu::packed]] ImageWhiteBalance {
    bool automatic = false;
    uint8_t _pad[7];
    double illum[3] = {};
    double colorMatrix[3][3] = {};
    
    uint8_t _reserved[128]; // For future use (we may want to specify which 2 illuminants we're interpolating between)
};

static_assert(!(sizeof(ImageWhiteBalance) % 8), "ImageWhiteBalance must be multiple of 16 bytes");

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
    bool reconstructHighlights = true;
    struct [[gnu::packed]] {
        bool show = false;
        Corner corner = Corner::BottomRight;
    } timestamp;
    uint8_t _pad[3];
    
    ImageWhiteBalance whiteBalance;
    
    double exposure = 0;
    double saturation = 0;
    double brightness = 0;
    double contrast = 0;
    struct {
        double amount = 0;
        double radius = 50;
    } localContrast;
    
    struct {
        bool render = false;
        uint8_t _pad[7];
    } thumb;
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[128];
};

static_assert(!(sizeof(ImageOptions) % 8), "ImageOptions must be multiple of 8 bytes");

} // namespace MDCStudio

#pragma once

namespace MDCStudio {

struct [[gnu::packed]] ImageWhiteBalance {
    bool automatic = false;
    uint8_t _pad[3];
    float value = 0;
    
    // illum: float3
    //   Memory layout matches simd::float3, which has a padding
    //   float, hence the `4`.
    float illum[4] = {};
    // colorMatrix: float3x3 (colorMatrix[x][y])
    //   Memory layout matches simd::float3x3 (column-major),
    //   which has a padding float for each column, hence the `4`.
    float colorMatrix[3][4] = {};
    
    uint8_t _reserved[128]; // For future use (we may want to specify which 2 illuminants we're interpolating between)
};

static_assert(!(sizeof(ImageWhiteBalance) % 8), "ImageWhiteBalance must be multiple of 8 bytes");

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
    
    float exposure = 0;
    float saturation = 0;
    float brightness = 0;
    float contrast = 0;
    struct {
        float amount = 0;
        float radius = 0;
    } localContrast;
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[128];
};

static_assert(!(sizeof(ImageOptions) % 8), "ImageOptions must be multiple of 8 bytes");

} // namespace MDCStudio

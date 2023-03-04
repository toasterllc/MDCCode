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
    uint8_t _reserved[16]; // For future use (we may want to specify which 2 illuminants we're interpolating between)
};

static_assert(!(sizeof(ImageWhiteBalance) % 8)); // Ensure that ImageWhiteBalance is a multiple of 8 bytes

} // namespace MDCStudio

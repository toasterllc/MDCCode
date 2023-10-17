#pragma once
#import <simd/simd.h>

namespace MDCStudio {
namespace FullSizeImageViewTypes {

struct RenderContext {
    simd::float4x4 transform = {};
    simd::float2 timestampOffset;
    simd::float2 timestampSize;
};

} // namespace FullSizeImageViewTypes
} // namespace MDCStudio

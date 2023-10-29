#pragma once
#import <simd/simd.h>

namespace MDCStudio {
namespace FullSizeImageViewTypes {

struct RenderContext {
    simd::float4x4 transform = {};
};

} // namespace FullSizeImageViewTypes
} // namespace MDCStudio

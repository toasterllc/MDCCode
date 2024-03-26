#pragma once
#import <simd/simd.h>
#import "Code/Lib/Toastbox/Mac/Grid.h"

namespace MDCStudio {
namespace ImageGridLayerTypes {

struct ImageRecordRef {
    // Chunk* chunk
    uint32_t _pad[2];
    
    // size_t idx:
    //   RecordStore::RecordRef::idx is size_t, and size_t is 64-bits,
    //   but Metal doesn't support 64-bit types. So for now just
    //   use the low 32-bits and assume that RecordRef will never
    //   hit >= 2^32 records
    uint32_t idx;
    uint32_t _pad2;
};

struct RenderContext {
    Toastbox::Grid grid;
    uint32_t idx = 0;
    bool sortNewestFirst = false;
    simd::float2 viewSize = {};
    simd::float4x4 transform = {};
    struct {
        uint32_t base = 0;
        uint32_t count = 0;
    } selection;
};

} // namespace ImageGridLayerTypes
} // namespace MDCStudio

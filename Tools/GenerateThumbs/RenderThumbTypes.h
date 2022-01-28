#pragma once
#include "MetalUtil.h"

//inline vector_uint2 VectorFromU64(uint64_t x) {
//    static_assert(sizeof(vector_uint2) == sizeof(uint64_t), "size mismatch");
//    return reinterpret_cast<MetalThread vector_uint2&>(x);
//}
//
//inline uint64_t U64FromVector(vector_uint2 x) {
//    static_assert(sizeof(vector_uint2) == sizeof(uint64_t), "size mismatch");
//    return reinterpret_cast<MetalThread uint64_t&>(x);
//}

struct RenderContext {
    static constexpr MetalConst uint32_t BytesPerPixel = 3;
    
    uint32_t thumbOff;
    
//    vector_uint2 thumbOff;
//    struct {
//        uint32_t hi;
//        uint32_t lo;
//    } thumbOff;
    
    uint32_t width = 0;
    uint32_t height = 0;
};

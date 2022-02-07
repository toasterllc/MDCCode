#pragma once
#import <simd/simd.h>
#import "Grid.h"
//#import "MetalUtil.h"

//#ifdef __METAL_VERSION__ // Only allow the code below in non-shader contexts
//#define METAL_CONSTANT constant
//#else
//#define METAL_CONSTANT
//#endif

//#ifdef __METAL_VERSION__
//    // Vertices that define a square
//    static constexpr constant vector_float4 square[6] = {
//        // Top-left triangle
//        { .5,  .5, 0, 1},
//        {-.5,  .5, 0, 1},
//        {-.5, -.5, 0, 1},
//        // Bottom-right triangle
//        {-.5, -.5, 0, 1},
//        { .5, -.5, 0, 1},
//        { .5,  .5, 0, 1},
//    };
//#endif

namespace MDCStudio {
namespace ImageGridLayerTypes {

//using ChunkRef = vector_uint2;
//
//template <typename T>
//vector_uint2 UInt2FromType(const MetalThread T& x) {
//    static_assert(sizeof(vector_uint2) == sizeof(T), "size mismatch");
//    return reinterpret_cast<const MetalThread vector_uint2&>(x);
//}
//
//template <typename T>
//T TypeFromUInt2(vector_uint2 x) {
//    static_assert(sizeof(vector_uint2) == sizeof(T), "size mismatch");
//    return reinterpret_cast<MetalThread T&>(x);
//}

struct ImageRef {
    uint32_t _pad[2];
    uint32_t idx;
};

struct RenderContext {
    Grid grid;
    uint32_t idxOff = 0;
    uint32_t imagesOff = 0;
//    uint32_t imageRefOff = 0;
    uint32_t imageSize = 0;
    vector_int2 viewOffset = {0,0};
    matrix_float4x4 viewMatrix = {};
    
    struct {
        uint32_t width  = 0;
        uint32_t height = 0;
        uint32_t pxSize = 0; // Bytes per pixel
        uint32_t off    = 0; // Offset of thumbnail from image base
    } thumb;
    
    uint32_t cellSize = 0;
//    uint32_t thumbInset = 0;
};

} // namespace ImageGridLayerTypes
} // namespace MDCStudio

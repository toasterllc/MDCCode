#pragma once
#import <simd/simd.h>
#import "Grid.h"

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
    uint32_t imageRecordSize = 0;
    
    uint32_t thumbCountX = 0;
    uint32_t thumbCountY = 0;
    
    uint32_t thumbWidth = 0;
    uint32_t thumbHeight = 0;
    
    Grid grid;
    uint32_t idx = 0;
    uint32_t imagesOff = 0;
    uint32_t imageSize = 0;
    vector_float2 viewSize = {};
    matrix_float4x4 transform = {};
    
    struct {
        uint32_t id = 0;        // Offset of image id from image base
        uint32_t options = 0;   // Offset of image options from image base
        uint32_t thumbData = 0; // Offset of thumbnail from image base
    } off;
    
    struct {
        uint32_t width  = 0;
        uint32_t height = 0;
        uint32_t pxSize = 0; // Bytes per pixel
    } thumb;
    
    struct {
        uint32_t first = 0;
        uint32_t count = 0;
    } selection;
    
    uint32_t cellWidth = 0;
    uint32_t cellHeight = 0;
//    uint32_t thumbInset = 0;
};

} // namespace ImageGridLayerTypes
} // namespace MDCStudio

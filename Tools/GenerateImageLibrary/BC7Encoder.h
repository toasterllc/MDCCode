#pragma once
#include "Code/Lib/bc7enc_rdo/bc7e_ispc.h"
#include "Code/Lib/bc7enc_rdo/rdo_bc_encoder.h"




//for (int32_t by = 0; by < static_cast<int32_t>(blocks_y); by++)
//{
//    // Process 64 blocks at a time, for efficient SIMD processing.
//    // Ideally, N >= 8 (or more) and (N % 8) == 0.
//    const int N = 64;
//    
//    for (uint32_t bx = 0; bx < blocks_x; bx += N)
//    {
//        const uint32_t num_blocks_to_process = std::min<uint32_t>(blocks_x - bx, N);
//
//        utils::color_quad_u8 pixels[16 * N];
//
//        // Extract num_blocks_to_process 4x4 pixel blocks from the source image and put them into the pixels[] array.
//        for (uint32_t b = 0; b < num_blocks_to_process; b++)
//            srcImg.get_block(bx + b, by, 4, 4, pixels + b * 16);
//        
//        // Compress the blocks to BC7.
//        // Note: If you've used Intel's ispc_texcomp, the input pixels are different. BC7E requires a pointer to an array of 16 pixels for each block.
//        bc7_block *pBlock = &blocks[bx + by * blocks_x];
//        ispc::bc7e_compress_blocks(num_blocks_to_process, reinterpret_cast<uint64_t *>(pBlock), reinterpret_cast<const uint32_t *>(pixels), &pack_params);
//    }
//}
//
//ImageRecord& rec = **imgRecIt;
//rec.info.id = imageId;
//
//const size_t blocksSize = blocks.size() * sizeof(*blocks.data());
//memcpy(rec.thumb.data, blocks.data(), blocksSize);
//assert(blocksSize == sizeof(rec.thumb.data));







template <size_t T_Width, size_t T_Height>
class BC7Encoder {
public:
    static constexpr size_t OutputLen() {
        return sizeof(_blocks);
    }
    
    BC7Encoder() {
        ispc::bc7e_compress_block_init();
        ispc::bc7e_compress_block_params_init_ultrafast(&_params, _Perceptual);
    }
    
    // `src` must be in the RGBA format
    // `dst` is in compressed BC7 format, with length `OutputLen()`
    void encode(const void* src, void* dst) {
        for (size_t by=0; by<_BlockCountY; by++) {
            for (size_t bx=0; bx<_BlockCountX; bx+=_ChunkSize) {
                const size_t blockCount = std::min<size_t>(_ChunkSize, _BlockCountX-bx);
                
                utils::color_quad_u8 tmp[16*_ChunkSize];
                
                // Extract blockCount 4x4 pixel blocks from the source image and put them in tmp
                for (size_t b=0; b<blockCount; b++) {
                    _BlockGet(bx+b, by, (utils::color_quad_u8*)src, tmp+b*16);
                }
                
                // Compress the blocks to BC7
                ispc::bc7e_compress_blocks((uint32_t)blockCount, (uint64_t*)&_blocks[by][bx], (uint32_t*)tmp, &_params);
            }
        }
        
        memcpy(dst, _blocks, sizeof(_blocks));
    }
    
private:
    static_assert(!(T_Width % 4));
    static_assert(!(T_Height % 4));
    struct [[gnu::packed]] _Block { uint64_t vals[2]; };
    
    // _ChunkSize: process 64 blocks at a time, for efficient SIMD processing.
    // Ideally, _ChunkSize >= 8 (or more) and (N % 8) == 0.
    static constexpr size_t _ChunkSize = 64;
    static constexpr bool _Perceptual = true;
    static constexpr size_t _BlockCountX = T_Width/4;
    static constexpr size_t _BlockCountY = T_Height/4;
    
    template <size_t T_Size=4>
	static void _BlockGet(size_t bx, size_t by, const utils::color_quad_u8* src, utils::color_quad_u8* dst) {
//		assert((bx * width + width) <= m_width);
//		assert((by * height + height) <= m_height);
        const size_t srcX = bx*T_Size;
		for (size_t y=0; y<T_Size; y++) {
//            size_t srcX = bx*T_Size;
//            size_t srcY = y + by*T_Size;
//            src[]
//            
//            m_pixels[x + m_width * y]
//            
//            src[(x) + T_Width * (y)]
//            
//            src[(bx*T_Size) + T_Width * (y + by*T_Size)]
//            
//            
//            src[(srcX) + T_Width * (srcY)]
//            
//            
//            
//            
            size_t srcY = y + by*T_Size;
			memcpy(dst+y*T_Size, &src[srcX+T_Width*srcY], T_Size*sizeof(*dst));
        }
	}
    
    ispc::bc7e_compress_block_params _params = {};
    _Block _blocks[_BlockCountY][_BlockCountX];
};

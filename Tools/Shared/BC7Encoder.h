#pragma once
#include "Code/Lib/bc7enc_rdo/bc7e_ispc.h"
#include "Code/Lib/bc7enc_rdo/rdo_bc_encoder.h"

template <size_t T_Width, size_t T_Height>
class BC7Encoder {
public:
    static constexpr size_t OutputLen() {
        return sizeof(_Blocks);
    }
    
    BC7Encoder() {
        ispc::bc7e_compress_block_init();
        ispc::bc7e_compress_block_params_init_ultrafast(&_params, _Perceptual);
    }
    
    // `src` must be in the RGBA format
    // `dst` is in compressed BC7 format, with length `OutputLen()`
    void encode(const void* src, void* dst) {
        // Verify that `dst` is as aligned as _Blocks requires
        assert(!((uintptr_t)dst & (alignof(_Blocks)-1)));
        _Blocks& blocks = *reinterpret_cast<_Blocks*>(dst);
        for (size_t by=0; by<_BlockCountY; by++) {
            for (size_t bx=0; bx<_BlockCountX; bx+=_ChunkSize) {
                const size_t blockCount = std::min<size_t>(_ChunkSize, _BlockCountX-bx);
                
                // Extract blockCount 4x4 pixel blocks from the source image and put them in _tmp
                for (size_t b=0; b<blockCount; b++) {
                    _BlockGet(bx+b, by, (utils::color_quad_u8*)src, _tmp+b*16);
                }
                
                // Compress the blocks to BC7
                ispc::bc7e_compress_blocks((uint32_t)blockCount, (uint64_t*)&blocks[by][bx], (uint32_t*)_tmp, &_params);
            }
        }
    }
    
private:
    static_assert(!(T_Width % 4));
    static_assert(!(T_Height % 4));
    
    // _ChunkSize: process 64 blocks at a time, for efficient SIMD processing.
    // Ideally, _ChunkSize >= 8 (or more) and (N % 8) == 0.
    static constexpr size_t _ChunkSize = 64;
    static constexpr bool _Perceptual = true;
    static constexpr size_t _BlockCountX = T_Width/4;
    static constexpr size_t _BlockCountY = T_Height/4;
    
    using _Blocks = uint64_t[_BlockCountY][_BlockCountX][2];
    
    template <size_t T_Size=4>
	static void _BlockGet(size_t bx, size_t by, const utils::color_quad_u8* src, utils::color_quad_u8* dst) {
        const size_t srcX = bx*T_Size;
		for (size_t y=0; y<T_Size; y++) {
            size_t srcY = y + by*T_Size;
			memcpy(dst+y*T_Size, &src[srcX+T_Width*srcY], T_Size*sizeof(*dst));
        }
	}
    
    ispc::bc7e_compress_block_params _params = {};
    utils::color_quad_u8 _tmp[16*_ChunkSize];
};
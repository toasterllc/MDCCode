//
// /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e_ispc_avx.h
// (Header automatically generated by the ispc compiler.)
// DO NOT EDIT THIS FILE.
//

#pragma once
#include <stdint.h>



#ifdef __cplusplus
namespace ispc { /* namespace */
#endif // __cplusplus

#ifndef __ISPC_ALIGN__
#if defined(__clang__) || !defined(_MSC_VER)
// Clang, GCC, ICC
#define __ISPC_ALIGN__(s) __attribute__((aligned(s)))
#define __ISPC_ALIGNED_STRUCT__(s) struct __ISPC_ALIGN__(s)
#else
// Visual Studio
#define __ISPC_ALIGN__(s) __declspec(align(s))
#define __ISPC_ALIGNED_STRUCT__(s) __ISPC_ALIGN__(s) struct
#endif
#endif

#ifndef __ISPC_STRUCT_$anon4__
#define __ISPC_STRUCT_$anon4__
struct $anon4 {
    uint32_t m_max_mode13_partitions_to_try;
    uint32_t m_max_mode0_partitions_to_try;
    uint32_t m_max_mode2_partitions_to_try;
    bool m_use_mode[7];
    bool m_unused1;
};
#endif

#ifndef __ISPC_STRUCT_$anon5__
#define __ISPC_STRUCT_$anon5__
struct $anon5 {
    uint32_t m_max_mode7_partitions_to_try;
    uint32_t m_mode67_error_weight_mul[4];
    bool m_use_mode4;
    bool m_use_mode5;
    bool m_use_mode6;
    bool m_use_mode7;
    bool m_use_mode4_rotation;
    bool m_use_mode5_rotation;
    bool m_unused2;
    bool m_unused3;
};
#endif

#ifndef __ISPC_STRUCT_bc7e_compress_block_params__
#define __ISPC_STRUCT_bc7e_compress_block_params__
struct bc7e_compress_block_params {
    uint32_t m_max_partitions_mode[8];
    uint32_t m_weights[4];
    uint32_t m_uber_level;
    uint32_t m_refinement_passes;
    uint32_t m_mode4_rotation_mask;
    uint32_t m_mode4_index_mask;
    uint32_t m_mode5_rotation_mask;
    uint32_t m_uber1_mask;
    bool m_perceptual;
    bool m_pbit_search;
    bool m_mode6_only;
    bool m_unused0;
    struct $anon4 m_opaque_settings;
    struct $anon5 m_alpha_settings;
};
#endif


///////////////////////////////////////////////////////////////////////////
// Functions exported from ispc code
///////////////////////////////////////////////////////////////////////////
#if defined(__cplusplus) && (! defined(__ISPC_NO_EXTERN_C) || !__ISPC_NO_EXTERN_C )
extern "C" {
#endif // __cplusplus
    extern void bc7e_compress_block_init();
    extern void bc7e_compress_block_params_init(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_basic(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_fast(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_slow(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_slowest(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_ultrafast(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_veryfast(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_block_params_init_veryslow(struct bc7e_compress_block_params * p, bool perceptual);
    extern void bc7e_compress_blocks(uint32_t num_blocks, uint64_t * pBlocks, const uint32_t * pPixelsRGBA, const struct bc7e_compress_block_params * pComp_params);
#if defined(__cplusplus) && (! defined(__ISPC_NO_EXTERN_C) || !__ISPC_NO_EXTERN_C )
} /* end extern C */
#endif // __cplusplus


#ifdef __cplusplus
} /* namespace */
#endif // __cplusplus

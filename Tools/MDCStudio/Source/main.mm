#import <Cocoa/Cocoa.h>
#import <filesystem>
#import <AppleTextureEncoder.h>
#import "Tools/Shared/BC7Encoder.h"

constexpr size_t ThumbWidth = 512;
constexpr size_t ThumbHeight = 288;

static void ate(void* inData) {
//    constexpr float ErrorThreshold = 0.0009765625;        // Fast
    constexpr float ErrorThreshold = 0.00003051757812;    // High quality
    
//    at_block_format_t outFormat = at_block_format_astc_4x4_ldr;
    at_block_format_t outFormat = at_block_format_bc7;
    
    at_encoder_t enc = at_encoder_create(
        at_texel_format_rgba8_unorm,
//        at_texel_format_bgra8_unorm,
        at_alpha_opaque,
        outFormat,
        at_alpha_opaque,
        nullptr
    );
    assert(enc);
    
    const at_texel_region_t src = {
        .texels = (void*)inData,
        .validSize = {
            .x = ThumbWidth,
            .y = ThumbHeight,
            .z = 1,
        },
        .rowBytes = ThumbWidth*4,
        .sliceBytes = 0,
    };
    
    alignas(16)
    uint8_t outData[ThumbWidth*ThumbHeight] = {};
    
    const at_block_buffer_t dst = {
        .blocks = outData,
        .rowBytes = ThumbWidth*4,
        .sliceBytes = 0,
    };
    
//    2048 bytes
//    4x4 region -> 16 bytes
//    4*4*4 = 64 bytes -> 16 bytes
    
    // 147456 pixels
    // 589824 bytes src
    // 147456 bytes dst
    
    float r = at_encoder_compress_texels(
        enc,
        &src,
        &dst,
        ErrorThreshold,
//        at_flags_default
        at_flags_print_debug_info
    );
    
    assert(r >= 0);
}

int main(int argc, const char* argv[]) {
    using namespace std::chrono;
    
    NSString* inPath = [[NSBundle mainBundle] pathForResource:@"thumb-raw" ofType:@"bin"];
    NSData* inData = [NSData dataWithContentsOfFile:inPath];
    assert(inData);
    
    void* inDataBytes = (void*)[inData bytes];
    
    constexpr int Iterations = 1000;
    
    // AppleTextureEncoder
    {
        auto timeStart = steady_clock::now();
        
        for (int i=0; i<Iterations; i++) @autoreleasepool {
            ate(inDataBytes);
        }
        
        const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
        const double msPerIter = ((double)duration.count()/Iterations);
        printf("AppleTextureEncoder: %.1f ms / iter\n", msPerIter);
    }
    
    // BC7Encoder
    {
        BC7Encoder<ThumbWidth, ThumbHeight> compressor;
        uint8_t data[ThumbHeight][ThumbWidth];
        
        auto timeStart = steady_clock::now();
        
        for (int i=0; i<Iterations; i++) @autoreleasepool {
            compressor.encode(inDataBytes, data);
        }
        
        const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
        const double msPerIter = ((double)duration.count()/Iterations);
        printf("BC7Encoder: %.1f ms / iter\n", msPerIter);
    }
}

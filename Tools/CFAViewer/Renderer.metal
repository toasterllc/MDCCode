#import <metal_stdlib>
#import "MetalUtil.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;

namespace CFAViewer {
namespace Shader {
namespace Renderer {

vertex VertexOutput VertexShader(uint vidx [[vertex_id]]) {
    return Standard::VertexShader(vidx);
}

template <typename T>
float LoadFloat(uint32_t w, uint32_t h, uint32_t samplesPerPixel, uint32_t maxValue, constant T* data, int2 pos) {
    return (float)data[samplesPerPixel*(w*pos.y + pos.x)] / maxValue;
}

template <typename T>
float4 LoadFloat4(uint32_t w, uint32_t h, uint32_t samplesPerPixel, uint32_t maxValue, constant T* data, int2 pos) {
    return float4(
        (float)data[samplesPerPixel*(w*pos.y + pos.x) + 0] / maxValue,
        (float)data[samplesPerPixel*(w*pos.y + pos.x) + 1] / maxValue,
        (float)data[samplesPerPixel*(w*pos.y + pos.x) + 2] / maxValue,
        1
    );
}

fragment float LoadFloatFromU8(
    constant uint32_t& w [[buffer(0)]],
    constant uint32_t& h [[buffer(1)]],
    constant uint32_t& samplesPerPixel [[buffer(2)]],
    constant uint32_t& maxValue [[buffer(3)]],
    constant uint8_t* data [[buffer(4)]],
    VertexOutput in [[stage_in]]
) {
    return LoadFloat(w, h, samplesPerPixel, maxValue, data, int2(in.pos.xy));
}

fragment float LoadFloatFromU16(
    constant uint32_t& w [[buffer(0)]],
    constant uint32_t& h [[buffer(1)]],
    constant uint32_t& samplesPerPixel [[buffer(2)]],
    constant uint32_t& maxValue [[buffer(3)]],
    constant uint16_t* data [[buffer(4)]],
    VertexOutput in [[stage_in]]
) {
    return LoadFloat(w, h, samplesPerPixel, maxValue, data, int2(in.pos.xy));
}

fragment float4 LoadFloat4FromU8(
    constant uint32_t& w [[buffer(0)]],
    constant uint32_t& h [[buffer(1)]],
    constant uint32_t& samplesPerPixel [[buffer(2)]],
    constant uint32_t& maxValue [[buffer(3)]],
    constant uint8_t* data [[buffer(4)]],
    VertexOutput in [[stage_in]]
) {
    return LoadFloat4(w, h, samplesPerPixel, maxValue, data, int2(in.pos.xy));
}

fragment float4 LoadFloat4FromU16(
    constant uint32_t& w [[buffer(0)]],
    constant uint32_t& h [[buffer(1)]],
    constant uint32_t& samplesPerPixel [[buffer(2)]],
    constant uint32_t& maxValue [[buffer(3)]],
    constant uint16_t* data [[buffer(4)]],
    VertexOutput in [[stage_in]]
) {
    return LoadFloat4(w, h, samplesPerPixel, maxValue, data, int2(in.pos.xy));
}

} // namespace Renderer
} // namespace Shader
} // namespace ImageLayer

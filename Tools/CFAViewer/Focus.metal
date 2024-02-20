#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImagePipeline/ImagePipelineTypes.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCTools::ImagePipeline;

static float _GrayscaleForRaw(
    texture2d<float> raw,
    VertexOutput in
) {
    const int2 posRaw = int2(in.pos.xy) * 2;
    const int2 posRawG0 = posRaw + int2{0,0};
    const int2 posRawG1 = posRaw + int2{1,1};
    const int2 posRawR = posRaw + int2{1,0};
    const int2 posRawB = posRaw + int2{0,1};
    
    const float r = Sample::R(raw, posRawR);
    const float g = (Sample::R(raw, posRawG0) + Sample::R(raw, posRawG1)) / 2;
    const float b = Sample::R(raw, posRawB);
    const float x = (r+g+b) / 3;
    return x;
}

fragment float GrayscaleForRaw(
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return _GrayscaleForRaw(raw, in);
}

fragment float4 GrayscaleRGBForRaw(
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float x = _GrayscaleForRaw(raw, in);
    return float4(x,x,x,1);
}

fragment float4 SearchRegionDarken(
    constant SampleRect& searchRegion [[buffer(0)]],
    texture2d<float> gray [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float4 s = Sample::RGBA(gray, pos);
    
    if (
           pos.x < searchRegion.left
        || pos.x >= searchRegion.right
        || pos.y < searchRegion.top
        || pos.y >= searchRegion.bottom
    ) {
        return float4(s.r/2, s.g/2, s.b/2, 1);
    }
    
    return s;
}

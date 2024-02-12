#import <metal_stdlib>
#import "MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;

fragment float GrayscaleForRaw(
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 posRaw = int2(in.pos.xy) * 2;
    const int2 posRawG0 = posRaw + int2{0,0};
    const int2 posRawG1 = posRaw + int2{1,1};
    const int2 posRawR = posRaw + int2{1,0};
    const int2 posRawB = posRaw + int2{0,1};
    
    const float r = Sample::R(raw, posRawR);
    const float g = (Sample::R(raw, posRawG0) + Sample::R(raw, posRawG1)) / 2;
    const float b = Sample::R(raw, posRawB);
    
    return (r+g+b) / 3;
}

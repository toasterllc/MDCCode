#import <metal_stdlib>
#import "ImagePipelineTypes.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
using namespace metal;
using namespace Toastbox::MetalUtil;
using namespace MDCTools::ImagePipeline;

namespace MDCTools {
namespace ImagePipeline {
namespace Shader {
namespace Saturation {

float Luv_u(float3 c_XYZ) {
    return 4*c_XYZ.x/(c_XYZ.x+15*c_XYZ.y+3*c_XYZ.z);
}

float Luv_v(float3 c_XYZ) {
    return 9*c_XYZ.y/(c_XYZ.x+15*c_XYZ.y+3*c_XYZ.z);
}

float3 LuvFromXYZ(float3 white_XYZ, float3 c_XYZ) {
    const float k1 = 24389./27;
    const float k2 = 216./24389;
    const float y = c_XYZ.y/white_XYZ.y;
    const float L = (y<=k2 ? k1*y : 116*pow(y, 1./3)-16);
    const float u_ = Luv_u(c_XYZ);
    const float v_ = Luv_v(c_XYZ);
    const float uw_ = Luv_u(white_XYZ);
    const float vw_ = Luv_v(white_XYZ);
    const float u = 13*L*(u_-uw_);
    const float v = 13*L*(v_-vw_);
    return {L,u,v};
}

float3 XYZFromLuv(float3 white_XYZ, float3 c_Luv) {
    const float uw_ = Luv_u(white_XYZ);
    const float vw_ = Luv_v(white_XYZ);
    const float u_ = c_Luv[1]/(13*c_Luv[0]) + uw_;
    const float v_ = c_Luv[2]/(13*c_Luv[0]) + vw_;
    const float Y = white_XYZ.y*(c_Luv[0]<=8 ? c_Luv[0]*(27./24389) : pow((c_Luv[0]+16)/116, 3));
    const float X = Y*(9*u_)/(4*v_);
    const float Z = Y*(12-3*u_-20*v_)/(4*v_);
    return {X,Y,Z};
}

fragment float4 LuvD50FromXYZD50(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    const float3 D50_XYZ(0.96422, 1.00000, 0.82521);
    return float4(LuvFromXYZ(D50_XYZ, c), 1);
}

fragment float4 XYZD50FromLuvD50(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    const float3 D50_XYZ(0.96422, 1.00000, 0.82521);
    return float4(XYZFromLuv(D50_XYZ, c), 1);
}

float3 LCHuvFromLuv(float3 c_Luv) {
    const float L = c_Luv[0];
    const float C = sqrt(c_Luv[1]*c_Luv[1] + c_Luv[2]*c_Luv[2]);
    const float H = atan2(c_Luv[2], c_Luv[1]);
    return {L,C,H};
}

float3 LuvFromLCHuv(float3 c_LCHuv) {
    const float L = c_LCHuv[0];
    const float u = c_LCHuv[1]*cos(c_LCHuv[2]);
    const float v = c_LCHuv[1]*sin(c_LCHuv[2]);
    return {L,u,v};
}

fragment float4 LCHuvFromLuv(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(LCHuvFromLuv(c), 1);
}

fragment float4 LuvFromLCHuv(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(LuvFromLCHuv(c), 1);
}

fragment float4 Saturation(
    constant float& sat [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    c[1] *= sat;
    return float4(c, 1);
}

} // namespace Saturation
} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCTools

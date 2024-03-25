#import <metal_stdlib>
#import "ImagePipelineTypes.h"
#import "../CFA.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
using namespace metal;
using namespace MDCTools;
using namespace MDCTools::ImagePipeline;
using namespace Toastbox::MetalUtil;

namespace MDCTools {
namespace ImagePipeline {
namespace Shader {
namespace DebayerBilinear {

#define PX(x,y) Sample::R(Sample::MirrorClamp, raw, pos+int2{x,y})
float r(constant MDCTools::CFADesc& cfaDesc, texture2d<float> raw, int2 pos) {
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    if (c==CFAColor::Blue || cn==CFAColor::Blue) {
        // ROW = B G B G ...
        
        // Have G
        // Want R
        // Sample @ y-1, y+1
        if (c == CFAColor::Green) return .5*PX(+0,-1) + .5*PX(+0,+1);
        
        // Have B
        // Want R
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*PX(-1,-1) + .25*PX(-1,+1) + .25*PX(+1,-1) + .25*PX(+1,+1);
    
    } else {
        // ROW = G R G R ...
        
        // Have G
        // Want R
        // Sample @ x-1 and x+1
        if (c == CFAColor::Green) return .5*PX(-1,+0) + .5*PX(+1,+0);
        
        // Have R
        // Want R
        // Sample @ this pixel
        else return PX(+0,+0);
    }
}

float g(constant CFADesc& cfaDesc, texture2d<float> raw, int2 pos) {
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    if (c==CFAColor::Blue || cn==CFAColor::Blue) {
        // ROW = B G B G ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (c == CFAColor::Green) return PX(+0,+0);
        
        // Have B
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*PX(-1,+0) + .25*PX(+1,+0) + .25*PX(+0,-1) + .25*PX(+0,+1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (c == CFAColor::Green) return PX(+0,+0);
        
        // Have R
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*PX(-1,+0) + .25*PX(+1,+0) + .25*PX(+0,-1) + .25*PX(+0,+1) ;
    }
}

float b(constant CFADesc& cfaDesc, texture2d<float> raw, int2 pos) {
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    if (c==CFAColor::Blue || cn==CFAColor::Blue) {
        // ROW = B G B G ...
        
        // Have G
        // Want B
        // Sample @ x-1, x+1
        if (c == CFAColor::Green) return .5*PX(-1,+0) + .5*PX(+1,+0);
        
        // Have B
        // Want B
        // Sample @ this pixel
        else return PX(+0,+0);
    
    } else {
        // ROW = G R G R ...
        
        // Have G
        // Want B
        // Sample @ y-1, y+1
        if (c == CFAColor::Green) return .5*PX(+0,-1) + .5*PX(+0,+1);
        
        // Have R
        // Want B
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*PX(-1,-1) + .25*PX(-1,+1) + .25*PX(+1,-1) + .25*PX(+1,+1) ;
    }
}
#undef PX

fragment float4 Debayer(
    constant CFADesc& cfaDesc [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    return float4(r(cfaDesc, raw, pos), g(cfaDesc, raw, pos), b(cfaDesc, raw, pos), 1);
}

} // namespace DebayerBilinear
} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCTools

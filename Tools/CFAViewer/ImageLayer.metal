#import <metal_stdlib>
#import "MetalUtil.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;

namespace CFAViewer {
namespace Shader {
namespace ImageLayer {

vertex Standard::VertexOutput VertexShader(uint vidx [[vertex_id]]) {
    return Standard::VertexShader(vidx);
}

} // namespace ImageLayer
} // namespace Shader
} // namespace ImageLayer

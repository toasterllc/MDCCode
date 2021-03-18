#import <metal_stdlib>
#import "MetalUtil.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;

namespace CFAViewer {
namespace Shader {
namespace Renderer {

vertex Standard::VertexOutput VertexShader(uint vidx [[vertex_id]]) {
    return Standard::VertexShader(vidx);
}

} // namespace Renderer
} // namespace Shader
} // namespace ImageLayer

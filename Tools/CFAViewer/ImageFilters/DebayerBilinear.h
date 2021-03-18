#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalUtil.h"
#import "ImageFilter.h"
#import "Renderer.h"

namespace CFAViewer {
    class DebayerBilinear : public ImageFilter {
    public:
        using ImageFilter::ImageFilter;
        void run(const CFADesc& cfaDesc, id<MTLTexture> raw, id<MTLTexture> rgb) {
            renderer().render("CFAViewer::Shader::DebayerBilinear::Debayer", rgb,
                // Buffer args
                cfaDesc,
                // Texture args
                raw
            );
        }
    };
};

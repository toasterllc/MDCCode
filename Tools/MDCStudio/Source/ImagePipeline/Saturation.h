#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipelineTypes.h"
#import "Tools/Shared/MetalUtil.h"

namespace MDCStudio::ImagePipeline {

class Saturation {
public:
    static void Run(MDCTools::Renderer& renderer, float sat, id<MTLTexture> xyz_d50) {
        id<MTLTexture> txt = xyz_d50;
        
        // XYZ.D50 -> Luv.D50
        renderer.render(txt,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Saturation::LuvD50FromXYZD50",
                txt
            )
        );
        
        // Luv.D50 -> LCHuv.D50
        renderer.render(txt,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Saturation::LCHuvFromLuv",
                txt
            )
        );
        
        // Saturation
        const float satpow = pow(2, 2*sat);
        renderer.render(txt,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Saturation::Saturation",
                satpow,
                txt
            )
        );
        
        // LCHuv.D50 -> Luv.D50
        renderer.render(txt,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Saturation::LuvFromLCHuv",
                txt
            )
        );
        
        // Luv.D50 -> XYZ.D50
        renderer.render(txt,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Saturation::XYZD50FromLuvD50",
                txt
            )
        );
    }
};

}; // MDCStudio::ImagePipeline

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipelineTypes.h"
#import "MetalUtil.h"

namespace MDCStudio::ImagePipeline {

class Saturation {
public:
    static void Run(MDCTools::Renderer& renderer, float sat, id<MTLTexture> xyz_d50) {
        id<MTLTexture> txt = xyz_d50;
        
        // XYZ.D50 -> Luv.D50
        renderer.render("MDCStudio::Shader::Saturation::LuvD50FromXYZD50", txt,
            txt
        );
        
        // Luv.D50 -> LCHuv.D50
        renderer.render("MDCStudio::Shader::Saturation::LCHuvFromLuv", txt,
            txt
        );
        
        // Saturation
        const float satpow = pow(2, 2*sat);
        renderer.render("MDCStudio::Shader::Saturation::Saturation", txt,
            satpow,
            txt
        );
        
        // LCHuv.D50 -> Luv.D50
        renderer.render("MDCStudio::Shader::Saturation::LuvFromLCHuv", txt,
            txt
        );
        
        // Luv.D50 -> XYZ.D50
        renderer.render("MDCStudio::Shader::Saturation::XYZD50FromLuvD50", txt,
            txt
        );
    }
};

}; // MDCStudio::ImagePipeline

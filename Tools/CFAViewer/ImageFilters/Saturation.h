#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImageFilter.h"
#import "MetalUtil.h"

namespace CFAViewer {
    class Saturation : public ImageFilter {
    public:
        using ImageFilter::ImageFilter;
        
        void run(float sat, id<MTLTexture> xyz_d50) {
            id<MTLTexture> txt = xyz_d50;
            
            // XYZ.D50 -> Luv.D50
            renderer().render("ImageLayer::LuvD50FromXYZD50", txt,
                txt
            );
            
            // Luv.D50 -> LCHuv.D50
            renderer().render("ImageLayer::LCHuvFromLuv", txt,
                txt
            );
            
            // Saturation
            const float satpow = pow(2, 2*sat);
            renderer().render("ImageLayer::Saturation", txt,
                satpow,
                txt
            );
            
            // LCHuv.D50 -> Luv.D50
            renderer().render("ImageLayer::LuvFromLCHuv", txt,
                txt
            );
            
            // Luv.D50 -> XYZ.D50
            renderer().render("ImageLayer::XYZD50FromLuvD50", txt,
                txt
            );
        }
    };
};

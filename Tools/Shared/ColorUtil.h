#pragma once
#import "Mat.h"

namespace ColorUtil {
    using ColorMatrix = Mat<double,3,3>;
    using Color3 = Mat<double,3,1>;
    using Color_XYY_D50 = Color3;
    using Color_XYZ_D50 = Color3;
    using Color_CIERGB_E = Color3;
    using Color_SRGB_D65 = Color3;
    using Color_CamRaw_D50 = Color3;
    
    inline Color_XYY_D50 XYYD50FromXYZD50(const Color_XYZ_D50& xyz) {
        const double denom = xyz[0]+xyz[1]+xyz[2];
        const double x = xyz[0]/denom;
        const double y = xyz[1]/denom;
        const double Y = xyz[1];
        return {x, y, Y};
    }
    
    inline Color_XYZ_D50 XYZD50FromXYYD50(const Color_XYY_D50& xyy) {
        const double X = (xyy[0]*xyy[2])/xyy[1];
        const double Y = xyy[2];
        const double Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
        return {X, Y, Z};
    }
    
    inline double SRGBGammaForward(double x) {
        // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        if (x <= 0.0031308) return 12.92*x;
        return 1.055*pow(x, 1/2.4)-.055;
    }
    
    inline double SRGBGammaReverse(double x) {
        // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        if (x <= 0.04045) return x/12.92;
        return pow((x+.055)/1.055, 2.4);
    }
    
    inline Color_XYZ_D50 XYZD50FromSRGBD65(const Color_SRGB_D65& srgb_d65) {
        // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        const ColorMatrix XYZD65_From_LSRGBD65(
            0.4124564, 0.3575761, 0.1804375,
            0.2126729, 0.7151522, 0.0721750,
            0.0193339, 0.1191920, 0.9503041
        );
        
        const ColorMatrix XYZD50_From_XYZD65(
            1.0478112,  0.0228866,  -0.0501270,
             0.0295424, 0.9904844,  -0.0170491,
            -0.0092345, 0.0150436,  0.7521316
        );
        
        // SRGB -> linear SRGB
        const Color3 lsrgb_d65(
            SRGBGammaReverse(srgb_d65[0]),
            SRGBGammaReverse(srgb_d65[1]),
            SRGBGammaReverse(srgb_d65[2])
        );
        
        // Linear SRGB -> XYZ.D65 -> XYZ.D50
        return XYZD50_From_XYZD65 * XYZD65_From_LSRGBD65 * lsrgb_d65;
    }
}

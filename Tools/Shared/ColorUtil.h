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
    
    inline Color_XYY_D50 XYYFromXYZ(const Color_XYZ_D50& xyz) {
        const double denom = xyz[0]+xyz[1]+xyz[2];
        const double x = xyz[0]/denom;
        const double y = xyz[1]/denom;
        const double Y = xyz[1];
        return {x, y, Y};
    }

    inline Color_XYZ_D50 XYZFromXYY(const Color_XYY_D50& xyy) {
        const double X = (xyy[0]*xyy[2])/xyy[1];
        const double Y = xyy[2];
        const double Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
        return {X, Y, Z};
    }
}

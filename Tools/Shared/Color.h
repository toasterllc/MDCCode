#pragma once
#import "Mat.h"

namespace White {
    struct D50 {
        static const inline Mat<double,3,1> XYZ = {0.96422, 1.00000, 0.82521};
    };
    
    struct D55 {
        static const inline Mat<double,3,1> XYZ = {0.95682, 1.00000, 0.92149};
    };
    
    struct D65 {
        static const inline Mat<double,3,1> XYZ = {0.95047, 1.00000, 1.08883};
    };
}

namespace ColorSpace {
    template <typename Space, typename White>
    Mat<double,3,3> XYZFromRGBMatrix() {
        const double xr = Space::R[0];
        const double yr = Space::R[1];
        
        const double xg = Space::G[0];
        const double yg = Space::G[1];
        
        const double xb = Space::B[0];
        const double yb = Space::B[1];
        
        const double Xr = xr/yr;
        const double Xg = xg/yg;
        const double Xb = xb/yb;
        
        const double Yr = 1;
        const double Yg = 1;
        const double Yb = 1;
        
        const double Zr = (1-xr-yr)/yr;
        const double Zg = (1-xg-yg)/yg;
        const double Zb = (1-xb-yb)/yb;
        
        const Mat<double,3,3> XYZ(
            Xr, Xg, Xb,
            Yr, Yg, Yb,
            Zr, Zg, Zb
        );
        
        const Mat<double,3,1> S = XYZ.solve(White::XYZ);
        const Mat<double,3,3> M(
            S[0]*Xr, S[1]*Xg, S[2]*Xb,
            S[0]*Yr, S[1]*Yg, S[2]*Yb,
            S[0]*Zr, S[1]*Zg, S[2]*Zb
        );
        return M;
    }
    
    template <typename Space, typename White>
    Mat<double,3,3> RGBFromXYZMatrix() {
        return XYZFromRGBMatrix<Space,White>().inv();
    }
    
    template <typename W>
    struct XYZ {
        static Mat<double,3,1> ToXYZ(const Mat<double,3,1>& c) { return c; }
        static Mat<double,3,1> FromXYZ(const Mat<double,3,1>& c) { return c; }
        using White = W;
    };
    
    // Linear SRGB
    struct LSRGB {
        static constexpr double R[] = {0.6400, 0.3300};
        static constexpr double G[] = {0.3000, 0.6000};
        static constexpr double B[] = {0.1500, 0.0600};
        using White = White::D65;
        
        static Mat<double,3,1> ToXYZ(const Mat<double,3,1>& c) {
            return XYZFromRGBMatrix<LSRGB,White>()*c;
        }
        
        static Mat<double,3,1> FromXYZ(const Mat<double,3,1>& c) {
            return RGBFromXYZMatrix<LSRGB,White>()*c;
        }
    };
    
    struct SRGB {
        static constexpr double R[] = {0.6400, 0.3300};
        static constexpr double G[] = {0.3000, 0.6000};
        static constexpr double B[] = {0.1500, 0.0600};
        using White = White::D65;
        
        static double GammaForward(double x) {
            // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
            if (x <= 0.0031308) return 12.92*x;
            return 1.055*pow(x, 1/2.4)-.055;
        }
        
        static double GammaReverse(double x) {
            // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
            if (x <= 0.04045) return x/12.92;
            return pow((x+.055)/1.055, 2.4);
        }
        
        static Mat<double,3,1> ToXYZ(const Mat<double,3,1>& c) {
            // Reverse gamma
            const Mat<double,3,1> lsrgb(
                GammaReverse(c[0]),
                GammaReverse(c[1]),
                GammaReverse(c[2])
            );
            return XYZFromRGBMatrix<SRGB,White>()*lsrgb;
        }
        
        static Mat<double,3,1> FromXYZ(const Mat<double,3,1>& c) {
            const Mat<double,3,1> lsrgb = RGBFromXYZMatrix<SRGB,White>()*c;
            // Forward gamma
            return Mat<double,3,1>(
                GammaForward(lsrgb[0]),
                GammaForward(lsrgb[1]),
                GammaForward(lsrgb[2])
            );
        }
    };
    
    struct ProPhotoRGB {
        static constexpr double R[] = {0.7347, 0.2653};
        static constexpr double G[] = {0.1596, 0.8404};
        static constexpr double B[] = {0.0366, 0.0001};
        using White = White::D50;
        
        static Mat<double,3,1> ToXYZ(const Mat<double,3,1>& c) {
            return XYZFromRGBMatrix<ProPhotoRGB,White>()*c;
        }
        
        static Mat<double,3,1> FromXYZ(const Mat<double,3,1>& c) {
            return RGBFromXYZMatrix<ProPhotoRGB,White>()*c;
        }
    };
}

template <typename Space>
class Color {
public:
    Color() {}
    Color(double x0, double x1, double x2) : m(x0,x1,x2) {}
    
    // TODO: minimize calculation when converting between LSRGB<->SRGB
    template <typename SpaceSrc>
    Color(const Color<SpaceSrc>& c) {
        m = c.m;
        // No further calculation if SpaceSrc==Space
        if constexpr (std::is_same<SpaceSrc,Space>::value) return;
        
        // Convert from the source colorspace to XYZ (SpaceSrc.WhiteSrc -> XYZ.WhiteSrc)
        m = SpaceSrc::ToXYZ(m);
        // Perform chromatic adaptation (XYZ.WhiteSrc -> XYZ.White)
        m = _AdaptChromaticity<typename SpaceSrc::White, typename Space::White>(m);
        // Convert from XYZ to the destination colorspace (XYZ.White -> Space.White)
        m = Space::FromXYZ(m);
    }
    
    double& operator[](size_t i) { return m[i]; }
    const double& operator[](size_t i) const { return m[i]; }
    
    Mat<double,3,1> m;
    
private:
    template <typename WhiteSrc, typename WhiteDst>
    static Mat<double,3,1> _AdaptChromaticity(const Mat<double,3,1>& c) {
        // Pass-through if WhiteSrc==WhiteDst
        if constexpr (std::is_same<WhiteSrc,WhiteDst>::value) {
//            printf("BYPASS CHROMATIC ADAPTATION\n");
            return c;
        }
        
        // From http://www.brucelindbloom.com/index.html?Eqn_XYZ_to_xyY.html
        const Mat<double,3,3> BradfordForward(
            0.8951000,  0.2664000,  -0.1614000,
            -0.7502000, 1.7135000,  0.0367000,
             0.0389000, -0.0685000, 1.0296000
        );
        
        const Mat<double,3,3> BradfordReverse(
            0.9869929,  -0.1470543, 0.1599627,
             0.4323053, 0.5183603,  0.0492912,
            -0.0085287, 0.0400428,  0.9684867
        );
        
        const Mat<double,3,1> S = BradfordForward*WhiteSrc::XYZ;
        const Mat<double,3,1> D = BradfordForward*WhiteDst::XYZ;
        
        const Mat<double,3,3> K(
            D[0]/S[0],  0.,         0.,
            0.,         D[1]/S[1],  0.,
            0.,         0.,         D[2]/S[2]
        );
        
        const Mat<double,3,3> M = BradfordReverse*(K*BradfordForward);
        return M*c;
    }
};

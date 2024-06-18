#pragma once
#import "Code/Lib/Toastbox/Mac/Mat.h"

#pragma mark - Linear

namespace Interp {
    // Returns `x` for the matrix equation `Ax=b`
    template<size_t Order>
    Mat<double,1,(Order+1)*(Order+1)> calcTerms2D(double ky, double kx) {
        // Calculate each term: ky^y * kx^x
        Mat<double,1,(Order+1)*(Order+1)> yx;
        for (ssize_t y=Order, i=0; y>=0; y--) {
            for (ssize_t x=Order; x>=0; x--, i++) {
                yx.at(i) = pow(ky,y)*pow(kx,x);
            }
        }
        return yx;
    }
}

namespace Interp::Linear {
    // interp() computes (a1-a0)x+b and stores the terms as separate
    // rows in the result matrix.
    // Since the result represents the individual terms of the interpolation,
    // it can be used as a row of `A` in the matrix equation `Ax=b`, to solve
    // for `x`.
    template<size_t H>
    Mat<double,H*2,1> interp(Mat<double,H,1> a0, Mat<double,H,1> a1) {
        Mat<double,H*2,1> r;
        for (size_t y=0; y<H; y++) {
            r[0*H+y] = a0[y]-a1[y]; // x^1 term
            r[1*H+y] = a0[y];       // x^0 term
        }
        return r;
    }
    
    Mat<double,4,1> interp2D(const Mat<double,2,2>& a) {
        return interp( // Interpolate along Y axis
            interp<1>({a.at(0,0)}, {a.at(0,1)}), // Interpolate along X axis (first set of points)
            interp<1>({a.at(1,0)}, {a.at(1,1)})  // Interpolate along X axis (second set of points)
        );
    }
    
//    // Returns `x` for the matrix equation `Ax=b`
//    Mat<double,1,4> calcTerms2D(double ky, double kx) {
//        // Calculate each term: ky^y * kx^x
//        Mat<double,1,4> yx;
//        for (ssize_t y=1, i=0; y>=0; y--) {
//            for (ssize_t x=1; x>=0; x--, i++) {
//                yx.at(i) = pow(ky,y)*pow(kx,x);
//            }
//        }
//        return yx;
//    }
//    
//    // Returns a row of `b` for the matrix equation `Ax=b`
//    Mat<double,1,1> calcb(const Mat<double,2,2>& a) {
//        // Calculate each term: ky^y * kx^x
//        constexpr double Y = -4.5;
//        constexpr double X = 9;
//        Mat<double,1,4> yx;
//        for (ssize_t y=1, i=0; y>=0; y--) {
//            for (ssize_t x=1; x>=0; x--, i++) {
//                yx.at(i) = pow(Y,y)*pow(X,x);
//            }
//        }
//        
//        return yx*interp2D(a);
//    }
}

#pragma mark - Linear4
namespace Interp::Linear4 {
    struct Dir {
        ssize_t y = 0;
        ssize_t x = 0;
        
        size_t index() const {
            if (y>=0 && x>=0) return 0;
            if (y>=0 && x< 0) return 1;
            if (y< 0 && x>=0) return 2;
            if (y< 0 && x< 0) return 3;
            abort();
        }
    };
    
    // Returns a row of `A` (for the matrix equation `Ax=b`) for a given direction `dir`
    Mat<double,16,1> calcA(const Mat<double,3,3>& a, const Dir& dir) {
        // Fill in the terms of `A` in the correct slot for the direction `dir`
        Mat<double,16,1> A;
        const Mat<double,4,1> terms = Linear::interp2D({
            a.at(1      ,1), a.at(1      ,1+dir.x),
            a.at(1+dir.y,1), a.at(1+dir.y,1+dir.x)
        });
        
        for (size_t i=0, y=4*dir.index(); i<4; i++, y++) {
            A[y] = terms[i];
        }
        return A;
    }
    
    // Returns a row of `b` (for the matrix equation `Ax=b`)
    Mat<double,1,1> calcb(const Mat<double,3,3>& a) {
        constexpr double Y = -4.5;
        constexpr double X = 9;
        const Dir YXOff = {(Y>=0?1:-1), (X>=0?1:-1)};
        
        // Calculate each term: ky^y * kx^x
        Mat<double,1,16> yx;
        for (ssize_t y=1, i=0; y>=0; y--) {
            for (ssize_t x=1; x>=0; x--, i++) {
                const double kykx = pow(std::abs(Y),y)*pow(std::abs(X),x);
                yx.at(i+ 0) = kykx; // y+ x+
                yx.at(i+ 4) = kykx; // y+ x-
                yx.at(i+ 8) = kykx; // y- x+
                yx.at(i+12) = kykx; // y- x-
            }
        }
        
        // Fill in the terms of `bcol` in the correct slot for the sign of Y/X
        Mat<double,16,1> bcol;
        const Mat<double,4,1> bterms = Linear::interp2D({
            a.at(1        ,1), a.at(1        ,1+YXOff.x),
            a.at(1+YXOff.y,1), a.at(1+YXOff.y,1+YXOff.x)
        });
        
        for (size_t i=0, y=4*YXOff.index(); i<4; i++, y++) {
            bcol[y] = bterms[i];
        }
        
        return yx*bcol;
    }
}







#pragma mark - Quadratic
namespace Interp::Quadratic {
    // interp() computes `k2 x^2 + k1 x + k0` (where k2/k1/k0 are set such that
    // f(-1)=a0, f(0)=a1, and f(1)=a2) and stores the terms as separate rows in
    // the result matrix. 
    // Since the result represents the individual terms of the interpolation,
    // it can be used as a row of `A` in the matrix equation `Ax=b`, to solve
    // for `x`.
    template<size_t H>
    Mat<double,H*3,1> interp(Mat<double,H,1> a0, Mat<double,H,1> a1, Mat<double,H,1> a2) {
        Mat<double,H*3,1> r;
        for (size_t y=0; y<H; y++) {
            r[0*H+y] = +.5*a0[y]-1.*a1[y]+.5*a2[y]; // x^2 term
            r[1*H+y] = -.5*a0[y]         +.5*a2[y]; // x^1 term
            r[2*H+y] =          +1.*a1[y]         ; // x^0 term
        }
        return r;
    }
    
    Mat<double,9,1> interp2D(const Mat<double,3,3>& a) {
        return interp( // Interpolate along Y axis
            interp<1>({a.at(0,0)}, {a.at(0,1)}, {a.at(0,2)}), // Interpolate along X axis (first set of points)
            interp<1>({a.at(1,0)}, {a.at(1,1)}, {a.at(1,2)}), // Interpolate along X axis (second set of points)
            interp<1>({a.at(2,0)}, {a.at(2,1)}, {a.at(2,2)})  // Interpolate along X axis (third set of points)
        );
    }
    
//    // Returns `x` for the matrix equation `Ax=b`
//    Mat<double,1,9> calcTerms2D(double ky, double kx) {
//        // Calculate each term: ky^y * kx^x
//        Mat<double,1,9> yx;
//        for (ssize_t y=2, i=0; y>=0; y--) {
//            for (ssize_t x=2; x>=0; x--, i++) {
//                yx.at(i) = pow(ky,y)*pow(kx,x);
//            }
//        }
//        return yx;
//    }
}









#pragma mark - Cubic

namespace Interp::Cubic {
    // interp() computes:
    //   k0*x3 + k1*x2 + k2*x + k3
    // and stores the terms as separate rows in the result
    template<size_t H>
    Mat<double,H*4,1> interp(Mat<double,H,1> z0, Mat<double,H,1> z1, Mat<double,H,1> z2, Mat<double,H,1> z3) {
        Mat<double,H*4,1> r;
        for (size_t y=0; y<H; y++) {
            
    //        r[0*H+y] = -z0[y] + z1[y] - z2[y] + z3[y]       ; // x^3 term
    //        r[1*H+y] = +2*z0[y] - 2*z1[y] + z2[y] - z3[y]   ; // x^2 term
    //        r[2*H+y] = -z0[y] + z2[y]                       ; // x^1 term
    //        r[3*H+y] = z1[y]                                ; // x^0 term
            
            r[0*H+y] = -0.5*z0[y]+1.5*z1[y]-1.5*z2[y]+0.5*z3[y] ; // x^3 term
            r[1*H+y] = +1.0*z0[y]-2.5*z1[y]+2.0*z2[y]-0.5*z3[y] ; // x^2 term
            r[2*H+y] = -0.5*z0[y]          +0.5*z2[y]           ; // x^1 term
            r[3*H+y] =           +1.0*z1[y]                     ; // x^0 term
        }
        return r;
    }
    
    Mat<double,16,1> interp2D(const Mat<double,4,4>& z) {
        return interp( // Interpolate along Y axis
            interp<1>(z.at(0,0), z.at(0,1), z.at(0,2), z.at(0,3)), // Interpolate along X axis (point set 0)
            interp<1>(z.at(1,0), z.at(1,1), z.at(1,2), z.at(1,3)), // Interpolate along X axis (point set 1)
            interp<1>(z.at(2,0), z.at(2,1), z.at(2,2), z.at(2,3)), // Interpolate along X axis (point set 2)
            interp<1>(z.at(3,0), z.at(3,1), z.at(3,2), z.at(3,3))  // Interpolate along X axis (point set 3)
        );
    }

    Mat<double,1,1> calcb(const Mat<double,4,4>& z) {
        // Calculate each term: ky^y * kx^x
        constexpr double Y = -4.5;
        constexpr double X = 9;
        Mat<double,1,16> yx;
        for (ssize_t y=3, i=0; y>=0; y--) {
            for (ssize_t x=3; x>=0; x--, i++) {
                yx.at(i) = pow(Y,y)*pow(X,x);
            }
        }
        
        return yx*interp2D(z);
    }
}

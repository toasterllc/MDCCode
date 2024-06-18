#include <vector>
#include <cmath>
#include <optional>
#include "Code/Lib/Toastbox/Mac/Mat.h"

// Poly2D represents a 2D polynomial of a specified order, that's solved for given
// the supplied {x,y,z} triplets, where f(x,y)=z.
// 
// An order of 2 implies a polynomial of the form:
//   A(y^0)(x^0) + B(y^0)(x^1) + C(y^1)(x^0) + D(y^1)(x^1) = Z
//
// An order of 3 implies a polynomial of the form:
//   A(y^0)(x^0) + B(y^0)(x^1) + C(y^0)(x^2) +
//   D(y^1)(x^0) + E(y^1)(x^1) + F(y^1)(x^2) +
//   G(y^2)(x^0) + H(y^2)(x^1) + I(y^2)(x^2)
//
// An order of 4 implies a polynomial of the form:
//   A(y^0)(x^0) + B(y^0)(x^1) + C(y^0)(x^2) + D(y^0)(x^3) +
//   E(y^1)(x^0) + F(y^1)(x^1) + G(y^1)(x^2) + H(y^1)(x^3) +
//   I(y^2)(x^0) + J(y^2)(x^1) + K(y^2)(x^2) + L(y^2)(x^3) +
//   M(y^3)(x^0) + N(y^3)(x^1) + O(y^3)(x^2) + P(y^3)(x^3)
// 
template<typename T, size_t Order>
class Poly2D {
private:
    static constexpr size_t _Terms = Order*Order;
    
public:
    // Add a point/solution triplet `(x,y,z)` with weight `wt`
    void addPoint(T wt, T x, T y, T z) {
        // A conceptually simpler way to implement this would be
        // to make the dimensions:
        //   A = [N x _Terms], and
        //   b = [N x 1],
        // where N=number of points. Then to solve:
        //   x = A.pinv()*b
        // The issue with this is merely that it requires that
        // A and b have dynamic heights, which Mat<> doesn't
        // currently support since it's a templated class.
        // This way also appears to be faster than that
        // technique.
        Toastbox::Mat<T,_Terms,1> k;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                // Calculate each term by raising the x,y values to the
                // power determined by the term.
                k[i] = std::pow(y,a)*std::pow(x,b);
            }
        }
        
        const Toastbox::Mat<T,_Terms,1> kwt = k*wt;
        _A = _A+kwt*k.trans();
        _b = _b+kwt*z;
    }
    
    T eval(T x, T y) {
        const auto& k = coeffs();
        
        T r = 0;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                const T term = std::pow(y,a)*std::pow(x,b);
                r += k.at(i)*term;
            }
        }
        return r;
    }
    
    const Toastbox::Mat<T,_Terms,1>& coeffs() {
        // Solve the system if we haven't done so yet
        if (!_x) _x = _A.solve(_b);
        return *_x;
    }
    
private:
    Toastbox::Mat<T,_Terms,_Terms> _A; // x,y points
    std::optional<Toastbox::Mat<T,_Terms,1>> _x; // Coefficients (solution to linear system)
    Toastbox::Mat<T,_Terms,1> _b; // z points
};










//#include <vector>
//#include <cmath>
//#include "Mat.h"
//
//// Poly2D represents a 2D polynomial of a specified order, that's solved for given
//// the supplied {x,y,z} triplets, where f(x,y)=z.
//// 
//// An order of 2 implies a polynomial of the form:
////   A(y^0)(x^0) + B(y^0)(x^1) + C(y^1)(x^0) + D(y^1)(x^1) = Z
////
//// An order of 3 implies a polynomial of the form:
////   A(y^0)(x^0) + B(y^0)(x^1) + C(y^0)(x^2) +
////   D(y^1)(x^0) + E(y^1)(x^1) + F(y^1)(x^2) +
////   G(y^2)(x^0) + H(y^2)(x^1) + I(y^2)(x^2)
////
//// An order of 4 implies a polynomial of the form:
////   A(y^0)(x^0) + B(y^0)(x^1) + C(y^0)(x^2) + D(y^0)(x^3) +
////   E(y^1)(x^0) + F(y^1)(x^1) + G(y^1)(x^2) + H(y^1)(x^3) +
////   I(y^2)(x^0) + J(y^2)(x^1) + K(y^2)(x^2) + L(y^2)(x^3) +
////   M(y^3)(x^0) + N(y^3)(x^1) + O(y^3)(x^2) + P(y^3)(x^3)
//// 
//template<typename T, size_t Order>
//class Poly2D {
//public:
//    Poly2D() = default;
//    
//    // `pts` is a vector of x,y,z triplets
//    // `wts` is the weight to apply to each triplet
//    Poly2D(const std::vector<T>& pts, const std::vector<T>& wts) {
//        for (size_t pti=0, wti=0; pti<pts.size(); pti+=3, wti++) {
//            _addPoint(wts.at(wti), pts.at(pti+0), pts.at(pti+1), pts.at(pti+2));
//        }
//        _x = _A.solve(_b);
//    }
//    
//    T eval(T x, T y) const {
//        T r = 0;
//        for (size_t a=0, i=0; a<Order; a++) {
//            for (size_t b=0; b<Order; b++, i++) {
//                const T k = std::pow(y,a)*std::pow(x,b);
//                r += k*_x.at(i);
//            }
//        }
//        return r;
//    }
//    
//private:
//    void _addPoint(T wt, T x, T y, T z) {
//        // A conceptually simpler way to implement this would be
//        // to make the dimensions:
//        //   A = [N x _Terms], and
//        //   b = [N x 1],
//        // where N=number of points. Then to solve:
//        //   x = A.pinv()*b
//        // The issue with this is merely that it requires that
//        // A and b have dynamic heights, which Mat<> doesn't
//        // currently support since it's a templated class.
//        // This way also appears to be faster than that
//        // technique.
//        Mat<T,_Terms,1> k;
//        for (size_t a=0, i=0; a<Order; a++) {
//            for (size_t b=0; b<Order; b++, i++) {
//                // Calculate each term by raising the x,y values to the
//                // power determined by the term.
//                k[i] = std::pow(y,a)*std::pow(x,b);
//            }
//        }
//        
//        const Mat<T,_Terms,1> kwt = k*wt;
//        _A = _A+kwt*k.trans();
//        _b = _b+kwt*z;
//    }
//    
//    static constexpr size_t _Terms = Order*Order;
//    
//    Mat<T,_Terms,_Terms> _A; // x,y points
//    Mat<T,_Terms,1> _x; // Coefficients (solution to linear system)
//    Mat<T,_Terms,1> _b; // z points
//};

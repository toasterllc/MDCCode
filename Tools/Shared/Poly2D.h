#include <vector>
#include <cmath>
#include "Mat.h"

#define FLAVOR 3

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

#if FLAVOR==3

template <typename T, size_t Order>
class Poly2D {
public:
    Poly2D() = default;
    
    // `pts` is a vector of x,y,z triplets
    // `wts` is the weight to apply to each triplet
    Poly2D(const std::vector<T>& pts, const std::vector<T>& wts) {
        for (size_t pti=0, wti=0; pti<pts.size(); pti+=3, wti++) {
            _addPoint(wts.at(wti), pts.at(pti+0), pts.at(pti+1), pts.at(pti+2));
        }
        
//        for (size_t y=0; y<_Terms; y++) {
//            for (size_t x=0; x<_Terms; x++) {
//                printf("A: %.3f\n", _A.at(y,x));
//            }
//        }
//        exit(0);
        
//        for (size_t y=0; y<_Terms; y++) {
//            printf("b: %.3f\n", _b[y]);
//        }
//        exit(0);
        
//        // Solve for the 2D polynomial coefficients
//        _x = _A.pinv()*_b;
        
        // Solve for the 2D polynomial coefficients
        _x = _A.inv()*_b;
        
//        for (const T& coeff : _x.vals) {
//            printf("Coeffs: %.3f\n", coeff);
//        }
//        exit(0);
    }
    
    T eval(T x, T y) const {
        T r = 0;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                const T k = std::pow(y,a)*std::pow(x,b);
                r += k*_x.at(i);
            }
        }
        return r;
    }
    
private:
    void _addPoint(T wt, T x, T y, T z) {
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
        Mat<T,_Terms,1> k;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                // Calculate each term by raising the x,y values to the
                // power determined by the term.
                k[i] = std::pow(y,a)*std::pow(x,b);
            }
        }
        
        const Mat<T,_Terms,1> kwt = k*wt;
        _A = _A+kwt*k.trans();
        _b = _b+kwt*z;
    }
    
    static constexpr size_t _Terms = Order*Order;
    
    Mat<T,_Terms,_Terms> _A; // x,y points
    Mat<T,_Terms,1> _x; // Coefficients (solution to linear system)
    Mat<T,_Terms,1> _b; // z points
};

#elif FLAVOR==2

template <typename T, size_t Order>
class Poly2D {
public:
    Poly2D() = default;
    
    #define SIZE (300)
    // `pts` is a vector of x,y,z triplets
    // `wts` is the weight to apply to each triplet
    Poly2D(const std::vector<T>& pts, const std::vector<T>& wtsvec) {
        assert(pts.size() == SIZE*3);
        Mat<T,SIZE,4> A;
        Mat<T,SIZE,1> b;
        
        for (size_t pti=0, row=0; pti<SIZE*3; pti+=3, row++) {
            T x = pts[pti+0];
            T y = pts[pti+1];
            T z = pts[pti+2];
            
            for (size_t powa=0, i=0; powa<Order; powa++) {
                for (size_t powb=0; powb<Order; powb++, i++) {
                    A.at(row,i) = std::pow(y,powa)*std::pow(x,powb);
                }
            }
            
            b[row] = z;
        }
        
        Mat<T,SIZE,1> wts;
        std::copy(wtsvec.begin(), wtsvec.end(), wts.vals);
        
        _x = A.pinv(wts) * b;
        
//        for (const T& coeff : _x.vals) {
//            printf("Coeffs: %.3f\n", coeff);
//        }
//        exit(0);
        
//        for (size_t pti=0, wti=0; pti<pts.size(); pti+=3, wti++) {
//            _addPoint(wts.at(wti), pts.at(pti+0), pts.at(pti+1), pts.at(pti+2));
//        }
//        _solve();
    }
    
    T eval(T x, T y) const {
        T r = 0;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                const T k = std::pow(y,a)*std::pow(x,b);
                r += k*_x[i];
            }
        }
        return r;
    }
    
private:
    void _addPoint(T wt, T x, T y, T z) {
        Mat<T,_Terms,1> k;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                k[i] = std::pow(y,a)*std::pow(x,b);
            }
        }
        
        _A = _A+(k*k.trans())*wt;
        _b = _b+(k*z)*wt;
    }
    
    // Solve for the 2D polynomial coefficients using Gaussian elimination
    void _solve() {
        for (size_t y=0; y<_Terms-1; y++) {
            // Find the row with the max element
            T maxElm = std::fabs(_A.at(y,y));
            size_t maxElmY = y;
            for (size_t i=y+1; i<_Terms; i++) {
                if (std::fabs(_A.at(i,y)) > maxElm) {
                    maxElm = _A.at(i,y);
                    maxElmY = i;
                }
            }
            
            // Swap the two rows if needed
            if (maxElmY != y) {
                for (size_t i=y; i<_Terms; i++) {
                    std::swap(_A.at(y,i), _A.at(maxElmY,i));
                }
                std::swap(_b[y], _b[maxElmY]);
            }
            
            if (_A.at(y,y) == 0) {
                throw std::runtime_error("failed to solve");
            }
            
            // Forward substitution
            for (size_t j=y+1; j<_Terms; j++) {
                const T k = -_A.at(j,y) / _A.at(y,y);
                for (size_t i=y; i<_Terms; i++) {
                    _A.at(j,i) += k*_A.at(y,i);
                }
                _b[j] += k*_b[y];
            }
        }
        
        // Backward substitution
        for (size_t y=_Terms-1;; y--) {
            _x[y] = _b[y];
            
            for (size_t i=y+1; i<_Terms; i++) {
                _x[y] -= _A.at(y,i)*_x[i];
            }
            
            _x[y] /= _A.at(y,y);
            if (!y) break;
        }
    }
    
    static constexpr size_t _Terms = Order*Order;
    
    Mat<T,_Terms,_Terms> _A; // x,y points
    Mat<T,_Terms,1> _x; // Coefficients (solution to linear system)
    Mat<T,_Terms,1> _b; // z points
};

#elif FLAVOR == 1

template <typename T, size_t Order>
class Poly2D {
public:
    Poly2D() = default;
    
    // `pts` is a vector of x,y,z triplets
    // `wts` is the weight to apply to each triplet
    Poly2D(const std::vector<T>& pts, const std::vector<T>& wts) {
        for (size_t pti=0, wti=0; pti<pts.size(); pti+=3, wti++) {
            _addPoint(wts.at(wti), pts.at(pti+0), pts.at(pti+1), pts.at(pti+2));
        }
        
//        for (size_t y=0; y<_Terms; y++) {
//            for (size_t x=0; x<_Terms; x++) {
//                printf("A: %.3f\n", _A[y][x]);
//            }
//        }
//        exit(0);
        
//        for (size_t y=0; y<_Terms; y++) {
//            printf("b: %.3f\n", _b[y]);
//        }
//        exit(0);
        
        _solve();
        
//        for (const T& coeff : _x) {
//            printf("Coeffs: %.3f\n", coeff);
//        }
//        exit(0);
    }
    
    T eval(T x, T y) const {
        T r = 0;
        for (size_t a=0, i=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, i++) {
                const T k = std::pow(y,a)*std::pow(x,b);
                r += k*_x[i];
            }
        }
        return r;
    }
    
private:
    void _addPoint(T wt, T x, T y, T z) {
        for (size_t a=0, row=0; a<Order; a++) {
            for (size_t b=0; b<Order; b++, row++) {
                const T krow = wt*std::pow(y,a)*std::pow(x,b);
                for (size_t c=0, col=0; c<Order; c++) {
                    for (size_t d=0; d<Order; d++, col++) {
                        const T kcol = std::pow(y,c)*std::pow(x,d);
                        _A[row][col] += krow*kcol;
                    }
                }
                
                _b[row] += krow*z;
            }
        }
    }
    
    // Solve for the 2D polynomial coefficients using Gaussian elimination
    void _solve() {
        for (size_t y=0; y<_Terms-1; y++) {
            // Find the row with the max element
            T maxElm = std::fabs(_A[y][y]);
            size_t maxElmY = y;
            for (size_t i=y+1; i<_Terms; i++) {
                if (std::fabs(_A[i][y]) > maxElm) {
                    maxElm = _A[i][y];
                    maxElmY = i;
                }
            }
            
            // Swap the two rows if needed
            if (maxElmY != y) {
                for (size_t i=y; i<_Terms; i++) {
                    std::swap(_A[y][i], _A[maxElmY][i]);
                }
                std::swap(_b[y], _b[maxElmY]);
            }
            
            if (_A[y][y] == 0) {
                throw std::runtime_error("failed to solve");
            }
            
            // Forward substitution
            for (size_t j=y+1; j<_Terms; j++) {
                const T k = -_A[j][y] / _A[y][y];
                for (size_t i=y; i<_Terms; i++) {
                    _A[j][i] += k*_A[y][i];
                }
                _b[j] += k*_b[y];
            }
        }
        
        // Backward substitution
        for (size_t y=_Terms-1;; y--) {
            _x[y] = _b[y];
            
            for (size_t i=y+1; i<_Terms; i++) {
                _x[y] -= _A[y][i]*_x[i];
            }
            
            _x[y] /= _A[y][y];
            if (!y) break;
        }
    }
    
    static constexpr size_t _Terms = Order*Order;
    
    // Ax=b
    T _A[_Terms][_Terms] = {}; // x,y points
    T _x[_Terms] = {}; // Coefficients (solution to linear system)
    T _b[_Terms] = {}; // z points
};

#endif

#pragma once
#import <Accelerate/Accelerate.h>

template <typename T, size_t H, size_t W>
class Mat {
public:
    Mat() {}
    
    Mat(const T v[]) {
        memcpy(vals, v, sizeof(vals));
    }
    
    Mat(T v[]) {
        memcpy(vals, v, sizeof(vals));
    }
    
    template <typename... Ts>
    Mat(Ts... vals) : vals{vals...} {
        static_assert(sizeof...(vals)==H*W, "invalid number of values");
    }
    
    // Copy constructor: use copy assignment operator
    Mat(const Mat& x) { *this = x; }
    // Copy assignment operator
    Mat& operator=(const Mat& x) {
        memcpy(vals, x.vals, sizeof(vals));
        return *this;
    }
    
    // Transpose
    Mat<T,W,H> trans() const {
        Mat<T,W,H> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mtrans(vals, 1, r.vals, 1, W, H);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mtransD(vals, 1, r.vals, 1, W, H);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Inverse
    Mat<T,H,W> inv() const {
        static_assert(H==W, "not a square matrix");
        
        Mat<T,H,H> r;
        memcpy(r.vals, vals, sizeof(vals));
        
        __CLPK_integer m = H;
        __CLPK_integer err = 0;
        __CLPK_integer pivot[m];
        T tmp[m];
        if constexpr(std::is_same_v<T, float>) {
            sgetrf_(&m, &m, r.vals, &m, pivot, &err);
            if (err) throw std::runtime_error("dgetrf_ failed");
            
            sgetri_(&m, r.vals, &m, pivot, tmp, &m, &err);
            if (err) throw std::runtime_error("dgetri_ failed");
        
        } else if constexpr(std::is_same_v<T, double>) {
            dgetrf_(&m, &m, r.vals, &m, pivot, &err);
            if (err) throw std::runtime_error("dgetrf_ failed");
            
            dgetri_(&m, r.vals, &m, pivot, tmp, &m, &err);
            if (err) throw std::runtime_error("dgetri_ failed");
        
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Moore-Penrose inverse
    Mat<T,W,H> pinv() const {
        return (trans()*(*this)).inv()*trans();
    }
    
    // Weighted Moore-Penrose inverse
    Mat<T,W,H> pinv(const Mat<T,H,1>& wts) const {
        Mat<T,H,H> w;
        for (size_t i=0; i<H; i++) {
            w.at(i,i) = wts[i];
        }
        return (trans()*w*(*this)).inv()*trans()*w;
    }
    
    // Matrix multiply
    template <size_t P>
    Mat<T,H,P> operator*(const Mat<T,W,P>& x) const {
        Mat<T,H,P> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mmul(vals, 1, x.vals, 1, r.vals, 1, H, P, W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mmulD(vals, 1, x.vals, 1, r.vals, 1, H, P, W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Matrix add
    Mat<T,H,W> operator+(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vadd(vals, 1, x.vals, 1, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vaddD(vals, 1, x.vals, 1, r.vals, 1, H*W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Matrix subtract
    Mat<T,H,W> operator-(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsub(vals, 1, x.vals, 1, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsubD(vals, 1, x.vals, 1, r.vals, 1, H*W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar add
    Mat<T,H,W> operator+(const T& x) const {
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsadd(vals, 1, &x, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsaddD(vals, 1, &x, r.vals, 1, H*W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar subtract
    Mat<T,H,W> operator-(const T& x) const {
        const T xn = -x;
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsadd(vals, 1, &xn, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsaddD(vals, 1, &xn, r.vals, 1, H*W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar multiply
    Mat<T,H,W> operator*(const T& x) const {
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsmul(vals, 1, &x, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsmulD(vals, 1, &x, r.vals, 1, H*W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar divide
    Mat<T,H,W> operator/(const T& x) const {
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsdiv(vals, 1, &x, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsdivD(vals, 1, &x, r.vals, 1, H*W);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    T& operator[](size_t i) {
        return vals[i];
    }
    
    const T& operator[](size_t i) const {
        return vals[i];
    }
    
    T& at(size_t y, size_t x) {
        assert(y < H);
        assert(x < W);
        return vals[y*W+x];
    }
    
    const T& at(size_t y, size_t x) const {
        assert(y < H);
        assert(x < W);
        return vals[y*W+x];
    }
    
    std::string str(int precision=6) const {
        std::stringstream ss;
        ss.precision(precision);
        for (size_t y=0; y<H; y++) {
            for (size_t x=0; x<W; x++) {
                ss << vals[y*W+x] << " ";
            }
            ss << "\n";
        }
        return ss.str();
    }
    
//    T* operator[](size_t i) {
//        return &vals[i*N];
//    }
    
    T vals[H*W] = {};
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
};

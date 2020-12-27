#pragma once

template <typename T, size_t M, size_t N>
class Mat {
public:
    Mat() {}
    
    template <typename... Ts>
    Mat(Ts... vals) : vals{vals...} {
        static_assert(sizeof...(vals)==M*N, "invalid number of values");
    }
    
    // Copy constructor: use copy assignment operator
    Mat(const Mat& x) { *this = x; }
    // Copy assignment operator
    Mat& operator=(const Mat& x) {
        memcpy(vals, x.vals, sizeof(vals));
        return *this;
    }
    
    // Transpose
    Mat<T,N,M> trans() const {
        Mat<T,N,M> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mtrans(vals, 1, r.vals, 1, N, M);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mtransD(vals, 1, r.vals, 1, N, M);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Inverse
    Mat<T,M,N> inv() const {
        static_assert(M==N, "not a square matrix");
        
        Mat<T,M,M> r;
        memcpy(r.vals, vals, sizeof(vals));
        
        __CLPK_integer m = M;
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
    Mat<T,N,M> pinv() const {
        return (trans()*(*this)).inv()*trans();
    }
    
    // Matrix multiply
    template <size_t P>
    Mat<T,M,P> operator*(const Mat<T,N,P>& x) const {
        Mat<T,M,P> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mmul(vals, 1, x.vals, 1, r.vals, 1, M, P, N);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mmulD(vals, 1, x.vals, 1, r.vals, 1, M, P, N);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar add
    Mat<T,M,N> operator+(const T& x) const {
        Mat<T,M,N> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsadd(vals, 1, &x, r.vals, 1, M*N);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsaddD(vals, 1, &x, r.vals, 1, M*N);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar subtract
    Mat<T,M,N> operator-(const T& x) const {
        const T xn = -x;
        Mat<T,M,N> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsadd(vals, 1, &xn, r.vals, 1, M*N);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsaddD(vals, 1, &xn, r.vals, 1, M*N);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar multiply
    Mat<T,M,N> operator*(const T& x) const {
        Mat<T,M,N> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsmul(vals, 1, &x, r.vals, 1, M*N);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsmulD(vals, 1, &x, r.vals, 1, M*N);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar divide
    Mat<T,M,N> operator/(const T& x) const {
        Mat<T,M,N> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vsdiv(vals, 1, &x, r.vals, 1, M*N);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vsdivD(vals, 1, &x, r.vals, 1, M*N);
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
    
    std::string str(int precision=6) const {
        std::stringstream ss;
        ss.precision(precision);
        for (size_t y=0; y<M; y++) {
            for (size_t x=0; x<N; x++) {
                ss << vals[y*N+x] << " ";
            }
            ss << "\n";
        }
        return ss.str();
    }
    
//    T* operator[](size_t i) {
//        return &vals[i*N];
//    }
    
    T vals[M*N] = {};
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
};

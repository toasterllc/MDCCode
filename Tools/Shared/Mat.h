#pragma once
#import <Accelerate/Accelerate.h>

template <typename T, size_t H, size_t W>
class Mat {
public:
    Mat() {}
    
    Mat(const T v[]) {
        memcpy(vals, v, sizeof(vals));
        _transVals(); // Transpose `vals` to put in column-major order
    }
    
    Mat(T v[]) {
        memcpy(vals, v, sizeof(vals));
        _transVals(); // Transpose `vals` to put in column-major order
    }
    
    template <typename... Ts>
    Mat(Ts... vs) : vals{vs...} {
        static_assert(sizeof...(vs)==H*W, "invalid number of values");
        _transVals(); // Transpose `vals` to put in column-major order
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
        for (size_t y=0; y<H; y++) {
            for (size_t x=0; x<W; x++) {
                r.at(x,y) = at(y,x);
            }
        }
        return r;
    }
    
    // Inverse
    Mat<T,H,W> inv() const {
        static_assert(H==W, "not a square matrix");
        
        Mat<T,H,H> r = *this;
        __CLPK_integer m = H;
        __CLPK_integer err = 0;
        __CLPK_integer pivot[m];
        T tmp[m];
        if constexpr(std::is_same_v<T, float>) {
            sgetrf_(&m, &m, r.vals, &m, pivot, &err);
            if (err) throw std::runtime_error("sgetrf_ failed");
            
            sgetri_(&m, r.vals, &m, pivot, tmp, &m, &err);
            if (err) throw std::runtime_error("sgetri_ failed");
        
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
    
    // Matrix multiply
    template <size_t N>
    Mat<T,H,N> operator*(const Mat<T,W,N>& b) const {
        const auto& a = *this;
        Mat<T,H,N> r;
        if constexpr(std::is_same_v<T, float>)
            cblas_sgemm(
                CblasColMajor, CblasNoTrans, CblasNoTrans,
                (int)a.rows, (int)b.cols, (int)a.cols,
                1, // alpha
                a.vals, (int)a.rows,
                b.vals, (int)b.rows,
                0, // beta
                r.vals, (int)r.rows
            );
        else if constexpr(std::is_same_v<T, double>)
            cblas_dgemm(
                CblasColMajor, CblasNoTrans, CblasNoTrans,
                (int)a.rows, (int)b.cols, (int)a.cols,
                1, // alpha
                a.vals, (int)a.rows,
                b.vals, (int)b.rows,
                0, // beta
                r.vals, (int)r.rows
            );
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise multiply
    Mat<T,H,W> mul(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        // There's apparently no BLAS function to do element-wise vector multiplication
        for (size_t i=0; i<H*W; i++) {
            r.vals[i] *= x.vals[i];
        }
        return r;
    }
    
    // Element-wise multiply-assign
    Mat<T,H,W>& muleq(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        // There's apparently no BLAS function to do element-wise vector multiplication
        for (size_t i=0; i<H*W; i++) {
            r.vals[i] *= x.vals[i];
        }
        return r;
    }
    
    // Scalar multiply
    Mat<T,H,W> operator*(const T& x) const {
        Mat<T,H,W> r = *this;
        if constexpr(std::is_same_v<T, float>)
            cblas_sscal(H*W, x, r.vals, 1);
        else if constexpr(std::is_same_v<T, double>)
            cblas_dscal(H*W, x, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise divide
    Mat<T,H,W> div(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        // There's apparently no BLAS function to do element-wise vector division
        for (size_t i=0; i<H*W; i++) {
            r.vals[i] /= x.vals[i];
        }
        return r;
    }
    
    // Scalar divide
    Mat<T,H,W> operator/(const T& x) const {
        Mat<T,H,W> r = *this;
        if constexpr(std::is_same_v<T, float>)
            cblas_sscal(H*W, T(1)/x, r.vals, 1);
        else if constexpr(std::is_same_v<T, double>)
            cblas_dscal(H*W, T(1)/x, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise add
    Mat<T,H,W> operator+(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        if constexpr(std::is_same_v<T, float>)
            catlas_saxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        else if constexpr(std::is_same_v<T, double>)
            catlas_daxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        else if constexpr(std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> one(1);
            catlas_caxpby(H*W, &one, x.vals, 1, &one, r.vals, 1);
        } else if constexpr(std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> one(1);
            catlas_zaxpby(H*W, &one, x.vals, 1, &one, r.vals, 1);
        } else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise add-assign
    Mat<T,H,W>& operator+=(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        if constexpr(std::is_same_v<T, float>)
            catlas_saxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        else if constexpr(std::is_same_v<T, double>)
            catlas_daxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise subtract
    Mat<T,H,W> operator-(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        if constexpr(std::is_same_v<T, float>)
            catlas_saxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else if constexpr(std::is_same_v<T, double>)
            catlas_daxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise subtract-assign
    Mat<T,H,W>& operator-=(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        if constexpr(std::is_same_v<T, float>)
            catlas_saxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else if constexpr(std::is_same_v<T, double>)
            catlas_daxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Solve `Ax=b` for x, where the receiver is A
    template <size_t N>
    Mat<T,W,N> solve(const Mat<T,H,N>& bconst) const {
        static_assert(H>=W, "matrix size must have H >= W");
        
        __CLPK_integer h = H;
        __CLPK_integer w = W;
        __CLPK_integer nrhs = N;
        Mat<T,H,W> A = *this;
        Mat<T,H,N> bx = bconst;
        __CLPK_integer err = 0;
        
        // 2 iterations: first iteration gets the size of `work`,
        // second iteration performs calculation
        __CLPK_integer lwork = -1;
        for (__CLPK_integer i=0; i<2; i++) {
            T work[std::max(1,lwork)];
            if constexpr(std::is_same_v<T, float>)
                sgels_(
                    (char*)"N", &h, &w, &nrhs,
                    A.vals, &h,
                    bx.vals, &h,
                    work, &lwork, &err
                );
                
            else if constexpr(std::is_same_v<T, double>)
                dgels_(
                    (char*)"N", &h, &w, &nrhs,
                    A.vals, &h,
                    bx.vals, &h,
                    work, &lwork, &err
                );
            
            else
                static_assert(_AlwaysFalse<T>);
            
            if (err) throw std::runtime_error("failed to solve");
            lwork = work[0];
        }
        
        // Copy each column into the destination matrix
        Mat<T,W,N> r;
        for (size_t x=0; x<N; x++) {
            T* col = &bx.at(0,x);
            std::copy(col, col+W, &r.at(0,x));
        }
        return r;
    }
    
    T& operator[](size_t i) {
        static_assert(H==1 || W==1, "subscript operator can only be used on vectors");
        return vals[i];
    }
    
    const T& operator[](size_t i) const {
        static_assert(H==1 || W==1, "subscript operator can only be used on vectors");
        return vals[i];
    }
    
    T& at(size_t i) {
        static_assert(H==1 || W==1, "not a 1D matrix");
        assert(i < std::size(vals));
        return vals[i];
    }
    
    const T& at(size_t i) const {
        static_assert(H==1 || W==1, "not a 1D matrix");
        assert(i < std::size(vals));
        return vals[i];
    }
    
    T& at(size_t y, size_t x) {
        assert(y < H);
        assert(x < W);
        // `vals` is in colum-major format
        return vals[x*H+y];
    }
    
    const T& at(size_t y, size_t x) const {
        assert(y < H);
        assert(x < W);
        // `vals` is in colum-major format
        return vals[x*H+y];
    }
    
    T* col(size_t x) {
        assert(x < W);
        return &vals[x*H];
    }
    
    const T* col(size_t x) const {
        assert(x < W);
        return &vals[x*H];
    }
    
    std::string str(int precision=6) const {
        std::stringstream ss;
        ss.precision(precision);
        ss << "[ ";
        for (size_t y=0; y<H; y++) {
            for (size_t x=0; x<W; x++) {
                ss << at(y,x);
                if (x != W-1) ss << " ";
            }
            if (y != H-1) ss << " ;" << "\n";
        }
        ss << " ]";
        return ss.str();
    }
    
    T vals[H*W] = {}; // Column-major order
    static constexpr size_t h = H;
    static constexpr size_t w = W;
    static constexpr size_t rows = H;
    static constexpr size_t cols = W;
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
    
    void _transVals() {
        // Transpose `vals`
        // Create a temporary copy of `vals`
        auto valsConst = std::make_unique<T[]>(std::size(vals));
        std::copy(vals, vals+std::size(vals), valsConst.get());
        
        for (size_t y=0, i=0; y<H; y++) {
            for (size_t x=0; x<W; x++, i++) {
                at(y,x) = valsConst[i];
            }
        }
    }
};

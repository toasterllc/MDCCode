#pragma once
#import <Accelerate/Accelerate.h>
#import <type_traits>

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
        if constexpr (std::is_same_v<T, float>) {
            sgetrf_(&m, &m, r.vals, &m, pivot, &err);
            if (err) throw std::runtime_error("sgetrf_ failed");
            
            sgetri_(&m, r.vals, &m, pivot, tmp, &m, &err);
            if (err) throw std::runtime_error("sgetri_ failed");
        
        } else if constexpr (std::is_same_v<T, double>) {
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
        if constexpr (std::is_same_v<T, float>)
            cblas_sgemm(
                CblasColMajor, CblasNoTrans, CblasNoTrans,
                (int)a.rows, (int)b.cols, (int)a.cols,
                1, // alpha
                a.vals, (int)a.rows,
                b.vals, (int)b.rows,
                0, // beta
                r.vals, (int)r.rows
            );
        else if constexpr (std::is_same_v<T, double>)
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
        if constexpr (std::is_same_v<T, float>)
            cblas_sscal(H*W, x, r.vals, 1);
        else if constexpr (std::is_same_v<T, double>)
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
        if constexpr (std::is_same_v<T, float>) {
            cblas_sscal(H*W, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            cblas_dscal(H*W, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> k(T(1)/x);
            cblas_cscal(H*W, &k, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> k(T(1)/x);
            cblas_zscal(H*W, &k, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Scalar divide-assign
    Mat<T,H,W>& operator/=(const T& x) {
        Mat<T,H,W>& r = *this;
        if constexpr (std::is_same_v<T, float>) {
            cblas_sscal(H*W, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            cblas_dscal(H*W, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> k(T(1)/x);
            cblas_cscal(H*W, &k, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> k(T(1)/x);
            cblas_zscal(H*W, &k, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Element-wise add
    Mat<T,H,W> operator+(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        if constexpr (std::is_same_v<T, float>) {
            catlas_saxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            catlas_daxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> one(1);
            catlas_caxpby(H*W, &one, x.vals, 1, &one, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> one(1);
            catlas_zaxpby(H*W, &one, x.vals, 1, &one, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Element-wise add-assign
    Mat<T,H,W>& operator+=(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        if constexpr (std::is_same_v<T, float>) {
            catlas_saxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            catlas_daxpby(H*W, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> one(1);
            catlas_caxpby(H*W, &one, x.vals, 1, &one, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> one(1);
            catlas_zaxpby(H*W, &one, x.vals, 1, &one, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Element-wise subtract
    Mat<T,H,W> operator-(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        if constexpr (std::is_same_v<T, float>)
            catlas_saxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else if constexpr (std::is_same_v<T, double>)
            catlas_daxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise subtract-assign
    Mat<T,H,W>& operator-=(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        if constexpr (std::is_same_v<T, float>)
            catlas_saxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else if constexpr (std::is_same_v<T, double>)
            catlas_daxpby(H*W, 1, x.vals, 1, -1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
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
            if constexpr (std::is_same_v<T, float>)
                sgels_(
                    (char*)"N", &h, &w, &nrhs,
                    A.vals, &h,
                    bx.vals, &h,
                    work, &lwork, &err
                );
                
            else if constexpr (std::is_same_v<T, double>)
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
    
    auto fft() {
        return _fft<kFFTDirection_Forward>();
    }
    
    auto ifft() {
        return _fft<kFFTDirection_Inverse>();
    }
    
private:
    template <typename I>
    static constexpr bool _IsPowerOf2(I x) {
        return x && ((x & (x-1)) == 0);
    }
    
    template <typename I>
    static I _Log2(I x) {
        if (x == 0) return 0;
        return flsll(x)-1;
    }
    
    static constexpr bool _DimsPowerOf2 = _IsPowerOf2(H) && _IsPowerOf2(W);
    
    // FFT (Real -> Complex)
    template<
    int Dir, // kFFTDirection_Forward or kFFTDirection_Inverse
    typename _T = T,
    typename std::enable_if_t<_DimsPowerOf2, int> = 0,
    typename std::enable_if_t<std::is_same_v<_T,float>||std::is_same_v<_T,double>, int> = 0
    >
    Mat<std::complex<T>,H,W> _fft() {
        using Float = T;
        constexpr size_t len = (H*(W/2));
        Mat<std::complex<Float>,H,W> r;
        FFTSetup<Float> s;
        
        auto outr = std::make_unique<Float[]>(len);
        auto outi = std::make_unique<Float[]>(len);
        
        // Separate the real/imaginary parts into `inr/ini`
        if constexpr (std::is_same_v<Float, float>) {
            vDSP_ctoz((const DSPComplex*)vals, 2, (DSPSplitComplex[]){outr.get(),outi.get()}, 1, len);
        } else if constexpr (std::is_same_v<Float, double>) {
            vDSP_ctozD((const DSPDoubleComplex*)vals, 2, (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, len);
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        // Perform 2D FFT
        if constexpr (std::is_same_v<Float, float>) {
            vDSP_fft2d_zrip(s,
                (DSPSplitComplex[]){outr.get(),outi.get()}, 1, 0,   // Output
                _Log2(W), _Log2(H),                                 // Dimensions
                Dir
            );
        } else if constexpr (std::is_same_v<Float, double>) {
            vDSP_fft2d_zripD(s,
                (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, 0, // Output
                _Log2(W), _Log2(H),                                     // Dimensions
                Dir
            );
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        for (size_t i=0; i<len; i++) {
            printf("%f %f\n", outr[i]/2, outi[i]/2);
        }
        exit(0);
        
        // Join the real/imaginary parts into `r.vals`
        if constexpr (std::is_same_v<Float, float>) {
            vDSP_ztoc((DSPSplitComplex[]){outr.get(),outi.get()}, 1, (DSPComplex*)r.vals, 2, len);
        } else if constexpr (std::is_same_v<Float, double>) {
            vDSP_ztocD((DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, (DSPDoubleComplex*)r.vals, 2, len);
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        if constexpr (Dir == kFFTDirection_Forward) {
            // Normalize based on the length
            r /= std::complex<Float>(2);
        
        } else if constexpr (Dir == kFFTDirection_Inverse) {
            // Normalize based on the length
            r /= std::complex<Float>(len);
        }
        
        return r;
    }
    
    // FFT (Complex -> Complex)
    template<
    int Dir, // kFFTDirection_Forward or kFFTDirection_Inverse
    typename _T = T,
    typename std::enable_if_t<_DimsPowerOf2, int> = 0,
    typename std::enable_if_t<std::is_same_v<_T,std::complex<float>>||std::is_same_v<_T,std::complex<double>>, int> = 0
    >
    Mat<T,H,W> _fft() {
        using Float = typename T::value_type;
        constexpr size_t len = H*W;
        Mat<std::complex<Float>,H,W> r;
        FFTSetup<Float> s;
        
        auto outr = std::make_unique<Float[]>(len);
        auto outi = std::make_unique<Float[]>(len);
        
        // Separate the real/imaginary parts into `outr/outi`
        if constexpr (std::is_same_v<Float, float>) {
            vDSP_ctoz((const DSPComplex*)vals, 2, (DSPSplitComplex[]){outr.get(),outi.get()}, 1, len);
        } else if constexpr (std::is_same_v<Float, double>) {
            vDSP_ctozD((const DSPDoubleComplex*)vals, 2, (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, len);
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        // Perform 2D FFT
        if constexpr (std::is_same_v<Float, float>) {
            vDSP_fft2d_zip(s,
                (DSPSplitComplex[]){outr.get(),outi.get()}, 1, 0,   // Output
                _Log2(W), _Log2(H),                                 // Dimensions
                Dir
            );
        } else if constexpr (std::is_same_v<Float, double>) {
            vDSP_fft2d_zipD(s,
                (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, 0, // Output
                _Log2(W), _Log2(H),                                     // Dimensions
                Dir
            );
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        // Join the real/imaginary parts into `r.vals`
        if constexpr (std::is_same_v<Float, float>) {
            vDSP_ztoc((DSPSplitComplex[]){outr.get(),outi.get()}, 1, (DSPComplex*)r.vals, 2, len);
        } else if constexpr (std::is_same_v<Float, double>) {
            vDSP_ztocD((DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, (DSPDoubleComplex*)r.vals, 2, len);
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        // Scale result
        if constexpr (Dir == kFFTDirection_Inverse) {
            r /= std::complex<Float>(len);
        }
        
        return r;
    }
    
public:
    
    T vals[H*W] = {}; // Column-major order
    static constexpr size_t h = H;
    static constexpr size_t w = W;
    static constexpr size_t rows = H;
    static constexpr size_t cols = W;
    
private:
    template <typename Float>
    class FFTSetup {
    public:
        FFTSetup() {
            if constexpr (std::is_same_v<Float,float>) {
                _s = vDSP_create_fftsetup(_Log2(std::max(H,W)), kFFTRadix2);
            } else if constexpr (std::is_same_v<Float, double>) {
                _s = vDSP_create_fftsetupD(_Log2(std::max(H,W)), kFFTRadix2);
            } else {
                static_assert(_AlwaysFalse<Float>);
            }
            assert(_s);
        }
        
        // Copy constructor: illegal
        FFTSetup(const FFTSetup& x) = delete;
        // Move constructor: illegal
        FFTSetup(FFTSetup&& x) = delete;
        
        ~FFTSetup() {
            if constexpr (std::is_same_v<Float,float>)
                vDSP_destroy_fftsetup((::FFTSetup)_s);
            else if constexpr (std::is_same_v<Float,double>)
                vDSP_destroy_fftsetupD((::FFTSetupD)_s);
            else
                static_assert(_AlwaysFalse<Float>);
        }
        
        template<
        typename _Float = Float,
        typename std::enable_if_t<std::is_same_v<_Float,float>, int> = 0>
        operator ::FFTSetup() { return (::FFTSetup)_s; }
        
        template<
        typename _Float = Float,
        typename std::enable_if_t<std::is_same_v<_Float,double>, int> = 0>
        operator ::FFTSetupD() { return (::FFTSetupD)_s; }
    
    private:
        void* _s = nullptr;
    };
    
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

#pragma once
#import <Accelerate/Accelerate.h>
#import <type_traits>
#import <iostream>

template <typename T, size_t H, size_t W>
class Mat {
public:
    Mat() {
        if constexpr (std::is_same_v<_Storage, _StorageInline>) {
            vals = _storage;
        } else {
            _storage = std::make_unique<T[]>(Count);
            vals = _storage.get();
        }
    }
    
//    Mat(const T v[]) : Mat() {
//        std::copy(v, v+Count, vals);
//        _transVals(); // Transpose `vals` to put in column-major order
//    }
//    
//    Mat(T v[]) : Mat() {
//        std::copy(v, v+Count, vals);
//        _transVals(); // Transpose `vals` to put in column-major order
//    }
    
    template <typename... Ts>
    Mat(Ts... ts) : Mat() {
        static_assert(sizeof...(ts)==Count, "invalid number of values");
        _load(0, ts...);
    }
    
    // Copy constructor: use copy assignment operator
    Mat(const Mat& x) : Mat() { *this = x; }
    // Copy assignment operator
    Mat& operator=(const Mat& x) {
        std::copy(x.vals, x.vals+Count, vals);
        return *this;
    }
    
    // Move constructor: illegal
    Mat(Mat&& x) = delete;
    // Move assignment operator: illegal
    Mat& operator=(Mat&& x) = delete;
    
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
                (int)a.Rows, (int)b.Cols, (int)a.Cols,
                1, // alpha
                a.vals, (int)a.Rows,
                b.vals, (int)b.Rows,
                0, // beta
                r.vals, (int)r.Rows
            );
        else if constexpr (std::is_same_v<T, double>)
            cblas_dgemm(
                CblasColMajor, CblasNoTrans, CblasNoTrans,
                (int)a.Rows, (int)b.Cols, (int)a.Cols,
                1, // alpha
                a.vals, (int)a.Rows,
                b.vals, (int)b.Rows,
                0, // beta
                r.vals, (int)r.Rows
            );
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise multiply
    Mat<T,H,W> elmMul(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        // There's apparently no BLAS function to do element-wise vector multiplication
        for (size_t i=0; i<Count; i++) {
            r.vals[i] *= x.vals[i];
        }
        return r;
    }
    
    // Element-wise multiply-assign
    Mat<T,H,W>& elmMulEq(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        // There's apparently no BLAS function to do element-wise vector multiplication
        for (size_t i=0; i<Count; i++) {
            r.vals[i] *= x.vals[i];
        }
        return r;
    }
    
    // Scalar multiply
    Mat<T,H,W> operator*(const T& x) const {
        Mat<T,H,W> r = *this;
        if constexpr (std::is_same_v<T, float>)
            cblas_sscal(Count, x, r.vals, 1);
        else if constexpr (std::is_same_v<T, double>)
            cblas_dscal(Count, x, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise divide
    Mat<T,H,W> elmDiv(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        // There's apparently no BLAS function to do element-wise vector division
        for (size_t i=0; i<Count; i++) {
            r.vals[i] /= x.vals[i];
        }
        return r;
    }
    
    // Scalar divide
    Mat<T,H,W> operator/(const T& x) const {
        Mat<T,H,W> r = *this;
        if constexpr (std::is_same_v<T, float>) {
            cblas_sscal(Count, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            cblas_dscal(Count, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> k(T(1)/x);
            cblas_cscal(Count, &k, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> k(T(1)/x);
            cblas_zscal(Count, &k, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Scalar divide-assign
    Mat<T,H,W>& operator/=(const T& x) {
        Mat<T,H,W>& r = *this;
        if constexpr (std::is_same_v<T, float>) {
            cblas_sscal(Count, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            cblas_dscal(Count, T(1)/x, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> k(T(1)/x);
            cblas_cscal(Count, &k, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> k(T(1)/x);
            cblas_zscal(Count, &k, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Element-wise add
    Mat<T,H,W> operator+(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        if constexpr (std::is_same_v<T, float>) {
            catlas_saxpby(Count, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            catlas_daxpby(Count, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> one(1);
            catlas_caxpby(Count, &one, x.vals, 1, &one, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> one(1);
            catlas_zaxpby(Count, &one, x.vals, 1, &one, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Element-wise add-assign
    Mat<T,H,W>& operator+=(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        if constexpr (std::is_same_v<T, float>) {
            catlas_saxpby(Count, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, double>) {
            catlas_daxpby(Count, 1, x.vals, 1, 1, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            const std::complex<float> one(1);
            catlas_caxpby(Count, &one, x.vals, 1, &one, r.vals, 1);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            const std::complex<double> one(1);
            catlas_zaxpby(Count, &one, x.vals, 1, &one, r.vals, 1);
        } else {
            static_assert(_AlwaysFalse<T>);
        }
        return r;
    }
    
    // Scalar add
    Mat<T,H,W> operator+(const T& x) const {
        Mat<T,H,W> r = *this;
        for (size_t i=0; i<Count; i++) r.vals[i] += x;
        return r;
    }
    
    // Scalar add-assign
    Mat<T,H,W> operator+=(const T& x) {
        Mat<T,H,W>& r = *this;
        for (size_t i=0; i<Count; i++) r.vals[i] += x;
        return r;
    }
    
    // Element-wise subtract
    Mat<T,H,W> operator-(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r = *this;
        if constexpr (std::is_same_v<T, float>)
            catlas_saxpby(Count, 1, x.vals, 1, -1, r.vals, 1);
        else if constexpr (std::is_same_v<T, double>)
            catlas_daxpby(Count, 1, x.vals, 1, -1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Element-wise subtract-assign
    Mat<T,H,W>& operator-=(const Mat<T,H,W>& x) {
        Mat<T,H,W>& r = *this;
        if constexpr (std::is_same_v<T, float>)
            catlas_saxpby(Count, 1, x.vals, 1, -1, r.vals, 1);
        else if constexpr (std::is_same_v<T, double>)
            catlas_daxpby(Count, 1, x.vals, 1, -1, r.vals, 1);
        else
            static_assert(_AlwaysFalse<T>);
        return r;
    }
    
    // Scalar subtract
    Mat<T,H,W> operator-(const T& x) const {
        Mat<T,H,W> r = *this;
        for (size_t i=0; i<Count; i++) r.vals[i] -= x;
        return r;
    }
    
    // Scalar subtract-assign
    Mat<T,H,W> operator-=(const T& x) {
        Mat<T,H,W>& r = *this;
        for (size_t i=0; i<Count; i++) r.vals[i] -= x;
        return r;
    }
    
    T& operator[](size_t i) {
        static_assert(H==1 || W==1, "not a vector");
        return vals[i];
    }
    
    const T& operator[](size_t i) const {
        static_assert(H==1 || W==1, "not a vector");
        return vals[i];
    }
    
    T& at(size_t i) {
        static_assert(H==1 || W==1, "not a vector");
        assert(i < Count);
        return vals[i];
    }
    
    const T& at(size_t i) const {
        static_assert(H==1 || W==1, "not a vector");
        assert(i < Count);
        return vals[i];
    }
    
    T& at(size_t y, size_t x) {
        assert(y < H);
        assert(x < W);
        return vals[x*H+y]; // `vals` is in column-major format
    }
    
    const T& at(size_t y, size_t x) const {
        assert(y < H);
        assert(x < W);
        return vals[x*H+y]; // `vals` is in column-major format
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
    
    void print() {
        std::cout << str(3) << "\n";
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
    
    T sum() const {
        T r{};
        for (const T& x : *this) r += x;
        return r;
    }
    
    Mat<T,1,W> sumCols() const {
        Mat<T,1,W> r;
        for (size_t x=0; x<W; x++) {
            double s = 0;
            for (size_t y=0; y<H; y++) s += at(y,x);
            r[x] = s;
        }
        return r;
    }
    
    Mat<T,H,1> sumRows() const {
        Mat<T,H,1> r;
        for (size_t y=0; y<H; y++) {
            double s = 0;
            for (size_t x=0; x<W; x++) s += at(y,x);
            r[y] = s;
        }
        return r;
    }
    
    auto fft() {
        return _fft<kFFTDirection_Forward>();
    }
    
    auto ifft() {
        return _fft<kFFTDirection_Inverse>();
    }
    
    // Iteration
    auto begin() {
        if constexpr (std::is_same_v<_Storage, _StorageInline>) {
            return _storage;
        } else {
            return _storage.get();
        }
    }
    
    auto end() {
        if constexpr (std::is_same_v<_Storage, _StorageInline>) {
            return _storage+Count;
        } else {
            return _storage.get()+Count;
        }
    }
    
    auto begin() const {
        if constexpr (std::is_same_v<_Storage, _StorageInline>) {
            return _storage;
        } else {
            return _storage.get();
        }
    }
    
    auto end() const {
        if constexpr (std::is_same_v<_Storage, _StorageInline>) {
            return _storage+Count;
        } else {
            return _storage.get()+Count;
        }
    }
    
private:
    using Float = std::conditional_t<
        std::is_same_v<T,float>||std::is_same_v<T,std::complex<float>>,
        float, double
    >;
    
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
    
//    // FFT (Real -> Complex)
//    template<
//    int Dir, // kFFTDirection_Forward or kFFTDirection_Inverse
//    typename _T = T,
//    typename std::enable_if_t<_DimsPowerOf2, int> = 0,
//    typename std::enable_if_t<std::is_same_v<_T,float>||std::is_same_v<_T,double>, int> = 0
//    >
//    Mat<std::complex<T>,H,W> _fft() {
//        using Float = T;
//        constexpr size_t len = (H*(W/2));
//        Mat<std::complex<Float>,H,W> r;
//        FFTSetup<Float> s;
//        
//        auto outr = std::make_unique<Float[]>(len);
//        auto outi = std::make_unique<Float[]>(len);
//        
//        // Separate the real/imaginary parts into `inr/ini`
//        if constexpr (std::is_same_v<Float, float>) {
//            vDSP_ctoz((const DSPComplex*)vals, 2, (DSPSplitComplex[]){outr.get(),outi.get()}, 1, len);
//        } else if constexpr (std::is_same_v<Float, double>) {
//            vDSP_ctozD((const DSPDoubleComplex*)vals, 2, (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, len);
//        } else {
//            static_assert(_AlwaysFalse<Float>);
//        }
//        
//        // Perform 2D FFT
//        if constexpr (std::is_same_v<Float, float>) {
//            vDSP_fft2d_zrip(s,
//                (DSPSplitComplex[]){outr.get(),outi.get()}, 1, 0,   // Output
//                _Log2(W), _Log2(H),                                 // Dimensions
//                Dir
//            );
//        } else if constexpr (std::is_same_v<Float, double>) {
//            vDSP_fft2d_zripD(s,
//                (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, 0, // Output
//                _Log2(W), _Log2(H),                                     // Dimensions
//                Dir
//            );
//        } else {
//            static_assert(_AlwaysFalse<Float>);
//        }
//        
//        for (size_t i=0; i<len; i++) {
//            printf("%f %f\n", outr[i]/2, outi[i]/2);
//        }
//        exit(0);
//        
//        // Join the real/imaginary parts into `r.vals`
//        if constexpr (std::is_same_v<Float, float>) {
//            vDSP_ztoc((DSPSplitComplex[]){outr.get(),outi.get()}, 1, (DSPComplex*)r.vals, 2, len);
//        } else if constexpr (std::is_same_v<Float, double>) {
//            vDSP_ztocD((DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, (DSPDoubleComplex*)r.vals, 2, len);
//        } else {
//            static_assert(_AlwaysFalse<Float>);
//        }
//        
//        if constexpr (Dir == kFFTDirection_Forward) {
//            // Normalize based on the length
//            r /= std::complex<Float>(2);
//        
//        } else if constexpr (Dir == kFFTDirection_Inverse) {
//            // Normalize based on the length
//            r /= std::complex<Float>(len);
//        }
//        
//        return r;
//    }
    
    // FFT
    template<
    int Dir, // kFFTDirection_Forward or kFFTDirection_Inverse
    bool __DimsPowerOf2 = _DimsPowerOf2,
    typename std::enable_if_t<__DimsPowerOf2, int> = 0
    >
    Mat<std::complex<Float>,H,W> _fft() {
        constexpr size_t len = Count;
        Mat<std::complex<Float>,H,W> r;
        FFTSetup<Float> s;
        
        auto outr = std::make_unique<Float[]>(len);
        auto outi = std::make_unique<Float[]>(len);
        
        // Separate the real/imaginary parts into `outr/outi`
        if constexpr (std::is_same_v<T, float> || std::is_same_v<T, double>) {
            // We only have real values, so only copy those, and leave `outi` zero'd
            std::copy(vals, vals+Count, outr.get());
        } else if constexpr (std::is_same_v<T, std::complex<float>>) {
            vDSP_ctoz((const DSPComplex*)vals, 2, (DSPSplitComplex[]){outr.get(),outi.get()}, 1, len);
        } else if constexpr (std::is_same_v<T, std::complex<double>>) {
            vDSP_ctozD((const DSPDoubleComplex*)vals, 2, (DSPDoubleSplitComplex[]){outr.get(),outi.get()}, 1, len);
        } else {
            static_assert(_AlwaysFalse<Float>);
        }
        
        // Perform 2D FFT
        // We're using the complex->complex FFT implementation (vDSP_fft2d_zip / vDSP_fft2d_zipD)
        // instead of the real->complex one (vDSP_fft2d_zrip / vDSP_fft2d_zripD), even though
        // the latter would be faster when the input data only contains real numbers.
        // This is because the real->complex version uses some strange output packing format
        // that I haven't been able to decipher and translate to the same format that MATLAB
        // uses. See "Data Packing for Real FFTs":
        //   https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html
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
    
    T* vals = nullptr; // Column-major order
    static constexpr size_t Height = H;
    static constexpr size_t Width = W;
    static constexpr size_t Rows = H;
    static constexpr size_t Cols = W;
    static constexpr size_t Count = H*W;
    using ValueType = T;
    
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
    
    void _load(size_t idx) {}
    
    // Load a parameter pack of elements (in row-major order), into `vals` (which is column-major order)
    template <typename... Ts>
    void _load(size_t idx, T& t, Ts&... ts) {
        constexpr size_t LastIdx = Count-1;
        vals[idx] = t;
        
        const size_t rem = LastIdx-idx;
        if (!rem)           ;               // Done
        else if (rem < H)   idx = H-rem;    // Return to first column and increment the row
        else                idx += H;       // Go to next column
        _load(idx, ts...);
    }
    
//    void _transVals() {
//        // Transpose `vals`
//        // Create a temporary copy of `vals`
//        auto valsConst = std::make_unique<T[]>(Count);
//        std::copy(vals, vals+Count, valsConst.get());
//        
//        for (size_t y=0, i=0; y<H; y++) {
//            for (size_t x=0; x<W; x++, i++) {
//                at(y,x) = valsConst[i];
//            }
//        }
//    }
    
    using _StorageInline = T[Count];
    using _StorageHeap = std::unique_ptr<T[]>;
    using _Storage = std::conditional_t<Count*sizeof(T) < 128, _StorageInline, _StorageHeap>;
    _Storage _storage;
};

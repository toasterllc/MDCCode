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
    
//    // Moore-Penrose inverse
//    Mat<T,W,H> pinv() const {
//        Mat<T,H,H> r = *this;
//        Mat<T,H,H> u;
//        Mat<T,1,std::min(H,W)> sigmadiag;
//        Mat<T,W,W> vt;
//        __CLPK_integer h = H;
//        __CLPK_integer w = W;
//        T work[4*(W*H)*(W*H)+6*(W*H)+std::max(H,W)]; // Recommended size from docs
//        __CLPK_integer lwork = std::size(work);
//        __CLPK_integer iwork[8*std::min(H,W)];
//        __CLPK_integer err = 0;
//        
//        // Perform singular value decomposition (SVD)
//        dgesdd_((char*)"A", &h, &w,
//            r.vals, &h,
//            sigmadiag.vals,
//            u.vals, &h,
//            vt.vals, &w,
//            work, &lwork, iwork, &err
//        );
//        
//        if (err) throw std::runtime_error("dgesdd_ failed");
//        
//        // TODO: set small values in `sigmadiag` to zero
//        
//        for (T& val : sigmadiag.vals) {
//            if (val > 0) {
//                val = T(1)/val;
//            }
//        }
//        
//        // TODO: finish writing
//        // TODO: see:
//        //   https://www.johndcook.com/blog/2018/05/05/svd/
//        //   https://math.stackexchange.com/questions/75789/what-is-step-by-step-logic-of-pinv-pseudoinverse
//        
////        if constexpr(std::is_same_v<T, float>)
////            sgesdd_((char*)"A", &m, &n, r.vals, &m, sigma.vals, u.vals, &m, vt.vals, &n, work, &lwork, iwork, &info);
////        else if constexpr(std::is_same_v<T, double>)
////            dgesdd_((char*)"A", &m, &n, r.vals, &m, sigma.vals, u.vals, &m, vt.vals, &n, work, &lwork, iwork, &info);
////        else
////            static_assert(_AlwaysFalse<T>);
////        return r;
//        
//        return (trans()*(*this)).inv()*trans();
//    }
//    
//    // Weighted Moore-Penrose inverse
//    Mat<T,W,H> pinv(const Mat<T,H,1>& wts) const {
//        Mat<T,H,H> w;
//        for (size_t i=0; i<H; i++) {
//            w.at(i,i) = wts[i];
//        }
//        return (trans()*w*(*this)).inv()*trans()*w;
//    }
    
    // Matrix multiply
    template <size_t N>
    Mat<T,H,N> operator*(const Mat<T,W,N>& x) const {
        Mat<T,H,N> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_mmul(vals, 1, x.vals, 1, r.vals, 1, H, N, W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_mmulD(vals, 1, x.vals, 1, r.vals, 1, H, N, W);
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
    
    // Element-wise add
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
    
    // Element-wise subtract
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
    
    // Element-wise divide
    Mat<T,H,W> operator/(const Mat<T,H,W>& x) const {
        Mat<T,H,W> r;
        if constexpr(std::is_same_v<T, float>)
            vDSP_vdiv(x.vals, 1, vals, 1, r.vals, 1, H*W);
        else if constexpr(std::is_same_v<T, double>)
            vDSP_vdivD(x.vals, 1, vals, 1, r.vals, 1, H*W);
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
    
    
    // Solve `Ax=b` for x, where the receiver is A
    template <size_t N>
    Mat<T,W,N> solve(const Mat<T,H,N>& bconst) const {
        static_assert(H>=W, "matrix size must have H >= W");
        __CLPK_integer m = H;
        __CLPK_integer n = (__CLPK_integer)W;
        __CLPK_integer nrhs = N;
        __CLPK_integer lda = m;
        __CLPK_integer ldb = m;
        Mat<T,W,H> A = trans(); // LAPACK requires column-major order
        Mat<T,N,H> bx = bconst.trans(); // LAPACK requires column-major order
        __CLPK_integer err = 0;
        
        T work[1024] = {};
        __CLPK_integer lwork = std::size(work);
        if constexpr(std::is_same_v<T, float>)
            sgels_((char*)"N", &m, &n, &nrhs,
                A.vals, &lda,
                bx.vals, &ldb,
                work, &lwork, &err
            );
            
        else if constexpr(std::is_same_v<T, double>)
            dgels_((char*)"N", &m, &n, &nrhs,
                A.vals, &lda,
                bx.vals, &ldb,
                work, &lwork, &err
            );
        
        else
            static_assert(_AlwaysFalse<T>);
        
        if (err) throw std::runtime_error("failed to solve");
        return Mat<T,W,N>(bx.vals);
    }
    
    
//    // Solve `Ax=b` for x, where the receiver is A
//    template <size_t N>
//    Mat<T,W,N> solve(const Mat<T,H,N>& bconst) const {
//        static_assert(H>=W, "matrix size must have H >= W");
//        // 2 iterations: first iteration gets the size of `work`,
//        // second iteration performs calculation
//        __CLPK_integer lwork = -1;
//        for (__CLPK_integer i=0; i<2; i++) {
//            __CLPK_integer m = H;
//            __CLPK_integer n = (__CLPK_integer)w;
//            __CLPK_integer nrhs = N;
//            __CLPK_integer lda = m;
//            __CLPK_integer ldb = m;
//            
////            __CLPK_integer h = H;
////            __CLPK_integer w = W;
////            __CLPK_integer nrhs = N;
////            __CLPK_integer ldb = H;
//            __CLPK_integer jpvt[W] = {};
//            __CLPK_integer rank = 0;
//    //        T rcond = .1;
//            T rcond = std::numeric_limits<T>::epsilon();
//            Mat<T,H,W> A = *this;
//            Mat<T,H,N> bx = bconst;
//            __CLPK_integer err = 0;
//            
//            T work[std::max(1,lwork)];
//            memset(work, 0, std::max(1,lwork)*sizeof(T));
//            if constexpr(std::is_same_v<T, float>)
//                sgelsy_(&m, &n, &nrhs, A.vals, &lda, bx.vals, &ldb, jpvt, &rcond,
//                    &rank, work, &lwork, &err);
//            else if constexpr(std::is_same_v<T, double>)
//                dgelsy_(&m, &n, &nrhs, A.vals, &lda, bx.vals, &ldb, jpvt, &rcond,
//                    &rank, work, &lwork, &err);
//            else
//                static_assert(_AlwaysFalse<T>);
//            
//            if (err) throw std::runtime_error("failed to solve");
//            lwork = work[0];
//            if (i) return Mat<T,W,N>(bx.vals);
//        }
//        exit(0);
//    }
    
    // Solve `Ax=b` for x, where the receiver is A
    Mat<T,H,1> solve2(const Mat<T,H,1>& bb) const {
        static_assert(H==W, "matrix must be square");
        Mat<T,H,W> A = *this;
        Mat<T,H,1> b = bb;
        Mat<T,H,1> x;
        for (size_t y=0; y<H-1; y++) {
            // Find the row with the max element
            T maxElm = std::fabs(A.at(y,y));
            size_t maxElmY = y;
            for (size_t i=y+1; i<H; i++) {
                if (std::fabs(A.at(i,y)) > maxElm) {
                    maxElm = A.at(i,y);
                    maxElmY = i;
                }
            }
            
            // Swap the two rows if needed
            if (maxElmY != y) {
                for (size_t i=y; i<H; i++) {
                    std::swap(A.at(y,i), A.at(maxElmY,i));
                }
                std::swap(b[y], b[maxElmY]);
            }
            
            if (A.at(y,y) == 0) {
                throw std::runtime_error("failed to solve");
            }
            
            // Forward substitution
            for (size_t j=y+1; j<H; j++) {
                const T k = -A.at(j,y) / A.at(y,y);
                for (size_t i=y; i<H; i++) {
                    A.at(j,i) += k*A.at(y,i);
                }
                b[j] += k*b[y];
            }
        }
        
        // Backward substitution
        for (size_t y=H-1;; y--) {
            x[y] = b[y];
            
            for (size_t i=y+1; i<H; i++) {
                x[y] -= A.at(y,i)*x[i];
            }
            
            x[y] /= A.at(y,y);
            if (!y) break;
        }
        return x;
    }
    
//    T norm() const {
//        __CLPK_integer m = H;
//        __CLPK_integer n = W;
//        if constexpr(std::is_same_v<T, float>)
//            return slange_((char*)"1", &m, &n, vals, &m, nullptr);
//        else if constexpr(std::is_same_v<T, double>)
//            return dlange_((char*)"1", &m, &n, (T*)vals, &m, nullptr);
//        else
//            static_assert(_AlwaysFalse<T>);
//    }
    
//    static float rcondf() {
//        return 1./(norm() * inv().norm());
//    }
//    
//    static double rcond() {
//        return 1./(norm() * inv().norm());
//    }
    
//    T rcond() const {
//        return rcond(inv());
//    }
//    
//    // Optimized rcond() version, in case the inverse has already been calculated
//    T rcond(const Mat<T,H,W>& inverse) const {
//        return T(1)/(norm() * inverse.norm());
//    }
    
    
//    // RCOND
//    T rcond() const {
//        Mat<T,H,H> lufact = *this;
//        __CLPK_integer m = H;
//        __CLPK_integer n = W;
//        __CLPK_integer err = 0;
//        __CLPK_integer pivot[m];
//        T tmp[m];
//        if constexpr(std::is_same_v<T, float>) {
//            T norm1 = slange_("1", &m, &n, vals, &m, nullptr);
//            
//            sgetrf_(&m, &m, lufact.vals, &m, pivot, &err);
//            if (err) throw std::runtime_error("sgetrf_ failed");
//            
//            sgecon_("1", &m, lufact.vals, &n, &norm1, <#__CLPK_real *__rcond#>, <#__CLPK_real *__work#>, <#__CLPK_integer *__iwork#>, <#__CLPK_integer *__info#>)
//        
//        } else if constexpr(std::is_same_v<T, double>) {
//            dgetrf_(&m, &m, r.vals, &m, pivot, &err);
//            if (err) throw std::runtime_error("dgetrf_ failed");
//            
//            
//        
//        } else {
//            static_assert(_AlwaysFalse<T>);
//        }
//        return r;
//    }
    
    T& operator[](size_t i) {
        return vals[i];
    }
    
    const T& operator[](size_t i) const {
        return vals[i];
    }
    
    T& at(size_t i) {
        assert(i < std::size(vals));
        return vals[i];
    }
    
    const T& at(size_t i) const {
        assert(i < std::size(vals));
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
    const size_t h = H;
    const size_t w = W;
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse;
};

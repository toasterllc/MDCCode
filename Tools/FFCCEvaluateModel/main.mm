#import <Foundation/Foundation.h>
#import <filesystem>
#import <complex>
#import "Mat.h"
#import "/Applications/MATLAB_R2021a.app/extern/include/mat.h"
namespace fs = std::filesystem;

using Mat64 = Mat<double,64,64>;
using Mat64c = Mat<std::complex<double>,64,64>;

MATFile* W_EM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-EvaluateModel.mat", "r");
MATFile* W_FBVM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FitBivariateVonMises.mat", "r");

struct FFCCModel {
    struct Params {
        struct {
            double vonMisesDiagonalEps = 0;
        } hyperparams;
        
        struct {
            double binSize = 0;
            double startingUV = 0;
        } histogram;
    };
    
    Params params;
    Mat64c F_fft[2];
    Mat64 B;
};

template <typename T, size_t H, size_t W, size_t Depth>
bool _equal(const Mat<T,H,W>* a, const Mat<T,H,W>* b) {
    constexpr double Eps = 1e-6;
    for (size_t z=0, i=0; z<Depth; z++) {
        for (size_t x=0; x<W; x++) {
            for (size_t y=0; y<H; y++, i++) {
                if (std::abs(a[z].at(y,x) - b[z].at(y,x)) > Eps) {
                    return false;
                }
            }
        }
    }
    return true;
}

template <typename T, size_t H, size_t W, size_t Depth>
bool equal(const Mat<T,H,W> (&a)[Depth], const Mat<T,H,W> (&b)[Depth]) {
    return _equal<T,H,W,Depth>(a, b);
}

template <typename T, size_t H, size_t W>
bool equal(const Mat<T,H,W>& a, const Mat<T,H,W>& b) {
    return _equal<T,H,W,1>(&a, &b);
}

template <typename T, size_t H, size_t W, size_t Depth>
bool equal(MATFile* f, const Mat<T,H,W> (&a)[Depth], const char* name) {
    Mat<T,H,W> b[Depth];
    load(f, name, b);
    return equal(a, b);
}

template <typename T, size_t H, size_t W>
bool equal(MATFile* f, const Mat<T,H,W>& a, const char* name) {
    Mat<T,H,W> b;
    load(f, name, b);
    return equal(a, b);
}

template <typename T>
bool equal(MATFile* f, const T& a, const char* name) {
    Mat<T,1,1> A(a);
    Mat<T,1,1> B;
    load(f, name, B);
    return equal(A, B);
}

template <typename T, size_t H, size_t W, size_t Depth>
void _load(MATFile* f, const char* name, Mat<T,H,W>* var) {
    mxArray* mxa = matGetVariable(f, name);
    assert(mxa);
    
    // Verify that the source and destination are both complex, or both not complex
    constexpr bool complex = std::is_same<T, std::complex<double>>::value;
    assert(mxIsComplex(mxa) == complex);
    const T* vals = (complex ? (T*)mxGetComplexDoubles(mxa) : (T*)mxGetDoubles(mxa));
    assert(vals);
    const mwSize dimCount = mxGetNumberOfDimensions(mxa);
    assert(dimCount==2 || dimCount==3);
    const mwSize* dims = mxGetDimensions(mxa);
    assert(dims[0] == H);
    assert(dims[1] == W);
    assert((dimCount==3 ? dims[2] : 1) == Depth);
    for (size_t z=0, i=0; z<Depth; z++) {
        // MATLAB stores in column-major order, so before going to the next column (x++),
        // iterate over all elements in the current column (y++)
        for (size_t x=0; x<W; x++) {
            for (size_t y=0; y<H; y++, i++) {
                (var[z]).at(y,x) = vals[i];
            }
        }
    }
}

template <typename T, size_t H, size_t W, size_t Depth>
void load(MATFile* f, const char* name, Mat<T,H,W> (&var)[Depth]) {
    _load<T,H,W,Depth>(f, name, var);
}

template <typename T, size_t H, size_t W>
void load(MATFile* f, const char* name, Mat<T,H,W>& var) {
    _load<T,H,W,1>(f, name, &var);
}

template <typename T>
void load(MATFile* f, const char* name, T& var) {
    Mat<T,1,1> m;
    _load<T,1,1,1>(f, name, &m);
    var = m[0];
}

// modulo function that matches MATLAB's implementation
// C fmod and MATLAB mod are the same for 
template <typename T>
T mod(T a, T b) {
    if (b == 0) return a; // Definition of MATLAB mod()
    const T r = std::fmod(a, b);
    if (r == 0) return 0;
    // If the sign of the remainder doesn't match the divisor,
    // add the divisor to make the signs match.
    if ((r > 0) != (b > 0)) return r+b;
    return r;
}

struct VecSigma {
    Mat<double,2,1> vec;
    Mat<double,2,2> sigma;
};

static VecSigma UVFromIdx(const FFCCModel& model, const VecSigma& idx) {
    return VecSigma{
        .vec = ((idx.vec-1)*model.params.histogram.binSize) + model.params.histogram.startingUV,
        .sigma = idx.sigma * (model.params.histogram.binSize * model.params.histogram.binSize),
    };
}

Mat<double,3,1> RGBFromUV(const Mat<double,2,1>& uv) {
    Mat<double,3,1> rgb(std::exp(-uv[0]), 1., std::exp(-uv[1]));
    rgb /= sqrt(rgb.elmMul(rgb).sum());
    return rgb;
}

static VecSigma fitBivariateVonMises(const Mat64& P) {
    constexpr size_t H = Mat64::Height;
    // Given a 2D PDF histogram (PMF), approximately fits a bivariate Von Mises
    // distribution to that PDF by computing the local moments. This produces a
    // center of mass of the PDF, where the PDF is assumed to lie on a torus rather
    // than a cartesian space.
    // 
    // Outputs:
    //   mu - the 2D location of the center of the bivariate Von Mises distribution,
    //        which is in 1-indexed coordinates of the input PDF P.
    //   Sigma - The covariance matrix which was used to compute "confidence".
    const size_t n = H;
    
    const double angleStep = (2*M_PI) / n;
    Mat<double,H,1> angles;
    double angle = 0;
    for (double& x : angles.vals) {
        x = angle;
        angle += angleStep;
    }
    
    // Fit the mean of the distribution by finding the first moments of of the
    // histogram on both axes, which can be done by finding the first moment of the
    // sin and cosine of both axes and computing the arctan. Taken from Section 6.2
    // of "Bayesian Methods in Structural Bioinformatics", but adapted to a
    // histogram. This process can be optimized by computing the rowwise and
    // columnwise sums of P and finding the moments on each axis independently.
    Mat<double,H,1> P1 = P.sumRows();
    Mat<double,H,1> P2 = P.sumCols().trans();
    
    assert(equal(W_FBVM, P1, "P1"));
    assert(equal(W_FBVM, P2, "P2"));
    
    Mat<double,H,1> sinAngles;
    Mat<double,H,1> cosAngles;
    for (size_t i=0; i<std::size(angles.vals); i++) {
        sinAngles[i] = sin(angles[i]);
        cosAngles[i] = cos(angles[i]);
    }
    
    const double y1 = P1.elmMul(sinAngles).sumCols()[0];
    const double x1 = P1.elmMul(cosAngles).sumCols()[0];
    const double y2 = P2.elmMul(sinAngles).sumCols()[0];
    const double x2 = P2.elmMul(cosAngles).sumCols()[0];
    assert(equal(W_FBVM, y1, "y1"));
    assert(equal(W_FBVM, x1, "x1"));
    assert(equal(W_FBVM, y2, "y2"));
    assert(equal(W_FBVM, x2, "x2"));
    
    const double mu1 = mod(std::atan2(y1,x1), 2*M_PI) / angleStep;
    const double mu2 = mod(std::atan2(y2,x2), 2*M_PI) / angleStep;
    assert(equal(W_FBVM, mu1, "mu1"));
    assert(equal(W_FBVM, mu2, "mu2"));
    
    #warning we probably want to remove this +1 since our indexing is 0-based, not 1-based
    const Mat<double,2,1> mu(mu1+1, mu2+1); // 1-indexing
    assert(equal(W_FBVM, mu, "mu"));
    
    // Fit the covariance matrix of the distribution by finding the second moments
    // of the angles with respect to the mean. This can be done straightforwardly
    // using the definition of variance, provided that the distance from the mean
    // is the minimum distance on the torus. This can become innacurate if the true
    // distribution is very large with respect to the size of the histogram.
    
    Mat<double,H,1> bins;
    for (size_t i=0; i<std::size(bins.vals); i++) {
        bins[i] = i+1;
    }
    
    auto wrap = [](double x) {
        return mod(x+(H/2)-1, (double)H)+1;
    };
    
    Mat<double,H,1> wrapped1;
    Mat<double,H,1> wrapped2;
    for (size_t i=0; i<std::size(wrapped1.vals); i++) {
        wrapped1[i] = wrap(bins[i]-round(mu[0]));
        wrapped2[i] = wrap(bins[i]-round(mu[1]));
    }
    
    assert(equal(W_FBVM, wrapped1, "wrapped1"));
    assert(equal(W_FBVM, wrapped2, "wrapped2"));
    
    const double E1 = P1.elmMul(wrapped1).sumCols()[0];
    const double E2 = P2.elmMul(wrapped2).sumCols()[0];
    
    assert(equal(W_FBVM, E1, "E1"));
    assert(equal(W_FBVM, E2, "E2"));
    
    const double Sigma1 = P1.elmMul(wrapped1.elmMul(wrapped1)).sum() - (E1*E1);
    const double Sigma2 = P2.elmMul(wrapped2.elmMul(wrapped2)).sum() - (E2*E2);
    const double Sigma12 = P.elmMul(wrapped1*wrapped2.trans()).sum() - (E1*E2);
    
    assert(equal(W_FBVM, Sigma1, "Sigma1"));
    assert(equal(W_FBVM, Sigma2, "Sigma2"));
    assert(equal(W_FBVM, Sigma12, "Sigma12"));
    
    Mat<double,2,2> Sigma(
        Sigma1, Sigma12,
        Sigma12, Sigma2
    );
    
    assert(equal(W_FBVM, Sigma, "Sigma"));
    
    return VecSigma{mu, Sigma};
}

static Mat64 softmaxForward(const Mat64& H) {
    Mat64 r = H;
    // Find the max value in `r`
    double maxVal = -INFINITY;
    for (double x : r.vals) maxVal = std::max(maxVal, x);
    // Subtract `maxVal` from every element
    r -= maxVal;
    // Raise e to each element in `r`
    for (double& x : r.vals) x = std::exp(x);
    // Sum all elements
    double sum = 0;
    for (double x : r.vals) sum += x;
    // Normalize `r` using the sum
    for (double& x : r.vals) x /= sum;
    return r;
}

static Mat<double,3,1> ffccEstimateIlluminant(
    const FFCCModel& model,
    const Mat64 X[2],
    const Mat64c X_fft[2]
) {
    Mat64c X_fft_Times_F_fft[2] = { X_fft[0].elmMul(model.F_fft[0]), X_fft[1].elmMul(model.F_fft[1]) };
    Mat64c FX_fft = X_fft_Times_F_fft[0] + X_fft_Times_F_fft[1];
    assert(equal(W_EM, FX_fft, "FX_fft"));
    
    Mat64c FXc = FX_fft.ifft();
    Mat64 FX;
    for (size_t i=0; i<std::size(FXc.vals); i++) {
        FX.vals[i] = FXc.vals[i].real();
    }
    assert(equal(W_EM, FX, "FX"));
    
    Mat64 H = FX+model.B;
    assert(equal(W_EM, H, "H"));
    
    Mat64 P = softmaxForward(H);
    assert(equal(W_EM, P, "P"));
    
    const VecSigma fit = fitBivariateVonMises(P);
    
    const Mat<double,2,2> VonMisesDiagEps(
        model.params.hyperparams.vonMisesDiagonalEps, 0.,
        0., model.params.hyperparams.vonMisesDiagonalEps
    );
    
    const VecSigma idx = {
        .vec = fit.vec,
        .sigma = fit.sigma + VonMisesDiagEps,
    };
    
    assert(equal(W_EM, idx.vec, "mu_idx"));
    assert(equal(W_EM, idx.sigma, "Sigma_idx"));
    
    const VecSigma uv = UVFromIdx(model, idx);
    return RGBFromUV(uv.vec);
}

static void processFile(const fs::path& path) {
    
}

static bool isPNGFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".png";
}

int main(int argc, const char* argv[]) {
    FFCCModel model = {
        .params = {
            .hyperparams = {
                .vonMisesDiagonalEps = 0.148650889375340,    // std::pow(2, -2.75)
            },
            
            .histogram = {
                .binSize = 1./32,
                .startingUV = -0.531250,
            },
        },
    };
    load(W_EM, "F_fft", model.F_fft);
    load(W_EM, "B", model.B);
    
    Mat64 X[2];
    load(W_EM, "X", X);
    Mat64c X_fft[2];
    load(W_EM, "X_fft", X_fft);
    
    Mat<double,3,1> illum = ffccEstimateIlluminant(model, X, X_fft);
    printf("%f %f %f\n", illum[0], illum[1], illum[2]);
    
    return 0;
    
//    argc = 2;
//    argv = (const char*[]){"", "/Users/dave/Desktop/FFCCImageSets/Indoor-Night2-ColorChecker-Small/indoor_night2_25.png"};
//    
//    for (int i=1; i<argc; i++) {
//        const char* pathArg = argv[i];
//        
//        // Regular file
//        if (isPNGFile(pathArg)) {
//            processFile(pathArg);
//        
//        // Directory
//        } else if (fs::is_directory(pathArg)) {
//            for (const auto& f : fs::directory_iterator(pathArg)) {
//                if (isPNGFile(f)) {
//                    processFile(f);
//                }
//            }
//        }
//    }
//    
    return 0;
}

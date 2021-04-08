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

//struct BivariateFit

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

static void /* [mu, Sigma] */ fitBivariateVonMises(const Mat64& P) {
    constexpr size_t H = Mat64::Height;
    constexpr size_t W = Mat64::Width;
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
    
    #warning we probably want to remove this +1 since our indexing isn't 1-based
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
    
//    const double Sigma2 = sum(P2 .* wrapped2.^2) - E2.^2;
//    const double Sigma12 = sum(sum(P .* bsxfun(@times, wrapped1, wrapped2'))) - E1 * E2;
    
//    bins = [1:size(P,1)]';
//    wrap = @(x) (mod(x + size(P,1)/2 - 1, size(P,1)) + 1);
//    wrapped1 = wrap(bins - round(mu(1)));
//    wrapped2 = wrap(bins - round(mu(2)));
//
//    E1 = sum(P1 .* wrapped1);
//    E2 = sum(P2 .* wrapped2);
//    Sigma1 = sum(P1 .* wrapped1.^2) - E1.^2;
//    Sigma2 = sum(P2 .* wrapped2.^2) - E2.^2;
//    Sigma12 = sum(sum(P .* bsxfun(@times, wrapped1, wrapped2'))) - E1 * E2;
//
//    Sigma = [Sigma1, Sigma12; Sigma12, Sigma2];
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

static void ffccEvalModel(
    const Mat64c F_fft[2],
    const Mat64& B,
    const Mat64 X[2],
    const Mat64c X_fft[2],
    const Mat<double,2,1>& Y
) {
    Mat64c X_fft_Times_F_fft[2] = { X_fft[0].elmMul(F_fft[0]), X_fft[1].elmMul(F_fft[1]) };
    assert(equal(W_EM, X_fft_Times_F_fft, "X_fft_Times_F_fft"));
    
    Mat64c FX_fft = X_fft_Times_F_fft[0] + X_fft_Times_F_fft[1];
    assert(equal(W_EM, FX_fft, "FX_fft"));
    
    Mat64c FXc = FX_fft.ifft();
    Mat64 FX;
    for (size_t i=0; i<std::size(FXc.vals); i++) {
        FX.vals[i] = FXc.vals[i].real();
    }
    assert(equal(W_EM, FX, "FX"));
    
    Mat64 H = FX+B;
    assert(equal(W_EM, H, "H"));
    
    Mat64 P = softmaxForward(H);
    assert(equal(W_EM, P, "P"));
    
    fitBivariateVonMises(P);
    
//    printf("%s\n", FX.str().c_str());
    
//    {
//        Mat64c Our_FX_fft = FX.fft();
//        Mat64c Our_FX = Our_FX_fft.ifft();
//        double maxDelta = 0;
//        for (size_t i=0; i<std::size(FX.vals); i++) {
//            maxDelta = std::max(maxDelta, (FX.vals[i]-Our_FX.vals[i].real()));
//        }
//        printf("maxDelta: %f\n", maxDelta);
//        
////        assert(equal(Our_FX_fft, "FX_fft"));
////        constexpr double Eps = .01;
////        for (size_t i=0; i<std::size(FX.vals); i++) {
////            const auto& their = Their_FX_fft.vals[i];
////            auto& our = Our_FX_fft.vals[i];
////            const auto delta = std::complex<double>(
////                std::abs(their.real()-our.real()),
////                std::abs(their.imag()-our.imag())
////            );
////            
////            our.real(delta.real() < Eps);
////            our.imag(delta.real() < Eps);
////        }
//        
////        printf("%s\n", Our_FX_fft.str().c_str());
//    }
//    
////    {
////        Mat64c Our_FX_fft = FXc.fft();
////        assert(equal(Our_FX_fft, "FX_fft"));
//////        printf("%s\n", Our_FX_fft.str().c_str());
//////        assert(equal(FX, "FX"));
////    }
    
    exit(0);
    
    
//    constexpr size_t len = std::size(FX_fft.vals);
//    double FX_fft_r[len];
//    double FX_fft_i[len];
//    // Copy the real/imaginary parts into separate arrays
//    vDSP_ctozD((const DSPDoubleComplex*)FX_fft.vals, 2, (DSPDoubleSplitComplex[]){FX_fft_r,FX_fft_i}, 1, len);
//    
//    // Perform inverse FFT
//    const FFTSetupD setup = vDSP_create_fftsetupD(12, 2);
//    vDSP_fft2d_zipD(setup, (DSPDoubleSplitComplex[]){FX_fft_r,FX_fft_i}, 1, 0, 6, 6, kFFTDirection_Inverse);
//    
//    // Join the real/imaginary parts into the same array
//    vDSP_ztocD((DSPDoubleSplitComplex[]){FX_fft_r,FX_fft_i}, 1, (DSPDoubleComplex*)FX_fft.vals, 2, len);
//    
//    FX_fft /= std::complex<double>(len);
//    
//    Mat64 FX;
//    for (size_t i=0; i<len; i++) {
//        FX.vals[i] = FX_fft.vals[i].real();
//    }
//    assert(equal(FX, "FX"));
    
    
    
    
//    FX.fft();
//    
//    {
//        Mat<float,64,64> a;
//        a.fft();
//        a.ifft();
//    }
//    
//    {
//        Mat<double,64,64> a;
//        a.fft();
//        a.ifft();
//    }
//    
//    {
//        Mat<std::complex<float>,64,64> a;
//        a.fft();
//        a.ifft();
//    }
//    
//    {
//        Mat<std::complex<double>,64,64> a;
//        a.fft();
//        a.ifft();
//    }
    

    
//    printf("%s\n", FX_fft.str().c_str());
    
//    for (size_t z=0; z<2; z++) {
//        for (size_t x=0; x<64; x++) {
//            for (size_t y=0; y<64; y++) {
//                auto theirs = X_fft_Times_F_fft[z].at(y,x);
//                auto ours = FX_fft[z].at(y,x);
//                auto diff = theirs-ours;
//                if (std::abs(diff) > 0) {
//                    printf("%f %f\n", diff.real(), diff.imag());
//                }
//            }
//        }
//    }
    
//    FX_fft = sum(bsxfun(@times, X_fft, F_fft), 3);
    
//    X_fft[0] * X_fft[1];
//function [state_obs, meta, sub_loss, sub_losses, state_next] = EvaluateModel(F_fft, B, X, X_fft, Y, state_last, avg_rgb, params)
//% Evaluates a an AWB model, and produces an estimate of the white point. If
//% provided with the necessary input, this function can also be used to:
//%   - Estimate a loss and gradient with respect to a ground-truth white point.
//%   - Update a running estimate of a white point.
//%   - Produce an estimate of the quality of the white point.
//%
//% Inputs:
//%   F_fft  - A learned model's n-channel filter bank in frequency space.
//%   B      - A learned model's per-chroma bias map. This argument is optional,
//%            and if it is omitted then the bias is assumed to be all zeros.
//%   X      - An n-channel feature histogram.
//%   X_fft  - The n-channel FFT of X, which we take as input to avoid having
//%            to repeatedly recompute the FFT of X during training.
//%   Y      - The ground-truth (u, v) coordinate of the true white point. Set to
//%            [] if the ground-truth is not known, or if this model is not being
//%            used for training purposes.
//%   state_last - A running model of the white point in a Kalman filter
//%            framework, which is a struct with a mean "mu" and covariance
//%            matrix "Sigma". Use [] as input if AWB is being run independently
//%            on a set of independent images or if you don't care to update the
//%            current state.
//%   params - A struct of parameters.
//%
//% Outputs:
//%   state_obs - A struct containing the estimated white point given just the
//%            current input X, where "mu" and "Sigma" are a bivariate Von Mises
//%            distribution modeling the estimated white point just using the
//%            current input X.
//%   meta   - Some metadata used to compute state_obs, useful for training
//%            and visualization.
//%   sub_loss - If Y is non-empty and params.loss_mult is defined, a struct
//%            containing the weighted loss to be minimized and its gradient.
//%   sub_losses - If Y is non-empty, this is a struct contaning the two
//%            losses (cross-entropy and von-mises) that are used to create the
//%            weighted average loss returned in "sub_loss". These are useful for
//%            reporting errors.
//%   state_next - A struct containing a bivariate Von Mises computed from the
//%            current observation and the running estimate. This struct should
//%            be used as input to the next frame.
//
//assert(~isempty(X));
//assert(~isempty(X_fft));
//
//if isempty(B)
//  B = zeros(size(X_fft,1), size(X_fft,2));
//end
//
//compute_gradient = (nargout >= 2);
//
//% The filtered histogram H = sum(conv(F, X),3) + B. The convolution is
//% performed with FFTs with the sum over channels performed in FFT-space so that
//% ifft2() need only be called once, and some intermediate quantities are
//% held onto as they are needed during backpropagation.
//FX_fft = sum(bsxfun(@times, X_fft, F_fft), 3);
//FX = real(ifft2(FX_fft));
//H = FX + B;
//
//% Turn the score histogram into a PDF by passing it through a softmax.
//if compute_gradient
//  [P, P_meta] = SoftmaxForward(H);
//else
//  P = SoftmaxForward(H);
//end
//
//% Fit a bivariate Von Mises distribution to the PDF to get an estimate of the
//% center of mass of the PDF, as well as a covariance matrix, and the partial
//% derivative of the mean and covariance matrix.
//if compute_gradient
//  [mu_idx, Sigma_idx, dmu_idx_P, dSigma_idx_P] = FitBivariateVonMises(P);
//else
//  [mu_idx, Sigma_idx] = FitBivariateVonMises(P);
//end
//
//if params.TRAINING.FORCE_ISOTROPIC_VON_MISES
//  % Whiten a convariance matrix while preserving its trace.
//  Sigma_idx = eye(2) * mean(diag(Sigma_idx));
//  % Note that the gradients dSigma_idx_P are now incorrect. This is
//  % rectified later during backpropagation.
//end
//
//if strcmp(params.HISTOGRAM.VON_MISES_DIAGONAL_MODE, 'clamp');
//  assert(params.TRAINING.FORCE_ISOTROPIC_VON_MISES);
//  % Clamp the diagonal of the variance to be at least EPS. This is only
//  % supported for diagonal von Mises distributions.
//  if (Sigma_idx(1) <= params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS)
//    Sigma_idx = eye(2) * params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS;
//    sigma_clamped = true;
//  else
//    sigma_clamped = false;
//  end
//elseif strcmp(params.HISTOGRAM.VON_MISES_DIAGONAL_MODE, 'pad');
//  % Add a constant to the diagonal of fitted Von Mises distributions to help
//  % generalization. The constant should be at least 1/12 (the variance of a
//  % unit-size box) but larger values regularize the Von Mises to be wider, which
//  % appears to help.
//  Sigma_idx = Sigma_idx + params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS * eye(2);
//else
//  assert(0)
//end
//
//[state_obs.mu, state_obs.Sigma] = IdxToUv(mu_idx, Sigma_idx, params);
//
//if params.DEBUG.GRAY_WORLD_UNWRAPPING
//  avg_uv = RgbToUv(avg_rgb);
//  deltas = state_obs.mu - avg_uv;
//  width = params.HISTOGRAM.NUM_BINS * params.HISTOGRAM.BIN_SIZE;
//  state_obs.mu = state_obs.mu - width * round(deltas / width);
//end
//
//if compute_gradient
//  dmu_P = cellfun(@(x) x * params.HISTOGRAM.BIN_SIZE, dmu_idx_P, ...
//    'UniformOutput', false);
//  dSigma_P = cellfun(@(x) x * params.HISTOGRAM.BIN_SIZE.^2, dSigma_idx_P, ...
//    'UniformOutput', false);
//end
//
//if strcmp(params.HISTOGRAM.VON_MISES_DIAGONAL_MODE, 'clamp');
//  % If the gradient has been clamped, then the derivative with respect to Sigma
//  % should be set to zero.
//  if (sigma_clamped)
//    dSigma_P{1} = 0;
//    dSigma_P{2} = 0;
//    dSigma_P{3} = 0;
//  end
//end
//
//meta.P = P;
//
//% The entropy of the Von Mises PDF.
//meta.entropy = 0.5 * log(det(state_obs.Sigma));
//
//% Because Sigma has a scaled identity matrix added to it, we can derive a lower
//% bound on entropy.
//meta.minimum_entropy = ...
//      0.5 * log(det(params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS ...
//      * (params.HISTOGRAM.BIN_SIZE.^2) * eye(2)));
//
//% This is a reasonable "confidence" measurement, in that it is a value in (0, 1]
//% where a large value means that the model predicted a very tightly localized
//% white point. Equivalent to:
//%   confidence = exp(-entropy) / exp(-minimum_entropy).
//meta.entropy_confidence = exp(meta.minimum_entropy - meta.entropy);
//
//sub_loss = struct();
//sub_losses = struct();
//if isfield(params, 'loss_mult')
//  sub_loss.loss = 0;
//  d_loss_H = 0;
//end
//
//if ~isempty(Y)
//  % Here we compute two losses: a convex loss (cross-entropy on a discrete label
//  % set, useful for pre-training) and a non-convex loss that produces higher
//  % quality results when/if a good minimum is found (Von Mises log-likelihood,
//  % useful for fine-tuning).
//
//  % This convex loss is just logistic regression between P and a ground-truth
//  % PDF indicating the location of the white point.
//
//  if params.TRAINING.SMOOTH_CROSS_ENTROPY
//    % Construct a one-hot vector from the ground truth.
//    Y_idx = UvToIdx(Y, params);
//    P_true = sparse(Y_idx(1), Y_idx(2), true, size(H,1), size(H,2));
//  else
//    % Construct a PDF from the ground truth.
//    P_true = UvToP(Y, params);
//  end
//
//  % Compute cross-entropy (aka log-loss) and its gradient.
//  log_P = P_meta.H_shifted - log(P_meta.expH_sum);
//  sub_losses.crossent = -full(sum(P_true(:) .* log_P(:)));
//  d_crossent_H = P - P_true;
//
//  assert(sub_losses.crossent >= -1e-4);
//  sub_losses.crossent = max(0, sub_losses.crossent);
//
//  if isfield(params, 'loss_mult')
//    sub_loss.loss = sub_loss.loss ...
//      + params.loss_mult.crossent * sub_losses.crossent;
//    d_loss_H = d_loss_H + params.loss_mult.crossent * d_crossent_H;
//  end
//
//  % Switch between different loss functions on the von mises distribution.
//  if strcmp(params.TRAINING.VON_MISES_LOSS, 'expected_squared_error')
//    % Computes the expected squared error in UV space.
//
//    % Y_sigma is the the covariance matrix of the error. We use a scale
//    % identity matrix (ie, isotropic error) which produces errors that are
//    % comparable to the other measures and to RGB angular error.
//    Y_sigma = eye(2) / 32;
//    inv_Y_sigma = inv(Y_sigma);
//
//    % This math is adopted from Section 0.5 of
//    % http://www.cogsci.ucsd.edu/~ajyu/Teaching/Tutorials/gaussid.pdf
//    sub_losses.vonmises = sum( ...
//      (inv_Y_sigma * (state_obs.mu - Y)) .* (state_obs.mu - Y)) ...
//      + trace(inv_Y_sigma * state_obs.Sigma); %#ok<MINV>
//
//    d_vonmises_mu = 2 * (state_obs.mu - Y);
//    d_vonmises_Sigma = inv_Y_sigma;
//
//  elseif strcmp(params.TRAINING.VON_MISES_LOSS, 'squared_error')
//    % Computes the squared error in UV space.
//    sub_losses.vonmises = sum((state_obs.mu - Y).^2);
//    d_vonmises_mu = 2 * (state_obs.mu - Y);
//    d_vonmises_Sigma = zeros(2, 2);
//
//  elseif strcmp(params.TRAINING.VON_MISES_LOSS, 'likelihood')
//
//    % Compute the log-likelihood of x. Here we treat the bivariate Von Mises
//    % distribution in state_obs as a simple multivariate normal, essentially
//    % un-wrapping the point from a torus to the least-wrapped Cartesian plane.
//    [sub_losses.vonmises, ~, d_vonmises_mu, d_vonmises_Sigma] = ...
//      LLMultivariateNormal(Y, state_obs.mu, state_obs.Sigma);
//
//    % Flipping the sign to turn log-likelihoods into losses.
//    sub_losses.vonmises = -sub_losses.vonmises;
//    d_vonmises_mu = -d_vonmises_mu;
//    d_vonmises_Sigma = -d_vonmises_Sigma;
//
//    % Because the Von Mises log-likelihood is computed using covariance matrices
//    % which have had a non-zero constant added to the diagonal, we can bound the
//    % log-likelihood and use this to shift the loss/log-likelihood such that it
//    % is non-negative, which makes optimization easier to reason about.
//    % Equivalent to:
//    %   vonmises_loss_min = -LLMultivariateNormal( ...
//    %     [0; 0], [0; 0], ...
//    %     eye(2) * (params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS * ...
//    %     params.HISTOGRAM.BIN_SIZE.^2));
//    vonmises_loss_min = log(2 * pi * ...
//      params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS * params.HISTOGRAM.BIN_SIZE^2);
//
//    sub_losses.vonmises = sub_losses.vonmises - vonmises_loss_min;
//  else
//    assert(false)
//  end
//
//  assert(sub_losses.vonmises >= -1e-4);
//  sub_losses.vonmises = max(0, sub_losses.vonmises);
//
//  % Backprop the gradient from the Von Mises onto the PDF.
//  if params.TRAINING.FORCE_ISOTROPIC_VON_MISES
//    d_var = 0.5 * (d_vonmises_Sigma(1,1) + d_vonmises_Sigma(2,2));
//    d_vonmises_P = ...
//      bsxfun(@plus, d_var * dSigma_P{1} + d_vonmises_mu(1) * dmu_P{1}, ...
//                    d_var * dSigma_P{3} + d_vonmises_mu(2) * dmu_P{2});
//  else
//  % The partial derivatives in dSigma_P have varied sizes so we add them in
//  % the most efficient order.
//    d_vonmises_P = bsxfun(@plus, bsxfun(@plus, ...
//      (2 * d_vonmises_Sigma(1,2)) * dSigma_P{2}, ...
//      (d_vonmises_mu(1) * dmu_P{1} + d_vonmises_Sigma(1,1) * dSigma_P{1})), ...
//      (d_vonmises_mu(2) * dmu_P{2} + d_vonmises_Sigma(2,2) * dSigma_P{3}));
//  end
//
//  % Backprop the gradient from the PDF to H.
//  d_vonmises_H = SoftmaxBackward(d_vonmises_P, P_meta);
//
//  power_loss = ...
//    isfield(params.TRAINING, 'VONMISES_POWER') ...
//    && (params.TRAINING.VONMISES_POWER ~= 1);
//
//  if power_loss
//    assert(params.TRAINING.VONMISES_POWER ~= 0);
//    [sub_losses.vonmises, d_vonmises_H] = ...
//      ApplyPower(params.TRAINING.VONMISES_POWER, ...
//        sub_losses.vonmises, d_vonmises_H);
//  end
//
//  if isfield(params, 'loss_mult')
//    sub_loss.loss = sub_loss.loss ...
//      + params.loss_mult.vonmises * sub_losses.vonmises;
//    d_loss_H = d_loss_H + params.loss_mult.vonmises * d_vonmises_H;
//  end
//
//  if isfield(params, 'loss_mult')
//    sub_loss.d_loss_F_fft =  ...
//      bsxfun(@times, conj(X_fft), fft2((1 / size(F_fft,1)^2) * d_loss_H));
//    if params.TRAINING.LEARN_BIAS
//      sub_loss.d_loss_B = d_loss_H;
//    end
//  end
//end
//
//if nargout >= 5
//  if (params.RUNTIME.FRAMES_PER_SECOND > 0) ...
//      && ~isinf(params.RUNTIME.KALMAN_NOISE_VARIANCE)
//    % The motion of the white point over time is assumed to be zero-mean
//    % Gaussian noise with an isotropic covariance matrix, whose diagonal
//    % elements are some assumed variance constant divided by the frame rate.
//    Sigma_noise = (params.RUNTIME.KALMAN_NOISE_VARIANCE ...
//      / params.RUNTIME.FRAMES_PER_SECOND) * eye(2);
//
//    % Update the current state's estimate of mu and Sigma using the observed
//    % mu and Sigma and the assumed transition model.
//    state_next = KalmanUpdate(state_obs, state_last, Sigma_noise);
//  else
//    % If we're ignoring temporal smoothness, then just set the state to be
//    % equal to the observation.
//    state_next = state_obs;
//  end
//end
}

static void processFile(const fs::path& path) {
    
}

static bool isPNGFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".png";
}

int main(int argc, const char* argv[]) {
    Mat64c F_fft[2];
    Mat64c X_fft[2];
    Mat64 B;
    Mat64 X[2];
    Mat<double, 2, 1> Y;
    
    load(W_EM, "F_fft", F_fft);
    load(W_EM, "X_fft", X_fft);
    load(W_EM, "B", B);
    load(W_EM, "X", X);
    
    ffccEvalModel(F_fft, B, X, X_fft, Y);
    
//    struct {
//        mxArray* F_fft = nullptr;
//    } matlab;
//    
//    matlab.F_fft = matGetVariable(MATWorkspace, "F_fft");
//    assert(matlab.F_fft);
    
//    std::complex<double>* arr = (std::complex<double>*)mxGetComplexDoubles(matlab.F_fft);
//    printf("%f %f\n", arr[0].real(), arr[0].imag());
//    printf("%f %f\n", arr[1].real(), arr[1].imag());
//    
//    mwSize dims = mxGetNumberOfDimensions(matlab.F_fft);
//    LIBMMWMATRIX_PUBLISHED_API_EXTERN_C const mwSize *mxGetDimensions(const mxArray *pa);
    
//    mxClassID classID = mxGetClassID(matlab.F_fft);
//    printf("%d\n", classID);
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

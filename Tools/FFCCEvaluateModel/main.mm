#import <Cocoa/Cocoa.h>
#import <filesystem>
#import <complex>
#import <iostream>
#import <atomic>
#import "Mat.h"
#import "Mod.h"
#import "Renderer.h"
#import "/Applications/MATLAB_R2021a.app/extern/include/mat.h"
#import "FFCC.h"
#import "FFCCTrainedModel.h"
#import "BitmapImage.h"
#import "Debug.h"
using namespace CFAViewer;
using namespace FFCC;
namespace fs = std::filesystem;

static constexpr size_t H = 256;
static constexpr size_t W = 455;

MATFile* W_EM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-EvaluateModel.mat", "r");
MATFile* W_FBVM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FitBivariateVonMises.mat", "r");

MATFile* W_FI = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FeaturizeImage.mat", "r");
MATFile* W_PTD = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-PrecomputeTrainingData.mat", "r");
MATFile* W_CV = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-CrossValidate.mat", "r");

struct VecSigma {
    Mat<double,2,1> vec;
    Mat<double,2,2> sigma;
};

static VecSigma UVForIdx(const Model& model, const VecSigma& idx) {
    return VecSigma{
        .vec = ((idx.vec-1)*model.params.histogram.binSize) + model.params.histogram.startingUV,
        .sigma = idx.sigma * (model.params.histogram.binSize * model.params.histogram.binSize),
    };
}

Mat<double,3,1> RGBForUV(const Mat<double,2,1>& uv) {
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
    for (double& x : angles) {
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
    for (size_t i=0; i<angles.Count; i++) {
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
    
    const double mu1 = Mod(std::atan2(y1,x1), 2*M_PI) / angleStep;
    const double mu2 = Mod(std::atan2(y2,x2), 2*M_PI) / angleStep;
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
    size_t i = 1;
    for (double& x : bins) x = i++;
    
    auto wrap = [](double x) {
        return Mod(x+(H/2)-1, (double)H)+1;
    };
    
    Mat<double,H,1> wrapped1;
    Mat<double,H,1> wrapped2;
    for (size_t i=0; i<wrapped1.Count; i++) {
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
    for (double x : r) maxVal = std::max(maxVal, x);
    // Subtract `maxVal` from every element
    r -= maxVal;
    // Raise e to each element in `r`
    for (double& x : r) x = std::exp(x);
    // Normalize `r` using its sum
    r /= r.sum();
    return r;
}

Renderer::Txt createMaskedImage(const Model& model, Renderer& renderer, id<MTLTexture> img, id<MTLTexture> mask) {
    Renderer::Txt maskedImg = renderer.createTexture(MTLPixelFormatRGBA32Float, W, H);
    renderer.render("ApplyMask", maskedImg,
        // Texture args
        img,
        mask
    );
    
    return maskedImg;
}

Renderer::Txt createAbsDevImage(const Model& model, Renderer& renderer, id<MTLTexture> img, id<MTLTexture> mask) {
    Renderer::Txt absDevImage = renderer.createTexture(MTLPixelFormatRGBA32Float, W, H);
    {
        Renderer::Txt coeff = renderer.createTexture(MTLPixelFormatR32Float, W, H);
        renderer.render("LocalAbsoluteDeviationCoeff", coeff,
            mask
        );
        
        renderer.render("LocalAbsoluteDeviation", absDevImage,
            img,
            mask,
            coeff
        );
    }
    
    return absDevImage;
}

Mat64 calcXFromImage(const Model& model, Renderer& renderer, id<MTLTexture> img, id<MTLTexture> mask) {
    Renderer::Txt u = renderer.createTexture(MTLPixelFormatR32Float, W, H);
    renderer.render("CalcU", u,
        // Texture args
        img
    );
    
    Renderer::Txt v = renderer.createTexture(MTLPixelFormatR32Float, W, H);
    renderer.render("CalcV", v,
        // Texture args
        img
    );
    
    using ValidPixelCount = uint32_t;
    Renderer::Buf validPixelCountBuf = renderer.createBuffer(sizeof(ValidPixelCount), MTLResourceStorageModeManaged);
    renderer.bufferClear(validPixelCountBuf);
    Renderer::Txt maskUV = renderer.createTexture(MTLPixelFormatR8Unorm, W, H);
    {
        const float thresh = model.params.histogram.minIntensity;
        renderer.render("CalcMaskUV", maskUV,
            // Buffer args
            thresh,
            validPixelCountBuf,
            // Texture args
            img,
            mask
        );
    }
    
    const uint32_t binCount = (uint32_t)model.params.histogram.binCount;
    const float binSize = model.params.histogram.binSize;
    const float binMin = model.params.histogram.startingUV;
    renderer.render("CalcBinUV", u,
        // Buffer args
        binCount,
        binSize,
        binMin,
        // Texture args
        u
    );
    
    renderer.render("CalcBinUV", v,
        // Buffer args
        binCount,
        binSize,
        binMin,
        // Texture args
        v
    );
    
    const size_t binsBufCount = binCount*binCount;
    const size_t binsBufLen = sizeof(std::atomic_uint)*binsBufCount;
    Renderer::Buf binsBuf = renderer.createBuffer(binsBufLen, MTLResourceStorageModeManaged);
    renderer.bufferClear(binsBuf);
    
    renderer.render("CalcHistogram", W, H,
        // Buffer args
        binCount,
        binsBuf,
        // Texture args
        u,
        v,
        maskUV
    );
    
    Renderer::Txt Xc = renderer.createTexture(MTLPixelFormatR32Float, binCount, binCount);
    renderer.render("LoadHistogram", Xc,
        // Buffer args
        binCount,
        binsBuf
    );
    
    renderer.render("NormalizeHistogram", Xc,
        // Buffer args
        validPixelCountBuf,
        // Texture args
        Xc
    );
    
    Renderer::Txt XcTransposed = renderer.createTexture(MTLPixelFormatR32Float, binCount, binCount);
    renderer.render("Transpose", XcTransposed,
        // Texture args
        Xc
    );
    
    renderer.sync(XcTransposed);
    renderer.commitAndWait();
    
    // Convert integer histogram to double histogram, to match MATLAB version
    auto histFloats = renderer.textureRead<float>(XcTransposed);
    Mat64 hist;
    // Copy the floats into the matrix
    // The source matrix (XcTransposed) is transposed, so the data is already
    // in column-major order. (If we didn't transpose it, it would be in row-major
    // order, since that's how textures are normally laid out...)
    std::copy(histFloats.begin(), histFloats.end(), hist.begin());
    return hist;
}

static Mat<double,3,1> ffccEstimateIlluminant(
    const Model& model,
    Renderer& renderer,
    id<MTLTexture> img
) {
    Renderer::Txt mask = renderer.createTexture(MTLPixelFormatR8Unorm, W, H);
    renderer.render("CreateMask", mask,
        // Texture args
        img
    );
    
    Renderer::Txt maskedImg = createMaskedImage(FFCCTrainedModel::Model, renderer, img, mask);
    Renderer::Txt absDevImg = createAbsDevImage(FFCCTrainedModel::Model, renderer, img, mask);
    
    Mat64 X1 = calcXFromImage(FFCCTrainedModel::Model, renderer, maskedImg, mask);
    Mat64 X2 = calcXFromImage(FFCCTrainedModel::Model, renderer, absDevImg, mask);
    
    // Compare to MATLAB version of X1/X2
    {
        Mat64 our[2] = {X1,X2};
        Mat64 their[2];
        load(W_EM, "X", their);
        // Our calculation of X differs from MATLAB's version because we use
        // 32-bit floats (since we use the GPU), while MATLAB uses 64-bit doubles.
        // So verify that our result matches theirs to close approximation, and then
        // replace our X with MATLAB's version, so that the rest of our algorithm uses
        // the same input at MATLAB. (Otherwise the algorithms they diverge further.)
        assert(rmsdiff(our, their) < 1e-6);
        X1 = their[0];
        X2 = their[1];
    }
    
    Mat64c X1_fft = X1.fft();
    Mat64c X2_fft = X2.fft();
    
    // Compare X1_fft/X2_fft to MATLAB version
    {
        Mat64c our[2] = {X1_fft,X2_fft};
        Mat64c their[2];
        load(W_EM, "X_fft", their);
        
        assert(equal(our, their));
    }
    
    // Compare their_X1.fft()/their_X2.fft() to MATLAB's X1_fft/X2_fft, to compare our
    // FFT implementation with MATLAB's FFT implementation
    {
        Mat64 their_X[2];
        load(W_EM, "X", their_X);
        
        Mat64c our[2] = {their_X[0].fft(), their_X[1].fft()};
        Mat64c their[2];
        load(W_EM, "X_fft", their);
        
        assert(equal(our, their));
    }
    
    Mat64c X_fft_Times_F_fft[2] = { X1_fft.elmMul(model.F_fft[0]), X2_fft.elmMul(model.F_fft[1]) };
    Mat64c FX_fft = X_fft_Times_F_fft[0] + X_fft_Times_F_fft[1];
    assert(equal(W_EM, FX_fft, "FX_fft"));
    
    Mat64c FXc = FX_fft.ifft();
    Mat64 FX;
    for (size_t i=0; i<FXc.Count; i++) {
        FX[i] = FXc[i].real();
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
    
    const VecSigma uv = UVForIdx(model, idx);
    return RGBForUV(uv.vec);
}

static void processImageFile(Renderer& renderer, const fs::path& path) {
    BitmapImage<uint16_t> png(path);
    assert(png.height == H);
    assert(png.width == W);
    
    // Create a texture and load it with the data from `img`
    Renderer::Txt img = renderer.createTexture(MTLPixelFormatRGBA32Float, W, H);
    renderer.textureWrite(img, png.data, png.samplesPerPixel);
    
    Mat<double,3,1> illum = ffccEstimateIlluminant(FFCCTrainedModel::Model, renderer, img);
    assert(equal(W_CV, illum, "rgb_est"));
    std::cout << "illum:\n" << illum << "\n\n";
    
    Mat<double,3,1> illum2 = ffccEstimateIlluminant(FFCCTrainedModel::Model, renderer, img);
    assert(equal(W_CV, illum2, "rgb_est"));
    std::cout << "illum2:\n" << illum2 << "\n\n";
    
    std::cout << "\n\n\n\n";
}

static bool isPNGFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".png";
}

int main(int argc, const char* argv[]) {
    // Create renderer
    Renderer renderer;
    {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        assert(dev);
        
        auto metalLibPath = fs::path(argv[0]).replace_filename("default.metallib");
        id<MTLLibrary> lib = [dev newLibraryWithFile:@(metalLibPath.c_str()) error:nil];
        assert(lib);
        id<MTLCommandQueue> commandQueue = [dev newCommandQueue];
        assert(commandQueue);
        
        renderer = Renderer(dev, lib, commandQueue);
    }
    
    argc = 2;
    argv = (const char*[]){"", "/Users/dave/repos/ffcc/data/AR0330/indoor_night2_132.png"};
    
    for (int i=1; i<argc; i++) {
        const char* pathArg = argv[i];
        
        // Regular file
        if (isPNGFile(pathArg)) {
            processImageFile(renderer, pathArg);
        
        // Directory
        } else if (fs::is_directory(pathArg)) {
            for (const auto& f : fs::directory_iterator(pathArg)) {
                if (isPNGFile(f)) {
                    processImageFile(renderer, f);
                }
            }
        }
    }
    
    return 0;
}

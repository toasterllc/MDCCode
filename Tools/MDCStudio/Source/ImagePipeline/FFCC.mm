#import "FFCC.h"
#import "ImagePipelineTypes.h"
#import "Tools/Shared/MetalUtil.h"
#import "Tools/Shared/Color.h"
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/Mod.h"
using namespace MDCStudio;
using namespace MDCStudio::ImagePipeline;
using namespace MDCTools;

using Mat64     = FFCC::Mat64;
using Mat64c    = FFCC::Mat64c;
using Vec2      = FFCC::Vec2;
using Vec3      = FFCC::Vec3;

#define _ShaderNamespace ImagePipelineShaderNamespace "FFCC::"

static Renderer::Txt _createMaskedImage(Renderer& renderer, id<MTLTexture> img, id<MTLTexture> mask) {
    Renderer::Txt maskedImg = renderer.textureCreate(img);
    renderer.render(_ShaderNamespace "ApplyMask", maskedImg,
        // Texture args
        img,
        mask
    );
    
    return maskedImg;
}

static Renderer::Txt _createAbsDevImage(Renderer& renderer, id<MTLTexture> img, id<MTLTexture> mask) {
    Renderer::Txt coeff = renderer.textureCreate(MTLPixelFormatR32Float, [img width], [img height]);
    renderer.render(_ShaderNamespace "LocalAbsoluteDeviationCoeff", coeff,
        mask
    );
    
    Renderer::Txt absDevImage = renderer.textureCreate(img);
    renderer.render(_ShaderNamespace "LocalAbsoluteDeviation", absDevImage,
        img,
        mask,
        coeff
    );
    
    return absDevImage;
}

static Mat64 _calcXFromImage(const FFCC::Model& model, Renderer& renderer, id<MTLTexture> img, id<MTLTexture> mask) {
    const uint32_t w = (uint32_t)[img width];
    const uint32_t h = (uint32_t)[img height];
    
    Renderer::Txt u = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
    renderer.render(_ShaderNamespace "CalcU", u,
        // Texture args
        img
    );
    
    Renderer::Txt v = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
    renderer.render(_ShaderNamespace "CalcV", v,
        // Texture args
        img
    );
    
    using ValidPixelCount = uint32_t;
    Renderer::Buf validPixelCountBuf = renderer.bufferCreate(sizeof(ValidPixelCount), MTLResourceStorageModeManaged);
    renderer.bufferClear(validPixelCountBuf);
    Renderer::Txt maskUV = renderer.textureCreate(MTLPixelFormatR8Unorm, w, h);
    {
        const float thresh = model.params.histogram.minIntensity;
        renderer.render(_ShaderNamespace "CalcMaskUV", maskUV,
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
    renderer.render(_ShaderNamespace "CalcBinUV", u,
        // Buffer args
        binCount,
        binSize,
        binMin,
        // Texture args
        u
    );
    
    renderer.render(_ShaderNamespace "CalcBinUV", v,
        // Buffer args
        binCount,
        binSize,
        binMin,
        // Texture args
        v
    );
    
    const size_t binsBufCount = binCount*binCount;
    const size_t binsBufLen = sizeof(std::atomic_uint)*binsBufCount;
    Renderer::Buf binsBuf = renderer.bufferCreate(binsBufLen, MTLResourceStorageModeManaged);
    renderer.bufferClear(binsBuf);
    
    renderer.render(_ShaderNamespace "CalcHistogram", w, h,
        // Buffer args
        binCount,
        binsBuf,
        // Texture args
        u,
        v,
        maskUV
    );
    
    Renderer::Txt Xc = renderer.textureCreate(MTLPixelFormatR32Float, binCount, binCount);
    renderer.render(_ShaderNamespace "LoadHistogram", Xc,
        // Buffer args
        binCount,
        binsBuf
    );
    
    renderer.render(_ShaderNamespace "NormalizeHistogram", Xc,
        // Buffer args
        validPixelCountBuf,
        // Texture args
        Xc
    );
    
    Renderer::Txt XcTransposed = renderer.textureCreate(MTLPixelFormatR32Float, binCount, binCount);
    renderer.render(_ShaderNamespace "Transpose", XcTransposed,
        // Texture args
        Xc
    );
    
    renderer.sync(XcTransposed);
    renderer.commitAndWait();
    
    // Copy the histogram from a texture -> Mat64
    std::vector<float> histFloats = renderer.textureRead<float>(XcTransposed);
    Mat64 hist;
    // Copy the floats into the matrix
    // The source matrix (XcTransposed) is transposed, so the data is already
    // in column-major order. (If we didn't transpose it, it would be in row-major
    // order, since that's how textures are normally laid out in memory...)
    std::copy(histFloats.begin(), histFloats.end(), hist.begin());
    return hist;
}

static Mat64 _softmaxForward(const Mat64& H) {
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

static Vec2 _fitBivariateVonMises(const Mat64& P) {
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
    const double mu1 = Mod(std::atan2(y1,x1), 2*M_PI) / angleStep;
    const double mu2 = Mod(std::atan2(y2,x2), 2*M_PI) / angleStep;
    return {mu1, mu2}; // 0-indexed; note that the MATLAB version is 1-indexed!
}

static Vec2 _uvForIdx(const FFCC::Model& model, const Vec2& idx) {
    return (idx*model.params.histogram.binSize) + model.params.histogram.startingUV;
}

static Vec3 _rgbForUV(const Vec2& uv) {
    Vec3 rgb(std::exp(-uv[0]), 1., std::exp(-uv[1]));
    rgb /= sqrt(rgb.elmMul(rgb).sum());
    return rgb;
}

FFCC::Vec3 FFCC::Run(
    const FFCC::Model& model,
    Renderer& renderer,
    const CFADesc& cfaDesc,
    id<MTLTexture> raw
) {
    
    const uint32_t w = 384;
    const uint32_t h = (uint32_t)((w*[raw height])/[raw width]);
    Renderer::Txt img = renderer.textureCreate(MTLPixelFormatRGBA32Float, w, h);
    renderer.render(ImagePipelineShaderNamespace "Base::DebayerDownsample", img,
        cfaDesc,
        raw,
        img
    );
    
    Renderer::Txt mask = renderer.textureCreate(MTLPixelFormatR8Unorm, w, h);
    renderer.render(_ShaderNamespace "CreateMask", mask,
        // Texture args
        img
    );
    
    const Renderer::Txt maskedImg = _createMaskedImage(renderer, img, mask);
    const Renderer::Txt absDevImg = _createAbsDevImage(renderer, img, mask);
    
    const Mat64 X1 = _calcXFromImage(model, renderer, maskedImg, mask);
    const Mat64 X2 = _calcXFromImage(model, renderer, absDevImg, mask);
    const Mat64c X1_fft = X1.fft();
    const Mat64c X2_fft = X2.fft();
    
    const Mat64c X_fft_Times_F_fft[2] = { X1_fft.elmMul(model.F_fft[0]), X2_fft.elmMul(model.F_fft[1]) };
    const Mat64c FX_fft = X_fft_Times_F_fft[0] + X_fft_Times_F_fft[1];
    
    const Mat64c FXc = FX_fft.ifft();
    Mat64 FX;
    for (size_t i=0; i<FXc.Count; i++) {
        FX[i] = FXc[i].real();
    }
    
    const Mat64 H = FX+model.B;
    const Mat64 P = _softmaxForward(H);
    
    const Vec2 fit = _fitBivariateVonMises(P);
    const Vec2 uv = _uvForIdx(model, fit);
    return _rgbForUV(uv);
}

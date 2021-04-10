#import <Cocoa/Cocoa.h>
#import <filesystem>
#import <complex>
#import <iostream>
#import "Mat.h"
#import "Renderer.h"
#import "/Applications/MATLAB_R2021a.app/extern/include/mat.h"
using namespace CFAViewer;
namespace fs = std::filesystem;

using Mat64 = Mat<double,64,64>;
using Mat64c = Mat<std::complex<double>,64,64>;

MATFile* W_EM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-EvaluateModel.mat", "r");
MATFile* W_FBVM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FitBivariateVonMises.mat", "r");

MATFile* W_FI = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FeaturizeImage.mat", "r");

struct FFCCModel {
    struct Params {
        struct {
            double vonMisesDiagonalEps = 0;
        } hyperparams;
        
        struct {
            double binSize = 0;
            double startingUV = 0;
            double minIntensity = 0;
        } histogram;
    };
    
    Params params;
    Mat64c F_fft[2];
    Mat64 B;
};

template <typename T, size_t H, size_t W, size_t Depth>
bool _equal(const Mat<T,H,W>* a, const Mat<T,H,W>* b) {
    constexpr double Eps = 1e-5;
    for (size_t z=0; z<Depth; z++) {
        for (size_t y=0; y<H; y++) {
            for (size_t x=0; x<W; x++) {
                const T va = a[z].at(y,x);
                const T vb = b[z].at(y,x);
                if (std::abs(va - vb) > Eps) {
                    std::cout << "(" << y << " " << x << ") " << va << " " << vb << "\n";
//                    printf("(%zu %zu) %f %f\n", y, x, va, vb);
                    abort();
                    return false;
                }
            }
        }
//        for (size_t i=0; i<H*W; i++) {
//            if (std::abs(a[z].vals[i] - b[z].vals[i]) > Eps) {
//                printf("(%d %d) %f %f\n", y,x,a[z].vals[i],b[z].vals[i]);
//                abort();
//                return false;
//            }
//        }
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
    struct MatArray { Mat<T,H,W> a[Depth]; };
    auto b = std::make_unique<MatArray>();
    load(f, name, (*b).a);
    return equal(a, (*b).a);
}

template <typename T, size_t H, size_t W>
bool equal(MATFile* f, const Mat<T,H,W>& a, const char* name) {
    auto b = std::make_unique<Mat<T,H,W>>();
    load(f, name, *b);
    return equal(a, *b);
}

template <typename T>
bool equal(MATFile* f, const T& a, const char* name) {
    auto A = std::make_unique<Mat<T,1,1>>(a);
    auto B = std::make_unique<Mat<T,1,1>>();
    load(f, name, *B);
    return equal(*A, *B);
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
    auto m = std::make_unique<Mat<T,1,1>>();
    _load<T,1,1,1>(f, name, m.get());
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






template <typename T>
class PNGImage {
public:
    PNGImage(const fs::path& path) : PNGImage([NSData dataWithContentsOfFile:@(path.c_str())]) {}
    
    PNGImage(NSData* nsdata) {
        image = [NSBitmapImageRep imageRepWithData:nsdata];
        assert(image);
        
        assert([image bitsPerSample] == 8*sizeof(T));
        width = [image pixelsWide];
        height = [image pixelsHigh];
        // samplesPerPixel = number of samples per pixel, including padding samples
        // validSamplesPerPixel = number of samples per pixel, excluding padding samples
        // For example, sometimes the alpha channel exists but isn't used, in which case:
        //        samplesPerPixel = 4
        //   validSamplesPerPixel = 3
        samplesPerPixel = ([image bitsPerPixel]/8) / sizeof(T);
        assert(samplesPerPixel==3 || samplesPerPixel==4);
        validSamplesPerPixel = [image samplesPerPixel];
        assert(validSamplesPerPixel==3 || validSamplesPerPixel==4);
        data = (T*)[image bitmapData];
        dataLen = width*height*samplesPerPixel*sizeof(T);
    }
    
    T sample(int y, int x, size_t channel) {
        assert(channel < validSamplesPerPixel);
        const size_t sx = _mirrorClamp(width, x);
        const size_t sy = _mirrorClamp(height, y);
        const size_t idx = samplesPerPixel*(width*sy+sx) + channel;
        assert(idx < dataLen);
        return data[idx];
    }
    
    NSBitmapImageRep* image = nullptr;
    size_t width = 0;
    size_t height = 0;
    size_t samplesPerPixel = 0;
    size_t validSamplesPerPixel = 0;
    T* data = nullptr;
    size_t dataLen = 0;
    
private:
    static size_t _mirrorClamp(size_t N, int n) {
        if (n < 0)                  return -n;
        else if ((size_t)n >= N)    return 2*(N-1)-(size_t)n;
        else                        return n;
    }
};

struct InputImage {
    Mat64 X[2];
};

static constexpr size_t H = 256;
static constexpr size_t W = 455;

struct ImageChannels {
public:
    ImageChannels() {}
    
    Mat<double,H,W>& operator[](size_t i) {
        assert(i < 3);
        return _c[i];
    }
    
    const Mat<double,H,W>& operator[](size_t i) const {
        assert(i < 3);
        return _c[i];
    }
private:
    Mat<double,H,W> _c[3];
};

// Compute a masked Local Absolute Deviation in sliding window fashion. The
// window size is 3x3. Only positions where mask(x, y) == true are considered
// in the absolute deviation computation. If the input image is between [a, b]
// then the output image will be between [0, b-a].
// This code with all mask(x ,y) == true should produce identical results to
// LocalAbsoluteDeviation().
ImageChannels MaskedLocalAbsoluteDeviation(const ImageChannels& im, const Mat<double,H,W>& mask) {
    
//    im_edge = {};
//    for c = 1:size(im,3)
//      numer = zeros(size(im,1), size(im,2), 'like', im);
//      denom = zeros(size(im,1), size(im,2), 'like', im);
//      for oi = -1:1
//        for oj = -1:1
//          if (oi == 0) && (oj == 0)
//            continue
//          end
//          im_shift = im_pad([1:size(im,1)] + oi + 1, [1:size(im,2)] + oj + 1, c);
//          mask_shift = mask_pad([1:size(im,1)] + oi + 1, [1:size(im,2)] + oj + 1);
//          numer = numer + mask .* mask_shift .* abs(im_shift - im(:,:,c));
//          denom = denom + mask .* mask_shift;
//        end
//      end
//      if strcmp(im_class, 'double')
//        im_edge{c} = numer ./ denom;
//      else
//        % This divide is ugly to make it match up with the non-masked code.
//        im_edge{c} = bitshift(bitshift(numer, 3) ./ denom, -3);
//      end
//    end
//    
//    
    return ImageChannels{};
}

//function im_edge = MaskedLocalAbsoluteDeviation(im, mask)
//im_class = class(im);
//
//if strcmp(im_class, 'uint16')
//  % Upgrade to 32-bit because we have minus here
//  im = int32(im);
//  im_pad = Pad1(im);
//  mask = int32(mask);
//  mask_pad = Pad1(mask);
//elseif strcmp(im_class, 'uint8')
//  % Upgrade to 16-bit because we have minus here
//  im = int16(im);
//  im_pad = Pad1(im);
//  mask = int16(mask);
//  mask_pad = Pad1(mask);
//elseif strcmp(im_class, 'double')
//  im_pad = Pad1(im);
//  mask_pad = Pad1(mask);
//else
//  assert(0)
//end
//
//im_edge = {};
//for c = 1:size(im,3)
//  numer = zeros(size(im,1), size(im,2), 'like', im);
//  denom = zeros(size(im,1), size(im,2), 'like', im);
//  for oi = -1:1
//    for oj = -1:1
//      if (oi == 0) && (oj == 0)
//        continue
//      end
//      im_shift = im_pad([1:size(im,1)] + oi + 1, [1:size(im,2)] + oj + 1, c);
//      mask_shift = mask_pad([1:size(im,1)] + oi + 1, [1:size(im,2)] + oj + 1);
//      numer = numer + mask .* mask_shift .* abs(im_shift - im(:,:,c));
//      denom = denom + mask .* mask_shift;
//    end
//  end
//  if strcmp(im_class, 'double')
//    im_edge{c} = numer ./ denom;
//  else
//    % This divide is ugly to make it match up with the non-masked code.
//    im_edge{c} = bitshift(bitshift(numer, 3) ./ denom, -3);
//  end
//end
//im_edge = cat(3, im_edge{:});
//
//if strcmp(im_class, 'uint16')
//  % Convert back to 16-bit
//  im_edge = uint16(im_edge);
//elseif strcmp(im_class, 'uint8')
//  % Convert back to 8-bit
//  im_edge = uint8(im_edge);
//end






//static InputImage readImage(const fs::path& path) {
//    PNGImage<uint16_t> img(path);
//    assert(img.height == H);
//    assert(img.width == W);
//    
//    #warning TODO: we need to mask out appropriate pixels (highlights=1 and shadows=0)
//    ImageChannels im_channels1;
//    for (int y=0; y<H; y++) {
//        for (int x=0; x<W; x++) {
//            for (int c=0; c<3; c++) {
//                im_channels1[c].at(y,x) = img.sample(y,x,c);
//            }
//        }
//    }
//    
//    ImageChannels im_channels2;
//    
//    printf("%f\n", im_channels1[2].at(4,5));
//    return {};
//    
//    
//    
////if isempty(mask)
////  mask = true(size(im,1), size(im,2));
////end
////
////im_channels = ChannelizeImage(im, mask);
////
////if isa(im, 'float')
////  assert(all(im(:) <= 1));
////  assert(all(im(:) >= 0));
////end
////
////X = {};
////for i_channel = 1:length(im_channels)
////
////  im_channel = im_channels{i_channel};
////
////  log_im_channel = {};
////  for c = 1:size(im_channel, 3)
////    log_im_channel{c} = log(double(im_channel(:,:,c)));
////  end
////  u = log_im_channel{2} - log_im_channel{1};
////  v = log_im_channel{2} - log_im_channel{3};
////
////  % Masked pixels or those with invalid log-chromas (nan or inf) are
////  % ignored.
////  valid = ~isinf(u) & ~isinf(v) & ~isnan(u) & ~isnan(v) & mask;
////
////  % Pixels whose intensities are less than a (scaled) minimum_intensity are
////  % ignored. This enables repeatable behavior for different input types,
////  % otherwise we see behavior where the input type affects output features
////  % strongly just by how intensity values get quantized to 0.
////  if isa(im, 'float')
////    min_val = params.HISTOGRAM.MINIMUM_INTENSITY;
////  else
////    min_val = intmax(class(im)) * params.HISTOGRAM.MINIMUM_INTENSITY;
////  end
////  valid = valid & all(im_channel >= min_val, 3);
////
////  Xc = Psplat2(u(valid), v(valid), ones(nnz(valid),1), ...
////    params.HISTOGRAM.STARTING_UV, params.HISTOGRAM.BIN_SIZE, ...
////    params.HISTOGRAM.NUM_BINS);
////
////  Xc = Xc / max(eps, sum(Xc(:)));
////
////  X{end+1} = Xc;
////end
////
////X = cat(3, X{:});
//    
//    
//    
//}

static void writePNG(Renderer& renderer, id<MTLTexture> txt, const fs::path& path) {
    id img = renderer.createCGImage(txt);
    if (!img) throw std::runtime_error("CGBitmapContextCreateImage returned nil");
    
    id imgDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
        (CFURLRef)[NSURL fileURLWithPath:@(path.c_str())], kUTTypePNG, 1, nullptr));
    if (!imgDest) throw std::runtime_error("CGImageDestinationCreateWithURL returned nil");
    CGImageDestinationAddImage((CGImageDestinationRef)imgDest, (CGImageRef)img, nullptr);
    CGImageDestinationFinalize((CGImageDestinationRef)imgDest);
}

template <typename T, size_t H, size_t W, size_t Depth>
struct MatImage { Mat<T,H,W> c[Depth]; };

template <typename T, size_t H, size_t W, size_t Depth>
using MatImagePtr = std::unique_ptr<MatImage<T,H,W,Depth>>;

template <typename T, size_t H, size_t W, size_t Depth>
MatImagePtr<T,H,W,Depth> MatImageFromTexture(Renderer& renderer, id<MTLTexture> txt) {
    assert([txt height] == H);
    assert([txt width] == W);
    
    using Sample = uint16_t; // Only support 16-bit samples for now
    const MTLPixelFormat fmt = [txt pixelFormat];
    assert(fmt==MTLPixelFormatR16Unorm || fmt==MTLPixelFormatRGBA16Unorm);
    const size_t bytesPerSample = Renderer::BytesPerSample(fmt);
    assert(bytesPerSample == sizeof(Sample));
    const size_t samplesPerPixel = Renderer::SamplesPerPixel(fmt);
    const size_t sampleCount = samplesPerPixel*W*H;
    auto samples = std::make_unique<Sample[]>(sampleCount);
    renderer.textureRead(txt, samples.get(), sampleCount);
    
    auto matImage = std::make_unique<MatImage<T,H,W,Depth>>();
    for (int y=0; y<H; y++) {
        for (int x=0; x<W; x++) {
            for (int c=0; c<samplesPerPixel; c++) {
                if (c < Depth) {
                    if constexpr (std::is_same_v<T, float> || std::is_same_v<T, double>) {
                        matImage->c[c].at(y,x) = (T)samples[samplesPerPixel*(y*W+x) + c] /
                            std::numeric_limits<Sample>::max();
                    } else {
                        matImage->c[c].at(y,x) = samples[samplesPerPixel*(y*W+x) + c];
                    }
                }
            }
        }
    }
    return matImage;
}

void calcX(const FFCCModel& model, Renderer& renderer, id<MTLTexture> txt, id<MTLTexture> mask) {
    Renderer::Txt u = renderer.createTexture(MTLPixelFormatR32Float, W, H);
    renderer.render("CalcU", u,
        // Texture args
        txt
    );
    
    Renderer::Txt v = renderer.createTexture(MTLPixelFormatR32Float, W, H);
    renderer.render("CalcV", v,
        // Texture args
        txt
    );
    
    Renderer::Txt maskUV = renderer.createTexture(MTLPixelFormatR8Unorm, W, H);
    {
        const float threshold = model.params.histogram.minIntensity;
        renderer.render("CalcMaskUV", maskUV,
            // Buffer args
            threshold,
            // Texture args
            mask,
            u,
            v
        );
    }
}

int main(int argc, const char* argv[]) {
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
    
    PNGImage<uint16_t> png("/Users/dave/repos/ffcc/data/AR0330/indoor_night2_132.png");
    assert(png.height == H);
    assert(png.width == W);
    
    // Create a texture and load it with the data from `img`
    Renderer::Txt img = renderer.createTexture(MTLPixelFormatRGBA16Unorm, W, H);
    renderer.textureWrite(img, png.data, png.samplesPerPixel);
    
    Renderer::Txt mask = renderer.createTexture(MTLPixelFormatR8Unorm, W, H);
    renderer.render("CreateMask", mask,
        // Texture args
        img
    );
    
    Renderer::Txt imgMasked = renderer.createTexture(MTLPixelFormatRGBA16Unorm, W, H);
    renderer.render("ApplyMask", imgMasked,
        // Texture args
        img,
        mask
    );
    
    Renderer::Txt imgAbsDev = renderer.createTexture(MTLPixelFormatRGBA16Unorm, W, H);
    {
        Renderer::Txt coeff = renderer.createTexture(MTLPixelFormatR32Float, W, H);
        renderer.render("LocalAbsoluteDeviationCoeff", coeff,
            mask
        );
        
        renderer.render("LocalAbsoluteDeviation", imgAbsDev,
            img,
            mask,
            coeff
        );
    }
    
    renderer.sync(imgMasked);
    renderer.sync(imgAbsDev);
    renderer.commitAndWait();
    
    auto im_channels1 = MatImageFromTexture<double,H,W,3>(renderer, imgMasked);
    assert(equal(W_FI, im_channels1->c, "im_channels1"));
    
    auto im_channels2 = MatImageFromTexture<double,H,W,3>(renderer, imgAbsDev);
    assert(equal(W_FI, im_channels2->c, "im_channels2"));
    
    
    
    
    
    
    FFCCModel model = {
        .params = {
            .hyperparams = {
                .vonMisesDiagonalEps = 0.148650889375340,    // std::pow(2, -2.75)
            },
            
            .histogram = {
                .binSize = 1./32,
                .startingUV = -0.531250,
                .minIntensity = 1./256,
            },
        },
    };
    load(W_EM, "F_fft", model.F_fft);
    load(W_EM, "B", model.B);
    
    Mat64 X[2];
    load(W_EM, "X", X);
    
    const Mat64c X_fft[2] = {X[0].fft(), X[1].fft()};
    assert(equal(W_EM, X_fft, "X_fft"));
    
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

#import <filesystem>
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/Mat.h"
#import "/Applications/MATLAB_R2021a.app/extern/include/mat.h"

template <typename T, size_t H, size_t W, size_t Depth>
double _rmsdiff(const Mat<T,H,W>* a, const Mat<T,H,W>* b) {
    double r = 0;
    for (size_t z=0; z<Depth; z++) {
        for (size_t y=0; y<H; y++) {
            for (size_t x=0; x<W; x++) {
                const T va = a[z].at(y,x);
                const T vb = b[z].at(y,x);
                const double d = std::abs(va-vb); // Using abs() so that this works on complex numbers
                r += d*d;
            }
        }
    }
    r /= H*W;
    r = std::sqrt(r);
    return r;
}

template <typename T, size_t H, size_t W, size_t Depth>
double rmsdiff(const Mat<T,H,W> (&a)[Depth], const Mat<T,H,W> (&b)[Depth]) {
    return _rmsdiff<T,H,W,Depth>(a, b);
}

template <typename T, size_t H, size_t W>
double rmsdiff(const Mat<T,H,W>& a, const Mat<T,H,W>& b) {
    return _rmsdiff<T,H,W,1>(&a, &b);
}

template <typename T, size_t H, size_t W, size_t Depth>
bool _equal(const Mat<T,H,W>* a, const Mat<T,H,W>* b) {
    constexpr double Eps = 1e-11;
    return _rmsdiff<T,H,W,Depth>(a, b) < Eps;
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
void _load(mxArray* mxa, Mat<T,H,W>* var) {
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
void load(mxArray* mxa, Mat<T,H,W> (&var)[Depth]) {
    _load<T,H,W,Depth>(mxa, var);
}

template <typename T, size_t H, size_t W>
void load(mxArray* mxa, Mat<T,H,W>& var) {
    _load<T,H,W,1>(mxa, &var);
}

template <typename T>
void load(mxArray* mxa, T& var) {
    auto m = std::make_unique<Mat<T,1,1>>();
    _load<T,1,1,1>(mxa, m.get());
    var = m[0];
}

template <typename T>
void load(MATFile* f, const char* name, T& var) {
    load(matGetVariable(f, name), var);
}




//template <typename T, size_t H, size_t W, size_t Depth>
//void load(MATFile* f, const char* name, Mat<T,H,W> (&var)[Depth]) {
//    _load<T,H,W,Depth>(matGetVariable(f, name), var);
//}
//
//template <typename T, size_t H, size_t W>
//void load(MATFile* f, const char* name, Mat<T,H,W>& var) {
//    _load<T,H,W,1>(matGetVariable(f, name), &var);
//}
//
//template <typename T>
//void load(MATFile* f, const char* name, T& var) {
//    auto m = std::make_unique<Mat<T,1,1>>();
//    _load<T,1,1,1>(matGetVariable(f, name), m.get());
//    var = m[0];
//}

template <typename T, size_t H, size_t W, size_t Depth>
struct MatImage { Mat<T,H,W> c[Depth]; };

template <typename T, size_t H, size_t W, size_t Depth>
MatImage<T,H,W,Depth> MatImageFromTexture(MDCTools::Renderer& renderer, id<MTLTexture> txt) {
    using namespace MDCTools;
    
    assert([txt height] == H);
    assert([txt width] == W);
    
    const MTLPixelFormat fmt = [txt pixelFormat];
    bool srcUnorm = false;
    switch (fmt) {
    case MTLPixelFormatR8Unorm:
    case MTLPixelFormatR16Unorm:
    case MTLPixelFormatRGBA16Unorm:
        srcUnorm = true;
        break;
    case MTLPixelFormatR32Float:
    case MTLPixelFormatRGBA32Float:
        break;
    default:
        abort(); // Unsupported format
    }
    const size_t samplesPerPixel = Renderer::SamplesPerPixel(fmt);
    const size_t bytesPerSample = Renderer::BytesPerSample(fmt);
    const size_t sampleCount = samplesPerPixel*W*H;
    const size_t len = sampleCount*bytesPerSample;
    auto buf = std::make_unique<uint8_t[]>(len);
    uint8_t* bufU8 = (uint8_t*)buf.get();
    uint16_t* bufU16 = (uint16_t*)buf.get();
    float* bufFloat = (float*)buf.get();
    if (bytesPerSample == 1) {
        renderer.textureRead(txt, bufU8, sampleCount);
    } else if (bytesPerSample == 2) {
        renderer.textureRead(txt, bufU16, sampleCount);
    } else if (bytesPerSample == 4) {
        renderer.textureRead(txt, bufFloat, sampleCount);
    } else {
        abort();
    }
    
    MatImage<T,H,W,Depth> matImage;
    for (int y=0; y<H; y++) {
        for (int x=0; x<W; x++) {
            for (int c=0; c<samplesPerPixel; c++) {
                if (c < Depth) {
                    if constexpr (std::is_same_v<T, float> || std::is_same_v<T, double>) {
                        if (srcUnorm) {
                            if (bytesPerSample == 1) {
                                // Source is unorm, destination is float: normalize
                                matImage.c[c].at(y,x) = (T)bufU8[samplesPerPixel*(y*W+x)+c] / 255;
                            } else if (bytesPerSample == 2) {
                                // Source is unorm, destination is float: normalize
                                matImage.c[c].at(y,x) = (T)bufU16[samplesPerPixel*(y*W+x)+c] / 65535;
                            }

                        } else {
                            // Source isn't a unorm, destination is float: just assign
                            matImage.c[c].at(y,x) = bufFloat[samplesPerPixel*(y*W+x)+c];
                        }
                    } else {
                        if (bytesPerSample == 1) {
                            // Destination isn't float
                            matImage.c[c].at(y,x) = bufU8[samplesPerPixel*(y*W+x)+c];
                        } else if (bytesPerSample == 2) {
                            // Destination isn't float
                            matImage.c[c].at(y,x) = bufU16[samplesPerPixel*(y*W+x)+c];
                        }
                    }
                }
            }
        }
    }
    return matImage;
}

void writePNG(MDCTools::Renderer& renderer, id<MTLTexture> txt, const std::filesystem::path& path) {
    id img = renderer.imageCreate(txt);
    if (!img) throw std::runtime_error("CGBitmapContextCreateImage returned nil");
    
    id imgDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
        (CFURLRef)[NSURL fileURLWithPath:@(path.c_str())], kUTTypePNG, 1, nullptr));
    if (!imgDest) throw std::runtime_error("CGImageDestinationCreateWithURL returned nil");
    CGImageDestinationAddImage((CGImageDestinationRef)imgDest, (CGImageRef)img, nullptr);
    CGImageDestinationFinalize((CGImageDestinationRef)imgDest);
}

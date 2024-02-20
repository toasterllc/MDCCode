#import "BaseView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <simd/simd.h>
#import <fstream>
#import <filesystem>
#import <map>
#import <set>
#import <chrono>
#import "ImageLayer.h"
#import "Code/Lib/Toastbox/Mmap.h"
#import "Code/Lib/Toastbox/Mac/Util.h"
#import "Code/Lib/Toastbox/Mac/CFA.h"
#import "Code/Lib/Toastbox/Mac/Mat.h"
#import "Code/Lib/Toastbox/Mac/Color.h"
#import "Util.h"
#import "MainView.h"
#import "HistogramView.h"
#import "ColorChecker.h"
#import "Tools/Shared/MDCUSBDevice.h"
#import "IOServiceMatcher.h"
#import "IOServiceWatcher.h"
#import "Assert.h"
#import "ImagePipelineTypes.h"
#import "PixelSampler.h"
#import "Img.h"
#import "ImgAutoExposure.h"
#import "ChecksumFletcher32.h"
#import "ELF32Binary.h"
#import "ImagePipeline.h"
#import "EstimateIlluminant.h"
#import "ColorMatrix.h"
#import "MDCDevicesManager.h"
using namespace CFAViewer;
using namespace ImagePipeline;
using namespace Toastbox;
using namespace std::chrono;
namespace fs = std::filesystem;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

using ImagePaths = std::vector<fs::path>;
using ImagePathsIter = ImagePaths::iterator;

struct ExposureSettings {
    bool autoExposureEnabled = false;
    MDCUSBDevice::ImgExposure exposure;
};

struct RawImage {
    Toastbox::CFADesc cfaDesc;
    size_t width = 0;
    size_t height = 0;
    const Img::Pixel* pixels = nullptr;
};

@interface AppDelegate : NSObject <NSApplicationDelegate, MainViewDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet NSWindow* _inspectorWindow;
    IBOutlet MainView* _mainView;
    
    IBOutlet NSSwitch* _streamImagesSwitch;
    
    IBOutlet NSButton* _autoExposureCheckbox;
    
    IBOutlet NSSlider* _coarseIntegrationTimeSlider;
    IBOutlet NSTextField* _coarseIntegrationTimeLabel;
    
    IBOutlet NSSlider* _fineIntegrationTimeSlider;
    IBOutlet NSTextField* _fineIntegrationTimeLabel;
    
    IBOutlet NSSwitch* _analogGainSlider;
    IBOutlet NSTextField* _analogGainLabel;
    
    IBOutlet NSButton* _colorCheckersCheckbox;
    IBOutlet NSButton* _resetColorCheckersButton;
    
    IBOutlet NSButton* _illumCheckbox;
    IBOutlet NSTextField* _illumTextField;
    
    IBOutlet NSButton* _colorMatrixCheckbox;
    IBOutlet NSTextField* _colorMatrixTextField;
    
    IBOutlet NSButton* _defringeCheckbox;
    IBOutlet NSSlider* _defringeRoundsSlider;
    IBOutlet NSTextField* _defringeRoundsLabel;
    IBOutlet NSSlider* _defringeαThresholdSlider;
    IBOutlet NSTextField* _defringeαThresholdLabel;
    IBOutlet NSSlider* _defringeγThresholdSlider;
    IBOutlet NSTextField* _defringeγThresholdLabel;
    IBOutlet NSSlider* _defringeγFactorSlider;
    IBOutlet NSTextField* _defringeγFactorLabel;
    IBOutlet NSSlider* _defringeδFactorSlider;
    IBOutlet NSTextField* _defringeδFactorLabel;
    
    IBOutlet NSButton* _reconstructHighlightsCheckbox;
    
    IBOutlet NSButton* _debayerLMMSEGammaCheckbox;
    
    IBOutlet NSSlider* _exposureSlider;
    IBOutlet NSTextField* _exposureLabel;
    IBOutlet NSSlider* _brightnessSlider;
    IBOutlet NSTextField* _brightnessLabel;
    IBOutlet NSSlider* _contrastSlider;
    IBOutlet NSTextField* _contrastLabel;
    IBOutlet NSSlider* _saturationSlider;
    IBOutlet NSTextField* _saturationLabel;
    
    IBOutlet NSSlider* _localContrastAmountSlider;
    IBOutlet NSTextField* _localContrastAmountLabel;
    IBOutlet NSSlider* _localContrastRadiusSlider;
    IBOutlet NSTextField* _localContrastRadiusLabel;
    
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
    
    IBOutlet NSTextField* _colorText_Raw;
    IBOutlet NSTextField* _colorText_XYZD50;
    IBOutlet NSTextField* _colorText_LSRGB;
    
    IBOutlet NSSlider*      _highlightFactorR0Slider;
    IBOutlet NSTextField*   _highlightFactorR0Label;
    IBOutlet NSSlider*      _highlightFactorR1Slider;
    IBOutlet NSTextField*   _highlightFactorR1Label;
    IBOutlet NSSlider*      _highlightFactorR2Slider;
    IBOutlet NSTextField*   _highlightFactorR2Label;
    
    IBOutlet NSSlider*      _highlightFactorG0Slider;
    IBOutlet NSTextField*   _highlightFactorG0Label;
    IBOutlet NSSlider*      _highlightFactorG1Slider;
    IBOutlet NSTextField*   _highlightFactorG1Label;
    IBOutlet NSSlider*      _highlightFactorG2Slider;
    IBOutlet NSTextField*   _highlightFactorG2Label;
    
    IBOutlet NSSlider*      _highlightFactorB0Slider;
    IBOutlet NSTextField*   _highlightFactorB0Label;
    IBOutlet NSSlider*      _highlightFactorB1Slider;
    IBOutlet NSTextField*   _highlightFactorB1Label;
    IBOutlet NSSlider*      _highlightFactorB2Slider;
    IBOutlet NSTextField*   _highlightFactorB2Label;
    
    ExposureSettings _exposureSettings;
    
    bool _colorCheckersEnabled;
    float _colorCheckerCircleRadius;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        bool running = false;
        bool cancel = false;
        ExposureSettings exposureSettings;
        Img::Pixel pixels[2200*2200];
        uint32_t width = 0;
        uint32_t height = 0;
    } _streamImagesThread;
    
    Renderer _renderer;
    id<MTLDevice> _device;
    Pipeline::Options _pipelineOptions;
    Pipeline::Options _pipelineOptionsPost;
    Renderer::Txt _txt;
    
    MDCStudio::Object::ObserverPtr _mdcDevicesOb;
    MDCStudio::MDCDeviceRealPtr _mdcDevice;
    
    struct {
        Img::Pixel pixels[2200*2200];
        RawImage image = {
            .cfaDesc = {
                Toastbox::CFAColor::Green, Toastbox::CFAColor::Red,
                Toastbox::CFAColor::Blue, Toastbox::CFAColor::Green,
            },
            .width = 0,
            .height = 0,
            .pixels = pixels,
        };
    } _raw;
    
    Toastbox::Color<Toastbox::ColorSpace::Raw> _sampleRaw;
    Toastbox::Color<Toastbox::ColorSpace::XYZD50> _sampleXYZD50;
    Toastbox::Color<Toastbox::ColorSpace::LSRGB> _sampleLSRGB;
    
    ImagePaths _imagePaths;
    ImagePathsIter _imagePathIter;
    std::optional<Color<ColorSpace::Raw>> _whiteBalanceColor;
    std::optional<CGRect> _focusPosterRect;
}

- (void)awakeFromNib {
    MDCStudio::MDCDevicesManager::IncompatibleVersionHandler handler = [=] (const MDCUSBDevice::IncompatibleVersion& e) {
        MDCUSBDevice::IncompatibleVersion ecopy = e;
        dispatch_async(dispatch_get_main_queue(), ^{
            abort();
        });
    };
    
    MDCDevicesManagerGlobal(MDCStudio::Object::Create<MDCStudio::MDCDevicesManager>(handler));

    _whiteBalanceColor = {0.263170, 0.278725, 0.097797};
    __weak auto weakSelf = self;
    
    _device = MTLCreateSystemDefaultDevice();
    _renderer = Renderer(_device, [_device newDefaultLibrary], [_device newCommandQueue]);
    
    static constexpr Toastbox::CFADesc CFADesc = {
        Toastbox::CFAColor::Green, Toastbox::CFAColor::Red,
        Toastbox::CFAColor::Blue, Toastbox::CFAColor::Green,
    };
    
    _pipelineOptions = {
        .cfaDesc = CFADesc,
        
        .illum = std::nullopt,
        .colorMatrix = std::nullopt,
        
        .defringe = { .en = false, },
        .reconstructHighlights = { .en = false, },
        .debayerLMMSE = { .applyGamma = true, },
        
        .exposure = 0,
        .saturation = 0,
        .brightness = 0,
        .contrast = 0,
        
        .localContrast = {
            .amount = .5,
            .radius = 50,
        },
    };
    
    _colorCheckerCircleRadius = 5;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    // /Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker/outdoor_5pm_45.cfa
//    [self _loadImages:{"/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker"}];
//    [self _loadImages:{"/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker"}];
//    [self _loadImages:{"/Users/dave/repos/ffcc/data/AR0330_64x36/outdoor_5pm_43.cfa"}];
    
//    [self _loadImages:{"/Users/dave/repos/ffcc/data/AR0330_64x36/indoor_night2_200.cfa"}];
//    [self _loadImages:{"/Users/dave/repos/ffcc/data/AR0330_64x36/outdoor_5pm_78.cfa"}];
//    [self _loadImages:{"/Users/dave/repos/ffcc/data/AR0330_64x36/indoor_night2_64.cfa"}];
    
    auto points = [self _prefsColorCheckerPositions];
    if (!points.empty()) {
        [_mainView setColorCheckerPositions:points];
    }
    
    [self _setExposureSettings:{
        .autoExposureEnabled = true,
    }];
    [self _setMDCDevice:nullptr];
    
    // Observe devices connecting/disconnecting
    {
        __weak auto selfWeak = self;
        _mdcDevicesOb = MDCStudio::MDCDevicesManagerGlobal()->observerAdd([=] (auto, auto) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _handleMDCDevicesChanged]; });
        });
    }
    
    [self _handleMDCDevicesChanged];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    // Hack -- we need to be document-based, and each document should handle this
    if ([item action] == @selector(_nextImage:) ||
        [item action] == @selector(_previousImage:)) {
        return [[[NSApp mainWindow] sheets] count] == 0;
    }
    return true;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    [self _streamImagesStop];
    
    // no_destroy attribute is required, otherwise DeviceLocks would be destroyed and
    // relinquish the locks, which is exactly what we don't want to do! The locks need
    // to be held throughout termination to prevent device IO, to ensure the device is
    // kept out of host mode.
    [[clang::no_destroy]]
    static std::vector<std::unique_lock<std::mutex>> DeviceLocks;
    
    // Ensure that all devices are out of host mode when we exit, by acquiring each device's
    // device lock and stashing the locks in our global DeviceLocks.
    MDCStudio::MDCDevicesManagerPtr devicesManager = MDCStudio::MDCDevicesManagerGlobal();
    const std::vector<MDCStudio::MDCDeviceRealPtr> devices = devicesManager->devices();
    for (MDCStudio::MDCDeviceRealPtr device : devices) {
        DeviceLocks.push_back(device->deviceLock(true));
    }
    printf("applicationShouldTerminate\n");
    return NSTerminateNow;
}

static std::vector<std::string> split(const std::string& str, char delim) {
    std::stringstream ss(str);
    std::string part;
    std::vector<std::string> parts;
    while (std::getline(ss, part, delim)) {
        parts.push_back(part);
    }
    return parts;
}

static bool less(const fs::path& a, const fs::path& b) {
    const std::string aFilename = a.filename().replace_extension().string();
    const std::string bFilename = b.filename().replace_extension().string();
    const std::vector<std::string> aParts = split(aFilename, '_');
    const std::vector<std::string> bParts = split(bFilename, '_');
    
    for (int i=0; i<(int)std::min(aParts.size(), bParts.size())-1; i++) {
        const std::string& aPart = aParts[i];
        const std::string& bPart = bParts[i];
        if (aPart != bPart) {
            return aPart<bPart;
        }
    }
    
    // If `aParts` and `bParts` have mismatched sizes, return a bool
    // reflecting the smaller of them.
    if (aParts.size() != bParts.size()) {
        return (aParts.size() < bParts.size() ? true : false);
    }
    
    const std::string& aLast = aParts.back();
    const std::string& bLast = bParts.back();
    
    const int aLastInt = std::stoi(aLast);
    const int bLastInt = std::stoi(bLast);
    
    return aLastInt < bLastInt;
}

static bool isCFAFile(const fs::path& path) {
    return path.string().at(0) != '.';
//    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

- (void)_loadImages:(const ImagePaths&)paths {
    _imagePaths.clear();
    
    for (const fs::path& p : paths) {
        // Regular file
        if (isCFAFile(p)) {
            _imagePaths.push_back(p);
        
        // Directory
        } else if (fs::is_directory(p)) {
            for (const auto& p2 : fs::directory_iterator(p)) {
                if (isCFAFile(p2)) {
                    _imagePaths.push_back(p2);
                }
            }
        }
    }
    
    std::sort(_imagePaths.begin(), _imagePaths.end(), less);
    
    // Load the first image
    _imagePathIter = _imagePaths.begin();
    if (_imagePathIter != _imagePaths.end()) {
        [self _loadImage:*_imagePathIter];
    }
}

- (void)_loadImage:(const fs::path&)path {
    std::cout << path.filename().string() << "\n";
    
    const Toastbox::Mmap imgData(path);
    
    // Support 2 different filetypes:
    // (1) solely raw pixel data
    if (imgData.len() == Img::Full::PixelLen) {
        _raw.image.width = Img::Full::PixelWidth;
        _raw.image.height = Img::Full::PixelHeight;
        
        // Copy the image data into _raw.image
        memcpy(_raw.pixels, imgData.data(), Img::Full::PixelLen);
    
    // (2) header + raw pixel data + checksum
    } else if (imgData.len()==Img::Full::ImageLen || imgData.len()==ImgSD::Full::ImagePaddedLen) {
        const Img::Header& header = *(Img::Header*)imgData.data();
        
        _raw.image.width = header.imageWidth;
        _raw.image.height = header.imageHeight;
        
        // Copy the image data into _raw.image
        memcpy(_raw.pixels, imgData.data()+Img::PixelsOffset, Img::Full::PixelLen);
        
        // Validate checksum
        const uint32_t checksumExpected = ChecksumFletcher32(imgData.data(), Img::Full::ChecksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, imgData.data()+Img::Full::ChecksumOffset, sizeof(checksumGot));
        assert(checksumExpected == checksumGot);
    
    // (3) header + raw pixel data + checksum
    } else if (imgData.len()==Img::Thumb::ImageLen || imgData.len()==ImgSD::Thumb::ImagePaddedLen) {
        const Img::Header& header = *(Img::Header*)imgData.data();
        
        _raw.image.width = header.imageWidth;
        _raw.image.height = header.imageHeight;
        
        // Copy the image data into _raw.image
        memcpy(_raw.pixels, imgData.data()+Img::PixelsOffset, Img::Thumb::PixelLen);
        
        // Validate checksum
        const uint32_t checksumExpected = ChecksumFletcher32(imgData.data(), Img::Thumb::ChecksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, imgData.data()+Img::Thumb::ChecksumOffset, sizeof(checksumGot));
        assert(checksumExpected == checksumGot);
    
    // invaid image
    } else {
        abort();
    }
    
    [self _render];
}

- (IBAction)_previousImage:(id)sender {
    if (_imagePathIter == _imagePaths.begin()) {
        NSBeep();
        return;
    }
    _imagePathIter--;
    [self _loadImage:*_imagePathIter];
}

- (IBAction)_nextImage:(id)sender {
    // Don't allow going further if we're already past the end,
    // or the next item is past the end.
    if (_imagePathIter==_imagePaths.end() || std::next(_imagePathIter)==_imagePaths.end()) {
        NSBeep();
        return;
    }
    _imagePathIter++;
    [self _loadImage:*_imagePathIter];
}

// MARK: - MDCUSBDevice

static void _nop(void* ctx, io_iterator_t iter) {}

static void _configureDevice(MDCUSBDevice& dev) {
    {
        const char* ICEBinPath = "/Users/dave/repos/MDCCode/Code/ICE40/ICEAppImgCaptureSTM/Synth/Top.bin";
        Mmap mmap(ICEBinPath);
        
        // Write the ICE40 binary
        dev.iceRAMWrite(mmap.data(), mmap.len());
    }
}

- (void)_renderCompleted:(const Pipeline::Options&)opts {
    // Update the estimated illuminant in the inspector UI
    assert(opts.illum);
    assert(opts.colorMatrix);
    _pipelineOptionsPost = opts;
    [self _updateInspectorUI];
}

static simd::float3 _SimdForMat(const Mat<double,3,1>& m) {
    return {
        simd::float3{(float)m[0], (float)m[1], (float)m[2]},
    };
}

static simd::float3x3 _SimdForMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
    };
}

static std::tuple<std::unique_ptr<float[]>,size_t> _SamplesRead(Renderer& renderer, const SampleRect& rect, const Renderer::Txt& txt) {
    const size_t w = rect.right-rect.left;
    const size_t h = rect.bottom-rect.top;
    const size_t sampleCount = w*h;
    std::unique_ptr<float[]> samples = std::make_unique<float[]>(sampleCount);
    renderer.textureRead(txt, samples.get(), sampleCount, MTLRegionMake2D(rect.left, rect.top, w, h));
    return std::make_tuple(std::move(samples), sampleCount);
}

- (void)_render {
    constexpr int32_t GrayWidth  = 2304/2;
    constexpr int32_t GrayHeight = 1296/2;
    constexpr int32_t SearchRegionWidth   =  75;
    constexpr int32_t SearchRegionHeight  = 100;
    constexpr int32_t SearchRegionOffsetX =   0;
    constexpr int32_t SearchRegionOffsetY = -20;
    constexpr SampleRect FocusPosterSearchRegion = {
        .left   =  GrayWidth/2 -  SearchRegionWidth/2 + SearchRegionOffsetX,
        .right  =  GrayWidth/2 +  SearchRegionWidth/2 + SearchRegionOffsetX,
        .top    = GrayHeight/2 - SearchRegionHeight/2 + SearchRegionOffsetY,
        .bottom = GrayHeight/2 + SearchRegionHeight/2 + SearchRegionOffsetY,
    };
    
    constexpr int32_t FocusPosterWidth  = 26;
    constexpr int32_t FocusPosterHeight = 33;
    
    Renderer::Txt rawTxt = Pipeline::TextureForRaw(_renderer, _raw.image.width, _raw.image.height, _raw.image.pixels);
    
    if (!_txt || [_txt width]!=_raw.image.width || [_txt height]!=_raw.image.height) {
        // _txt: using RGBA16 (instead of RGBA8 or similar) so that we maintain a full-depth
        // representation of the pipeline result without clipping to 8-bit components, so we can
        // render to an HDR display and make use of the depth.
        _txt = _renderer.textureCreate(rawTxt, MTLPixelFormatRGBA16Float);
    }
    
    Pipeline::Options popts = _pipelineOptions;
    if (!popts.illum) popts.illum = EstimateIlluminant::Run(_renderer, _raw.image.cfaDesc, rawTxt);
    if (!popts.colorMatrix) popts.colorMatrix = MDCStudio::ColorMatrixForIlluminant(*popts.illum).matrix;
    
    
    // White balance
    Color<ColorSpace::Raw> color = (_whiteBalanceColor ? *_whiteBalanceColor : Color<ColorSpace::Raw>{1,1,1});
//    Color<ColorSpace::Raw> illum = (_whiteBalanceColor ? *_whiteBalanceColor : Color<ColorSpace::Raw>{1,1,1});
//    if (_whiteBalanceColor) {
//        illum = *_whiteBalanceColor;
//    }
    const double factor = std::max(std::max(color[0], color[1]), color[2]);
//    const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
    const Mat<double,3,1> wb(factor/color[0], factor/color[1], factor/color[2]);
    const simd::float3 simdWB = _SimdForMat(wb);
    _renderer.render(rawTxt,
        _renderer.FragmentShader("MDCTools::ImagePipeline::Shader::" "Base::WhiteBalanceRaw",
            // Buffer args
            _raw.image.cfaDesc,
            simdWB,
            // Texture args
            rawTxt
        )
    );
    
    
    Renderer::Txt grayTxt = _renderer.textureCreate(MTLPixelFormatR32Float, _raw.image.width/2, _raw.image.height/2);
    _renderer.render(grayTxt,
        _renderer.FragmentShader("GrayscaleForRaw",
            // Texture args
            rawTxt
        )
    );
    
//    Renderer::Txt grayTxt = _renderer.textureCreate(MTLPixelFormatRGBA8Unorm_sRGB, _raw.image.width/2, _raw.image.height/2);
//    _renderer.render(grayTxt,
//        _renderer.FragmentShader("GrayscaleRGBForRaw",
//            // Texture args
//            rawTxt
//        )
//    );
    
    _renderer.render(grayTxt,
        _renderer.FragmentShader("SearchRegionDarken",
            // Buffer args
            FocusPosterSearchRegion,
            // Texture args
            grayTxt
        )
    );
    
    
    _renderer.sync(grayTxt);
    _renderer.commitAndWait();
    
    
    
    
    
    {
        auto [ samples, sampleCount ] = _SamplesRead(_renderer, FocusPosterSearchRegion, grayTxt);
        
        const int32_t W = FocusPosterSearchRegion.right-FocusPosterSearchRegion.left;
        const int32_t H = FocusPosterSearchRegion.bottom-FocusPosterSearchRegion.top;
        
        // Calculate `avgRow`
        std::unique_ptr<float[]> avgRow = std::make_unique<float[]>(H);
        for (int32_t y=0; y<H; y++) {
            float avg = 0;
            for (int32_t x=0; x<W; x++) {
                const float s = samples[y*W + x];
                avg += s;
            }
            avg /= W;
            avgRow[y] = avg;
        }
        
        // Calculate `avgCol`
        std::unique_ptr<float[]> avgCol = std::make_unique<float[]>(W);
        for (int32_t x=0; x<W; x++) {
            float avg = 0;
            for (int32_t y=0; y<H; y++) {
                const float s = samples[y*W + x];
                avg += s;
            }
            avg /= H;
            avgCol[x] = avg;
        }
        
        // Calculate background color
//        const float bg = (avgRow[0] + avgRow[H-1] + avgCol[0] + avgCol[W-1]) / 4;
        
        // Calculate `stdDevRow`
        std::unique_ptr<float[]> stdDevRow = std::make_unique<float[]>(H);
        for (int32_t y=0; y<H; y++) {
            float sum = 0;
            for (int32_t x=0; x<W; x++) {
                const float s = samples[y*W + x];
                const float d = s - avgRow[y];
                sum += d*d;
            }
            sum /= W;
            stdDevRow[y] = std::sqrt(sum);
        }
        
        // Calculate `stdDevCol`
        std::unique_ptr<float[]> stdDevCol = std::make_unique<float[]>(W);
        for (int32_t x=0; x<W; x++) {
            float sum = 0;
            for (int32_t y=0; y<H; y++) {
                const float s = samples[y*W + x];
                const float d = s - avgCol[x];
                sum += d*d;
            }
            sum /= H;
            stdDevCol[x] = std::sqrt(sum);
//            printf("%.5f ", std::sqrt(sum));
        }
//        printf("\n");
//        printf("\n ======================= \n");
        
        // Calculate `stdDevRowDelta`
        std::unique_ptr<float[]> stdDevRowDelta = std::make_unique<float[]>(H-1);
        for (int32_t y=0; y<H-1; y++) {
            stdDevRowDelta[y] = stdDevRow[y] - stdDevRow[y+1];
        }
        
        // Calculate `stdDevColDelta`
        std::unique_ptr<float[]> stdDevColDelta = std::make_unique<float[]>(W-1);
        for (int32_t x=0; x<W-1; x++) {
            stdDevColDelta[x] = stdDevCol[x] - stdDevCol[x+1];
        }
        
        int32_t xMinIdx = 0;
        int32_t xMaxIdx = 0;
        int32_t yMinIdx = 0;
        int32_t yMaxIdx = 0;
        float xMin = INFINITY;
        float xMax = -INFINITY;
        float yMin = INFINITY;
        float yMax = -INFINITY;
        
        // Calculate yMinIdx / yMaxIdx
        for (int32_t y=0; y<H-1; y++) {
            const float s = stdDevRowDelta[y];
            if (s < yMin) {
                yMin = s;
                yMinIdx = y;
            }
            
            if (s > yMax) {
                yMax = s;
                yMaxIdx = y;
            }
        }
        
        // Calculate xMinIdx / xMaxIdx
        for (int32_t x=0; x<W-1; x++) {
            const float s = stdDevColDelta[x];
            if (s < xMin) {
                xMin = s;
                xMinIdx = x;
            }
            
            if (s > xMax) {
                xMax = s;
                xMaxIdx = x;
            }
        }
        
//        constexpr int32_t DeltaXMin = +1;
//        constexpr int32_t DeltaXMax = +1;
//        constexpr int32_t DeltaYMin = +3;
//        constexpr int32_t DeltaYMax = -3;
        
        const bool good =
            xMinIdx < xMaxIdx &&
            yMinIdx < yMaxIdx &&
            xMinIdx>=0 && xMaxIdx>=0 && yMinIdx>=0 && yMaxIdx>=0;
        
        if (good) {
            float x = (xMinIdx + xMaxIdx) / 2;
            float y = (yMinIdx + yMaxIdx) / 2;
            x += FocusPosterSearchRegion.left;
            y += FocusPosterSearchRegion.top;
            x -= FocusPosterWidth / 2;
            y -= FocusPosterHeight / 2;
            x = std::floor(x);
            y = std::floor(y);
            
            _focusPosterRect = {
                { (float)x / GrayWidth, (float)y / GrayHeight },
                { (float)FocusPosterWidth / GrayWidth, (float)FocusPosterHeight / GrayHeight },
            };
            
            [_mainView setSampleRect:*_focusPosterRect];
        
        } else {
            _focusPosterRect = std::nullopt;
            [_mainView setSampleRect:{}];
        }
        
//        float x = (xMaxIdx - xMinIdx) / 2;
//        float y = (yMaxIdx - yMinIdx) / 2;
//        x -= FocusPosterWidth / 2;
//        y -= FocusPosterHeight / 2;
//        
//        
//        
//        constexpr int32_t DeltaXMin = 0;
//        constexpr int32_t DeltaXMax = 0;
//        constexpr int32_t DeltaYMin = 0;
//        constexpr int32_t DeltaYMax = 0;
//        
//        xMinIdx += FocusPosterSearchRegion.left + DeltaXMin;
//        xMaxIdx += FocusPosterSearchRegion.left + DeltaXMax;
//        
//        yMinIdx += FocusPosterSearchRegion.top + DeltaYMin;
//        yMaxIdx += FocusPosterSearchRegion.top + DeltaYMax;
//        
//        const bool good =
//            xMinIdx < xMaxIdx &&
//            yMinIdx < yMaxIdx &&
//            xMinIdx>=0 && xMaxIdx>=0 && yMinIdx>=0 && yMaxIdx>=0;
//        
//        if (good) {
//            _focusPosterRect = {
//                { (float)xMinIdx / GrayWidth, (float)yMinIdx / GrayHeight },
//                { (float)(xMaxIdx-xMinIdx) / GrayWidth, (float)(yMaxIdx-yMinIdx) / GrayHeight },
//            };
//            
//            [_mainView setSampleRect:*_focusPosterRect];
//        
//        } else {
//            _focusPosterRect = std::nullopt;
//            [_mainView setSampleRect:{}];
//        }
    }
    
    if (_focusPosterRect) {
        const SampleRect sampleRect = _SampleRectForCGRect(*_focusPosterRect, [grayTxt width], [grayTxt height]);
        auto [ samples, sampleCount ] = _SamplesRead(_renderer, sampleRect, grayTxt);
        
        float avg = 0;
        for (size_t i=0; i<sampleCount; i++) {
            avg += samples[i];
        }
        avg /= sampleCount;
//        printf("avg: %f\n", avg);
        
        float k = 0;
        for (size_t i=0; i<sampleCount; i++) {
            float s = samples[i];
            k += pow(avg-s, 2);
        }
        k /= sampleCount;
        k *= 1000;
        printf("k: %f\n", k);
    }
    
    static int count = 0;
    count++;
    if (!(count % 10)) {
        static const fs::path ImageDir = "/Users/dave/Desktop/Focus-Train-Images";
        static bool imageDirCreated = false;
        if (!imageDirCreated) {
            std::filesystem::create_directory(ImageDir);
            imageDirCreated = true;
        }
        
        const fs::path imagePath = ImageDir / (std::to_string(count) + ".png");
        
        id img = _renderer.imageCreate(grayTxt);
        assert(img);
        NSURL* outputURL = [NSURL fileURLWithPath:@(imagePath.c_str())];
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithURL((CFURLRef)outputURL, kUTTypePNG, 1, nullptr);
        CGImageDestinationAddImage(imageDest, (__bridge CGImageRef)img, nullptr);
        CGImageDestinationFinalize(imageDest);
    }
    
    
    [[_mainView imageLayer] setTexture:grayTxt];
    [self _renderCompleted:popts];
}

- (void)_handleMDCDevicesChanged {
    std::vector<MDCStudio::MDCDeviceRealPtr> devices = MDCStudio::MDCDevicesManagerGlobal()->devices();
    assert(devices.size()==0 || devices.size()==1);
    MDCStudio::MDCDeviceRealPtr device = (!devices.empty() ? devices.at(0) : nullptr);
    [self _setMDCDevice:device];
    
}

- (void)_setMDCDevice:(MDCStudio::MDCDeviceRealPtr)dev {
    [self _streamImagesStop];
    
    _mdcDevice = dev;
    [_streamImagesSwitch setEnabled:(bool)_mdcDevice];
    [_streamImagesSwitch setState:NSControlStateValueOff];
    
    if (_mdcDevice) {
        [self _setStreamImagesEnabled:true];
    }
}

- (void)_handleStreamImage {
    assert([NSThread isMainThread]);
    
    // Copy the image from `_streamImagesThread` into `_raw.image`
    auto lock = std::unique_lock(_streamImagesThread.lock);
        _raw.image.width = _streamImagesThread.width;
        _raw.image.height = _streamImagesThread.height;
        const size_t len = _streamImagesThread.width*_streamImagesThread.height*sizeof(*_streamImagesThread.pixels);
        memcpy(_raw.pixels, _streamImagesThread.pixels, len);
    lock.unlock();
    
    [self _render];
}

- (void)_threadStreamImages:(MDCStudio::MDCDeviceRealPtr)device {
    assert(device);
    
//    NSString* dirName = [NSString stringWithFormat:@"CFAViewerSession-%f", [NSDate timeIntervalSinceReferenceDate]];
//    NSString* dirPath = [NSString stringWithFormat:@"/Users/dave/Desktop/%@", dirName];
//    assert([[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:false attributes:nil error:nil]);
    
    try {
        // TODO: stop accessing privates of MDCUSBDevice!
        auto hostMode = device->_hostModeEnter();
        // Get the MDCUSBDevice only after entering host mode!
        // Otherwise there's a race before MDCDeviceReal has assigned its _device.device.
        MDCUSBDevice& dev = *device->_device.device;
        
        _configureDevice(dev);
        
//        float intTime = .5;
//        const size_t tmpPixelsCap = std::size(_streamImagesThread.pixels);
//        auto tmpPixels = std::make_unique<MDC::Pixel[]>(tmpPixelsCap);
        
        dev.imgInit();
        
        std::optional<Img::AutoExposure> autoExp;
        
        MDCUSBDevice::ImgExposure exposure;
        MDCUSBDevice::ImgExposure lastExposure;
        for (uint32_t i=0;; i++) {
            // Set the image exposure if it changed
            const bool setExp = memcmp(&exposure, &lastExposure, sizeof(exposure));
            if (setExp) {
                dev.imgExposureSet(exposure);
                lastExposure = exposure;
//                printf("Set exposure %d\n", exposure.coarseIntTime);
//                usleep(100000);
            }
            
            constexpr Img::Size ImageSize = Img::Size::Full;
            constexpr uint8_t DstBlock = 0; // Always save to RAM block 0
            constexpr size_t ImageWidth  = (ImageSize==Img::Size::Full ? Img::Full::PixelWidth       : Img::Thumb::PixelWidth       );
            constexpr size_t ImageHeight = (ImageSize==Img::Size::Full ? Img::Full::PixelHeight      : Img::Thumb::PixelHeight      );
            constexpr size_t ImageLen    = (ImageSize==Img::Size::Full ? ImgSD::Full::ImagePaddedLen : ImgSD::Thumb::ImagePaddedLen );
            const uint8_t skipCount = (setExp ? 1 : 0); // Skip one image if we set the exposure, so that the image we receive has the exposure applied
            const STM::ImgCaptureStats imgStats = dev.imgCapture(DstBlock, skipCount, ImageSize);
            if (imgStats.len != ImageLen) {
                throw Toastbox::RuntimeError("invalid image length (expected: %ju, got: %ju)", (uintmax_t)ImageLen, (uintmax_t)imgStats.len);
            }
            
//            printf("Highlights: %ju   Shadows: %ju\n", (uintmax_t)imgStats.highlightCount, (uintmax_t)imgStats.shadowCount);
            
            std::unique_ptr<uint8_t[]> img = dev.imgReadout(ImageSize);
            {
                auto lock = std::unique_lock(_streamImagesThread.lock);
                
                // Check if we've been cancelled
                if (_streamImagesThread.cancel) break;
                
                _streamImagesThread.width = ImageWidth;
                _streamImagesThread.height = ImageHeight;
                
                // Copy the image into the persistent buffer
                memcpy(_streamImagesThread.pixels, img.get()+Img::PixelsOffset, Img::Full::PixelLen);
                
                // While we have the lock, copy the exposure settings
                if (_streamImagesThread.exposureSettings.autoExposureEnabled && !autoExp) {
                    autoExp.emplace();
                } else if (!_streamImagesThread.exposureSettings.autoExposureEnabled && autoExp) {
                    autoExp = std::nullopt;
                }
                
                if (!autoExp) {
                    exposure = _streamImagesThread.exposureSettings.exposure;
                }
            }
            
            // Invoke -_handleStreamImage on the main thread.
            // Don't use dispatch_async here, because dispatch_async's don't get drained
            // while the runloop is run recursively, eg during mouse tracking.
            __weak auto weakSelf = self;
            CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
                [weakSelf _handleStreamImage];
            });
            CFRunLoopWakeUp(CFRunLoopGetMain());
            
//            if (!(i % 10)) {
//                NSString* imagePath = [dirPath stringByAppendingPathComponent:[NSString
//                    stringWithFormat:@"%ju.cfa",(uintmax_t)saveIdx]];
//                std::ofstream f;
//                f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
//                f.open([imagePath UTF8String]);
//                f.write((char*)_streamImagesThread.pixels, pixelCount*sizeof(MDC::Pixel));
//                saveIdx++;
//                printf("Saved %s\n", [imagePath UTF8String]);
//            }
            
            // Perform auto exposure
            if (autoExp) {
                autoExp->update(imgStats.highlightCount, imgStats.shadowCount);
//                exposure.coarseIntTime = autoExp->integrationTime();
                exposure.coarseIntTime = 1000;
                
                CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
                    [weakSelf _updateAutoExposureUI:exposure];
                });
                CFRunLoopWakeUp(CFRunLoopGetMain());
            }
        }
    
    } catch (const std::exception& e) {
        printf("Streaming failed: %s\n", e.what());
    }
    
    // Notify that our thread has exited
    _streamImagesThread.lock.lock();
        _streamImagesThread.running = false;
        _streamImagesThread.signal.notify_all();
    _streamImagesThread.lock.unlock();
}

- (bool)_streamImagesEnabled {
    auto lock = std::unique_lock(_streamImagesThread.lock);
    return _streamImagesThread.running;
}

- (void)_streamImagesStop {
    // Cancel streaming and wait for it to stop
    for (;;) {
        auto lock = std::unique_lock(_streamImagesThread.lock);
        if (!_streamImagesThread.running) break;
        _streamImagesThread.cancel = true;
        _streamImagesThread.signal.wait(lock);
    }
}

- (void)_setStreamImagesEnabled:(bool)en {
    // Cancel streaming and wait for it to stop
    [self _streamImagesStop];
    
    [_streamImagesSwitch setState:(en ? NSControlStateValueOn : NSControlStateValueOff)];
    
    if (en) {
        assert(_mdcDevice); // Verify that we have a valid device, since we're trying to enable image streaming
        
        // Kick off a new streaming thread
        _streamImagesThread.lock.lock();
            _streamImagesThread.running = true;
            _streamImagesThread.cancel = false;
            _streamImagesThread.signal.notify_all();
        _streamImagesThread.lock.unlock();
        
        auto dev = _mdcDevice;
        [NSThread detachNewThreadWithBlock:^{
            [self _threadStreamImages:dev];
        }];
    }
}

// MARK: - Color Matrix

template<size_t H, size_t W>
Mat<double,H,W> _matFromString(NSString* nsstr) {
    const std::string& str = [nsstr UTF8String];
    const std::regex floatRegex("[-+]?[0-9]*\\.?[0-9]+");
    auto begin = std::sregex_iterator(str.begin(), str.end(), floatRegex);
    auto end = std::sregex_iterator();
    Mat<double,H,W> r;
    
    auto rt = r.beginRow();
    for (std::sregex_iterator si=begin; si!=end; si++) {
        if (rt == r.endRow()) {
            NSLog(@"Failed to parse color matrix");
            return {};
        }
        *rt = std::stod(si->str());
        rt++;
    }
    
    // Verify that we had the exact right number of arguments
    if (rt != r.endRow()) {
        NSLog(@"Failed to parse matrix");
        return {};
    }
    
    return r;
}

- (void)controlTextDidEndEditing:(NSNotification*)note {
    NSLog(@"controlTextDidEndEditing:");
    NSTextField* textField = Toastbox::CastOrNull<NSTextField*>([note object]);
    if (!textField) return;
    if (textField == _illumTextField) {
        if (!_pipelineOptions.illum) return;
        _pipelineOptions.illum = _matFromString<3,1>([_illumTextField stringValue]);
        [self _render];
    
    } else if (textField == _colorMatrixTextField) {
        if (!_pipelineOptions.colorMatrix) return;
        _pipelineOptions.colorMatrix = _matFromString<3,3>([_colorMatrixTextField stringValue]);
        [self _render];
    }
}

// MARK: - Histograms

- (void)_updateHistograms {
//    [[_inputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] inputHistogram]];
//    [[_outputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] outputHistogram]];
}

// MARK: - Sample

static Mat<double,3,1> _averageRaw(const SampleRect& rect, const CFADesc& cfaDesc, id<MTLBuffer> buf) {
    const simd::float3* vals = (simd::float3*)[buf contents];
    assert([buf length] >= rect.count()*sizeof(simd::float3));
    
    size_t i = 0;
    Mat<double,3,1> r;
    uint32_t count[3] = {};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const CFAColor c = cfaDesc.color(x, y);
            const simd::float3& val = vals[i];
            if (c == CFAColor::Red)     count[0]++;
            if (c == CFAColor::Green)   count[1]++;
            if (c == CFAColor::Blue)    count[2]++;
            r += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    
    if (count[0]) r[0] /= count[0];
    if (count[1]) r[1] /= count[1];
    if (count[2]) r[2] /= count[2];
    return r;
}

static Mat<double,3,1> _averageRGB(const SampleRect& rect, id<MTLBuffer> buf) {
    const simd::float3* vals = (simd::float3*)[buf contents];
    assert([buf length] >= rect.count()*sizeof(simd::float3));
    
    Mat<double,3,1> r;
    size_t i = 0;
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const simd::float3& val = vals[i];
            r += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (i) r /= i;
    return r;
}

static Color<ColorSpace::Raw> sampleImageCircle(const RawImage& img, int x, int y, int radius) {
    const int left      = std::clamp(x-radius, 0, (int)img.width -1  )   ;
    const int right     = std::clamp(x+radius, 0, (int)img.width -1  )+1 ;
    const int bottom    = std::clamp(y-radius, 0, (int)img.height-1  )   ;
    const int top       = std::clamp(y+radius, 0, (int)img.height-1  )+1 ;
    const auto sampler = PixelSampler(img.width, img.height, img.pixels);
    uint32_t vals[3] = {};
    uint32_t counts[3] = {};
    for (int iy=bottom; iy<top; iy++) {
        for (int ix=left; ix<right; ix++) {
            if (sqrt(pow((double)ix-x,2) + pow((double)iy-y,2)) < (double)radius) {
                const CFAColor c = img.cfaDesc.color(ix, iy);
                vals[(int)c] += sampler.px(ix, iy);
                counts[(int)c]++;
            }
        }
    }
    
    Color<ColorSpace::Raw> r;
    for (size_t i=0; i<3; i++) {
        if (counts[i]) r[i] = (double)vals[i] / (ImagePixelMax*counts[i]);
    }
    return r;
}

// MARK: - UI

- (void)_saveImage:(NSString*)path {
    const std::string ext([[[path pathExtension] lowercaseString] UTF8String]);
    if (ext == "cfa") {
        std::ofstream f;
        f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
        f.open([path UTF8String]);
        const size_t pixelCount = _raw.image.width*_raw.image.height;
        f.write((char*)_raw.image.pixels, pixelCount*sizeof(*_raw.image.pixels));
    
    } else if (ext == "png") {
        id img = _renderer.imageCreate(_txt);
        Assert(img, return);
        
        id imgDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
            (CFURLRef)[NSURL fileURLWithPath:path], kUTTypePNG, 1, nullptr));
        CGImageDestinationAddImage((CGImageDestinationRef)imgDest, (CGImageRef)img, nullptr);
        CGImageDestinationFinalize((CGImageDestinationRef)imgDest);
    }
}

- (IBAction)saveDocument:(id)sender {
    static NSString*const LastImageNameKey = @"LastImageName";
    NSSavePanel* panel = [NSSavePanel savePanel];
    
    NSString* fileName = [[NSUserDefaults standardUserDefaults] objectForKey:LastImageNameKey];
    if (!fileName) fileName = @"image.png";
    [panel setNameFieldStringValue:fileName];
    
    __weak auto weakSelf = self;
    __weak auto weakPanel = panel;
    [panel beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
        if (result != NSModalResponseOK) return;
        
        auto panel = weakPanel;
        Assert(panel, return);
        auto strongSelf = weakSelf;
        Assert(strongSelf, return);
        
        NSString* path = [[panel URL] path];
        
        [[NSUserDefaults standardUserDefaults]
            setObject:[path lastPathComponent] forKey:LastImageNameKey];
        
        [strongSelf _saveImage:path];
    }];
}

- (IBAction)_streamImagesSwitchAction:(id)sender {
    [self _setStreamImagesEnabled:([_streamImagesSwitch state]==NSControlStateValueOn)];
}

- (IBAction)_streamSettingsAction:(id)sender {
    [self _setExposureSettings:{
        .autoExposureEnabled = [_autoExposureCheckbox state]==NSControlStateValueOn,
        .exposure = {
            .coarseIntTime  = (uint16_t)([_coarseIntegrationTimeSlider doubleValue] * Img::CoarseIntTimeMax),
            .fineIntTime    = (uint16_t)([_fineIntegrationTimeSlider doubleValue]   * Img::FineIntTimeMax),
            .analogGain     = (uint16_t)([_analogGainSlider doubleValue]            * Img::AnalogGainMax),
        },
    }];
    
//    _imgExp.coarseIntTime = [_coarseIntegrationTimeSlider doubleValue]*65535;
//    _imgExp.fineIntTime = [_fineIntegrationTimeSlider doubleValue]*65535;
//    _imgExp.gain = [_analogGainSlider doubleValue]*65535;
//    
//    auto lock = std::unique_lock(_streamImagesThread.lock);
//    _streamImagesThread.exp = _imgExp;
}

- (void)_setExposureSettings:(const ExposureSettings&)settings {
    _exposureSettings = settings;
    
    [_autoExposureCheckbox setState:(_exposureSettings.autoExposureEnabled ? NSControlStateValueOn : NSControlStateValueOff)];
    
    [_coarseIntegrationTimeSlider setDoubleValue:
        (double)settings.exposure.coarseIntTime/Img::CoarseIntTimeMax];
    [_coarseIntegrationTimeSlider setEnabled:!_exposureSettings.autoExposureEnabled];
    [_coarseIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)settings.exposure.coarseIntTime]];
    
    [_fineIntegrationTimeSlider setDoubleValue:
        (double)settings.exposure.fineIntTime/Img::FineIntTimeMax];
    [_fineIntegrationTimeSlider setEnabled:!_exposureSettings.autoExposureEnabled];
    [_fineIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)settings.exposure.fineIntTime]];
    
    [_analogGainSlider setDoubleValue:
        (double)settings.exposure.analogGain/Img::AnalogGainMax];
    [_analogGainSlider setEnabled:!_exposureSettings.autoExposureEnabled];
    [_analogGainLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)settings.exposure.analogGain]];
    
    auto lock = std::unique_lock(_streamImagesThread.lock);
    _streamImagesThread.exposureSettings = _exposureSettings;
}

- (void)_updateAutoExposureUI:(const MDCUSBDevice::ImgExposure&)exposure {
    // Bail if auto exposure is disabled
    if (!_exposureSettings.autoExposureEnabled) return;
    [self _setExposureSettings:{
        .autoExposureEnabled = _exposureSettings.autoExposureEnabled,
        .exposure = exposure,
    }];
}

//- (void)_setCoarseIntegrationTime:(double)intTime {
//    auto lock = std::unique_lock(_streamImagesThread.lock);
//    _streamImagesThread.exposure.emplace();
//    ExposureConfig& exp = *_streamImagesThread.exposure;
//    exp.coarseIntegrationTime = intTime*16384;
//    [_coarseIntegrationTimeSlider setDoubleValue:intTime];
//    [_coarseIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju",
//        (uintmax_t)exp.coarseIntegrationTime]];
//}
//
//- (void)_setFineIntegrationTime:(double)intTime {
//    auto lock = std::unique_lock(_streamImagesThread.lock);
//    _streamImagesThread.exposure.emplace();
//    ExposureConfig& exp = *_streamImagesThread.exposure;
//    exp.fineIntegrationTime = intTime*UINT16_MAX;
//    [_fineIntegrationTimeSlider setDoubleValue:intTime];
//    [_fineIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju",
//        (uintmax_t)exp.fineIntegrationTime]];
//}
//
//- (void)_setAnalogGain:(double)gain {
//    const uint32_t i = gain*0x3F;
//    auto lock = std::unique_lock(_streamImagesThread.lock);
//    _streamImagesThread.exposure.emplace();
//    ExposureConfig& exp = *_streamImagesThread.exposure;
//    exp.analogGain = i;
//    [_analogGainSlider setDoubleValue:gain];
//    [_analogGainLabel setStringValue:[NSString stringWithFormat:@"%ju",
//        (uintmax_t)exp.analogGain]];
//}

- (IBAction)_illumCheckboxAction:(id)sender {
    const bool en = ([_illumCheckbox state] == NSControlStateValueOn);
    if (en) _pipelineOptions.illum = _pipelineOptionsPost.illum;
    else    _pipelineOptions.illum = std::nullopt;
    [self _render];
}

- (IBAction)_illumIdentityAction:(id)sender {
    [_inspectorWindow makeFirstResponder:nil];
    _pipelineOptions.illum = { 1.,1.,1. };
    [_inspectorWindow makeFirstResponder:_illumTextField];
    [self _render];
}

- (IBAction)_colorMatrixCheckboxAction:(id)sender {
    const bool en = ([_colorMatrixCheckbox state] == NSControlStateValueOn);
    if (en) _pipelineOptions.colorMatrix = _pipelineOptionsPost.colorMatrix;
    else    _pipelineOptions.colorMatrix = std::nullopt;
    [self _render];
}

- (IBAction)_colorMatrixIdentityAction:(id)sender {
    [_inspectorWindow makeFirstResponder:nil];
    [self _setColorCheckersEnabled:false];
    _pipelineOptions.colorMatrix = {
        1.,0.,0.,
        0.,1.,0.,
        0.,0.,1.
    };
    [_inspectorWindow makeFirstResponder:_colorMatrixTextField];
    [self _render];
}

- (void)_setColorCheckersEnabled:(bool)en {
    if (_colorCheckersEnabled == en) return;
    _colorCheckersEnabled = en;
    [_colorCheckersCheckbox setState:
        (_colorCheckersEnabled ? NSControlStateValueOn : NSControlStateValueOff)];
    [_colorMatrixTextField setEditable:!_colorCheckersEnabled];
    [_mainView setColorCheckersVisible:_colorCheckersEnabled];
    [_resetColorCheckersButton setHidden:!_colorCheckersEnabled];
    _pipelineOptions.illum = std::nullopt;
    _pipelineOptions.colorMatrix = std::nullopt;
}

- (IBAction)_resetColorCheckersButtonAction:(id)sender {
    [_mainView resetColorCheckerPositions];
    [self _updateColorMatrix];
}

- (IBAction)_colorCheckersCheckboxAction:(id)sender {
    [self _setColorCheckersEnabled:([_colorCheckersCheckbox state]==NSControlStateValueOn)];
    if (_colorCheckersEnabled) {
        [self _updateColorMatrix];
    }
    [self _render];
}

- (IBAction)_imageOptionsAction:(id)sender {
    auto& opts = _pipelineOptions;
    opts.defringe.en = ([_defringeCheckbox state]==NSControlStateValueOn);
    opts.defringe.opts.rounds = (uint32_t)[_defringeRoundsSlider intValue];
    opts.defringe.opts.αthresh = [_defringeαThresholdSlider floatValue];
    opts.defringe.opts.γthresh = [_defringeγThresholdSlider floatValue];
    opts.defringe.opts.γfactor = [_defringeγFactorSlider floatValue];
    opts.defringe.opts.δfactor = [_defringeδFactorSlider floatValue];
    
    opts.reconstructHighlights.en = ([_reconstructHighlightsCheckbox state]==NSControlStateValueOn);
    
    opts.debayerLMMSE.applyGamma = ([_debayerLMMSEGammaCheckbox state]==NSControlStateValueOn);
    
    opts.exposure = [_exposureSlider floatValue];
    opts.brightness = [_brightnessSlider floatValue];
    opts.contrast = [_contrastSlider floatValue];
    opts.saturation = [_saturationSlider floatValue];
    
    opts.localContrast.amount = [_localContrastAmountSlider floatValue];
    opts.localContrast.radius = [_localContrastRadiusSlider floatValue];
    
    [self _render];
}

- (void)_updateInspectorUI {
    const auto& optsPre = _pipelineOptions;
    const auto& opts = _pipelineOptionsPost;
    
    // Defringe
    {
        [_defringeCheckbox setState:(opts.defringe.en ? NSControlStateValueOn : NSControlStateValueOff)];
        
        [_defringeRoundsSlider setIntValue:opts.defringe.opts.rounds];
        [_defringeRoundsLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)opts.defringe.opts.rounds]];
        
        [_defringeαThresholdSlider setFloatValue:opts.defringe.opts.αthresh];
        [_defringeαThresholdLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.defringe.opts.αthresh]];
        
        [_defringeγThresholdSlider setFloatValue:opts.defringe.opts.γthresh];
        [_defringeγThresholdLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.defringe.opts.γthresh]];
        
        [_defringeγFactorSlider setFloatValue:opts.defringe.opts.γfactor];
        [_defringeγFactorLabel setStringValue:[NSString stringWithFormat:@"%.3f",
            opts.defringe.opts.γfactor]];
        
        [_defringeδFactorSlider setFloatValue:opts.defringe.opts.δfactor];
        [_defringeδFactorLabel setStringValue:[NSString stringWithFormat:@"%.3f",
            opts.defringe.opts.δfactor]];
    }
    
    // Reconstruct Highlights
    {
        [_reconstructHighlightsCheckbox setState:(opts.reconstructHighlights.en ?
            NSControlStateValueOn : NSControlStateValueOff)];
    }
    
    // LMMSE
    {
        [_debayerLMMSEGammaCheckbox setState:(opts.debayerLMMSE.applyGamma ?
            NSControlStateValueOn : NSControlStateValueOff)];
    }
    
    // Illuminant
    {
        if (_colorCheckersEnabled) {
            [_illumCheckbox setState:NSControlStateValueOff];
            [_illumCheckbox setEnabled:false];
            [_illumTextField setEditable:false];
        
        } else {
            [_illumCheckbox setState:((bool)optsPre.illum ? NSControlStateValueOn : NSControlStateValueOff)];
            [_illumCheckbox setEnabled:true];
            [_illumTextField setEditable:(bool)optsPre.illum];
        }
        [self _setIllumText:*opts.illum];
    }
    
    // Color matrix
    {
        if (_colorCheckersEnabled) {
            [_colorMatrixCheckbox setState:NSControlStateValueOff];
            [_colorMatrixCheckbox setEnabled:false];
            [_colorMatrixTextField setEditable:false];
        
        } else {
            [_colorMatrixCheckbox setState:((bool)optsPre.colorMatrix ? NSControlStateValueOn : NSControlStateValueOff)];
            [_colorMatrixCheckbox setEnabled:true];
            [_colorMatrixTextField setEditable:(bool)optsPre.colorMatrix];
        }
        [self _setColorMatrixText:*opts.colorMatrix];
    }
    
    {
        [_exposureSlider setFloatValue:opts.exposure];
        [_exposureLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.exposure]];
        
        [_brightnessSlider setFloatValue:opts.brightness];
        [_brightnessLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.brightness]];
        
        [_contrastSlider setFloatValue:opts.contrast];
        [_contrastLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.contrast]];
        
        [_saturationSlider setFloatValue:opts.saturation];
        [_saturationLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.saturation]];
    }
    
    // Local contrast
    {
        [_localContrastAmountSlider setFloatValue:opts.localContrast.amount];
        [_localContrastAmountLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.localContrast.amount]];
        
        [_localContrastRadiusSlider setFloatValue:opts.localContrast.radius];
        [_localContrastRadiusLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.localContrast.radius]];
    }
    
    // Update sample colors
    // Currently broken -- we remove sampling from the ImagePipeline a long time ago. Need to add back.
//    const SampleRect rect = _imagePipelineManager->options.sampleRect;
//    const auto& sampleBufs = _imagePipelineManager->result.sampleBufs;
//    _sampleRaw = _averageRaw(rect, _raw.image.cfaDesc, sampleBufs.raw);
//    _sampleXYZD50 = _averageRGB(rect, sampleBufs.xyzD50);
//    _sampleLSRGB = _averageRGB(rect, sampleBufs.lsrgb);
//    
//    [_colorText_Raw setStringValue:
//        [NSString stringWithFormat:@"%f %f %f", _sampleRaw[0], _sampleRaw[1], _sampleRaw[2]]];
//    [_colorText_XYZD50 setStringValue:
//        [NSString stringWithFormat:@"%f %f %f", _sampleXYZD50[0], _sampleXYZD50[1], _sampleXYZD50[2]]];
//    [_colorText_LSRGB setStringValue:
//        [NSString stringWithFormat:@"%f %f %f", _sampleLSRGB[0], _sampleLSRGB[1], _sampleLSRGB[2]]];
}

- (IBAction)_highlightFactorSliderAction:(id)sender {
//    Mat<double,9,1> highlightFactor(
//        [_highlightFactorR0Slider doubleValue],
//        [_highlightFactorR1Slider doubleValue],
//        [_highlightFactorR2Slider doubleValue],
//        
//        [_highlightFactorG0Slider doubleValue],
//        [_highlightFactorG1Slider doubleValue],
//        [_highlightFactorG2Slider doubleValue],
//        
//        [_highlightFactorB0Slider doubleValue],
//        [_highlightFactorB1Slider doubleValue],
//        [_highlightFactorB2Slider doubleValue]
//    );
//    
//    [self _updateInspectorUI];
//    
//    [_highlightFactorR0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[0]]];
//    [_highlightFactorR1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[1]]];
//    [_highlightFactorR2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[2]]];
//    [_highlightFactorG0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[3]]];
//    [_highlightFactorG1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[4]]];
//    [_highlightFactorG2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[5]]];
//    [_highlightFactorB0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[6]]];
//    [_highlightFactorB1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[7]]];
//    [_highlightFactorB2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[8]]];
//    [self mainViewSampleRectChanged:nil];
}

- (void)_setIllumText:(const Color<ColorSpace::Raw>&)illum {
    [_illumTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f", illum[0], illum[1], illum[2]
    ]];
}

- (void)_setColorMatrixText:(const Mat<double,3,3>&)colorMatrix {
    [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
        @"%+f %+f %+f\n"
        @"%+f %+f %+f\n"
        @"%+f %+f %+f\n",
        colorMatrix.at(0,0), colorMatrix.at(0,1), colorMatrix.at(0,2),
        colorMatrix.at(1,0), colorMatrix.at(1,1), colorMatrix.at(1,2),
        colorMatrix.at(2,0), colorMatrix.at(2,1), colorMatrix.at(2,2)
    ]];
}

static SampleRect _SampleRectForCGRect(CGRect rect, size_t width, size_t height) {
    rect.origin.x *= width;
    rect.origin.y *= height;
    rect.size.width *= width;
    rect.size.height *= height;
    return SampleRect{
        .left = std::clamp((int32_t)round(CGRectGetMinX(rect)), 0, (int32_t)width),
        .right = std::clamp((int32_t)round(CGRectGetMaxX(rect)), 0, (int32_t)width),
        .top = std::clamp((int32_t)round(CGRectGetMinY(rect)), 0, (int32_t)height),
        .bottom = std::clamp((int32_t)round(CGRectGetMaxY(rect)), 0, (int32_t)height),
    };
}

// MARK: - MainViewDelegate

- (void)mainViewSampleRectChanged:(MainView*)v {
    CGRect rect = [_mainView sampleRect];
    SampleRect sampleRect = _SampleRectForCGRect(rect, _raw.image.width, _raw.image.height);
    
    
    // Click point: update white balance
    if (sampleRect.left == sampleRect.right) {
        constexpr int WhiteBalanceRectSize = 10;
        sampleRect.left -= WhiteBalanceRectSize/2;
        sampleRect.right += WhiteBalanceRectSize/2;
        sampleRect.top -= WhiteBalanceRectSize/2;
        sampleRect.bottom += WhiteBalanceRectSize/2;
        
        const auto sampler = PixelSampler(_raw.image.width, _raw.image.height, _raw.image.pixels);
        uint32_t vals[3] = {};
        uint32_t counts[3] = {};
        for (int iy=sampleRect.top; iy<sampleRect.bottom; iy++) {
            for (int ix=sampleRect.left; ix<sampleRect.right; ix++) {
                const CFAColor c = _raw.image.cfaDesc.color(ix, iy);
                vals[(int)c] += sampler.px(ix, iy);
                counts[(int)c]++;
            }
        }
        
        Color<ColorSpace::Raw> c;
        for (size_t i=0; i<3; i++) {
            if (counts[i]) c[i] = (double)vals[i] / (ImagePixelMax*counts[i]);
        }
        _whiteBalanceColor = c;
        
        printf("%f %f %f\n", c[0], c[1], c[2]);
        
    // Drag rect: set the focus sample rect
    } else {
        _focusPosterRect = rect;
    }
    
    
//    printf("%.3f %.3f %.3f\n", r[0], r[1], r[2]);
    
}







//static Color<ColorSpace::Raw> sampleImageCircle(const RawImage& img, int x, int y, int radius) {
//    const int left      = std::clamp(x-radius, 0, (int)img.width -1  )   ;
//    const int right     = std::clamp(x+radius, 0, (int)img.width -1  )+1 ;
//    const int bottom    = std::clamp(y-radius, 0, (int)img.height-1  )   ;
//    const int top       = std::clamp(y+radius, 0, (int)img.height-1  )+1 ;
//    const auto sampler = PixelSampler(img.width, img.height, img.pixels);
//    uint32_t vals[3] = {};
//    uint32_t counts[3] = {};
//    for (int iy=bottom; iy<top; iy++) {
//        for (int ix=left; ix<right; ix++) {
//            if (sqrt(pow((double)ix-x,2) + pow((double)iy-y,2)) < (double)radius) {
//                const CFAColor c = img.cfaDesc.color(ix, iy);
//                vals[(int)c] += sampler.px(ix, iy);
//                counts[(int)c]++;
//            }
//        }
//    }
//    
//    Color<ColorSpace::Raw> r;
//    for (size_t i=0; i<3; i++) {
//        if (counts[i]) r[i] = (double)vals[i] / (ImagePixelMax*counts[i]);
//    }
//    return r;
//}


- (void)mainViewColorCheckerPositionsChanged:(MainView*)v {
    [self _updateColorMatrix];
}

- (void)_updateColorMatrix {
    assert(_colorCheckersEnabled);
    
    const std::vector<CGPoint> points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorChecker::Count);
    
    // Sample the white square to get the illuminant
    const CGPoint whitePos = points[ColorChecker::WhiteIdx];
    const Color<ColorSpace::Raw> illum = sampleImageCircle(
        _raw.image,
        round(whitePos.x*_raw.image.width),
        round(whitePos.y*_raw.image.height),
        _colorCheckerCircleRadius
    );
    
    const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
    const Mat<double,3,1> whiteBalance(factor/illum[0], factor/illum[1], factor/illum[2]);
    
    constexpr size_t W = ColorChecker::Count;
    Mat<double,3,W> x; // Colors that we have
    {
        size_t i = 0;
        for (const CGPoint& p : points) {
            const Color<ColorSpace::Raw> rawColor = sampleImageCircle(
                _raw.image,
                round(p.x*_raw.image.width),
                round(p.y*_raw.image.height),
                _colorCheckerCircleRadius
            );
            const Color<ColorSpace::Raw> c = whiteBalance.elmMul(rawColor.m);
            
            x.at(0,i) = c[0];
            x.at(1,i) = c[1];
            x.at(2,i) = c[2];
            i++;
        }
    }
    
    Mat<double,3,W> b; // Colors that we want
    {
        size_t i = 0;
        for (const auto& c : ColorChecker::Colors) {
            const Color<ColorSpace::ProPhotoRGB> ppc(c);
            b.at(0,i) = ppc[0];
            b.at(1,i) = ppc[1];
            b.at(2,i) = ppc[2];
            i++;
        }
    }
    
//    // Constrain the least squares regression so that each column sums to 1
//    // in the resulting 3x3 color matrix.
//    //
//    // How: Use the same large number in a single column of `x` and `b`
//    // Why: We don't want the CCM, which is applied after white balancing,
//    //      to disturb the white balance. (Ie, a neutral color before
//    //      applying the CCM should be neutral after applying the CCM.)
//    //      This is accomplished by ensuring that each row of the CCM
//    //      sums to 1.
//    for (int i=0; i<3; i++) {
//        const double λ = 1e8;
//        x.at(i,W-1) = λ;
//        b.at(i,W-1) = λ;
//    }
    
    std::cout << x.str() << "\n\n";
    std::cout << b.str() << "\n\n";
    
    // Solve for the color matrix A in the standard matrix equation Ax=b.
    // In the standard equation, `x` is normally solved for, but we want to solve
    // for A instead. To do so, we manipulate the equation as follows:
    //   Ax=b  =>  (Ax)'=b'  =>  x'A'=b'
    // and solve for A' (which is now in the position that x is in, in the standard
    // matrix equation Ax=b), and finally transpose A' to get A (since (A')' = A).
    Mat<double,3,3> colorMatrix = x.trans().solve(b.trans()).trans();
    
    // Force each row of `colorMatrix` sums to 1. See comment above.
    const Mat<double,3,1> rowSum = colorMatrix.sumRows();
    for (int y=0; y<3; y++) {
        for (int x=0; x<3; x++) {
            colorMatrix.at(y,x) /= rowSum[y];
        }
    }
    
    [self _prefsSetColorCheckerPositions:points];
    
    _pipelineOptions.illum = illum;
    _pipelineOptions.colorMatrix = colorMatrix;
    [self _render];
}

// MARK: - Prefs

- (std::vector<CGPoint>)_prefsColorCheckerPositions {
    NSArray* nspoints = [[NSUserDefaults standardUserDefaults] objectForKey:ColorCheckerPositionsKey];
    std::vector<CGPoint> points;
    if ([nspoints count] != ColorChecker::Count) return {};
    if (![nspoints isKindOfClass:[NSArray class]]) return {};
    for (NSArray* nspoint : nspoints) {
        if (![nspoint isKindOfClass:[NSArray class]]) return {};
        if ([nspoint count] != 2) return {};
        
        NSNumber* nsx = nspoint[0];
        NSNumber* nsy = nspoint[1];
        if (![nsx isKindOfClass:[NSNumber class]]) return {};
        if (![nsy isKindOfClass:[NSNumber class]]) return {};
        points.push_back({[nsx doubleValue], [nsy doubleValue]});
    }
    return points;
}

- (void)_prefsSetColorCheckerPositions:(const std::vector<CGPoint>&)points {
    NSMutableArray* nspoints = [NSMutableArray new];
    for (const CGPoint& p : points) {
        [nspoints addObject:@[@(p.x), @(p.y)]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:nspoints forKey:ColorCheckerPositionsKey];
}


// MARK: - Drag & Drop
static ImagePaths getPathsFromPasteboard(NSPasteboard* pb, const std::vector<std::string>& types) {
    NSCParameterAssert(pb);
    const std::set<fs::path> exts(types.begin(), types.end());
    ImagePaths paths;
    NSArray* urls = [pb readObjectsForClasses:@[[NSURL class]]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    for (NSURL* url : urls) {
        const fs::path p([url fileSystemRepresentation]);
        // Allow directories
        if (fs::is_directory(p)) {
            paths.push_back(p);
        } else if (fs::is_regular_file(p) && exts.find(p.extension())!=exts.end()) {
            paths.push_back(p);
        }
    }
    return paths;
}

static ImagePaths getPathsFromPasteboard(NSPasteboard* pb) {
    NSCParameterAssert(pb);
    return getPathsFromPasteboard(pb, {".cfa"});
}

- (NSDragOperation)mainViewDraggingEntered:(id<NSDraggingInfo>)sender {
    if (!getPathsFromPasteboard([sender draggingPasteboard]).empty()) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (bool)mainViewPerformDragOperation:(id<NSDraggingInfo>)sender {
    const ImagePaths paths = getPathsFromPasteboard([sender draggingPasteboard]);
    [self _loadImages:paths];
    return true;
}

@end

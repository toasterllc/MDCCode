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
#import "ImageLayer.h"
#import "HistogramLayer.h"
#import "Mmap.h"
#import "Util.h"
#import "Mat.h"
#import "TimeInstant.h"
#import "MainView.h"
#import "HistogramView.h"
#import "ColorChecker.h"
#import "MDCDevice.h"
#import "IOServiceMatcher.h"
#import "IOServiceWatcher.h"
#import "MDCUtil.h"
#import "Assert.h"
#import "ImagePipelineTypes.h"
#import "Color.h"
#import "ImagePipelineManager.h"
#import "PixelSampler.h"
using namespace CFAViewer;
using namespace MetalUtil;
using namespace ImagePipeline;
namespace fs = std::filesystem;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

using ImagePaths = std::vector<fs::path>;
using ImagePathsIter = ImagePaths::iterator;

struct PixConfig {
    uint16_t coarseIntegrationTime = 0;
    uint16_t fineIntegrationTime = 0;
    uint8_t analogGain = 0;
};

@interface AppDelegate : NSObject <NSApplicationDelegate, MainViewDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
    
    IBOutlet NSSwitch* _streamImagesSwitch;
    
    IBOutlet NSSlider* _coarseIntegrationTimeSlider;
    IBOutlet NSTextField* _coarseIntegrationTimeLabel;
    
    IBOutlet NSSlider* _fineIntegrationTimeSlider;
    IBOutlet NSTextField* _fineIntegrationTimeLabel;
    
    IBOutlet NSSwitch* _analogGainSlider;
    IBOutlet NSTextField* _analogGainLabel;
    
    IBOutlet NSTextField* _illumTextField;
    
    IBOutlet NSButton* _colorCheckersCheckbox;
    IBOutlet NSButton* _resetColorCheckersButton;
    
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
    
    IBOutlet NSTextField* _colorMatrixTextField;
    
    IBOutlet NSButton* _debayerLMMSEGammaCheckbox;
    
    IBOutlet NSSlider* _exposureSlider;
    IBOutlet NSTextField* _exposureLabel;
    IBOutlet NSSlider* _brightnessSlider;
    IBOutlet NSTextField* _brightnessLabel;
    IBOutlet NSSlider* _contrastSlider;
    IBOutlet NSTextField* _contrastLabel;
    IBOutlet NSSlider* _saturationSlider;
    IBOutlet NSTextField* _saturationLabel;
    
    IBOutlet NSButton* _localContrastCheckbox;
    IBOutlet NSSlider* _localContrastAmountSlider;
    IBOutlet NSTextField* _localContrastAmountLabel;
    IBOutlet NSSlider* _localContrastRadiusSlider;
    IBOutlet NSTextField* _localContrastRadiusLabel;
    
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
    
    IBOutlet NSTextField* _colorText_Raw;
    IBOutlet NSTextField* _colorText_XYZD50;
    IBOutlet NSTextField* _colorText_SRGB;
    
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
    
    bool _colorCheckersEnabled;
    float _colorCheckerCircleRadius;
    
    IOServiceMatcher _serviceWatcher;
    MDCDevice _mdcDevice;
    IOServiceWatcher _mdcDeviceWatcher;
    
    PixConfig _pixConfig;
    ImagePipelineManager* _imagePipelineManager;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        bool running = false;
        bool cancel = false;
        STApp::Pixel pixels[2200*2200];
    } _streamImagesThread;
    
    struct {
        STApp::Pixel pixels[2200*2200];
        Pipeline::RawImage img = {
            .cfaDesc = {
                CFAColor::Green, CFAColor::Red,
                CFAColor::Blue, CFAColor::Green,
            },
            .width = 2304,
            .height = 1296,
            .pixels = pixels,
        };
    } _rawImage;
    
    Color<ColorSpace::Raw> _sampleRaw;
    Color<ColorSpace::XYZD50> _sampleXYZD50;
    Color<ColorSpace::SRGB> _sampleSRGB;
    
    ImagePaths _imagePaths;
    ImagePathsIter _imagePathIter;
}

- (void)awakeFromNib {
    __weak auto weakSelf = self;
    
    _colorCheckerCircleRadius = 5;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    _imagePipelineManager = [ImagePipelineManager new];
    _imagePipelineManager->rawImage = _rawImage.img;
    _imagePipelineManager->renderCallback = [=]() {
        [weakSelf _renderCallback];
    };
    [[_mainView imageLayer] setImagePipelineManager:_imagePipelineManager];
    
    // /Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker/outdoor_5pm_45.cfa
    [self _loadImages:{"/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker"}];
//    [self _loadImages:{"/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker"}];
//    [self _loadImages:{"/Users/dave/repos/ffcc/data/AR0330-166-384x216/outdoor_5pm_43.cfa"}];
    
    _imagePipelineManager->options = {
        .rawMode = false,
        
        .illum = std::nullopt,
        
        .reconstructHighlights = {
            .en = true,
        },
        
        .debayerLMMSE = {
            .applyGamma = true,
        },
        
        .defringe = {
            .en = false,
        },
    };
    
    [self _updateInspectorUI];
    
    auto points = [self _prefsColorCheckerPositions];
    if (!points.empty()) {
        [_mainView setColorCheckerPositions:points];
    }
    
    [self _setCoarseIntegrationTime:0];
    [self _setFineIntegrationTime:0];
    [self _setAnalogGain:0];
    
    [self _setMDCDevice:MDCDevice()];
    _serviceWatcher = IOServiceMatcher(dispatch_get_main_queue(), MDCDevice::MatchingDictionary(), ^(SendRight&& service) {
        [weakSelf _handleUSBDevice:std::move(service)];
    });
    
    [NSThread detachNewThreadWithBlock:^{
        [self _threadReadInputCommands];
    }];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    // Hack -- we need to be document-based, and each document should handle this
    if ([item action] == @selector(_nextImage:) ||
        [item action] == @selector(_previousImage:)) {
        return [[[NSApp mainWindow] sheets] count] == 0;
    }
    return true;
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
        if (aPart < bPart) return true;
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
    return fs::is_regular_file(path) && path.extension() == ".cfa";
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
    
    const Mmap<MetalUtil::ImagePixel> imgData(path);
    const size_t pixelCount = _rawImage.img.width*_rawImage.img.height;
    // Verify that the size of the file matches the size of the image
    assert(imgData.len() == pixelCount);
    // Copy the image data into _rawImage
    std::copy(imgData.data(), imgData.data()+pixelCount, _rawImage.pixels);
    [[_mainView imageLayer] setNeedsDisplay];
    
    // Reset the illuminant so auto-white-balance is enabled again
    _imagePipelineManager->options.illum = std::nullopt;
    // Reset the sample rect
    _imagePipelineManager->options.sampleRect = {};
    // Reset the image scale / position
    [_mainView reset];
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

#pragma mark - MDCDevice

- (void)_handleUSBDevice:(SendRight&&)service {
    MDCDevice device;
    try {
        device = MDCDevice(std::move(service));
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to create MDCDevice (it probably needs to be bootloaded): %s\n", e.what());
    }
    [self _setMDCDevice:std::move(device)];
}

// Throws on error
static void initMDCDevice(const MDCDevice& device) {
    // Reset the device to put it back in a pre-defined state
    device.reset();
    device.pixReset();
    device.pixConfig();
}

// Throws on error
static void configMDCDevice(const MDCDevice& device, const PixConfig& cfg) {
    // Set coarse_integration_time
    device.pixI2CWrite(0x3012, cfg.coarseIntegrationTime);
    // Set fine_integration_time
    device.pixI2CWrite(0x3014, cfg.fineIntegrationTime);
    // Set analog_gain
    device.pixI2CWrite(0x3060, cfg.analogGain);
}

- (void)_setMDCDevice:(MDCDevice&&)device {
    // Disable streaming
    [self _setStreamImagesEnabled:false];
    
    _mdcDevice = std::move(device);
    [_streamImagesSwitch setEnabled:_mdcDevice];
    
    // Watch the MDCDevice so we know when it's terminated
    if (_mdcDevice) {
        __weak auto weakSelf = self;
        try {
            initMDCDevice(_mdcDevice);
            _mdcDeviceWatcher = _mdcDevice.createWatcher(dispatch_get_main_queue(), ^(uint32_t msgType, void* msgArg) {
                [weakSelf _handleMDCDeviceNotificationType:msgType arg:msgArg];
            });
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Failed to initialize MDCDevice: %s\n", e.what());
            // If something goes wrong, assume the device was disconnected
            [self _setMDCDevice:MDCDevice()];
        }
    }
}

- (void)_handleMDCDeviceNotificationType:(uint32_t)msgType arg:(void*)msgArg {
    if (msgType == kIOMessageServiceIsTerminated) {
        [self _setMDCDevice:MDCDevice()];
    }
}

- (void)_threadReadInputCommands {
    for (;;) {
        std::string line;
        std::getline(std::cin, line);
        
        std::vector<std::string> argStrs;
        std::stringstream argStream(line);
        std::string argStr;
        while (std::getline(argStream, argStr, ' ')) {
            if (!argStr.empty()) argStrs.push_back(argStr);
        }
        
        __weak auto weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf _handleInputCommand:argStrs];
        });
    }
}

- (void)_threadStreamImages:(MDCDevice)device {
//    using namespace STApp;
//    assert(device);
//    
//    NSString* dirName = [NSString stringWithFormat:@"CFAViewerSession-%f", [NSDate timeIntervalSinceReferenceDate]];
//    NSString* dirPath = [NSString stringWithFormat:@"/Users/dave/Desktop/%@", dirName];
//    assert([[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:false attributes:nil error:nil]);
//    
//    ImageLayer* layer = [_mainView imageLayer];
//    try {
//        // Reset the device to put it back in a pre-defined state
//        device.reset();
//        
//        float intTime = .5;
//        const size_t tmpPixelBufLen = std::size(_streamImages.pixelBuf);
//        auto tmpPixelBuf = std::make_unique<STApp::Pixel[]>(tmpPixelBufLen);
//        uint32_t saveIdx = 1;
//        for (uint32_t i=0;; i++) {
//            // Capture an image, timing-out after 1s so we can check the device status,
//            // in case it reports a streaming error
//            const STApp::PixHeader pixStatus = device.pixCapture(tmpPixelBuf.get(), tmpPixelBufLen, 1000);
//            
//            auto lock = std::unique_lock(_streamImages.lock);
//                // Check if we've been cancelled
//                if (_streamImages.cancel) break;
//                
//                // Copy the image into our persistent buffer
//                const size_t len = pixStatus.width*pixStatus.height*sizeof(STApp::Pixel);
//                memcpy(_streamImages.img.pixels, tmpPixelBuf.get(), len);
//                _streamImages.img.width = pixStatus.width;
//                _streamImages.img.height = pixStatus.height;
//            lock.unlock();
//            
//            [layer setNeedsDisplay];
//            
//            if (!(i % 10)) {
//                NSString* imagePath = [dirPath stringByAppendingPathComponent:[NSString
//                    stringWithFormat:@"%ju.cfa",(uintmax_t)saveIdx]];
//                std::ofstream f;
//                f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
//                f.open([imagePath UTF8String]);
//                f.write((char*)_streamImages.img.pixels, len);
//                saveIdx++;
//                printf("Saved %s\n", [imagePath UTF8String]);
//            }
//            
//            // Adjust exposure
//            const uint32_t SubsampleFactor = 16;
//            const uint32_t pixelCount = (uint32_t)pixStatus.width*(uint32_t)pixStatus.height;
//            const uint32_t highlightCount = (uint32_t)pixStatus.highlightCount*SubsampleFactor;
//            const uint32_t shadowCount = (uint32_t)pixStatus.shadowCount*SubsampleFactor;
//            const float highlightFraction = (float)highlightCount/pixelCount;
//            const float shadowFraction = (float)shadowCount/pixelCount;
////            printf("Highlight fraction: %f\nShadow fraction: %f\n\n", highlightFraction, shadowFraction);
//            
//            const float diff = shadowFraction-highlightFraction;
//            const float absdiff = fabs(diff);
//            const float adjust = 1.+((diff>0?1:-1)*pow(absdiff, .6));
//            
//            if (absdiff > .01) {
//                bool updateIntTime = false;
//                if (shadowFraction > highlightFraction) {
//                    // Increase exposure
//                    intTime *= adjust;
//                    updateIntTime = true;
//                
//                } else if (highlightFraction > shadowFraction) {
//                    // Decrease exposure
//                    intTime *= adjust;
//                    updateIntTime = true;
//                }
//                
//                intTime = std::clamp(intTime, 0.001f, 1.f);
//                const float gain = intTime/3;
//                
//                printf("adjust:%f\n"
//                       "shadowFraction:%f\n"
//                       "highlightFraction:%f\n"
//                       "intTime: %f\n\n",
//                       adjust,
//                       shadowFraction,
//                       highlightFraction,
//                       intTime
//                );
//                
//                if (updateIntTime) {
//                    device.pixI2CWrite(0x3012, intTime*16384);
//                    device.pixI2CWrite(0x3060, gain*63);
//                }
//            }
//            
//            
//            
////            const float ShadowAdjustThreshold = 0.1;
////            const float HighlightAdjustThreshold = 0.1;
////            const float AdjustDelta = 1.1;
////            bool updateIntTime = false;
////            if (shadowFraction > ShadowAdjustThreshold) {
////                // Increase exposure
////                intTime *= AdjustDelta;
////                updateIntTime = true;
////            
////            } else if (highlightFraction > HighlightAdjustThreshold) {
////                // Decrease exposure
////                intTime /= AdjustDelta;
////                updateIntTime = true;
////            }
////            
////            intTime = std::clamp(intTime, 0.f, 1.f);
////            const float gain = intTime/3;
////            
////            if (updateIntTime) {
////                device.pixI2CWrite(0x3012, intTime*16384);
////                device.pixI2CWrite(0x3060, gain*63);
////            }
//        }
//    
//    } catch (const std::exception& e) {
//        printf("Streaming failed: %s\n", e.what());
//        
//        PixState pixState = PixState::Idle;
//        try {
//            pixState = device.pixStatus().state;
//        } catch (const std::exception& e) {
//            printf("pixStatus() failed: %s\n", e.what());
//        }
//        
//        if (pixState != PixState::Capturing) {
//            printf("pixStatus.state != PixState::Capturing\n");
//        }
//    }
//    
//    // Notify that our thread has exited
//    _streamImages.lock.lock();
//        _streamImages.running = false;
//        _streamImages.signal.notify_all();
//    _streamImages.lock.unlock();
}

- (void)_handleInputCommand:(std::vector<std::string>)cmdStrs {
    MDCUtil::Args args;
    try {
        args = MDCUtil::ParseArgs(cmdStrs);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
        MDCUtil::PrintUsage();
        return;
    }
    
    if (!_mdcDevice) {
        fprintf(stderr, "No MDC device connected\n\n");
        return;
    }
    
    // Disable streaming before we talk to the device
    bool oldStreamImagesEnabled = [self _streamImagesEnabled];
    [self _setStreamImagesEnabled:false];
    
    try {
        MDCUtil::Run(_mdcDevice, args);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return;
    }
    
    // Re-enable streaming (if it was enabled previously)
    if (oldStreamImagesEnabled) [self _setStreamImagesEnabled:true];
}

- (bool)_streamImagesEnabled {
    auto lock = std::unique_lock(_streamImagesThread.lock);
    return _streamImagesThread.running;
}

- (void)_setStreamImagesEnabled:(bool)en {
    // Cancel streaming and wait for it to stop
    for (;;) {
        auto lock = std::unique_lock(_streamImagesThread.lock);
        if (!_streamImagesThread.running) break;
        _streamImagesThread.cancel = true;
        _streamImagesThread.signal.wait(lock);
    }
    
    [_streamImagesSwitch setState:(en ? NSControlStateValueOn : NSControlStateValueOff)];
    
    if (en) {
        assert(_mdcDevice); // Verify that we have a valid device, since we're trying to enable image streaming
        
        // Reset the device to put it back in a pre-defined state
        // so that we can talk to it
        _mdcDevice.reset();
        
        // Configure the device
        configMDCDevice(_mdcDevice, _pixConfig);
        
        // Kick off a new streaming thread
        _streamImagesThread.lock.lock();
            _streamImagesThread.running = true;
            _streamImagesThread.cancel = false;
            _streamImagesThread.signal.notify_all();
        _streamImagesThread.lock.unlock();
        
        MDCDevice device = _mdcDevice;
        [NSThread detachNewThreadWithBlock:^{
            [self _threadStreamImages:device];
        }];
    }
}

#pragma mark - Color Matrix

template<size_t H, size_t W>
Mat<double,H,W> _matrixFromString(const std::string& str) {
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

template <size_t H, size_t W>
Mat<double,H,W> _matFromString(const std::string& str) {
    return _matrixFromString<H,W>(str);
}

- (void)controlTextDidChange:(NSNotification*)note {
    auto& opts = _imagePipelineManager->options;
    if ([note object] == _illumTextField) {
        opts.illum = _matFromString<3,1>([[_illumTextField stringValue] UTF8String]);
        [self _updateInspectorUI];
        [[_mainView imageLayer] setNeedsDisplay];
    
    } else if ([note object] == _colorMatrixTextField) {
        opts.colorMatrix = _matFromString<3,3>([[_colorMatrixTextField stringValue] UTF8String]);
        [self _updateInspectorUI];
        [[_mainView imageLayer] setNeedsDisplay];
    }
}

#pragma mark - Histograms

- (void)_updateHistograms {
//    [[_inputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] inputHistogram]];
//    [[_outputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] outputHistogram]];
}

#pragma mark - Sample

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

- (void)_updateSampleColorsUI {
    const SampleRect rect = _imagePipelineManager->options.sampleRect;
    const auto& sampleBufs = _imagePipelineManager->result.sampleBufs;
    _sampleRaw = _averageRaw(rect, _rawImage.img.cfaDesc, sampleBufs.raw);
    _sampleXYZD50 = _averageRGB(rect, sampleBufs.xyzD50);
    _sampleSRGB = _averageRGB(rect, sampleBufs.srgb);
    
    [_colorText_Raw setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _sampleRaw[0], _sampleRaw[1], _sampleRaw[2]]];
    [_colorText_XYZD50 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _sampleXYZD50[0], _sampleXYZD50[1], _sampleXYZD50[2]]];
    [_colorText_SRGB setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _sampleSRGB[0], _sampleSRGB[1], _sampleSRGB[2]]];
}

static Color<ColorSpace::Raw> sampleImageCircle(const Pipeline::RawImage& img, int x, int y, int radius) {
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

#pragma mark - UI

- (void)_saveImage:(NSString*)path {
    const std::string ext([[[path pathExtension] lowercaseString] UTF8String]);
    if (ext == "cfa") {
        std::ofstream f;
        f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
        f.open([path UTF8String]);
        const size_t pixelCount = _rawImage.img.width*_rawImage.img.height;
        f.write((char*)_rawImage.pixels, pixelCount*sizeof(*_rawImage.pixels));
    
    } else if (ext == "png") {
        id img = _imagePipelineManager->renderer.createCGImage(_imagePipelineManager->result.txt);
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
    [self _setCoarseIntegrationTime:[_coarseIntegrationTimeSlider doubleValue]];
    [self _setFineIntegrationTime:[_fineIntegrationTimeSlider doubleValue]];
    [self _setAnalogGain:[_analogGainSlider doubleValue]];
    
    if ([self _streamImagesEnabled]) {
        [self _setStreamImagesEnabled:false];
        [self _setStreamImagesEnabled:true];
    }
}

- (void)_setCoarseIntegrationTime:(double)intTime {
    _pixConfig.coarseIntegrationTime = intTime*16384;
    [_coarseIntegrationTimeSlider setDoubleValue:intTime];
    [_coarseIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju",
        (uintmax_t)_pixConfig.coarseIntegrationTime]];
}

- (void)_setFineIntegrationTime:(double)intTime {
    _pixConfig.fineIntegrationTime = intTime*UINT16_MAX;
    [_fineIntegrationTimeSlider setDoubleValue:intTime];
    [_fineIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju",
        (uintmax_t)_pixConfig.fineIntegrationTime]];
}

- (void)_setAnalogGain:(double)gain {
    const uint32_t i = gain*0x3F;
    _pixConfig.analogGain = i;
    [_analogGainSlider setDoubleValue:gain];
    [_analogGainLabel setStringValue:[NSString stringWithFormat:@"%ju",
        (uintmax_t)_pixConfig.analogGain]];
}

- (IBAction)_illumIdentityButtonAction:(id)sender {
    auto& opts = _imagePipelineManager->options;
    opts.illum = { 1.,1.,1. };
    [self _updateInspectorUI];
    [[_mainView imageLayer] setNeedsDisplay];
}

- (IBAction)_colorMatrixIdentityButtonAction:(id)sender {
    auto& opts = _imagePipelineManager->options;
    [self _setColorCheckersEnabled:false];
    opts.colorMatrix = {
        1.,0.,0.,
        0.,1.,0.,
        0.,0.,1.
    };
    [self _updateInspectorUI];
    [[_mainView imageLayer] setNeedsDisplay];
}

- (void)_setColorCheckersEnabled:(bool)en {
    _colorCheckersEnabled = en;
    [_colorCheckersCheckbox setState:
        (_colorCheckersEnabled ? NSControlStateValueOn : NSControlStateValueOff)];
    [_colorMatrixTextField setEditable:!_colorCheckersEnabled];
    [_mainView setColorCheckersVisible:_colorCheckersEnabled];
    [_resetColorCheckersButton setHidden:!_colorCheckersEnabled];
}

- (IBAction)_resetColorCheckersButtonAction:(id)sender {
    [_mainView resetColorCheckerPositions];
    [self _updateColorMatrix];
}

- (IBAction)_colorCheckersAction:(id)sender {
    [self _setColorCheckersEnabled:([_colorCheckersCheckbox state]==NSControlStateValueOn)];
    if (_colorCheckersEnabled) {
        [self _updateColorMatrix];
    }
}

- (IBAction)_imageOptionsAction:(id)sender {
    auto& opts = _imagePipelineManager->options;
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
    
    opts.localContrast.en = ([_localContrastCheckbox state]==NSControlStateValueOn);
    opts.localContrast.amount = [_localContrastAmountSlider floatValue];
    opts.localContrast.radius = [_localContrastRadiusSlider floatValue];
    
    [[_mainView imageLayer] setNeedsDisplay];
    [self _updateInspectorUI];
}

- (void)_updateInspectorUI {
    const auto& opts = _imagePipelineManager->options;
    // Illuminant matrix
    {
        if (_imagePipelineManager->options.illum) {
            [self _updateIllumEstTextField:*_imagePipelineManager->options.illum];
        }
    }
    
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
    
    // Color matrix
    {
        [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
            @"%f %f %f\n"
            @"%f %f %f\n"
            @"%f %f %f\n",
            opts.colorMatrix.at(0,0), opts.colorMatrix.at(0,1), opts.colorMatrix.at(0,2),
            opts.colorMatrix.at(1,0), opts.colorMatrix.at(1,1), opts.colorMatrix.at(1,2),
            opts.colorMatrix.at(2,0), opts.colorMatrix.at(2,1), opts.colorMatrix.at(2,2)
        ]];
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
        [_localContrastCheckbox setState:(opts.localContrast.en ? NSControlStateValueOn : NSControlStateValueOff)];
        
        [_localContrastAmountSlider setFloatValue:opts.localContrast.amount];
        [_localContrastAmountLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.localContrast.amount]];
        
        [_localContrastRadiusSlider setFloatValue:opts.localContrast.radius];
        [_localContrastRadiusLabel setStringValue:[NSString stringWithFormat:@"%.3f", opts.localContrast.radius]];
    }
    
//    [[_mainView imageLayer] setOptions:opts];
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

- (void)_updateIllumEstTextField:(const Color<ColorSpace::Raw>&)illumEst {
    [_illumTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f", illumEst[0], illumEst[1], illumEst[2]
    ]];
}

- (void)_renderCallback {
    // Commit and wait so we can read the sample buffers
    _imagePipelineManager->renderer.commitAndWait();
    
    // Update the estimated illuminant in the inspector UI,
    // if we weren't overriding the illuminant
    if (!_imagePipelineManager->options.illum) {
        [self _updateIllumEstTextField:_imagePipelineManager->result.illumEst];
    }
    
    [self _updateSampleColorsUI];
}

#pragma mark - MainViewDelegate

- (void)mainViewSampleRectChanged:(MainView*)v {
    CGRect rect = [_mainView sampleRect];
    rect.origin.x *= _rawImage.img.width;
    rect.origin.y *= _rawImage.img.height;
    rect.size.width *= _rawImage.img.width;
    rect.size.height *= _rawImage.img.height;
    SampleRect sampleRect = {
        .left = std::clamp((int32_t)round(CGRectGetMinX(rect)), 0, (int32_t)_rawImage.img.width),
        .right = std::clamp((int32_t)round(CGRectGetMaxX(rect)), 0, (int32_t)_rawImage.img.width),
        .top = std::clamp((int32_t)round(CGRectGetMinY(rect)), 0, (int32_t)_rawImage.img.height),
        .bottom = std::clamp((int32_t)round(CGRectGetMaxY(rect)), 0, (int32_t)_rawImage.img.height),
    };
    
    if (sampleRect.left == sampleRect.right) sampleRect.right++;
    if (sampleRect.top == sampleRect.bottom) sampleRect.bottom++;
    
    _imagePipelineManager->options.sampleRect = sampleRect;
    [_imagePipelineManager render];
}

- (void)mainViewColorCheckerPositionsChanged:(MainView*)v {
    [self _updateColorMatrix];
}

- (void)_updateColorMatrix {
    auto points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorChecker::Count);
    
    // Use the illuminant override (if specified), otherwise use
    // the estimated illuminant
    Color<ColorSpace::Raw> illum;
    if (_imagePipelineManager->options.illum) {
        illum = *_imagePipelineManager->options.illum;
    } else {
        illum = _imagePipelineManager->result.illumEst;
    }
    const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
    const Mat<double,3,1> whiteBalance(factor/illum[0], factor/illum[1], factor/illum[2]);
    
    constexpr size_t H = ColorChecker::Count;
    Mat<double,H,3> A; // Colors that we have
    {
        size_t y = 0;
        for (const CGPoint& p : points) {
            const Color<ColorSpace::Raw> rawColor = sampleImageCircle(
                _rawImage.img,
                round(p.x*_rawImage.img.width),
                round(p.y*_rawImage.img.height),
                _colorCheckerCircleRadius
            );
            const Color<ColorSpace::Raw> c = whiteBalance.elmMul(rawColor.m);
            
            A.at(y,0) = c[0];
            A.at(y,1) = c[1];
            A.at(y,2) = c[2];
            y++;
        }
    }
    
    Mat<double,H,3> b; // Colors that we want
    {
        size_t y = 0;
        for (const auto& c : ColorChecker::Colors) {
            const Color<ColorSpace::ProPhotoRGB> ppc(c);
            b.at(y,0) = ppc[0];
            b.at(y,1) = ppc[1];
            b.at(y,2) = ppc[2];
            y++;
        }
    }
    
//    // Constrain the least squares regression so that each row sums to 1
//    // in the resulting 3x3 color matrix.
//    //
//    // How: Use the same large number in a single row of `A` and `b`
//    // Why: We don't want the CCM, which is applied after white balancing,
//    //      to disturb the white balance. (Ie, a neutral color before
//    //      applying the CCM should be neutral after applying the CCM.)
//    //      This is accomplished by ensuring that each row of the CCM
//    //      sums to 1.
//    for (int i=0; i<3; i++) {
//        const double λ = 1e8;
//        A.at(H-1,i) = λ;
//        b.at(H-1,i) = λ;
//    }
    
    std::cout << A.str() << "\n\n";
    std::cout << b.str() << "\n\n";
    
    // Solve `Ax=b` for `x`, which is the color matrix
    auto& opts = _imagePipelineManager->options;
    Mat<double,3,3> colorMatrix = A.solve(b).trans();
    
    // Force each row of `colorMatrix` sums to 1. See comment above.
    const Mat<double,3,1> rowSum = colorMatrix.sumRows();
    for (int y=0; y<3; y++) {
        for (int x=0; x<3; x++) {
            colorMatrix.at(y,x) /= rowSum[y];
        }
    }
    
    opts.colorMatrix = colorMatrix;
    [self _updateInspectorUI];
    [[_mainView imageLayer] setNeedsDisplay];
    
    [self _prefsSetColorCheckerPositions:points];
}

#pragma mark - Prefs

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

@end

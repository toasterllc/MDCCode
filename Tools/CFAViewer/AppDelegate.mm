#import "BaseView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <simd/simd.h>
#import <fstream>
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

using namespace CFAViewer;
using namespace MetalUtil;
using namespace ImagePipeline;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

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
}

- (void)awakeFromNib {
    __weak auto weakSelf = self;
    
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    _imagePipelineManager = [ImagePipelineManager new];
    _imagePipelineManager->rawImage = _rawImage.img;
    _imagePipelineManager->renderCallback = [=]() {
        [weakSelf _renderCallback];
    };
    [[_mainView imageLayer] setImagePipelineManager:_imagePipelineManager];
    
    // Load our image from disk
    {
        Mmap<MetalUtil::ImagePixel> imgData("/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker/outdoor_5pm_45.cfa");
        
        const size_t pixelCount = _rawImage.img.width*_rawImage.img.height;
        // Verify that the size of the file matches the size of the image
        assert(imgData.len() == pixelCount);
        std::copy(imgData.data(), imgData.data()+pixelCount, _rawImage.pixels);
        [[_mainView imageLayer] setNeedsDisplay];
    }
    
//    [[_mainView imageLayer] setDataChangedHandler:^(ImageLayer*) {
//        [weakSelf _updateHistograms];
//        [weakSelf _updateSampleColors];
//    }];
    
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
    
    [self _tagStartSession];
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

- (void)_updateSampleColors {
//    // Make sure we're not on the main thread, since calculating the average sample can take some time
//    assert(![NSThread isMainThread]);
//    
//    auto sampleRaw = [[_mainView imageLayer] sampleRaw];
//    auto sampleXYZD50 = [[_mainView imageLayer] sampleXYZD50];
//    auto sampleSRGB = [[_mainView imageLayer] sampleSRGB];
//    
//    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
//        self->_sampleRaw = sampleRaw;
//        self->_sampleXYZD50 = sampleXYZD50;
//        self->_sampleSRGB = sampleSRGB;
//        [self _updateSampleColorsText];
//    });
//    CFRunLoopWakeUp(CFRunLoopGetMain());
}

static Mat<double,3,1> _averageRaw(const SampleRect& rect, const CFADesc& cfaDesc, id<MTLBuffer> buf) {
//    return {};
//    // Copy _state.sampleOpts.raw locally
//    auto lock = std::unique_lock(_state.lock);
//        auto vals = copyMTLBuffer<simd::float3>(_state.sampleOpts.raw);
//        auto rect = _state.sampleOpts.rect;
//    lock.unlock();
    
    const simd::float3* vals = (simd::float3*)[buf contents];
    assert([buf length]/sizeof(simd::float3) >= rect.count());
    
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
    // Copy _state.sampleOpts.xyzD50 locally
//    auto lock = std::unique_lock(_state.lock);
//        auto vals = copyMTLBuffer<simd::float3>(_state.sampleOpts.xyzD50);
//        auto rect = _state.sampleOpts.rect;
//    lock.unlock();
    
    const simd::float3* vals = (simd::float3*)[buf contents];
    assert([buf length]/sizeof(simd::float3) >= rect.count());
    
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

//  Row0    G1  R  G1  R
//  Row1    B   G2 B   G2
//  Row2    G1  R  G1  R
//  Row3    B   G2 B   G2

//static double px(ImageLayerTypes::Image& img, uint32_t x, int32_t dx, uint32_t y, int32_t dy) {
//    int32_t xc = (int32_t)x + dx;
//    int32_t yc = (int32_t)y + dy;
//    xc = std::clamp(xc, (int32_t)0, (int32_t)img.width-1);
//    yc = std::clamp(yc, (int32_t)0, (int32_t)img.height-1);
//    return (double)img.pixels[(yc*img.width)+xc] / ImagePixelMax;
//}
//
//static double sampleR(ImageLayerTypes::Image& img, uint32_t x, uint32_t y) {
//    if (y % 2) {
//        // ROW = B G B G ...
//        
//        // Have G
//        // Want R
//        // Sample @ y-1, y+1
//        if (x % 2) return .5*px(img, x, 0, y, -1) + .5*px(img, x, 0, y, +1);
//        
//        // Have B
//        // Want R
//        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
//        else return .25*px(img, x, -1, y, -1) +
//                    .25*px(img, x, -1, y, +1) +
//                    .25*px(img, x, +1, y, -1) +
//                    .25*px(img, x, +1, y, +1) ;
//    
//    } else {
//        // ROW = G R G R ...
//        
//        // Have R
//        // Want R
//        // Sample @ this pixel
//        if (x % 2) return px(img, x, 0, y, 0);
//        
//        // Have G
//        // Want R
//        // Sample @ x-1 and x+1
//        else return .5*px(img, x, -1, y, 0) + .5*px(img, x, +1, y, 0);
//    }
//}
//
//static double sampleG(ImageLayerTypes::Image& img, uint32_t x, uint32_t y) {
////    return px(img, x, 0, y, 0);
//    
//    if (y % 2) {
//        // ROW = B G B G ...
//        
//        // Have G
//        // Want G
//        // Sample @ this pixel
//        if (x % 2) return px(img, x, 0, y, 0);
//        
//        // Have B
//        // Want G
//        // Sample @ x-1, x+1, y-1, y+1
//        else return .25*px(img, x, -1, y, 0) +
//                    .25*px(img, x, +1, y, 0) +
//                    .25*px(img, x, 0, y, -1) +
//                    .25*px(img, x, 0, y, +1) ;
//    
//    } else {
//        // ROW = G R G R ...
//        
//        // Have R
//        // Want G
//        // Sample @ x-1, x+1, y-1, y+1
//        if (x % 2) return   .25*px(img, x, -1, y, 0) +
//                            .25*px(img, x, +1, y, 0) +
//                            .25*px(img, x, 0, y, -1) +
//                            .25*px(img, x, 0, y, +1) ;
//        
//        // Have G
//        // Want G
//        // Sample @ this pixel
//        else return px(img, x, 0, y, 0);
//    }
//}
//
//static double sampleB(ImageLayerTypes::Image& img, uint32_t x, uint32_t y) {
////    return px(img, x, 0, y, 0);
//    
//    if (y % 2) {
//        // ROW = B G B G ...
//        
//        // Have G
//        // Want B
//        // Sample @ x-1, x+1
//        if (x % 2) return .5*px(img, x, -1, y, 0) + .5*px(img, x, +1, y, 0);
//        
//        // Have B
//        // Want B
//        // Sample @ this pixel
//        else return px(img, x, 0, y, 0);
//    
//    } else {
//        // ROW = G R G R ...
//        
//        // Have R
//        // Want B
//        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
//        if (x % 2) return   .25*px(img, x, -1, y, -1) +
//                            .25*px(img, x, -1, y, +1) +
//                            .25*px(img, x, +1, y, -1) +
//                            .25*px(img, x, +1, y, +1) ;
//        
//        // Have G
//        // Want B
//        // Sample @ y-1, y+1
//        else return .5*px(img, x, 0, y, -1) + .5*px(img, x, 0, y, +1);
//    }
//}
//
//static Color<ColorSpace::Raw> sampleImageCircle(ImageLayerTypes::Image& img, uint32_t x, uint32_t y, uint32_t radius) {
//    uint32_t left = std::clamp((int32_t)x-(int32_t)radius, (int32_t)0, (int32_t)img.width-1);
//    uint32_t right = std::clamp((int32_t)x+(int32_t)radius, (int32_t)0, (int32_t)img.width-1)+1;
//    uint32_t bottom = std::clamp((int32_t)y-(int32_t)radius, (int32_t)0, (int32_t)img.height-1);
//    uint32_t top = std::clamp((int32_t)y+(int32_t)radius, (int32_t)0, (int32_t)img.height-1)+1;
//    
//    Color<ColorSpace::Raw> c;
//    uint32_t i = 0;
//    for (uint32_t iy=bottom; iy<top; iy++) {
//        for (uint32_t ix=left; ix<right; ix++) {
//            if (sqrt(pow((double)ix-x,2) + pow((double)iy-y,2)) < (double)radius) {
//                c[0] += sampleR(img, ix, iy);
//                c[1] += sampleG(img, ix, iy);
//                c[2] += sampleB(img, ix, iy);
//                i++;
//            }
//        }
//    }
//    
//    c[0] /= i;
//    c[1] /= i;
//    c[2] /= i;
//    return c;
//}

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
    
//    [self _updateInspectorUI];
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
    
    // If we weren't overriding the illuminant, update the inspector
    // with the estimated illuminant from the image
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
    
//    sampleOpts.raw =
//        _state.renderer.bufferCreate(sizeof(simd::float3)*std::max(1, sampleRect.count()));
//    
//    sampleOpts.xyzD50 =
//        _state.renderer.bufferCreate(sizeof(simd::float3)*std::max(1, sampleRect.count()));
//    
//    sampleOpts.srgb =
//        _state.renderer.bufferCreate(sizeof(simd::float3)*std::max(1, sampleRect.count()));
//    
//    [self setNeedsDisplay];
//}
//    
//    
//    
//    
//    _imagePipelineManager->options.sampleRect = sampleRect;
//    [[_mainView imageLayer] setSampleRect:sampleRect];
//    [self _tagHandleSampleRectChanged];
}

- (void)mainViewColorCheckerPositionsChanged:(MainView*)v {
    [self _updateColorMatrix];
}

- (void)_updateColorMatrix {
//    auto points = [_mainView colorCheckerPositions];
//    assert(points.size() == ColorChecker::Count);
//    
//    Mat<double,ColorChecker::Count,3> A; // Colors that we have
//    {
//        auto lock = std::unique_lock(_streamImages.lock);
//        size_t y = 0;
//        for (const CGPoint& p : points) {
//            Color<ColorSpace::Raw> c = sampleImageCircle(_streamImages.img,
//                round(p.x*_streamImages.img.width),
//                round(p.y*_streamImages.img.height),
//                _colorCheckerCircleRadius);
//            A.at(y,0) = c[0];
//            A.at(y,1) = c[1];
//            A.at(y,2) = c[2];
//            y++;
//        }
//    }
//    
//    Mat<double,ColorChecker::Count,3> b; // Colors that we want
//    {
//        size_t y = 0;
//        for (const auto& c : ColorChecker::Colors) {
//            
//            const Color<ColorSpace::ProPhotoRGB> ppc(c);
//            b.at(y,0) = ppc[0];
//            b.at(y,1) = ppc[1];
//            b.at(y,2) = ppc[2];
//            
////            // Convert the color from SRGB.D65 -> XYZ.D50
////            const Color_XYZ_D50 cxyz = XYZD50FromSRGBD65(c);
////            b.at(y,0) = cxyz[0];
////            b.at(y,1) = cxyz[1];
////            b.at(y,2) = cxyz[2];
//            
//            y++;
//        }
//    }
//    
//    // Solve Ax=b for the color matrix
//    _imgOpts.colorMatrix = A.solve(b).trans();
//    [self _updateInspectorUI];
//    [self _prefsSetColorCheckerPositions:points];
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









namespace fs = std::filesystem;
struct Illum {
    fs::path p;
    Color<ColorSpace::Raw> c;
};
using Illums = std::vector<Illum>;

static const fs::path _TagDir("/Users/dave/repos/ffcc/data/AR0330-166-384x216");
Illums _TagIllums = {
{ "indoor_night2_25", { 0.669472, 0.691433, 0.271528 } },
{ "indoor_night2_26", { 0.669055, 0.691907, 0.271347 } },
{ "indoor_night2_27", { 0.668835, 0.692054, 0.271517 } },
{ "indoor_night2_28", { 0.668964, 0.691980, 0.271388 } },
{ "indoor_night2_29", { 0.669661, 0.691496, 0.270902 } },
{ "indoor_night2_30", { 0.669600, 0.691536, 0.270949 } },
{ "indoor_night2_31", { 0.669422, 0.691655, 0.271085 } },
{ "indoor_night2_32", { 0.669712, 0.691465, 0.270855 } },
{ "indoor_night2_41", { 0.659010, 0.698609, 0.278659 } },
{ "indoor_night2_42", { 0.658787, 0.698899, 0.278461 } },
{ "indoor_night2_43", { 0.658375, 0.698795, 0.279695 } },
{ "indoor_night2_44", { 0.658371, 0.698973, 0.279255 } },
{ "indoor_night2_46", { 0.669434, 0.691609, 0.271174 } },
{ "indoor_night2_49", { 0.668944, 0.692052, 0.271251 } },
{ "indoor_night2_53", { 0.669915, 0.691333, 0.270687 } },
{ "indoor_night2_54", { 0.669144, 0.692000, 0.270890 } },
{ "indoor_night2_55", { 0.669923, 0.691351, 0.270623 } },
{ "indoor_night2_56", { 0.669832, 0.691476, 0.270530 } },
{ "indoor_night2_57", { 0.669933, 0.691348, 0.270607 } },
{ "indoor_night2_64", { 0.656945, 0.699150, 0.282158 } },
{ "indoor_night2_65", { 0.656887, 0.699145, 0.282305 } },
{ "indoor_night2_66", { 0.656818, 0.699154, 0.282443 } },
{ "indoor_night2_67", { 0.656957, 0.699101, 0.282251 } },
{ "indoor_night2_68", { 0.656829, 0.699146, 0.282437 } },
{ "indoor_night2_69", { 0.656820, 0.699142, 0.282466 } },
{ "indoor_night2_74", { 0.657878, 0.699016, 0.280308 } },
{ "indoor_night2_75", { 0.659479, 0.698443, 0.277967 } },
{ "indoor_night2_76", { 0.656884, 0.699103, 0.282414 } },
{ "indoor_night2_77", { 0.665167, 0.694234, 0.274941 } },
{ "indoor_night2_78", { 0.658585, 0.698311, 0.280405 } },
{ "indoor_night2_79", { 0.657636, 0.699192, 0.280440 } },
{ "indoor_night2_80", { 0.657578, 0.698914, 0.281263 } },
{ "indoor_night2_81", { 0.657001, 0.699146, 0.282036 } },
{ "indoor_night2_89", { 0.707650, 0.665436, 0.237541 } },
{ "indoor_night2_90", { 0.708040, 0.665151, 0.237178 } },
{ "indoor_night2_91", { 0.707938, 0.665220, 0.237289 } },
{ "indoor_night2_92", { 0.707753, 0.665364, 0.237439 } },
{ "indoor_night2_93", { 0.707996, 0.665186, 0.237211 } },
{ "indoor_night2_96", { 0.707655, 0.665442, 0.237512 } },
{ "indoor_night2_97", { 0.707751, 0.665370, 0.237428 } },
{ "indoor_night2_98", { 0.706989, 0.665942, 0.238093 } },
{ "indoor_night2_132", { 0.671084, 0.690437, 0.270079 } },
{ "indoor_night2_133", { 0.671522, 0.690145, 0.269737 } },
{ "indoor_night2_134", { 0.671462, 0.690259, 0.269597 } },
{ "indoor_night2_135", { 0.671395, 0.690341, 0.269552 } },
{ "indoor_night2_136", { 0.670953, 0.690542, 0.270138 } },
{ "indoor_night2_137", { 0.671170, 0.690315, 0.270178 } },
{ "indoor_night2_138", { 0.670824, 0.690574, 0.270375 } },
{ "indoor_night2_139", { 0.670241, 0.691086, 0.270513 } },
{ "indoor_night2_140", { 0.670623, 0.690827, 0.270227 } },
{ "indoor_night2_141", { 0.671037, 0.690519, 0.269985 } },
{ "indoor_night2_142", { 0.670680, 0.690758, 0.270262 } },
{ "indoor_night2_149", { 0.705234, 0.667252, 0.239624 } },
{ "indoor_night2_156", { 0.708047, 0.665148, 0.237166 } },
{ "indoor_night2_157", { 0.708046, 0.665148, 0.237166 } },
{ "indoor_night2_158", { 0.708046, 0.665149, 0.237167 } },
{ "indoor_night2_170", { 0.680923, 0.683952, 0.261829 } },
{ "indoor_night2_171", { 0.682106, 0.683518, 0.259875 } },
{ "indoor_night2_172", { 0.680757, 0.684370, 0.261165 } },
{ "indoor_night2_173", { 0.682508, 0.683245, 0.259538 } },
{ "indoor_night2_174", { 0.682292, 0.683397, 0.259706 } },
{ "indoor_night2_183", { 0.681376, 0.681508, 0.266973 } },
{ "indoor_night2_184", { 0.681411, 0.681489, 0.266930 } },
{ "indoor_night2_185", { 0.681327, 0.681560, 0.266964 } },
{ "indoor_night2_199", { 0.670223, 0.691033, 0.270694 } },
{ "indoor_night2_200", { 0.670241, 0.690998, 0.270740 } },
{ "indoor_night2_201", { 0.669806, 0.691389, 0.270815 } },
{ "indoor_night2_203", { 0.668578, 0.692304, 0.271511 } },
{ "indoor_night2_204", { 0.668571, 0.692371, 0.271360 } },
{ "indoor_night2_205", { 0.668688, 0.692298, 0.271256 } },
{ "indoor_night2_206", { 0.669161, 0.691925, 0.271043 } },
{ "indoor_night2_207", { 0.668392, 0.692533, 0.271384 } },
{ "indoor_night2_208", { 0.667237, 0.693423, 0.271955 } },
{ "indoor_night2_223", { 0.670071, 0.693695, 0.264183 } },
{ "indoor_night2_224", { 0.669698, 0.693935, 0.264497 } },
{ "indoor_night2_225", { 0.662194, 0.698584, 0.271072 } },
{ "indoor_night2_226", { 0.666200, 0.696150, 0.267492 } },
{ "indoor_night2_227", { 0.665510, 0.696547, 0.268178 } },
{ "indoor_night2_228", { 0.661183, 0.699182, 0.271996 } },
{ "indoor_night2_229", { 0.659766, 0.700033, 0.273245 } },
{ "indoor_night2_233", { 0.682176, 0.683599, 0.259477 } },
{ "indoor_night2_234", { 0.681710, 0.684007, 0.259627 } },
{ "indoor_night2_235", { 0.681059, 0.684571, 0.259850 } },
{ "indoor_night2_244", { 0.680469, 0.682184, 0.267557 } },
{ "indoor_night2_245", { 0.681393, 0.681533, 0.266863 } },
{ "indoor_night2_247", { 0.680593, 0.682100, 0.267455 } },
{ "indoor_night2_248", { 0.680633, 0.682187, 0.267133 } },
{ "indoor_night2_249", { 0.680034, 0.682700, 0.267348 } },
{ "indoor_night2_250", { 0.679777, 0.682916, 0.267449 } },
{ "indoor_night2_251", { 0.679681, 0.683004, 0.267470 } },
{ "indoor_night2_252", { 0.679745, 0.682948, 0.267451 } },
{ "indoor_night2_253", { 0.679968, 0.682740, 0.267413 } },
{ "indoor_night2_266", { 0.683502, 0.680165, 0.264955 } },
{ "indoor_night2_267", { 0.683494, 0.680238, 0.264789 } },
{ "indoor_night2_273", { 0.682285, 0.681697, 0.264154 } },
{ "indoor_night2_274", { 0.682062, 0.681634, 0.264889 } },
{ "indoor_night2_275", { 0.682467, 0.681231, 0.264883 } },
{ "indoor_night2_282", { 0.682975, 0.682574, 0.260073 } },
{ "indoor_night2_283", { 0.683155, 0.681843, 0.261513 } },
{ "indoor_night2_284", { 0.682883, 0.682604, 0.260236 } },
{ "indoor_night2_285", { 0.682908, 0.682715, 0.259880 } },
{ "outdoor_5pm_31", { 0.453028, 0.677382, 0.579586 } },
{ "outdoor_5pm_32", { 0.456922, 0.677233, 0.576696 } },
{ "outdoor_5pm_33", { 0.463818, 0.679282, 0.568725 } },
{ "outdoor_5pm_36", { 0.431688, 0.674821, 0.598550 } },
{ "outdoor_5pm_37", { 0.423879, 0.672250, 0.606965 } },
{ "outdoor_5pm_38", { 0.423597, 0.672328, 0.607075 } },
{ "outdoor_5pm_39", { 0.467618, 0.691951, 0.550034 } },
{ "outdoor_5pm_40", { 0.461875, 0.700691, 0.543786 } },
{ "outdoor_5pm_41", { 0.444779, 0.684236, 0.577920 } },
{ "outdoor_5pm_42", { 0.430890, 0.673982, 0.600069 } },
{ "outdoor_5pm_43", { 0.451642, 0.678632, 0.579205 } },
{ "outdoor_5pm_44", { 0.446611, 0.677077, 0.584898 } },
{ "outdoor_5pm_45", { 0.426873, 0.673529, 0.603439 } },
{ "outdoor_5pm_49", { 0.446871, 0.677678, 0.584002 } },
{ "outdoor_5pm_50", { 0.492368, 0.714676, 0.496802 } },
{ "outdoor_5pm_51", { 0.478826, 0.702666, 0.526295 } },
{ "outdoor_5pm_52", { 0.476177, 0.711239, 0.517102 } },
{ "outdoor_5pm_53", { 0.474827, 0.710693, 0.519090 } },
{ "outdoor_5pm_54", { 0.476746, 0.712398, 0.514978 } },
{ "outdoor_5pm_55", { 0.476369, 0.710771, 0.517569 } },
{ "outdoor_5pm_56", { 0.477469, 0.712934, 0.513564 } },
{ "outdoor_5pm_73", { 0.509159, 0.718401, 0.473980 } },
{ "outdoor_5pm_74", { 0.507949, 0.717434, 0.476735 } },
{ "outdoor_5pm_75", { 0.509446, 0.718907, 0.472903 } },
{ "outdoor_5pm_76", { 0.507491, 0.718478, 0.475650 } },
{ "outdoor_5pm_77", { 0.508590, 0.717941, 0.475287 } },
{ "outdoor_5pm_78", { 0.509139, 0.718675, 0.473586 } },
{ "outdoor_5pm_80", { 0.506837, 0.719061, 0.475466 } },
{ "outdoor_5pm_99", { 0.455539, 0.703563, 0.545419 } },
{ "outdoor_5pm_100", { 0.455350, 0.703473, 0.545694 } },
{ "outdoor_5pm_101", { 0.457973, 0.703958, 0.542867 } },
{ "outdoor_5pm_102", { 0.453953, 0.703010, 0.547452 } },
{ "outdoor_5pm_103", { 0.453985, 0.702997, 0.547442 } },
{ "outdoor_5pm_104", { 0.453539, 0.702883, 0.547958 } },
{ "outdoor_5pm_105", { 0.453791, 0.702968, 0.547640 } },
{ "outdoor_5pm_106", { 0.453838, 0.702998, 0.547564 } },
{ "outdoor_5pm_107", { 0.453901, 0.703015, 0.547488 } },
{ "outdoor_5pm_125", { 0.444609, 0.699120, 0.559958 } },
{ "outdoor_5pm_126", { 0.445274, 0.699723, 0.558676 } },
{ "outdoor_5pm_127", { 0.437677, 0.695988, 0.569245 } },
{ "outdoor_5pm_128", { 0.426577, 0.689928, 0.584835 } },
{ "outdoor_5pm_129", { 0.424742, 0.689818, 0.586298 } },
{ "outdoor_5pm_130", { 0.414822, 0.683303, 0.600849 } },
{ "outdoor_5pm_131", { 0.414133, 0.682605, 0.602116 } },
{ "outdoor_5pm_132", { 0.414242, 0.682899, 0.601708 } },
{ "outdoor_5pm_133", { 0.414063, 0.682609, 0.602160 } },
{ "outdoor_5pm_134", { 0.414278, 0.682839, 0.601751 } },
{ "outdoor_5pm_144", { 0.481974, 0.715933, 0.505114 } },
{ "outdoor_5pm_145", { 0.482339, 0.717219, 0.502937 } },
{ "outdoor_5pm_146", { 0.481916, 0.716998, 0.503657 } },
{ "outdoor_5pm_147", { 0.481575, 0.716761, 0.504320 } },
{ "outdoor_5pm_148", { 0.482812, 0.717208, 0.502499 } },
{ "outdoor_5pm_149", { 0.483194, 0.716747, 0.502790 } },
{ "outdoor_5pm_150", { 0.480532, 0.716613, 0.505524 } },
{ "outdoor_5pm_151", { 0.482964, 0.717147, 0.502440 } },
{ "outdoor_5pm_152", { 0.481286, 0.717318, 0.503804 } },
{ "outdoor_5pm_153", { 0.479615, 0.717135, 0.505655 } },
{ "outdoor_5pm_169", { 0.416379, 0.669149, 0.615523 } },
{ "outdoor_5pm_170", { 0.412907, 0.668498, 0.618561 } },
{ "outdoor_5pm_171", { 0.418286, 0.670463, 0.612793 } },
{ "outdoor_5pm_172", { 0.414706, 0.669926, 0.615807 } },
{ "outdoor_5pm_173", { 0.417309, 0.670285, 0.613654 } },
{ "outdoor_5pm_174", { 0.416416, 0.670074, 0.614490 } },
{ "outdoor_5pm_175", { 0.416560, 0.670181, 0.614277 } },
{ "outdoor_5pm_176", { 0.414622, 0.669828, 0.615970 } },};
Illums::iterator _TagCurrentIllum = _TagIllums.end();

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

- (void)_tagStartSession {
    return;
//    _TagIllums = {};
//    for (const auto& f : fs::directory_iterator(_TagDir)) {
//        if (isCFAFile(f)) {
//            auto fname = f.path().filename().replace_extension();
//            _TagIllums.push_back({fname, {1,1,1}});
//        }
//    }
    
    _TagCurrentIllum = _TagIllums.begin();
    if (_TagCurrentIllum == _TagIllums.end()) return;
    [self _tagLoadImage];
}

- (IBAction)_tagPreviousImage:(id)sender {
    if (_TagCurrentIllum == _TagIllums.begin()) {
        NSBeep();
        return;
    }
    _TagCurrentIllum--;
    [self _tagLoadImage];
}

- (IBAction)_tagNextImage:(id)sender {
    // Don't allow going further if we're already past the end,
    // or the next item is past the end.
    if (_TagCurrentIllum==_TagIllums.end() || std::next(_TagCurrentIllum)==_TagIllums.end()) {
        NSBeep();
        return;
    }
    _TagCurrentIllum++;
    [self _tagLoadImage];
}

- (IBAction)_tagPrintStats:(id)sender {
    for (const auto& i : _TagIllums) {
        printf("{ \"%s\", { %f, %f, %f } },\n", i.p.c_str(), i.c[0], i.c[1], i.c[2]);
    }
}

- (void)_tagLoadImage {
    if (_TagCurrentIllum == _TagIllums.end()) return;
    
    const Illum& illum = (*_TagCurrentIllum);
    const fs::path& imgName = illum.p;
    const fs::path imgFilename = fs::path(imgName).replace_extension(".cfa");
    std::cout << imgName.string() << "\n";
    {
        Mmap<MetalUtil::ImagePixel> imgData(_TagDir/imgFilename);
        const size_t pixelCount = _rawImage.img.width*_rawImage.img.height;
        // Verify that the size of the file matches the size of the image
        assert(imgData.len() == pixelCount);
        std::copy(imgData.data(), imgData.data()+pixelCount, _rawImage.pixels);
        [[_mainView imageLayer] setNeedsDisplay];
    }
    
//    const Color<ColorSpace::Raw>& c = illum.c;
//    _imgOpts.whiteBalance = { c[1]/c[0], c[1]/c[1], c[1]/c[2] };
//    [self _updateInspectorUI];
    
    _imagePipelineManager->options.illum = std::nullopt;
    _imagePipelineManager->options.sampleRect = {};
    [_mainView reset];
}

- (void)_tagHandleSampleRectChanged {
////    return;
//    
//    [[_mainView imageLayer] display]; // Crappiness to force the sample to be updated
//    
//    const Color<ColorSpace::Raw> c = [[_mainView imageLayer] sampleRaw];
////    _imgOpts.whiteBalance = { c[1]/c[0], c[1]/c[1], c[1]/c[2] };
//    [self _updateInspectorUI];
//    
////    if (_TagCurrentIllum != _TagIllums.end()) {
////        Illum& illum = (*_TagCurrentIllum);
////        illum.c = c;
////        [self _tagNextImage:nil];
////    }
}

@end

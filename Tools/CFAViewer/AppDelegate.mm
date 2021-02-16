#import "BaseView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <simd/simd.h>
#import "ImageLayer.h"
#import "HistogramLayer.h"
#import "Mmap.h"
#import "Util.h"
#import "Mat.h"
#import "ColorUtil.h"
#import "TimeInstant.h"
#import "MainView.h"
#import "HistogramView.h"
#import "ColorChecker.h"
#import "MDCDevice.h"
#import "IOServiceMatcher.h"
#import "IOServiceWatcher.h"
#import "MDCUtil.h"
#import "Assert.h"

using namespace CFAViewer;
using namespace MetalTypes;
using namespace ImageLayerTypes;
using namespace ColorUtil;

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
    
    IBOutlet NSButton* _colorCheckersCheckbox;
    IBOutlet NSButton* _resetColorCheckersButton;
    
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
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
    
    IBOutlet NSTextField* _colorText_cameraRaw;
    IBOutlet NSTextField* _colorText_XYZ_D50;
    IBOutlet NSTextField* _colorText_SRGB_D65;
    
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
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        bool running = false;
        bool cancel = false;
    } _streamImages;
    
    ColorMatrix _colorMatrix;
    Mmap _imageData;
    Image _image;
    
    Color_CamRaw_D50 _sample_CamRaw_D50;
    Color_XYZ_D50 _sample_XYZ_D50;
    Color_SRGB_D65 _sample_SRGB_D65;
}

//float LabfInv(float x) {
//    // From https://en.wikipedia.org/wiki/CIELAB_color_space
//    const float d = 6./29;
//    if (x > d)  return pow(x, 3);
//    else        return 3*d*d*(x - 4./29);
//}
//
//simd::float3 XYZFromLab(simd::float3 white_XYZ, simd::float3 c_Lab) {
//    // From https://en.wikipedia.org/wiki/CIELAB_color_space
//    const float k = (c_Lab.x+16)/116;
//    const float X = white_XYZ.x * LabfInv(k+c_Lab.y/500);
//    const float Y = white_XYZ.y * LabfInv(k);
//    const float Z = white_XYZ.z * LabfInv(k-c_Lab.z/200);
//    return simd::float3{X,Y,Z};
//}
//
//float Labf(float x) {
//    const float d = 6./29;
//    const float d3 = d*d*d;
//    if (x > d3) return pow(x, 1./3);
//    else        return (x/(3*d*d)) + 4./29;
//}
//
//simd::float3 LabFromXYZ(simd::float3 white_XYZ, simd::float3 c_XYZ) {
//    const float k = Labf(c_XYZ.y/white_XYZ.y);
//    const float L = 116*k - 16;
//    const float a = 500*(Labf(c_XYZ.x/white_XYZ.x) - k);
//    const float b = 200*(k - Labf(c_XYZ.z/white_XYZ.z));
//    return simd::float3{L,a,b};
//}

float nothighlights(float x) {
    if (x < 0) return 0;
    return exp(-pow(x+.1, 10));
}

float notshadows(float x) {
    if (x > 1) return 1;
    return exp(-pow(x-1.1, 10));
}

float Luv_u(simd::float3 c_XYZ) {
    return 4*c_XYZ.x/(c_XYZ.x+15*c_XYZ.y+3*c_XYZ.z);
}

float Luv_v(simd::float3 c_XYZ) {
    return 9*c_XYZ.y/(c_XYZ.x+15*c_XYZ.y+3*c_XYZ.z);
}

simd::float3 LuvFromXYZ(simd::float3 white_XYZ, simd::float3 c_XYZ) {
    const float k1 = 24389./27;
    const float k2 = 216./24389;
    const float y = c_XYZ.y/white_XYZ.y;
    const float L = (y<=k2 ? k1*y : 116*pow(y, 1./3)-16);
    const float u_ = Luv_u(c_XYZ);
    const float v_ = Luv_v(c_XYZ);
    const float uw_ = Luv_u(white_XYZ);
    const float vw_ = Luv_v(white_XYZ);
    const float u = 13*L*(u_-uw_);
    const float v = 13*L*(v_-vw_);
    return simd::float3{L,u,v};
}

simd::float3 XYZFromLuv(simd::float3 white_XYZ, simd::float3 c_Luv) {
    const float uw_ = Luv_u(white_XYZ);
    const float vw_ = Luv_v(white_XYZ);
    const float u_ = c_Luv[1]/(13*c_Luv[0]) + uw_;
    const float v_ = c_Luv[2]/(13*c_Luv[0]) + vw_;
    const float Y = white_XYZ.y*(c_Luv[0]<=8 ? c_Luv[0]*(27./24389) : pow((c_Luv[0]+16)/116, 3));
    const float X = Y*(9*u_)/(4*v_);
    const float Z = Y*(12-3*u_-20*v_)/(4*v_);
    return simd::float3{X,Y,Z};
}

simd::float3 LCHuvFromLuv(simd::float3 c_Luv) {
    const float L = c_Luv[0];
    const float C = sqrt(c_Luv[1]*c_Luv[1] + c_Luv[2]*c_Luv[2]);
    const float H = atan2f(c_Luv[2], c_Luv[1]);
    return {L,C,H};
}

simd::float3 LuvFromLCHuv(simd::float3 c_LCHuv) {
    const float L = c_LCHuv[0];
    const float u = c_LCHuv[1]*cos(c_LCHuv[2]);
    const float v = c_LCHuv[1]*sin(c_LCHuv[2]);
    return {L,u,v};
}

- (void)awakeFromNib {
//    const simd::float3 D50_XYZ = {0.96422, 1.00000, 0.82521};
//    const simd::float3 c_XYZ_D50 = {0.280097, 0.303140, 0.353856};
//    const simd::float3 c_Luv_D50 = LuvFromXYZ(D50_XYZ, c_XYZ_D50);
//    const simd::float3 c_LCHuv_D50 = LCHuvFromLuv(c_Luv_D50);
//    const simd::float3 c_Luv_D50_2 = LuvFromLCHuv(c_LCHuv_D50);
//    const simd::float3 c_XYZ_D50_2 = XYZFromLuv(D50_XYZ, c_Luv_D50_2);
//    printf("c_XYZ_D50:\t\t%f %f %f\n", c_XYZ_D50[0], c_XYZ_D50[1], c_XYZ_D50[2]);
//    printf("c_Luv_D50:\t\t%f %f %f\n", c_Luv_D50[0], c_Luv_D50[1], c_Luv_D50[2]);
//    printf("c_LCHuv_D50:\t%f %f %f\n", c_LCHuv_D50[0], c_LCHuv_D50[1], c_LCHuv_D50[2]);
//    printf("c_Luv_D50_2:\t%f %f %f\n", c_Luv_D50_2[0], c_Luv_D50_2[1], c_Luv_D50_2[2]);
//    printf("c_XYZ_D50_2:\t%f %f %f\n", c_XYZ_D50_2[0], c_XYZ_D50_2[1], c_XYZ_D50_2[2]);
//    exit(0);
    
    
    
//    printf("%f\n", nothighlights(-10));
//    printf("%f\n", notshadows(3));
//    return;
//    const simd::float3 D50_XYZ = {0.96422, 1.00000, 0.82521};
//    const simd::float3 c_XYZ_D50 = {0.185938, 0.202315, 0.250133};
//    const simd::float3 c_Lab_D50 = LabFromXYZ(D50_XYZ, c_XYZ_D50);
//    const simd::float3 c_XYZ_D50_2 = XYZFromLab(D50_XYZ, c_Lab_D50);
//    printf("Lab: %f %f %f\n", c_Lab_D50[0], c_Lab_D50[1], c_Lab_D50[2]);
//    printf("XYZ: %f %f %f\n", c_XYZ_D50_2[0], c_XYZ_D50_2[1], c_XYZ_D50_2[2]);
//    exit(0);
    
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    _colorMatrix = {1., 0., 0., 0., 1., 0., 0., 0., 1.};
    
    _imageData = Mmap("/Users/dave/Desktop/ChromaticAberrationCorrection/img-CAC-new.cfa");
//    _imageData = Mmap("/Users/dave/Desktop/ChromaticAberrationCorrection/img-CAC-Good-SSERemoved-FactorOutGInterp-FactorOutLPHPFilters-Float1.cfa");
    
//    _imageData = Mmap("/Users/dave/Desktop/ChromaticAberrationCorrection/img-CAC-GoodSSERemoved-1.cfa");
//    _imageData = Mmap("/Users/dave/Desktop/ChromaticAberrationCorrection/img-CAC-GoodSSERemoved-65535.cfa");
//    _imageData = Mmap("/Users/dave/Desktop/ChromaticAberrationCorrection/img-CAC-GoodSSERemoved-FactorOutGInterp-ButBadBorders.cfa");
    
    _image = {
        .width = 2304,
        .height = 1296,
        .pixels = (MetalTypes::ImagePixel*)_imageData.data(),
    };
    
    [[_mainView imageLayer] setImage:_image];
    
    __weak auto weakSelf = self;
    [[_mainView imageLayer] setDataChangedHandler:^(ImageLayer*) {
        [weakSelf _updateHistograms];
        [weakSelf _updateSampleColors];
    }];
    
    [self _resetColorMatrix];
    
    [self _setDebayerLMMSEGammaEnabled:true];
    
    [self _setImageAdjustments:{
        .exposure = -2.4,
        .brightness = 0.203,
        .contrast = 0.6,
        .saturation = 0.1,
        
        .localContrast = {
            .enable = true,
            .amount = .2,
            .radius = 80,
        },
    }];
    
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
    using namespace STApp;
    assert(device);
    
    ImageLayer* layer = [_mainView imageLayer];
    try {
        // Reset the device to put it back in a pre-defined state
        device.reset();
        const size_t pixelBufCount = 2000*2000;
        auto pixelBuf = std::make_unique<Pixel[]>(pixelBufCount);
        
        float intTime = .5;
        for (;;) {
            // Check if we've been cancelled
            bool cancel = false;
            _streamImages.lock.lock();
                cancel = _streamImages.cancel;
            _streamImages.lock.unlock();
            if (cancel) break;
            
            // Capture an image, timing-out after 1s so we can check the device status,
            // in case it reports a streaming error
            const STApp::PixHeader pixStatus = device.pixCapture(pixelBuf.get(), pixelBufCount, 1000);
            const Image image = {
                .width = pixStatus.width,
                .height = pixStatus.height,
                .pixels = pixelBuf.get(),
            };
            [layer setImage:image];
            
            // Adjust exposure
            const uint32_t SubsampleFactor = 16;
            const uint32_t pixelCount = (uint32_t)pixStatus.width*(uint32_t)pixStatus.height;
            const uint32_t highlightCount = (uint32_t)pixStatus.highlightCount*SubsampleFactor;
            const uint32_t shadowCount = (uint32_t)pixStatus.shadowCount*SubsampleFactor;
            const float highlightFraction = (float)highlightCount/pixelCount;
            const float shadowFraction = (float)shadowCount/pixelCount;
//            printf("Highlight fraction: %f\nShadow fraction: %f\n\n", highlightFraction, shadowFraction);
            
            const float diff = shadowFraction-highlightFraction;
            const float absdiff = fabs(diff);
            const float adjust = 1.+((diff>0?1:-1)*pow(absdiff, .6));
            
            bool updateIntTime = false;
            if (absdiff > .01) {
                if (shadowFraction > highlightFraction) {
                    // Increase exposure
                    intTime *= adjust;
                    updateIntTime = true;
                
                } else if (highlightFraction > shadowFraction) {
                    // Decrease exposure
                    intTime *= adjust;
                    updateIntTime = true;
                }
                
                intTime = std::clamp(intTime, 0.01f, 1.f);
                const float gain = intTime/3;
                
                printf("adjust:%f\n"
                       "shadowFraction:%f\n"
                       "highlightFraction:%f\n"
                       "intTime: %f\n\n",
                       adjust,
                       shadowFraction,
                       highlightFraction,
                       intTime
                );
                
                if (updateIntTime) {
                    device.pixI2CWrite(0x3012, intTime*16384);
                    device.pixI2CWrite(0x3060, gain*63);
                }
            }
            
            
            
//            const float ShadowAdjustThreshold = 0.1;
//            const float HighlightAdjustThreshold = 0.1;
//            const float AdjustDelta = 1.1;
//            bool updateIntTime = false;
//            if (shadowFraction > ShadowAdjustThreshold) {
//                // Increase exposure
//                intTime *= AdjustDelta;
//                updateIntTime = true;
//            
//            } else if (highlightFraction > HighlightAdjustThreshold) {
//                // Decrease exposure
//                intTime /= AdjustDelta;
//                updateIntTime = true;
//            }
//            
//            intTime = std::clamp(intTime, 0.f, 1.f);
//            const float gain = intTime/3;
//            
//            if (updateIntTime) {
//                device.pixI2CWrite(0x3012, intTime*16384);
//                device.pixI2CWrite(0x3060, gain*63);
//            }
        }
    
    } catch (const std::exception& e) {
        printf("Streaming failed: %s\n", e.what());
        
        PixState pixState = PixState::Idle;
        try {
            pixState = device.pixStatus().state;
        } catch (const std::exception& e) {
            printf("pixStatus() failed: %s\n", e.what());
        }
        
        if (pixState != PixState::Capturing) {
            printf("pixStatus.state != PixState::Capturing\n");
        }
    }
    
    // Notify that our thread has exited
    _streamImages.lock.lock();
        _streamImages.running = false;
        _streamImages.signal.notify_all();
    _streamImages.lock.unlock();
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
    auto lock = std::unique_lock(_streamImages.lock);
    return _streamImages.running;
}

- (void)_setStreamImagesEnabled:(bool)en {
    // Cancel streaming and wait for it to stop
    for (;;) {
        auto lock = std::unique_lock(_streamImages.lock);
        if (!_streamImages.running) break;
        _streamImages.cancel = true;
        _streamImages.signal.wait(lock);
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
        _streamImages.lock.lock();
            _streamImages.running = true;
            _streamImages.cancel = false;
            _streamImages.signal.notify_all();
        _streamImages.lock.unlock();
        
        MDCDevice device = _mdcDevice;
        [NSThread detachNewThreadWithBlock:^{
            [self _threadStreamImages:device];
        }];
    }
}

#pragma mark - Color Matrix

- (void)controlTextDidChange:(NSNotification*)note {
    if ([note object] == _colorMatrixTextField) {
        [self _updateColorMatrixFromString:[[_colorMatrixTextField stringValue] UTF8String]];
    }
}

- (void)_resetColorMatrix {
    [self _updateColorMatrix:{1.,0.,0.,0.,1.,0.,0.,0.,1.}];
}

- (void)_updateColorMatrixFromString:(const std::string&)str {
    const std::regex floatRegex("[-+]?[0-9]*\\.?[0-9]+");
    auto begin = std::sregex_iterator(str.begin(), str.end(), floatRegex);
    auto end = std::sregex_iterator();
    std::vector<double> vals;
    
    for (std::sregex_iterator i=begin; i!=end; i++) {
        vals.push_back(std::stod(i->str()));
    }
    
    if (vals.size() != 9) {
        NSLog(@"Failed to parse color matrix");
        return;
    }
    
    [self _updateColorMatrix:vals.data()];
}

- (void)_updateColorMatrix:(const ColorMatrix&)colorMatrix {
    _colorMatrix = colorMatrix;
    
    [[_mainView imageLayer] setColorMatrix:colorMatrix];
    
    [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f\n"
        @"%f %f %f\n"
        @"%f %f %f\n",
        _colorMatrix.at(0,0), _colorMatrix.at(0,1), _colorMatrix.at(0,2),
        _colorMatrix.at(1,0), _colorMatrix.at(1,1), _colorMatrix.at(1,2),
        _colorMatrix.at(2,0), _colorMatrix.at(2,1), _colorMatrix.at(2,2)
    ]];
}

#pragma mark - Histograms

- (void)_updateHistograms {
    [[_inputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] inputHistogram]];
    [[_outputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] outputHistogram]];
}

#pragma mark - Sample

- (void)_updateSampleColors {
    // Make sure we're not on the main thread, since calculating the average sample can take some time
    assert(![NSThread isMainThread]);
    
    auto sample_CamRaw_D50 = [[_mainView imageLayer] sample_CamRaw_D50];
    auto sample_XYZ_D50 = [[_mainView imageLayer] sample_XYZ_D50];
    auto sample_SRGB_D65 = [[_mainView imageLayer] sample_SRGB_D65];
    
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        self->_sample_CamRaw_D50 = sample_CamRaw_D50;
        self->_sample_XYZ_D50 = sample_XYZ_D50;
        self->_sample_SRGB_D65 = sample_SRGB_D65;
        [self _updateSampleColorsText];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (void)_updateSampleColorsText {
    [_colorText_cameraRaw setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _sample_CamRaw_D50[0], _sample_CamRaw_D50[1], _sample_CamRaw_D50[2]]];
    [_colorText_XYZ_D50 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _sample_XYZ_D50[0], _sample_XYZ_D50[1], _sample_XYZ_D50[2]]];
    [_colorText_SRGB_D65 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _sample_SRGB_D65[0], _sample_SRGB_D65[1], _sample_SRGB_D65[2]]];
}

//  Row0    G1  R  G1  R
//  Row1    B   G2 B   G2
//  Row2    G1  R  G1  R
//  Row3    B   G2 B   G2

static double px(Image& img, uint32_t x, int32_t dx, uint32_t y, int32_t dy) {
    int32_t xc = (int32_t)x + dx;
    int32_t yc = (int32_t)y + dy;
    xc = std::clamp(xc, (int32_t)0, (int32_t)img.width-1);
    yc = std::clamp(yc, (int32_t)0, (int32_t)img.height-1);
    return (double)img.pixels[(yc*img.width)+xc] / ImagePixelMax;
}

static double sampleR(Image& img, uint32_t x, uint32_t y) {
    if (y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want R
        // Sample @ y-1, y+1
        if (x % 2) return .5*px(img, x, 0, y, -1) + .5*px(img, x, 0, y, +1);
        
        // Have B
        // Want R
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*px(img, x, -1, y, -1) +
                    .25*px(img, x, -1, y, +1) +
                    .25*px(img, x, +1, y, -1) +
                    .25*px(img, x, +1, y, +1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want R
        // Sample @ this pixel
        if (x % 2) return px(img, x, 0, y, 0);
        
        // Have G
        // Want R
        // Sample @ x-1 and x+1
        else return .5*px(img, x, -1, y, 0) + .5*px(img, x, +1, y, 0);
    }
}

static double sampleG(Image& img, uint32_t x, uint32_t y) {
//    return px(img, x, 0, y, 0);
    
    if (y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (x % 2) return px(img, x, 0, y, 0);
        
        // Have B
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*px(img, x, -1, y, 0) +
                    .25*px(img, x, +1, y, 0) +
                    .25*px(img, x, 0, y, -1) +
                    .25*px(img, x, 0, y, +1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        if (x % 2) return   .25*px(img, x, -1, y, 0) +
                            .25*px(img, x, +1, y, 0) +
                            .25*px(img, x, 0, y, -1) +
                            .25*px(img, x, 0, y, +1) ;
        
        // Have G
        // Want G
        // Sample @ this pixel
        else return px(img, x, 0, y, 0);
    }
}

static double sampleB(Image& img, uint32_t x, uint32_t y) {
//    return px(img, x, 0, y, 0);
    
    if (y % 2) {
        // ROW = B G B G ...
        
        // Have G
        // Want B
        // Sample @ x-1, x+1
        if (x % 2) return .5*px(img, x, -1, y, 0) + .5*px(img, x, +1, y, 0);
        
        // Have B
        // Want B
        // Sample @ this pixel
        else return px(img, x, 0, y, 0);
    
    } else {
        // ROW = G R G R ...
        
        // Have R
        // Want B
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        if (x % 2) return   .25*px(img, x, -1, y, -1) +
                            .25*px(img, x, -1, y, +1) +
                            .25*px(img, x, +1, y, -1) +
                            .25*px(img, x, +1, y, +1) ;
        
        // Have G
        // Want B
        // Sample @ y-1, y+1
        else return .5*px(img, x, 0, y, -1) + .5*px(img, x, 0, y, +1);
    }
}

static Color_CamRaw_D50 sampleImageCircle(Image& img, uint32_t x, uint32_t y, uint32_t radius) {
    uint32_t left = std::clamp((int32_t)x-(int32_t)radius, (int32_t)0, (int32_t)img.width-1);
    uint32_t right = std::clamp((int32_t)x+(int32_t)radius, (int32_t)0, (int32_t)img.width-1)+1;
    uint32_t bottom = std::clamp((int32_t)y-(int32_t)radius, (int32_t)0, (int32_t)img.height-1);
    uint32_t top = std::clamp((int32_t)y+(int32_t)radius, (int32_t)0, (int32_t)img.height-1)+1;
    
    Color_CamRaw_D50 c;
    uint32_t i = 0;
    for (uint32_t iy=bottom; iy<top; iy++) {
        for (uint32_t ix=left; ix<right; ix++) {
            if (sqrt(pow((double)ix-x,2) + pow((double)iy-y,2)) < (double)radius) {
                c[0] += sampleR(img, ix, iy);
                c[1] += sampleG(img, ix, iy);
                c[2] += sampleB(img, ix, iy);
                i++;
            }
        }
    }
    
    c[0] /= i;
    c[1] /= i;
    c[2] /= i;
    return c;
}

#pragma mark - UI

- (void)_saveImage:(NSString*)path {
    id image = [[_mainView imageLayer] CGImage];
    Assert(image, return);
    
    id imageDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
        (CFURLRef)[NSURL fileURLWithPath:path], kUTTypePNG, 1, nullptr));
    CGImageDestinationAddImage((CGImageDestinationRef)imageDest, (CGImageRef)image, nullptr);
    CGImageDestinationFinalize((CGImageDestinationRef)imageDest);
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

- (IBAction)_identityButtonAction:(id)sender {
    [self _setColorCheckersEnabled:false];
    [self _resetColorMatrix];
}

- (void)_setColorCheckersEnabled:(bool)en {
    _colorCheckersEnabled = en;
    [_colorCheckersCheckbox setState:(en ? NSControlStateValueOn : NSControlStateValueOff)];
    [_colorMatrixTextField setEditable:!_colorCheckersEnabled];
    [_mainView setColorCheckersVisible:_colorCheckersEnabled];
    [_resetColorCheckersButton setHidden:!_colorCheckersEnabled];
    
    if (_colorCheckersEnabled) {
        [self mainViewColorCheckerPositionsChanged:nil];
    }
}

- (IBAction)_colorCheckersCheckboxAction:(id)sender {
    [self _setColorCheckersEnabled:([_colorCheckersCheckbox state]==NSControlStateValueOn)];
}

- (IBAction)_resetColorCheckersButtonAction:(id)sender {
    [_mainView resetColorCheckerPositions];
    [self mainViewColorCheckerPositionsChanged:nil];
}

- (IBAction)_debayerOptionsAction:(id)sender {
    [self _setDebayerLMMSEGammaEnabled:([_debayerLMMSEGammaCheckbox state]==NSControlStateValueOn)];
}

- (void)_setDebayerLMMSEGammaEnabled:(bool)en {
    [_debayerLMMSEGammaCheckbox setState:(en ? NSControlStateValueOn : NSControlStateValueOff)];
    [[_mainView imageLayer] setDebayerLMMSEGammaEnabled:en];
}

- (IBAction)_imageAdjustmentsAction:(id)sender {
    const ImageAdjustments adj = {
        .exposure = [_exposureSlider floatValue],
        .brightness = [_brightnessSlider floatValue],
        .contrast = [_contrastSlider floatValue],
        .saturation = [_saturationSlider floatValue],
        
        .localContrast = {
            .enable = [_localContrastCheckbox state]==NSControlStateValueOn,
            .amount = [_localContrastAmountSlider floatValue],
            .radius = [_localContrastRadiusSlider floatValue],
        },
    };
    [self _setImageAdjustments:adj];
}

- (void)_setImageAdjustments:(const ImageAdjustments&)adj {
    [_exposureSlider setFloatValue:adj.exposure];
    [_exposureLabel setStringValue:[NSString stringWithFormat:@"%.3f", adj.exposure]];
    
    [_brightnessSlider setFloatValue:adj.brightness];
    [_brightnessLabel setStringValue:[NSString stringWithFormat:@"%.3f", adj.brightness]];
    
    [_contrastSlider setFloatValue:adj.contrast];
    [_contrastLabel setStringValue:[NSString stringWithFormat:@"%.3f", adj.contrast]];
    
    [_saturationSlider setFloatValue:adj.saturation];
    [_saturationLabel setStringValue:[NSString stringWithFormat:@"%.3f", adj.saturation]];
    
    [_localContrastCheckbox setState:(adj.localContrast.enable ? NSControlStateValueOn : NSControlStateValueOff)];
    
    [_localContrastAmountSlider setFloatValue:adj.localContrast.amount];
    [_localContrastAmountLabel setStringValue:[NSString stringWithFormat:@"%.3f", adj.localContrast.amount]];
    
    [_localContrastRadiusSlider setFloatValue:adj.localContrast.radius];
    [_localContrastRadiusLabel setStringValue:[NSString stringWithFormat:@"%.3f", adj.localContrast.radius]];
    
    [[_mainView imageLayer] setImageAdjustments:adj];
}

- (IBAction)_highlightFactorSliderAction:(id)sender {
    Mat<double,3,3> highlightFactor(
        [_highlightFactorR0Slider doubleValue],
        [_highlightFactorR1Slider doubleValue],
        [_highlightFactorR2Slider doubleValue],
        
        [_highlightFactorG0Slider doubleValue],
        [_highlightFactorG1Slider doubleValue],
        [_highlightFactorG2Slider doubleValue],
        
        [_highlightFactorB0Slider doubleValue],
        [_highlightFactorB1Slider doubleValue],
        [_highlightFactorB2Slider doubleValue]
    );
    
    [[_mainView imageLayer] setHighlightFactor:highlightFactor];
    [_highlightFactorR0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(0,0)]];
    [_highlightFactorR1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(0,1)]];
    [_highlightFactorR2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(0,2)]];
    [_highlightFactorG0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(1,0)]];
    [_highlightFactorG1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(1,1)]];
    [_highlightFactorG2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(1,2)]];
    [_highlightFactorB0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(2,0)]];
    [_highlightFactorB1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(2,1)]];
    [_highlightFactorB2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor.at(2,2)]];
    [self mainViewSampleRectChanged:nil];
}

#pragma mark - MainViewDelegate

- (void)mainViewSampleRectChanged:(MainView*)v {
    const CGRect sampleRect = [_mainView sampleRect];
    [[_mainView imageLayer] setSampleRect:sampleRect];
}

- (void)mainViewColorCheckerPositionsChanged:(MainView*)v {
    auto points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorChecker::Count);
    
    Mat<double,ColorChecker::Count,3> A; // Colors that we have
    size_t y = 0;
    for (const CGPoint& p : points) {
        Color_CamRaw_D50 c = sampleImageCircle(_image,
            round(p.x*_image.width),
            round(p.y*_image.height),
            _colorCheckerCircleRadius);
        A.at(y,0) = c[0];
        A.at(y,1) = c[1];
        A.at(y,2) = c[2];
        y++;
    }
    
    Mat<double,ColorChecker::Count,3> b; // Colors that we want
    y = 0;
    for (Color_SRGB_D65 c : ColorChecker::Colors) {
        // Convert the color from SRGB -> XYZ -> XYY
        Color_XYZ_D50 cxyy = XYYFromXYZ(XYZFromSRGB(c));
        const Color_XYZ_D50 cxyz = XYZFromXYY(cxyy);
        
        b.at(y,0) = cxyz[0];
        b.at(y,1) = cxyz[1];
        b.at(y,2) = cxyz[2];
        y++;
    }
    
    // Solve Ax=b for the color matrix
    ColorMatrix x = A.solve(b).trans();
    [self _updateColorMatrix:x];
    [self _prefsSetColorCheckerPositions:points];
    
//    NSMutableArray* nspoints = [NSMutableArray new];
//    for (const CGPoint& p : points) {
//        [nspoints addObject:[NSValue valueWithPoint:p]];
//    }
//    [[NSUserDefaults standardUserDefaults] setObject:nspoints forKey:ColorCheckerPositionsKey];
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

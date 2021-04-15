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
    
    IBOutlet NSTextField* _whiteBalanceTextField;
    
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
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        bool running = false;
        bool cancel = false;
        
        STApp::Pixel pixelBuf[2200*2200];
        ImageLayerTypes::Image img = {
            .cfaDesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green},
            .width = 0,
            .height = 0,
            .pixels = pixelBuf,
        };
    } _streamImages;
    
    ImageLayerTypes::Options _imgOpts;
    
    Color<ColorSpace::Raw> _sampleRaw;
    Color<ColorSpace::XYZD50> _sampleXYZD50;
    Color<ColorSpace::SRGB> _sampleSRGB;
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
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    // Load our image from disk
    {
        auto lock = std::unique_lock(_streamImages.lock);
//        Mmap imgData("/Users/dave/repos/C5/TestSet-AR0330-4/image001_sensorname_AR0330.cfa");
//        Mmap imgData("/Users/dave/Desktop/AR0330TestImages/1.cfa");
//        Mmap imgData("/Users/dave/Desktop/AR0330TestImages/1.cfa");
//        Mmap imgData("/Users/dave/Desktop/ColorCheckerRaw.cfa");
//        Mmap imgData("/Users/dave/repos/MotionDetectorCamera/Tools/CFAViewer/img.cfa");
//        Mmap imgData("/Users/dave/Desktop/test.cfa");
//        Mmap imgData("/Users/dave/Desktop/CFAViewerSession-Outdoor-Noon/106.cfa");
//        Mmap imgData("/Users/dave/Desktop/CFAViewerSession-Outdoor-Noon/158.cfa");
        
//        // Back yard
//        Mmap imgData("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-Outdoor-4pm/30.cfa");
        
//        // Sue, backyard, color checker
//        Mmap imgData("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-Outdoor-4pm/35.cfa");
        
//        // Front yard, car
//        Mmap imgData("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-Outdoor-4pm/139.cfa");
        
//        // Front of house
//        Mmap imgData("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-Outdoor-4pm/127.cfa");
        
//        // Sue, living room, color checker
//        Mmap imgData("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-Indoor-Night/69.cfa");
        
//        Mmap imgData("/Users/dave/matlab/1.cfa");
        
        // Cabinet
//        Mmap imgData("/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker/indoor_night2_26.cfa");
        // Orange
        Mmap imgData("/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker/indoor_night2_53.cfa");
        
        _streamImages.img.width = 2304;
        _streamImages.img.height = 1296;
//        _streamImages.img.width = 2601;
//        _streamImages.img.height = 1732;
        
        const size_t len = _streamImages.img.width*_streamImages.img.height*sizeof(*_streamImages.img.pixels);
        // Verify that the size of the file matches the the width/height of the image
        assert(imgData.len() == len);
        // Verify that our buffer is large enough to fit `len` bytes
        assert(sizeof(_streamImages.pixelBuf) >= len);
        memcpy(_streamImages.pixelBuf, imgData.data(), len);
        
        [[_mainView imageLayer] setImage:_streamImages.img];
    }
    
    __weak auto weakSelf = self;
    [[_mainView imageLayer] setDataChangedHandler:^(ImageLayer*) {
        [weakSelf _updateHistograms];
        [weakSelf _updateSampleColors];
    }];
    
    _imgOpts = {
        .rawMode = false,
        
        .reconstructHighlights = {
            .en = true,
            .badPixelFactors    = {1.130, 1.613, 1.000},
            .goodPixelFactors   = {1.051, 1.544, 1.195},
        },
        
//        illum = 2.4743327397, 2.5535876543, 1
        .whiteBalance = { 0.691343/0.669886, 0.691343/0.691343, 0.691343/0.270734 },
//        .whiteBalance = { 1.368683, 1.000000, 1.513193 },
        
        .defringe = {
            .en = false,
            .opts = {
                .whiteBalanceFactors = {
                    0.296587/0.203138,  // Red
                    0.296587/0.296587,  // Green
                    0.296587/0.161148,  // Blue
                }
            }
        },
    };
    
    
//    _imgOpts = {
//        .rawMode = false,
//        
//        .whiteBalance = { 1., 1., 1. },
//        
//        .defringe = {
//            .en = true,
//            .opts = {
//                .whiteBalanceFactors = {
//                    0.296587/0.203138,  // Red
//                    0.296587/0.296587,  // Green
//                    0.296587/0.161148,  // Blue
//                }
//            }
//        },
//        
//        .reconstructHighlights = {
//            .en = true,
//            .badPixelFactors    = {1.130, 1.613, 1.000},
//            .goodPixelFactors   = {1.051, 1.544, 1.195},
//        },
//        
//        .debayerLMMSE = {
//            .applyGamma = true,
//        },
//        
//        .colorMatrix = {
//            +3.040751, +1.406093, +0.746958,
//            -0.293108, +4.785811, -0.756907,
//            -0.578106, -1.496914, +8.609732,
//        },
//        
//        .exposure = -2.4,
//        .brightness = 0.203,
//        .contrast = 0.6,
//        .saturation = 0.1,
//        
//        .localContrast = {
//            .en = true,
//            .amount = .2,
//            .radius = 80,
//        },
//    };
    
    [self _updateImageOptions];
    
//    bool rawMode = false;
//    
//    struct {
//        bool en = false;
//        Defringe::Options options;
//    } defringe;
//    
//    bool reconstructHighlights = false;
//    
//    struct {
//        bool applyGamma = false;
//    } debayerLMMSE;
//    
//    simd::float3x3 colorMatrix = {
//        simd::float3{1,0,0},
//        simd::float3{0,1,0},
//        simd::float3{0,0,1},
//    };
//    
//    float exposure = 0;
//    float brightness = 0;
//    float contrast = 0;
//    float saturation = 0;
//    
//    struct {
//        bool enable = false;
//        float amount = 0;
//        float radius = 0;
//    } localContrast;
    
//    [self _setDefringe:true options:ImagePipeline::Defringe::Options{}];
//    
//    [self _setReconstructHighlights:true];
//    
//    [self _setDebayerLMMSEApplyGamma:true];
    
//    [self _setImageAdjustments:{
//        .exposure = -2.4,
//        .brightness = 0.203,
//        .contrast = 0.6,
//        .saturation = 0.1,
//        
//        .localContrast = {
//            .enable = true,
//            .amount = .2,
//            .radius = 80,
//        },
//    }];
    
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
    using namespace STApp;
    assert(device);
    
    NSString* dirName = [NSString stringWithFormat:@"CFAViewerSession-%f", [NSDate timeIntervalSinceReferenceDate]];
    NSString* dirPath = [NSString stringWithFormat:@"/Users/dave/Desktop/%@", dirName];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:false attributes:nil error:nil]);
    
    ImageLayer* layer = [_mainView imageLayer];
    try {
        // Reset the device to put it back in a pre-defined state
        device.reset();
        
        float intTime = .5;
        const size_t tmpPixelBufLen = std::size(_streamImages.pixelBuf);
        auto tmpPixelBuf = std::make_unique<STApp::Pixel[]>(tmpPixelBufLen);
        uint32_t saveIdx = 1;
        for (uint32_t i=0;; i++) {
            // Capture an image, timing-out after 1s so we can check the device status,
            // in case it reports a streaming error
            const STApp::PixHeader pixStatus = device.pixCapture(tmpPixelBuf.get(), tmpPixelBufLen, 1000);
            
            auto lock = std::unique_lock(_streamImages.lock);
                // Check if we've been cancelled
                if (_streamImages.cancel) break;
                
                // Copy the image into our persistent buffer
                const size_t len = pixStatus.width*pixStatus.height*sizeof(STApp::Pixel);
                memcpy(_streamImages.pixelBuf, tmpPixelBuf.get(), len);
                _streamImages.img.width = pixStatus.width;
                _streamImages.img.height = pixStatus.height;
            lock.unlock();
            
            [layer setImage:_streamImages.img];
            
            if (!(i % 10)) {
                NSString* imagePath = [dirPath stringByAppendingPathComponent:[NSString
                    stringWithFormat:@"%ju.cfa",(uintmax_t)saveIdx]];
                std::ofstream f;
                f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
                f.open([imagePath UTF8String]);
                f.write((char*)_streamImages.img.pixels, len);
                saveIdx++;
                printf("Saved %s\n", [imagePath UTF8String]);
            }
            
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
            
            if (absdiff > .01) {
                bool updateIntTime = false;
                if (shadowFraction > highlightFraction) {
                    // Increase exposure
                    intTime *= adjust;
                    updateIntTime = true;
                
                } else if (highlightFraction > shadowFraction) {
                    // Decrease exposure
                    intTime *= adjust;
                    updateIntTime = true;
                }
                
                intTime = std::clamp(intTime, 0.001f, 1.f);
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

static Mat<double,3,1> _whiteBalanceMatrixFromString(const std::string& str) {
    return _matrixFromString<3,1>(str);
}

static Mat<double,3,3> _colorMatrixFromString(const std::string& str) {
    return _matrixFromString<3,3>(str);
}

- (void)controlTextDidChange:(NSNotification*)note {
    if ([note object] == _whiteBalanceTextField) {
        _imgOpts.whiteBalance = _whiteBalanceMatrixFromString([[_whiteBalanceTextField stringValue] UTF8String]);
        [self _updateImageOptions];
    
    } else if ([note object] == _colorMatrixTextField) {
        _imgOpts.colorMatrix = _colorMatrixFromString([[_colorMatrixTextField stringValue] UTF8String]);
        [self _updateImageOptions];
    }
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
    
    auto sampleRaw = [[_mainView imageLayer] sampleRaw];
    auto sampleXYZD50 = [[_mainView imageLayer] sampleXYZD50];
    auto sampleSRGB = [[_mainView imageLayer] sampleSRGB];
    
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        self->_sampleRaw = sampleRaw;
        self->_sampleXYZD50 = sampleXYZD50;
        self->_sampleSRGB = sampleSRGB;
        [self _updateSampleColorsText];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (void)_updateSampleColorsText {
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

static double px(ImageLayerTypes::Image& img, uint32_t x, int32_t dx, uint32_t y, int32_t dy) {
    int32_t xc = (int32_t)x + dx;
    int32_t yc = (int32_t)y + dy;
    xc = std::clamp(xc, (int32_t)0, (int32_t)img.width-1);
    yc = std::clamp(yc, (int32_t)0, (int32_t)img.height-1);
    return (double)img.pixels[(yc*img.width)+xc] / ImagePixelMax;
}

static double sampleR(ImageLayerTypes::Image& img, uint32_t x, uint32_t y) {
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

static double sampleG(ImageLayerTypes::Image& img, uint32_t x, uint32_t y) {
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

static double sampleB(ImageLayerTypes::Image& img, uint32_t x, uint32_t y) {
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

static Color<ColorSpace::Raw> sampleImageCircle(ImageLayerTypes::Image& img, uint32_t x, uint32_t y, uint32_t radius) {
    uint32_t left = std::clamp((int32_t)x-(int32_t)radius, (int32_t)0, (int32_t)img.width-1);
    uint32_t right = std::clamp((int32_t)x+(int32_t)radius, (int32_t)0, (int32_t)img.width-1)+1;
    uint32_t bottom = std::clamp((int32_t)y-(int32_t)radius, (int32_t)0, (int32_t)img.height-1);
    uint32_t top = std::clamp((int32_t)y+(int32_t)radius, (int32_t)0, (int32_t)img.height-1)+1;
    
    Color<ColorSpace::Raw> c;
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
    const std::string ext([[[path pathExtension] lowercaseString] UTF8String]);
    if (ext == "cfa") {
        auto lock = std::unique_lock(_streamImages.lock);
            std::ofstream f;
            f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
            f.open([path UTF8String]);
            const size_t len = _streamImages.img.width*_streamImages.img.height*sizeof(*_streamImages.img.pixels);
            f.write((char*)_streamImages.img.pixels, len);
        lock.unlock();
    
    } else if (ext == "png") {
        id image = [[_mainView imageLayer] CGImage];
        Assert(image, return);
        
        id imageDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
            (CFURLRef)[NSURL fileURLWithPath:path], kUTTypePNG, 1, nullptr));
        CGImageDestinationAddImage((CGImageDestinationRef)imageDest, (CGImageRef)image, nullptr);
        CGImageDestinationFinalize((CGImageDestinationRef)imageDest);
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

- (IBAction)_whiteBalanceIdentityButtonAction:(id)sender {
    _imgOpts.whiteBalance = { 1.,1.,1. };
    [self _updateImageOptions];
}

- (IBAction)_colorMatrixIdentityButtonAction:(id)sender {
    [self _setColorCheckersEnabled:false];
    _imgOpts.colorMatrix = {
        1.,0.,0.,
        0.,1.,0.,
        0.,0.,1.
    };
    [self _updateImageOptions];
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
    _imgOpts.defringe.en = ([_defringeCheckbox state]==NSControlStateValueOn);
    _imgOpts.defringe.opts.rounds = (uint32_t)[_defringeRoundsSlider intValue];
    _imgOpts.defringe.opts.αthresh = [_defringeαThresholdSlider floatValue];
    _imgOpts.defringe.opts.γthresh = [_defringeγThresholdSlider floatValue];
    _imgOpts.defringe.opts.γfactor = [_defringeγFactorSlider floatValue];
    _imgOpts.defringe.opts.δfactor = [_defringeδFactorSlider floatValue];
    
    _imgOpts.reconstructHighlights.en = ([_reconstructHighlightsCheckbox state]==NSControlStateValueOn);
    
    _imgOpts.debayerLMMSE.applyGamma = ([_debayerLMMSEGammaCheckbox state]==NSControlStateValueOn);
    
    _imgOpts.exposure = [_exposureSlider floatValue];
    _imgOpts.brightness = [_brightnessSlider floatValue];
    _imgOpts.contrast = [_contrastSlider floatValue];
    _imgOpts.saturation = [_saturationSlider floatValue];
    
    _imgOpts.localContrast.en = ([_localContrastCheckbox state]==NSControlStateValueOn);
    _imgOpts.localContrast.amount = [_localContrastAmountSlider floatValue];
    _imgOpts.localContrast.radius = [_localContrastRadiusSlider floatValue];
    
    [self _updateImageOptions];
}

- (void)_updateImageOptions {
    // White balance matrix
    {
        [_whiteBalanceTextField setStringValue:[NSString stringWithFormat:
            @"%f %f %f", _imgOpts.whiteBalance[0], _imgOpts.whiteBalance[1], _imgOpts.whiteBalance[2]
        ]];
    }
    
    // Defringe
    {
        [_defringeCheckbox setState:(_imgOpts.defringe.en ? NSControlStateValueOn : NSControlStateValueOff)];
        
        [_defringeRoundsSlider setIntValue:_imgOpts.defringe.opts.rounds];
        [_defringeRoundsLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)_imgOpts.defringe.opts.rounds]];
        
        [_defringeαThresholdSlider setFloatValue:_imgOpts.defringe.opts.αthresh];
        [_defringeαThresholdLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.defringe.opts.αthresh]];
        
        [_defringeγThresholdSlider setFloatValue:_imgOpts.defringe.opts.γthresh];
        [_defringeγThresholdLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.defringe.opts.γthresh]];
        
        [_defringeγFactorSlider setFloatValue:_imgOpts.defringe.opts.γfactor];
        [_defringeγFactorLabel setStringValue:[NSString stringWithFormat:@"%.3f",
            _imgOpts.defringe.opts.γfactor]];
        
        [_defringeδFactorSlider setFloatValue:_imgOpts.defringe.opts.δfactor];
        [_defringeδFactorLabel setStringValue:[NSString stringWithFormat:@"%.3f",
            _imgOpts.defringe.opts.δfactor]];
    }
    
    // Reconstruct Highlights
    {
        [_reconstructHighlightsCheckbox setState:(_imgOpts.reconstructHighlights.en ?
            NSControlStateValueOn : NSControlStateValueOff)];
    }
    
    // LMMSE
    {
        [_debayerLMMSEGammaCheckbox setState:(_imgOpts.debayerLMMSE.applyGamma ?
            NSControlStateValueOn : NSControlStateValueOff)];
    }
    
    // Color matrix
    {
        [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
            @"%f %f %f\n"
            @"%f %f %f\n"
            @"%f %f %f\n",
            _imgOpts.colorMatrix.at(0,0), _imgOpts.colorMatrix.at(0,1), _imgOpts.colorMatrix.at(0,2),
            _imgOpts.colorMatrix.at(1,0), _imgOpts.colorMatrix.at(1,1), _imgOpts.colorMatrix.at(1,2),
            _imgOpts.colorMatrix.at(2,0), _imgOpts.colorMatrix.at(2,1), _imgOpts.colorMatrix.at(2,2)
        ]];
    }
    
    {
        [_exposureSlider setFloatValue:_imgOpts.exposure];
        [_exposureLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.exposure]];
        
        [_brightnessSlider setFloatValue:_imgOpts.brightness];
        [_brightnessLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.brightness]];
        
        [_contrastSlider setFloatValue:_imgOpts.contrast];
        [_contrastLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.contrast]];
        
        [_saturationSlider setFloatValue:_imgOpts.saturation];
        [_saturationLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.saturation]];
    }
    
    // Local contrast
    {
        [_localContrastCheckbox setState:(_imgOpts.localContrast.en ? NSControlStateValueOn : NSControlStateValueOff)];
        
        [_localContrastAmountSlider setFloatValue:_imgOpts.localContrast.amount];
        [_localContrastAmountLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.localContrast.amount]];
        
        [_localContrastRadiusSlider setFloatValue:_imgOpts.localContrast.radius];
        [_localContrastRadiusLabel setStringValue:[NSString stringWithFormat:@"%.3f", _imgOpts.localContrast.radius]];
    }
    
    [[_mainView imageLayer] setOptions:_imgOpts];
}

- (IBAction)_highlightFactorSliderAction:(id)sender {
    Mat<double,9,1> highlightFactor(
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
    
//    0.924
//    1.368
//    1.431
//    
//    0.959
//    1.455
//    1.491
    
    _imgOpts.reconstructHighlights.badPixelFactors = {highlightFactor[0], highlightFactor[1], highlightFactor[2]};
    _imgOpts.reconstructHighlights.goodPixelFactors = {highlightFactor[3], highlightFactor[4], highlightFactor[5]};
    [self _updateImageOptions];
    
    [_highlightFactorR0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[0]]];
    [_highlightFactorR1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[1]]];
    [_highlightFactorR2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[2]]];
    [_highlightFactorG0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[3]]];
    [_highlightFactorG1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[4]]];
    [_highlightFactorG2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[5]]];
    [_highlightFactorB0Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[6]]];
    [_highlightFactorB1Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[7]]];
    [_highlightFactorB2Label setStringValue:[NSString stringWithFormat:@"%.3f", highlightFactor[8]]];
    [self mainViewSampleRectChanged:nil];
}

#pragma mark - MainViewDelegate

- (void)mainViewSampleRectChanged:(MainView*)v {
    const CGRect sampleRect = [_mainView sampleRect];
    [[_mainView imageLayer] setSampleRect:sampleRect];
    [self _tagHandleSampleRectChanged];
}

- (void)mainViewColorCheckerPositionsChanged:(MainView*)v {
    [self _updateColorMatrix];
}

- (void)_updateColorMatrix {
    auto points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorChecker::Count);
    
    Mat<double,ColorChecker::Count,3> A; // Colors that we have
    {
        auto lock = std::unique_lock(_streamImages.lock);
        size_t y = 0;
        for (const CGPoint& p : points) {
            Color<ColorSpace::Raw> c = sampleImageCircle(_streamImages.img,
                round(p.x*_streamImages.img.width),
                round(p.y*_streamImages.img.height),
                _colorCheckerCircleRadius);
            A.at(y,0) = c[0];
            A.at(y,1) = c[1];
            A.at(y,2) = c[2];
            y++;
        }
    }
    
    Mat<double,ColorChecker::Count,3> b; // Colors that we want
    {
        size_t y = 0;
        for (const auto& c : ColorChecker::Colors) {
            
            const Color<ColorSpace::ProPhotoRGB> ppc(c);
            b.at(y,0) = ppc[0];
            b.at(y,1) = ppc[1];
            b.at(y,2) = ppc[2];
            
//            // Convert the color from SRGB.D65 -> XYZ.D50
//            const Color_XYZ_D50 cxyz = XYZD50FromSRGBD65(c);
//            b.at(y,0) = cxyz[0];
//            b.at(y,1) = cxyz[1];
//            b.at(y,2) = cxyz[2];
            
            y++;
        }
    }
    
    // Solve Ax=b for the color matrix
    _imgOpts.colorMatrix = A.solve(b).trans();
    [self _updateImageOptions];
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









namespace fs = std::filesystem;
struct Illum {
    fs::path p;
    Color<ColorSpace::Raw> c;
};
using Illums = std::vector<Illum>;

static const fs::path _TagDir("/Users/dave/Desktop/Old/2021:4:9/FFCCImageSets/Both");
Illums _TagIllums = {
{ "indoor_night2_25", { 0.669053, 0.691836, 0.271534 } },
{ "indoor_night2_26", { 0.669755, 0.691402, 0.270909 } },
{ "indoor_night2_27", { 0.669239, 0.691722, 0.271368 } },
{ "indoor_night2_28", { 0.668643, 0.692090, 0.271898 } },
{ "indoor_night2_29", { 0.669835, 0.691353, 0.270836 } },
{ "indoor_night2_30", { 0.669427, 0.691607, 0.271198 } },
{ "indoor_night2_31", { 0.669813, 0.691367, 0.270855 } },
{ "indoor_night2_32", { 0.669731, 0.691418, 0.270926 } },
{ "indoor_night2_41", { 0.660777, 0.698072, 0.275807 } },
{ "indoor_night2_42", { 0.660576, 0.698835, 0.274352 } },
{ "indoor_night2_43", { 0.661906, 0.697711, 0.274006 } },
{ "indoor_night2_44", { 0.660398, 0.699010, 0.274336 } },
{ "indoor_night2_46", { 0.669986, 0.691259, 0.270702 } },
{ "indoor_night2_49", { 0.669205, 0.691907, 0.270980 } },
{ "indoor_night2_53", { 0.669886, 0.691343, 0.270734 } },
{ "indoor_night2_54", { 0.669818, 0.691399, 0.270761 } },
{ "indoor_night2_55", { 0.669763, 0.691448, 0.270773 } },
{ "indoor_night2_56", { 0.669673, 0.691521, 0.270808 } },
{ "indoor_night2_57", { 0.669849, 0.691374, 0.270746 } },
{ "indoor_night2_64", { 0.656832, 0.699137, 0.282453 } },
{ "indoor_night2_65", { 0.656802, 0.699154, 0.282481 } },
{ "indoor_night2_66", { 0.656799, 0.699155, 0.282483 } },
{ "indoor_night2_67", { 0.656823, 0.699142, 0.282461 } },
{ "indoor_night2_68", { 0.656804, 0.699153, 0.282479 } },
{ "indoor_night2_69", { 0.656799, 0.699155, 0.282483 } },
{ "indoor_night2_74", { 0.658146, 0.698442, 0.281110 } },
{ "indoor_night2_75", { 0.657050, 0.699034, 0.282200 } },
{ "indoor_night2_76", { 0.656859, 0.699121, 0.282429 } },
{ "indoor_night2_77", { 0.669299, 0.691683, 0.271318 } },
{ "indoor_night2_78", { 0.657437, 0.698787, 0.281911 } },
{ "indoor_night2_79", { 0.657943, 0.698500, 0.281440 } },
{ "indoor_night2_80", { 0.658475, 0.698184, 0.280979 } },
{ "indoor_night2_81", { 0.657044, 0.699015, 0.282262 } },
{ "indoor_night2_89", { 0.708048, 0.665147, 0.237164 } },
{ "indoor_night2_90", { 0.708022, 0.665166, 0.237188 } },
{ "indoor_night2_91", { 0.708047, 0.665147, 0.237168 } },
{ "indoor_night2_92", { 0.707017, 0.665920, 0.238071 } },
{ "indoor_night2_93", { 0.707769, 0.665357, 0.237410 } },
{ "indoor_night2_96", { 0.708035, 0.665157, 0.237177 } },
{ "indoor_night2_97", { 0.708042, 0.665152, 0.237171 } },
{ "indoor_night2_98", { 0.708031, 0.665159, 0.237181 } },
{ "indoor_night2_132", { 0.672722, 0.689541, 0.268286 } },
{ "indoor_night2_133", { 0.672660, 0.689565, 0.268383 } },
{ "indoor_night2_134", { 0.672747, 0.689525, 0.268266 } },
{ "indoor_night2_135", { 0.671826, 0.690110, 0.269070 } },
{ "indoor_night2_136", { 0.671731, 0.690170, 0.269152 } },
{ "indoor_night2_137", { 0.670586, 0.690880, 0.270185 } },
{ "indoor_night2_138", { 0.670190, 0.691124, 0.270542 } },
{ "indoor_night2_139", { 0.670288, 0.691070, 0.270439 } },
{ "indoor_night2_140", { 0.670352, 0.691032, 0.270375 } },
{ "indoor_night2_141", { 0.670471, 0.690958, 0.270269 } },
{ "indoor_night2_142", { 0.670101, 0.691187, 0.270600 } },
{ "indoor_night2_149", { 0.684020, 0.682338, 0.257937 } },
{ "indoor_night2_156", { 0.708057, 0.665132, 0.237183 } },
{ "indoor_night2_157", { 0.708045, 0.665147, 0.237174 } },
{ "indoor_night2_158", { 0.708043, 0.665150, 0.237172 } },
{ "indoor_night2_170", { 0.680059, 0.683989, 0.263966 } },
{ "indoor_night2_171", { 0.682345, 0.683337, 0.259725 } },
{ "indoor_night2_172", { 0.681387, 0.683950, 0.260622 } },
{ "indoor_night2_173", { 0.682410, 0.683302, 0.259644 } },
{ "indoor_night2_174", { 0.682448, 0.683284, 0.259592 } },
{ "indoor_night2_183", { 0.681285, 0.681623, 0.266909 } },
{ "indoor_night2_184", { 0.681239, 0.681679, 0.266884 } },
{ "indoor_night2_185", { 0.681203, 0.681698, 0.266928 } },
{ "indoor_night2_199", { 0.674932, 0.687068, 0.269081 } },
{ "indoor_night2_200", { 0.677171, 0.685083, 0.268514 } },
{ "indoor_night2_201", { 0.672552, 0.689041, 0.269993 } },
{ "indoor_night2_203", { 0.670858, 0.690479, 0.270533 } },
{ "indoor_night2_204", { 0.670086, 0.691122, 0.270805 } },
{ "indoor_night2_205", { 0.668344, 0.692427, 0.271775 } },
{ "indoor_night2_206", { 0.670402, 0.690869, 0.270667 } },
{ "indoor_night2_207", { 0.670080, 0.691097, 0.270882 } },
{ "indoor_night2_208", { 0.667073, 0.693216, 0.272881 } },
{ "indoor_night2_223", { 0.670957, 0.692919, 0.263970 } },
{ "indoor_night2_224", { 0.669257, 0.693878, 0.265760 } },
{ "indoor_night2_225", { 0.661754, 0.698774, 0.271656 } },
{ "indoor_night2_226", { 0.665560, 0.696346, 0.268574 } },
{ "indoor_night2_227", { 0.661048, 0.699236, 0.272185 } },
{ "indoor_night2_228", { 0.659763, 0.700024, 0.273274 } },
{ "indoor_night2_229", { 0.659371, 0.700213, 0.273738 } },
{ "indoor_night2_233", { 0.682370, 0.683313, 0.259721 } },
{ "indoor_night2_234", { 0.682174, 0.683447, 0.259883 } },
{ "indoor_night2_235", { 0.679772, 0.685033, 0.261994 } },
{ "indoor_night2_244", { 0.680872, 0.681979, 0.267056 } },
{ "indoor_night2_245", { 0.680898, 0.682026, 0.266869 } },
{ "indoor_night2_247", { 0.680844, 0.681997, 0.267078 } },
{ "indoor_night2_248", { 0.677554, 0.684837, 0.268177 } },
{ "indoor_night2_249", { 0.678590, 0.683977, 0.267752 } },
{ "indoor_night2_250", { 0.678117, 0.684363, 0.267964 } },
{ "indoor_night2_251", { 0.679407, 0.683269, 0.267488 } },
{ "indoor_night2_252", { 0.678113, 0.684366, 0.267967 } },
{ "indoor_night2_253", { 0.678888, 0.683691, 0.267727 } },
{ "indoor_night2_266", { 0.682997, 0.682918, 0.259109 } },
{ "indoor_night2_267", { 0.683111, 0.682862, 0.258957 } },
{ "indoor_night2_273", { 0.677695, 0.685661, 0.265705 } },
{ "indoor_night2_274", { 0.679234, 0.684392, 0.265045 } },
{ "indoor_night2_275", { 0.678753, 0.685005, 0.264692 } },
{ "indoor_night2_282", { 0.682420, 0.682987, 0.260444 } },
{ "indoor_night2_283", { 0.682485, 0.683008, 0.260221 } },
{ "indoor_night2_284", { 0.682582, 0.683005, 0.259972 } },
{ "indoor_night2_285", { 0.681762, 0.683480, 0.260875 } },
{ "outdoor_5pm_31", { 0.443348, 0.676545, 0.587987 } },
{ "outdoor_5pm_32", { 0.447206, 0.677253, 0.584239 } },
{ "outdoor_5pm_33", { 0.477468, 0.688802, 0.545505 } },
{ "outdoor_5pm_36", { 0.436017, 0.675291, 0.594870 } },
{ "outdoor_5pm_37", { 0.434859, 0.674683, 0.596406 } },
{ "outdoor_5pm_38", { 0.434328, 0.674685, 0.596790 } },
{ "outdoor_5pm_39", { 0.456344, 0.686802, 0.565733 } },
{ "outdoor_5pm_40", { 0.471267, 0.696880, 0.540616 } },
{ "outdoor_5pm_41", { 0.438494, 0.677193, 0.590874 } },
{ "outdoor_5pm_42", { 0.434285, 0.674461, 0.597076 } },
{ "outdoor_5pm_43", { 0.437337, 0.675694, 0.593443 } },
{ "outdoor_5pm_44", { 0.436417, 0.675307, 0.594560 } },
{ "outdoor_5pm_45", { 0.448194, 0.682113, 0.577791 } },
{ "outdoor_5pm_49", { 0.431477, 0.674222, 0.599376 } },
{ "outdoor_5pm_50", { 0.494896, 0.717033, 0.490859 } },
{ "outdoor_5pm_51", { 0.481760, 0.710237, 0.513293 } },
{ "outdoor_5pm_52", { 0.480411, 0.711769, 0.512436 } },
{ "outdoor_5pm_53", { 0.480956, 0.713381, 0.509675 } },
{ "outdoor_5pm_54", { 0.482725, 0.710443, 0.512101 } },
{ "outdoor_5pm_55", { 0.482684, 0.710369, 0.512243 } },
{ "outdoor_5pm_56", { 0.483071, 0.710754, 0.511342 } },
{ "outdoor_5pm_73", { 0.508742, 0.717732, 0.475440 } },
{ "outdoor_5pm_74", { 0.509389, 0.717918, 0.474465 } },
{ "outdoor_5pm_75", { 0.509150, 0.717632, 0.475153 } },
{ "outdoor_5pm_76", { 0.507235, 0.717320, 0.477666 } },
{ "outdoor_5pm_77", { 0.508245, 0.717632, 0.476122 } },
{ "outdoor_5pm_78", { 0.507895, 0.717289, 0.477010 } },
{ "outdoor_5pm_80", { 0.499771, 0.715136, 0.488681 } },
{ "outdoor_5pm_99", { 0.456573, 0.703358, 0.544819 } },
{ "outdoor_5pm_100", { 0.458058, 0.703706, 0.543122 } },
{ "outdoor_5pm_101", { 0.465212, 0.704589, 0.535846 } },
{ "outdoor_5pm_102", { 0.456315, 0.703335, 0.545065 } },
{ "outdoor_5pm_103", { 0.456406, 0.703358, 0.544959 } },
{ "outdoor_5pm_104", { 0.455428, 0.703262, 0.545901 } },
{ "outdoor_5pm_105", { 0.457122, 0.703480, 0.544201 } },
{ "outdoor_5pm_106", { 0.454431, 0.703108, 0.546930 } },
{ "outdoor_5pm_107", { 0.457901, 0.703618, 0.543368 } },
{ "outdoor_5pm_125", { 0.443126, 0.697675, 0.562929 } },
{ "outdoor_5pm_126", { 0.452248, 0.702480, 0.549540 } },
{ "outdoor_5pm_127", { 0.448658, 0.700685, 0.554749 } },
{ "outdoor_5pm_128", { 0.420499, 0.686568, 0.593132 } },
{ "outdoor_5pm_129", { 0.419209, 0.685547, 0.595222 } },
{ "outdoor_5pm_130", { 0.416372, 0.684327, 0.598607 } },
{ "outdoor_5pm_131", { 0.414865, 0.682887, 0.601293 } },
{ "outdoor_5pm_132", { 0.414866, 0.682582, 0.601638 } },
{ "outdoor_5pm_133", { 0.415271, 0.682381, 0.601587 } },
{ "outdoor_5pm_134", { 0.414591, 0.682589, 0.601820 } },
{ "outdoor_5pm_144", { 0.478351, 0.716492, 0.507760 } },
{ "outdoor_5pm_145", { 0.484239, 0.717512, 0.500689 } },
{ "outdoor_5pm_146", { 0.485704, 0.717492, 0.499296 } },
{ "outdoor_5pm_147", { 0.487457, 0.717609, 0.497416 } },
{ "outdoor_5pm_148", { 0.487661, 0.717793, 0.496952 } },
{ "outdoor_5pm_149", { 0.482145, 0.717092, 0.503304 } },
{ "outdoor_5pm_150", { 0.480630, 0.717195, 0.504606 } },
{ "outdoor_5pm_151", { 0.480672, 0.717241, 0.504499 } },
{ "outdoor_5pm_152", { 0.478836, 0.716926, 0.506688 } },
{ "outdoor_5pm_153", { 0.479453, 0.716909, 0.506129 } },
{ "outdoor_5pm_169", { 0.420303, 0.672095, 0.609617 } },
{ "outdoor_5pm_170", { 0.417537, 0.670473, 0.613294 } },
{ "outdoor_5pm_171", { 0.419330, 0.671006, 0.611484 } },
{ "outdoor_5pm_172", { 0.414475, 0.669666, 0.616245 } },
{ "outdoor_5pm_173", { 0.417791, 0.670595, 0.612987 } },
{ "outdoor_5pm_174", { 0.416750, 0.670310, 0.614006 } },
{ "outdoor_5pm_175", { 0.417646, 0.670611, 0.613069 } },
{ "outdoor_5pm_176", { 0.417877, 0.670925, 0.612567 } },
};
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
        auto lock = std::unique_lock(_streamImages.lock);
        Mmap imgData(_TagDir/imgFilename);
        
        _streamImages.img.width = 2304;
        _streamImages.img.height = 1296;
        
        const size_t len = _streamImages.img.width*_streamImages.img.height*sizeof(*_streamImages.img.pixels);
        // Verify that the size of the file matches the the width/height of the image
        assert(imgData.len() == len);
        // Verify that our buffer is large enough to fit `len` bytes
        assert(sizeof(_streamImages.pixelBuf) >= len);
        memcpy(_streamImages.pixelBuf, imgData.data(), len);
        [[_mainView imageLayer] setImage:_streamImages.img];
    }
    
    const Color<ColorSpace::Raw>& c = illum.c;
    _imgOpts.whiteBalance = { c[1]/c[0], c[1]/c[1], c[1]/c[2] };
    [self _updateImageOptions];
    
    [_mainView reset];
}

- (void)_tagHandleSampleRectChanged {
    return;
    [[_mainView imageLayer] display]; // Crappiness to force the sample to be updated
    
    const Color<ColorSpace::Raw> c = [[_mainView imageLayer] sampleRaw];
    _imgOpts.whiteBalance = { c[1]/c[0], c[1]/c[1], c[1]/c[2] };
    [self _updateImageOptions];
    
//    if (_TagCurrentIllum != _TagIllums.end()) {
//        Illum& illum = (*_TagCurrentIllum);
//        illum.c = c;
//        [self _tagNextImage:nil];
//    }
}

@end

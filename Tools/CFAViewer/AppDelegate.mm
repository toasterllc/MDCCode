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
        
        STApp::Pixel pixelBuf[2000*2000];
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
        
        Mmap imgData("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-Indoor-Night/indoor_night_176.cfa");
        
//        _streamImages.img.width = 384;
//        _streamImages.img.height = 256;
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
        
        .whiteBalance = { 1.368683, 1.000000, 1.513193 },
        
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

static Mat<double,3,1> _whiteBalanceMatrixFromString(const std::string& str) {
    const std::regex floatRegex("[-+]?[0-9]*\\.?[0-9]+");
    auto begin = std::sregex_iterator(str.begin(), str.end(), floatRegex);
    auto end = std::sregex_iterator();
    std::vector<double> vals;
    
    for (std::sregex_iterator i=begin; i!=end; i++) {
        vals.push_back(std::stod(i->str()));
    }
    
    if (vals.size() != 3) {
        NSLog(@"Failed to parse color matrix");
        return {};
    }
    
    return vals.data();
}

static Mat<double,3,3> _colorMatrixFromString(const std::string& str) {
    const std::regex floatRegex("[-+]?[0-9]*\\.?[0-9]+");
    auto begin = std::sregex_iterator(str.begin(), str.end(), floatRegex);
    auto end = std::sregex_iterator();
    std::vector<double> vals;
    
    for (std::sregex_iterator i=begin; i!=end; i++) {
        vals.push_back(std::stod(i->str()));
    }
    
    if (vals.size() != 9) {
        NSLog(@"Failed to parse color matrix");
        return {};
    }
    
    return vals.data();
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

static const fs::path _TagDir("/Users/dave/Desktop/Old/2021:3:31/CFAViewerSession-All-FilteredGood");
Illums _TagIllums = {
{ "indoor_night_3", { 0.380482, 0.366261, 0.129353 } },
{ "indoor_night_4", { 0.377407, 0.362345, 0.127849 } },
{ "indoor_night_5", { 0.372972, 0.356812, 0.125556 } },
{ "indoor_night_6", { 0.406046, 0.393773, 0.139295 } },
{ "indoor_night_7", { 0.405238, 0.386366, 0.136330 } },
{ "indoor_night_8", { 0.405642, 0.390472, 0.137368 } },
{ "indoor_night_15", { 0.373599, 0.356569, 0.129842 } },
{ "indoor_night_16", { 0.366279, 0.348220, 0.127408 } },
{ "indoor_night_17", { 0.357394, 0.339872, 0.123713 } },
{ "indoor_night_18", { 0.353458, 0.338337, 0.124003 } },
{ "indoor_night_19", { 0.355630, 0.340546, 0.124579 } },
{ "indoor_night_20", { 0.340742, 0.331656, 0.121639 } },
{ "indoor_night_24", { 0.483282, 0.456142, 0.161159 } },
{ "indoor_night_25", { 0.482208, 0.460768, 0.162238 } },
{ "indoor_night_26", { 0.476491, 0.455756, 0.160079 } },
{ "indoor_night_27", { 0.450202, 0.437512, 0.151763 } },
{ "indoor_night_28", { 0.521223, 0.477798, 0.160000 } },
{ "indoor_night_34", { 0.464009, 0.428040, 0.146924 } },
{ "indoor_night_35", { 0.463150, 0.425174, 0.144418 } },
{ "indoor_night_36", { 0.462743, 0.425344, 0.144572 } },
{ "indoor_night_37", { 0.467864, 0.431844, 0.146748 } },
{ "indoor_night_38", { 0.463973, 0.425006, 0.143750 } },
{ "indoor_night_39", { 0.466138, 0.428006, 0.145518 } },
{ "indoor_night_40", { 0.467231, 0.427687, 0.144837 } },
{ "indoor_night_41", { 0.464106, 0.426569, 0.145059 } },
{ "indoor_night_42", { 0.465360, 0.427366, 0.145307 } },
{ "indoor_night_43", { 0.462328, 0.424752, 0.144287 } },
{ "indoor_night_44", { 0.462654, 0.423542, 0.143553 } },
{ "indoor_night_45", { 0.463282, 0.424998, 0.144134 } },
{ "indoor_night_46", { 0.462867, 0.423546, 0.143656 } },
{ "indoor_night_47", { 0.464669, 0.426104, 0.145256 } },
{ "indoor_night_48", { 0.463805, 0.426471, 0.145929 } },
{ "indoor_night_49", { 0.463487, 0.425369, 0.144767 } },
{ "indoor_night_50", { 0.559829, 0.515578, 0.175517 } },
{ "indoor_night_51", { 0.551134, 0.506483, 0.172965 } },
{ "indoor_night_54", { 0.249225, 0.255533, 0.100095 } },
{ "indoor_night_55", { 0.254369, 0.264585, 0.100866 } },
{ "indoor_night_56", { 0.267075, 0.273361, 0.105882 } },
{ "indoor_night_57", { 0.265991, 0.272737, 0.106713 } },
{ "indoor_night_60", { 0.324077, 0.329768, 0.127658 } },
{ "indoor_night_61", { 0.232844, 0.237822, 0.092432 } },
{ "indoor_night_62", { 0.234765, 0.239128, 0.092789 } },
{ "indoor_night_63", { 0.283030, 0.288403, 0.112175 } },
{ "indoor_night_64", { 0.291632, 0.298091, 0.115346 } },
{ "indoor_night_65", { 0.291854, 0.297241, 0.115458 } },
{ "indoor_night_66", { 0.291318, 0.297504, 0.115206 } },
{ "indoor_night_67", { 0.290813, 0.296416, 0.114892 } },
{ "indoor_night_68", { 0.291583, 0.297849, 0.115354 } },
{ "indoor_night_69", { 0.290654, 0.296623, 0.114920 } },
{ "indoor_night_72", { 0.461352, 0.480897, 0.186726 } },
{ "indoor_night_74", { 0.443778, 0.451178, 0.174645 } },
{ "indoor_night_75", { 0.438104, 0.446480, 0.172628 } },
{ "indoor_night_76", { 0.436450, 0.445855, 0.172627 } },
{ "indoor_night_77", { 0.435171, 0.444850, 0.172547 } },
{ "indoor_night_78", { 0.352286, 0.360221, 0.141264 } },
{ "indoor_night_79", { 0.319594, 0.329162, 0.129272 } },
{ "indoor_night_80", { 0.292221, 0.302181, 0.118589 } },
{ "indoor_night_81", { 0.453167, 0.462518, 0.179672 } },
{ "indoor_night_82", { 0.425257, 0.435275, 0.169542 } },
{ "indoor_night_83", { 0.426134, 0.433778, 0.168450 } },
{ "indoor_night_84", { 0.441802, 0.451676, 0.175603 } },
{ "indoor_night_85", { 0.443802, 0.453274, 0.176658 } },
{ "indoor_night_86", { 0.435485, 0.441852, 0.171101 } },
{ "indoor_night_87", { 0.442199, 0.449309, 0.173651 } },
{ "indoor_night_88", { 0.445996, 0.454694, 0.176740 } },
{ "indoor_night_89", { 0.439275, 0.447783, 0.174002 } },
{ "indoor_night_99", { 0.547442, 0.567520, 0.220017 } },
{ "indoor_night_100", { 0.682431, 0.709175, 0.275643 } },
{ "indoor_night_103", { 0.549427, 0.573518, 0.221829 } },
{ "indoor_night_104", { 0.522829, 0.543142, 0.210725 } },
{ "indoor_night_105", { 0.525296, 0.544726, 0.211284 } },
{ "indoor_night_106", { 0.519408, 0.538001, 0.208129 } },
{ "indoor_night_107", { 0.523858, 0.542648, 0.210586 } },
{ "indoor_night_108", { 0.531004, 0.548322, 0.212136 } },
{ "indoor_night_109", { 0.522947, 0.538619, 0.207674 } },
{ "indoor_night_110", { 0.528153, 0.547532, 0.211591 } },
{ "indoor_night_111", { 0.534843, 0.551509, 0.212821 } },
{ "indoor_night_117", { 0.532374, 0.554740, 0.214139 } },
{ "indoor_night_121", { 0.425150, 0.414387, 0.151519 } },
{ "indoor_night_122", { 0.420802, 0.409142, 0.149317 } },
{ "indoor_night_123", { 0.411973, 0.401241, 0.146959 } },
{ "indoor_night_124", { 0.423314, 0.413005, 0.151615 } },
{ "indoor_night_125", { 0.490281, 0.489578, 0.183781 } },
{ "indoor_night_128", { 0.432966, 0.440053, 0.166063 } },
{ "indoor_night_133", { 0.290831, 0.309443, 0.116568 } },
{ "indoor_night_136", { 0.277101, 0.278965, 0.103195 } },
{ "indoor_night_139", { 0.251138, 0.262207, 0.097750 } },
{ "indoor_night_148", { 0.501063, 0.503858, 0.196149 } },
{ "indoor_night_150", { 0.492527, 0.498152, 0.195502 } },
{ "indoor_night_151", { 0.492207, 0.500367, 0.196279 } },
{ "indoor_night_157", { 0.493078, 0.486733, 0.186666 } },
{ "indoor_night_158", { 0.497255, 0.491368, 0.188727 } },
{ "indoor_night_159", { 0.497255, 0.491368, 0.188727 } },
{ "indoor_night_160", { 0.543736, 0.545134, 0.210541 } },
{ "indoor_night_161", { 0.426004, 0.423734, 0.163323 } },
{ "indoor_night_162", { 0.595708, 0.591358, 0.227932 } },
{ "indoor_night_163", { 0.595708, 0.591358, 0.227932 } },
{ "indoor_night_166", { 0.595708, 0.591358, 0.227932 } },
{ "indoor_night_168", { 0.552471, 0.550417, 0.213573 } },
{ "indoor_night_169", { 0.467930, 0.462000, 0.179943 } },
{ "indoor_night_170", { 0.567985, 0.556150, 0.203060 } },
{ "indoor_night_171", { 0.553533, 0.540725, 0.195459 } },
{ "indoor_night_172", { 0.534608, 0.518083, 0.187468 } },
{ "indoor_night_173", { 0.540613, 0.526215, 0.191046 } },
{ "indoor_night_174", { 0.525793, 0.509873, 0.184155 } },
{ "indoor_night_175", { 0.520082, 0.502432, 0.181543 } },
{ "indoor_night_176", { 0.537492, 0.521349, 0.188924 } },
{ "outdoor_4pm_2", { 0.042360, 0.062211, 0.034440 } },
{ "outdoor_4pm_3", { 0.120491, 0.177537, 0.097266 } },
{ "outdoor_4pm_4", { 0.121344, 0.174582, 0.092200 } },
{ "outdoor_4pm_5", { 0.132477, 0.191530, 0.101956 } },
{ "outdoor_4pm_6", { 0.133871, 0.193909, 0.103077 } },
{ "outdoor_4pm_17", { 0.128891, 0.185024, 0.098874 } },
{ "outdoor_4pm_18", { 0.058852, 0.082527, 0.043862 } },
{ "outdoor_4pm_19", { 0.096358, 0.135740, 0.071994 } },
{ "outdoor_4pm_20", { 0.139900, 0.198851, 0.105003 } },
{ "outdoor_4pm_21", { 0.247890, 0.392221, 0.223949 } },
{ "outdoor_4pm_23", { 0.389095, 0.594901, 0.326451 } },
{ "outdoor_4pm_25", { 0.031097, 0.043442, 0.024822 } },
{ "outdoor_4pm_26", { 0.260585, 0.364761, 0.202295 } },
{ "outdoor_4pm_27", { 0.659870, 0.964086, 0.608618 } },
{ "outdoor_4pm_28", { 0.055855, 0.075400, 0.052433 } },
{ "outdoor_4pm_29", { 0.736134, 0.995992, 0.633875 } },
{ "outdoor_4pm_30", { 0.035524, 0.051289, 0.035311 } },
{ "outdoor_4pm_31", { 0.033343, 0.046512, 0.032045 } },
{ "outdoor_4pm_32", { 0.037327, 0.052722, 0.036039 } },
{ "outdoor_4pm_33", { 0.107895, 0.157571, 0.106146 } },
{ "outdoor_4pm_34", { 0.095450, 0.140822, 0.096201 } },
{ "outdoor_4pm_35", { 0.096402, 0.141046, 0.095521 } },
{ "outdoor_4pm_36", { 0.648962, 0.974746, 0.638457 } },
{ "outdoor_4pm_37", { 0.047992, 0.071155, 0.052365 } },
{ "outdoor_4pm_38", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_39", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_40", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_41", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_42", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_43", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_44", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_45", { 0.120012, 0.176429, 0.146046 } },
{ "outdoor_4pm_46", { 0.147932, 0.217469, 0.177970 } },
{ "outdoor_4pm_47", { 0.147141, 0.216186, 0.178970 } },
{ "outdoor_4pm_48", { 0.149804, 0.220839, 0.183996 } },
{ "outdoor_4pm_51", { 0.092874, 0.138167, 0.116158 } },
{ "outdoor_4pm_52", { 0.092168, 0.137818, 0.115463 } },
{ "outdoor_4pm_53", { 0.157178, 0.232458, 0.194244 } },
{ "outdoor_4pm_54", { 0.111211, 0.163109, 0.138980 } },
{ "outdoor_4pm_55", { 0.101046, 0.150565, 0.128069 } },
{ "outdoor_4pm_56", { 0.076198, 0.114818, 0.097393 } },
{ "outdoor_4pm_57", { 0.083597, 0.124300, 0.104115 } },
{ "outdoor_4pm_58", { 0.142748, 0.214621, 0.180946 } },
{ "outdoor_4pm_59", { 0.139964, 0.212963, 0.180066 } },
{ "outdoor_4pm_60", { 0.140549, 0.212529, 0.179726 } },
{ "outdoor_4pm_61", { 0.140549, 0.212529, 0.179726 } },
{ "outdoor_4pm_62", { 0.140549, 0.212529, 0.179726 } },
{ "outdoor_4pm_63", { 0.140549, 0.212529, 0.179726 } },
{ "outdoor_4pm_64", { 0.622680, 0.929768, 0.602896 } },
{ "outdoor_4pm_65", { 0.660099, 0.978301, 0.634539 } },
{ "outdoor_4pm_66", { 0.098227, 0.143445, 0.097218 } },
{ "outdoor_4pm_67", { 0.107873, 0.155537, 0.106114 } },
{ "outdoor_4pm_68", { 0.114629, 0.165346, 0.112192 } },
{ "outdoor_4pm_69", { 0.132479, 0.196581, 0.137124 } },
{ "outdoor_4pm_70", { 0.108103, 0.157901, 0.108048 } },
{ "outdoor_4pm_71", { 0.104979, 0.152474, 0.105371 } },
{ "outdoor_4pm_72", { 0.098720, 0.144574, 0.091740 } },
{ "outdoor_4pm_73", { 0.034401, 0.049074, 0.034145 } },
{ "outdoor_4pm_74", { 0.030310, 0.042694, 0.029361 } },
{ "outdoor_4pm_75", { 0.126685, 0.191643, 0.145526 } },
{ "outdoor_4pm_76", { 0.102484, 0.144470, 0.098078 } },
{ "outdoor_4pm_77", { 0.137711, 0.181251, 0.115792 } },
{ "outdoor_4pm_78", { 0.085904, 0.113755, 0.073241 } },
{ "outdoor_4pm_79", { 0.066411, 0.091966, 0.062189 } },
{ "outdoor_4pm_80", { 0.123106, 0.177233, 0.143846 } },
{ "outdoor_4pm_81", { 0.122226, 0.175238, 0.145014 } },
{ "outdoor_4pm_82", { 0.107083, 0.154593, 0.128090 } },
{ "outdoor_4pm_83", { 0.145559, 0.210117, 0.173766 } },
{ "outdoor_4pm_84", { 0.142718, 0.207455, 0.172555 } },
{ "outdoor_4pm_85", { 0.143144, 0.191296, 0.122123 } },
{ "outdoor_4pm_86", { 0.155881, 0.209519, 0.135420 } },
{ "outdoor_4pm_87", { 0.133062, 0.185944, 0.122599 } },
{ "outdoor_4pm_88", { 0.095115, 0.143041, 0.108107 } },
{ "outdoor_4pm_89", { 0.124045, 0.186658, 0.139889 } },
{ "outdoor_4pm_90", { 0.135433, 0.204611, 0.156392 } },
{ "outdoor_4pm_91", { 0.119827, 0.174365, 0.151262 } },
{ "outdoor_4pm_92", { 0.192211, 0.284044, 0.250817 } },
{ "outdoor_4pm_93", { 0.192238, 0.279956, 0.242315 } },
{ "outdoor_4pm_94", { 0.192238, 0.279956, 0.242315 } },
{ "outdoor_4pm_95", { 0.153399, 0.234414, 0.181124 } },
{ "outdoor_4pm_96", { 0.125023, 0.200493, 0.160287 } },
{ "outdoor_4pm_97", { 0.082538, 0.122147, 0.090554 } },
{ "outdoor_4pm_98", { 0.104969, 0.161247, 0.121503 } },
{ "outdoor_4pm_99", { 0.101380, 0.151638, 0.116321 } },
{ "outdoor_4pm_100", { 0.102454, 0.145100, 0.107458 } },
{ "outdoor_4pm_101", { 0.101139, 0.148762, 0.105948 } },
{ "outdoor_4pm_102", { 0.109534, 0.157546, 0.122846 } },
{ "outdoor_4pm_103", { 0.109290, 0.154428, 0.119448 } },
{ "outdoor_4pm_104", { 0.101530, 0.146496, 0.117848 } },
{ "outdoor_4pm_105", { 0.083790, 0.126273, 0.103686 } },
{ "outdoor_4pm_106", { 0.129124, 0.186447, 0.145936 } },
{ "outdoor_4pm_107", { 0.123807, 0.172430, 0.134786 } },
{ "outdoor_4pm_108", { 0.140224, 0.203122, 0.152226 } },
{ "outdoor_4pm_109", { 0.116235, 0.171746, 0.135937 } },
{ "outdoor_4pm_110", { 0.122557, 0.194297, 0.158908 } },
{ "outdoor_4pm_111", { 0.189584, 0.300317, 0.239288 } },
{ "outdoor_4pm_112", { 0.347926, 0.539171, 0.406044 } },
{ "outdoor_4pm_113", { 0.173320, 0.266318, 0.206957 } },
{ "outdoor_4pm_114", { 0.155087, 0.243831, 0.222944 } },
{ "outdoor_4pm_115", { 0.228697, 0.357878, 0.327689 } },
{ "outdoor_4pm_116", { 0.091078, 0.144743, 0.135892 } },
{ "outdoor_4pm_117", { 0.074171, 0.116819, 0.108913 } },
{ "outdoor_4pm_118", { 0.114415, 0.178859, 0.165187 } },
{ "outdoor_4pm_119", { 0.166693, 0.271068, 0.257576 } },
{ "outdoor_4pm_120", { 0.140407, 0.231213, 0.221127 } },
{ "outdoor_4pm_121", { 0.157938, 0.251222, 0.234728 } },
{ "outdoor_4pm_122", { 0.163813, 0.258367, 0.241199 } },
{ "outdoor_4pm_123", { 0.207999, 0.336963, 0.313433 } },
{ "outdoor_4pm_124", { 0.086819, 0.132182, 0.098828 } },
{ "outdoor_4pm_125", { 0.093971, 0.151410, 0.145574 } },
{ "outdoor_4pm_126", { 0.073022, 0.117547, 0.094126 } },
{ "outdoor_4pm_127", { 0.106694, 0.154102, 0.121668 } },
{ "outdoor_4pm_128", { 0.106694, 0.154102, 0.121668 } },
{ "outdoor_4pm_129", { 0.106694, 0.154102, 0.121668 } },
{ "outdoor_4pm_130", { 0.106694, 0.154102, 0.121668 } },
{ "outdoor_4pm_131", { 0.195729, 0.291888, 0.262430 } },
{ "outdoor_4pm_132", { 0.106694, 0.154102, 0.121668 } },
{ "outdoor_4pm_133", { 0.091186, 0.133438, 0.105920 } },
{ "outdoor_4pm_134", { 0.116943, 0.174582, 0.138319 } },
{ "outdoor_4pm_135", { 0.101478, 0.151370, 0.120220 } },
{ "outdoor_4pm_136", { 0.109093, 0.161130, 0.129363 } },
{ "outdoor_4pm_137", { 0.104071, 0.155733, 0.125774 } },
{ "outdoor_4pm_138", { 0.073409, 0.107568, 0.080313 } },
{ "outdoor_4pm_139", { 0.055216, 0.084833, 0.064265 } },
{ "outdoor_4pm_140", { 0.050954, 0.074038, 0.058650 } },
{ "outdoor_4pm_141", { 0.064608, 0.098576, 0.079275 } },
{ "outdoor_4pm_142", { 0.514635, 0.756718, 0.499451 } },
{ "outdoor_4pm_143", { 0.232503, 0.333762, 0.220601 } },
{ "outdoor_4pm_144", { 0.132643, 0.190474, 0.121939 } },
{ "outdoor_4pm_146", { 0.090029, 0.119234, 0.076473 } },
{ "outdoor_4pm_147", { 0.112149, 0.153875, 0.098339 } },
{ "outdoor_4pm_148", { 0.105970, 0.140931, 0.093501 } },
{ "outdoor_4pm_149", { 0.087125, 0.121808, 0.083221 } },
{ "outdoor_4pm_150", { 0.087125, 0.121808, 0.083221 } },
{ "outdoor_4pm_151", { 0.087125, 0.121808, 0.083221 } },
{ "outdoor_4pm_152", { 0.087125, 0.121808, 0.083221 } },
{ "outdoor_4pm_159", { 0.162760, 0.240864, 0.165864 } },
{ "outdoor_4pm_160", { 0.127837, 0.178292, 0.109951 } },
{ "outdoor_4pm_163", { 0.708461, 0.968162, 0.595619 } },
{ "outdoor_4pm_164", { 0.278158, 0.432118, 0.361639 } },
{ "outdoor_4pm_165", { 0.141777, 0.201442, 0.110435 } },
{ "outdoor_4pm_166", { 0.222925, 0.335816, 0.190125 } },
{ "outdoor_4pm_167", { 0.029855, 0.043563, 0.024618 } },
{ "outdoor_4pm_168", { 0.029305, 0.042990, 0.024360 } },
{ "outdoor_4pm_172", { 0.079455, 0.115293, 0.063255 } },
{ "outdoor_noon_3", { 0.027231, 0.039633, 0.023516 } },
{ "outdoor_noon_4", { 0.033082, 0.048389, 0.028379 } },
{ "outdoor_noon_6", { 0.013280, 0.018494, 0.011194 } },
{ "outdoor_noon_7", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_8", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_9", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_10", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_11", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_12", { 0.154921, 0.235527, 0.163757 } },
{ "outdoor_noon_15", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_16", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_17", { 0.419767, 0.619566, 0.411731 } },
{ "outdoor_noon_18", { 0.467714, 0.720486, 0.503037 } },
{ "outdoor_noon_19", { 0.112389, 0.160974, 0.102160 } },
{ "outdoor_noon_20", { 0.156235, 0.222183, 0.156396 } },
{ "outdoor_noon_21", { 0.176246, 0.252631, 0.176493 } },
{ "outdoor_noon_22", { 0.164465, 0.232531, 0.159837 } },
{ "outdoor_noon_23", { 0.150755, 0.216820, 0.148168 } },
{ "outdoor_noon_24", { 0.125988, 0.181539, 0.118049 } },
{ "outdoor_noon_25", { 0.119394, 0.177898, 0.124897 } },
{ "outdoor_noon_26", { 0.136091, 0.202204, 0.142553 } },
{ "outdoor_noon_27", { 0.137618, 0.200071, 0.142203 } },
{ "outdoor_noon_28", { 0.182597, 0.261136, 0.189173 } },
{ "outdoor_noon_29", { 0.148177, 0.209747, 0.145386 } },
{ "outdoor_noon_30", { 0.150822, 0.220662, 0.159663 } },
{ "outdoor_noon_31", { 0.157217, 0.225864, 0.160144 } },
{ "outdoor_noon_32", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_33", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_34", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_35", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_36", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_37", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_38", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_39", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_40", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_41", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_42", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_43", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_44", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_45", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_46", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_47", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_48", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_49", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_50", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_51", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_52", { 0.156836, 0.226405, 0.160246 } },
{ "outdoor_noon_53", { 0.112062, 0.152216, 0.097179 } },
{ "outdoor_noon_54", { 0.087319, 0.118849, 0.078519 } },
{ "outdoor_noon_55", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_56", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_57", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_58", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_59", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_60", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_61", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_62", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_63", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_64", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_65", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_66", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_67", { 0.122677, 0.172449, 0.119451 } },
{ "outdoor_noon_68", { 0.165643, 0.243714, 0.175010 } },
{ "outdoor_noon_69", { 0.166880, 0.244945, 0.174807 } },
{ "outdoor_noon_70", { 0.166880, 0.244945, 0.174807 } },
{ "outdoor_noon_71", { 0.166880, 0.244945, 0.174807 } },
{ "outdoor_noon_72", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_73", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_74", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_75", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_76", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_77", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_78", { 0.161972, 0.243104, 0.167404 } },
{ "outdoor_noon_79", { 0.612809, 0.906972, 0.602791 } },
{ "outdoor_noon_80", { 0.612809, 0.906972, 0.602791 } },
{ "outdoor_noon_81", { 0.612809, 0.906972, 0.602791 } },
{ "outdoor_noon_82", { 0.612809, 0.906972, 0.602791 } },
{ "outdoor_noon_83", { 0.612809, 0.906972, 0.602791 } },
{ "outdoor_noon_84", { 0.633466, 0.907991, 0.595273 } },
{ "outdoor_noon_85", { 0.633466, 0.907991, 0.595273 } },
{ "outdoor_noon_86", { 0.633466, 0.907991, 0.595273 } },
{ "outdoor_noon_87", { 0.499277, 0.729857, 0.486494 } },
{ "outdoor_noon_88", { 0.440236, 0.635263, 0.421097 } },
{ "outdoor_noon_89", { 0.594042, 0.829404, 0.529120 } },
{ "outdoor_noon_90", { 0.606526, 0.823642, 0.507726 } },
{ "outdoor_noon_91", { 0.075341, 0.114312, 0.088975 } },
{ "outdoor_noon_92", { 0.584765, 0.783299, 0.482385 } },
{ "outdoor_noon_93", { 0.577775, 0.781411, 0.483668 } },
{ "outdoor_noon_94", { 0.074267, 0.114724, 0.091091 } },
{ "outdoor_noon_95", { 0.143353, 0.214351, 0.164250 } },
{ "outdoor_noon_96", { 0.207513, 0.312340, 0.234246 } },
{ "outdoor_noon_97", { 0.161436, 0.246447, 0.181947 } },
{ "outdoor_noon_98", { 0.175672, 0.264967, 0.190991 } },
{ "outdoor_noon_99", { 0.185705, 0.272140, 0.190584 } },
{ "outdoor_noon_100", { 0.187647, 0.275929, 0.196062 } },
{ "outdoor_noon_101", { 0.168087, 0.256443, 0.188336 } },
{ "outdoor_noon_102", { 0.428382, 0.613412, 0.409578 } },
{ "outdoor_noon_103", { 0.363926, 0.543708, 0.361458 } },
{ "outdoor_noon_104", { 0.063492, 0.092494, 0.065032 } },
{ "outdoor_noon_105", { 0.081494, 0.124874, 0.088687 } },
{ "outdoor_noon_106", { 0.090065, 0.133687, 0.094016 } },
{ "outdoor_noon_107", { 0.097366, 0.145432, 0.106127 } },
{ "outdoor_noon_108", { 0.061097, 0.091871, 0.063250 } },
{ "outdoor_noon_109", { 0.062331, 0.090006, 0.062652 } },
{ "outdoor_noon_110", { 0.106683, 0.148715, 0.098626 } },
{ "outdoor_noon_111", { 0.079441, 0.117982, 0.082400 } },
{ "outdoor_noon_112", { 0.102314, 0.124218, 0.074028 } },
{ "outdoor_noon_113", { 0.101611, 0.124418, 0.074140 } },
{ "outdoor_noon_114", { 0.154313, 0.190420, 0.108968 } },
{ "outdoor_noon_115", { 0.158026, 0.197589, 0.112695 } },
{ "outdoor_noon_116", { 0.149182, 0.184838, 0.103126 } },
{ "outdoor_noon_117", { 0.139560, 0.172122, 0.096207 } },
{ "outdoor_noon_118", { 0.155271, 0.190714, 0.106047 } },
{ "outdoor_noon_119", { 0.156275, 0.191414, 0.106012 } },
{ "outdoor_noon_120", { 0.179101, 0.222223, 0.129712 } },
{ "outdoor_noon_121", { 0.137000, 0.170401, 0.100393 } },
{ "outdoor_noon_122", { 0.107576, 0.132261, 0.074207 } },
{ "outdoor_noon_129", { 0.071323, 0.111709, 0.078974 } },
{ "outdoor_noon_130", { 0.130987, 0.198411, 0.140600 } },
{ "outdoor_noon_131", { 0.124569, 0.189248, 0.137314 } },
{ "outdoor_noon_132", { 0.200221, 0.281540, 0.186400 } },
{ "outdoor_noon_133", { 0.152149, 0.211982, 0.141575 } },
{ "outdoor_noon_134", { 0.572727, 0.782703, 0.486760 } },
{ "outdoor_noon_135", { 0.581970, 0.787794, 0.490492 } },
{ "outdoor_noon_136", { 0.586616, 0.816505, 0.515329 } },
{ "outdoor_noon_137", { 0.210969, 0.300175, 0.196371 } },
{ "outdoor_noon_138", { 0.210969, 0.300175, 0.196371 } },
{ "outdoor_noon_139", { 0.210969, 0.300175, 0.196371 } },
{ "outdoor_noon_140", { 0.210969, 0.300175, 0.196371 } },
{ "outdoor_noon_142", { 0.681516, 0.998384, 0.668580 } },
{ "outdoor_noon_145", { 0.681516, 0.998384, 0.668580 } },
{ "outdoor_noon_146", { 0.681516, 0.998384, 0.668580 } },
{ "outdoor_noon_148", { 0.130513, 0.193887, 0.114233 } },
{ "outdoor_noon_150", { 0.035378, 0.052507, 0.031350 } },
{ "outdoor_noon_151", { 0.126020, 0.186059, 0.104322 } },
{ "outdoor_noon_152", { 0.212740, 0.321649, 0.184655 } },
{ "outdoor_noon_153", { 0.182893, 0.269394, 0.150715 } },
{ "outdoor_noon_155", { 0.163244, 0.237969, 0.136024 } },
{ "outdoor_noon_156", { 0.116762, 0.170011, 0.102972 } },
{ "outdoor_noon_157", { 0.167207, 0.240460, 0.146085 } },
{ "outdoor_noon_158", { 0.093827, 0.139326, 0.078799 } },
{ "outdoor_noon_161", { 0.064034, 0.088281, 0.046303 } },
{ "outdoor_noon_162", { 0.095283, 0.132000, 0.068269 } },
{ "outdoor_noon_164", { 0.035887, 0.051989, 0.028703 } },
{ "outdoor_noon_165", { 0.044802, 0.065807, 0.037018 } },
{ "outdoor_noon_166", { 0.069414, 0.102336, 0.057254 } },
{ "outdoor_noon_167", { 0.114953, 0.166478, 0.089680 } },
{ "outdoor_noon_177", { 0.481948, 0.636319, 0.310236 } },
{ "outdoor_noon_182", { 0.137629, 0.188032, 0.100117 } },
{ "outdoor_noon_187", { 0.044024, 0.062344, 0.034080 } },
{ "outdoor_noon_188", { 0.117393, 0.169708, 0.104430 } },
{ "outdoor_noon_189", { 0.069270, 0.100534, 0.057517 } },
};
Illums::iterator _TagCurrentIllum = _TagIllums.end();

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

- (void)_tagStartSession {
//    _TagIllums = {};
//    for (const auto& f : fs::directory_iterator(_TagDir)) {
//        if (isCFAFile(f)) {
//            auto fname = f.path().filename().replace_extension();
//            _TagIllums.push_back({fname, {}});
//        }
//    }
    
    _TagCurrentIllum = _TagIllums.begin();
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
    const Illum& illum = (*_TagCurrentIllum);
    const fs::path& imgName = illum.p;
    const fs::path imgFilename = fs::path(imgName).replace_extension(".cfa");
    std::cout << imgName.string() << "\n";
    {
        auto lock = std::unique_lock(_streamImages.lock);
        Mmap imgData(_TagDir/imgFilename);
        
    //        _streamImages.img.width = 384;
    //        _streamImages.img.height = 256;
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
    Illum& illum = (*_TagCurrentIllum);
    [[_mainView imageLayer] display]; // Crappiness to force the sample to be updated
    
    const Color<ColorSpace::Raw> c = [[_mainView imageLayer] sampleRaw];
    illum.c = c;
    
    _imgOpts.whiteBalance = { c[1]/c[0], c[1]/c[1], c[1]/c[2] };
    [self _updateImageOptions];
    
//    [self _tagNextImage:nil];
//    printf("sampleRaw: %f %f %f\n", sampleRaw[0], sampleRaw[1], sampleRaw[2]);
}

@end

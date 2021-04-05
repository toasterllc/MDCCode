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
        Mmap imgData("/Users/dave/Desktop/Old/2021:4:4/C5TestSets/Indoor-Night2-ColorChecker/indoor_night2_32.cfa");
        
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

static const fs::path _TagDir("/Users/dave/Desktop/Old/2021:4:4/C5TestSets/Indoor-Night2-ColorChecker");
Illums _TagIllums = {
{ "indoor_night2_25", { 0.6610428094863892, 0.6956881880760193, 0.2811412215232849 } },
{ "indoor_night2_26", { 0.6615281105041504, 0.6955646872520447, 0.2803042232990265 } },
{ "indoor_night2_27", { 0.6610894203186035, 0.6960588693618774, 0.28011229634284973 } },
{ "indoor_night2_28", { 0.663303017616272, 0.6948638558387756, 0.2778366506099701 } },
{ "indoor_night2_29", { 0.6622173190116882, 0.6953386664390564, 0.27923521399497986 } },
{ "indoor_night2_30", { 0.6615803241729736, 0.6958312392234802, 0.27951815724372864 } },
{ "indoor_night2_31", { 0.6605921983718872, 0.6964685320854187, 0.28026700019836426 } },
{ "indoor_night2_32", { 0.6606820821762085, 0.69637131690979, 0.2802966237068176 } },
{ "indoor_night2_41", { 0.6608990430831909, 0.6966180801391602, 0.27916961908340454 } },
{ "indoor_night2_42", { 0.6617681384086609, 0.6960736513137817, 0.2784678339958191 } },
{ "indoor_night2_43", { 0.6615067720413208, 0.6962314248085022, 0.2786942720413208 } },
{ "indoor_night2_44", { 0.6617894768714905, 0.6961191892623901, 0.27830347418785095 } },
{ "indoor_night2_46", { 0.6649115085601807, 0.6946393847465515, 0.2745336592197418 } },
{ "indoor_night2_49", { 0.6651672124862671, 0.6946261525154114, 0.27394726872444153 } },
{ "indoor_night2_53", { 0.6654446125030518, 0.6946574449539185, 0.2731931805610657 } },
{ "indoor_night2_54", { 0.6638003587722778, 0.6955618858337402, 0.27488693594932556 } },
{ "indoor_night2_55", { 0.6623727679252625, 0.6962365508079529, 0.27661702036857605 } },
{ "indoor_night2_56", { 0.6628625988960266, 0.6960951685905457, 0.2757982313632965 } },
{ "indoor_night2_57", { 0.6646910905838013, 0.6953681707382202, 0.27321937680244446 } },
{ "indoor_night2_64", { 0.6635785698890686, 0.6945860981941223, 0.27787336707115173 } },
{ "indoor_night2_65", { 0.6637321710586548, 0.6943405270576477, 0.27812016010284424 } },
{ "indoor_night2_66", { 0.6630839109420776, 0.6941995620727539, 0.28001201152801514 } },
{ "indoor_night2_67", { 0.6631548404693604, 0.694744884967804, 0.2784874439239502 } },
{ "indoor_night2_68", { 0.6630584001541138, 0.6945089101791382, 0.27930423617362976 } },
{ "indoor_night2_69", { 0.6621127724647522, 0.6938026547431946, 0.2832748591899872 } },
{ "indoor_night2_74", { 0.662424623966217, 0.6946214437484741, 0.28052571415901184 } },
{ "indoor_night2_75", { 0.6631459593772888, 0.6947492957115173, 0.27849751710891724 } },
{ "indoor_night2_76", { 0.6641885638237, 0.6940415501594543, 0.2777765393257141 } },
{ "indoor_night2_77", { 0.6622558236122131, 0.6930427551269531, 0.28479620814323425 } },
{ "indoor_night2_78", { 0.6639726161956787, 0.6936396956443787, 0.27929261326789856 } },
{ "indoor_night2_79", { 0.6619681715965271, 0.6943600177764893, 0.2822452485561371 } },
{ "indoor_night2_80", { 0.662886381149292, 0.6941688656806946, 0.28055539727211 } },
{ "indoor_night2_81", { 0.6622798442840576, 0.6942716240882874, 0.2817307114601135 } },
{ "indoor_night2_89", { 0.6888017654418945, 0.6786335110664368, 0.2549680471420288 } },
{ "indoor_night2_90", { 0.6909374594688416, 0.6771501302719116, 0.25312668085098267 } },
{ "indoor_night2_91", { 0.6922383308410645, 0.6762732267379761, 0.25191402435302734 } },
{ "indoor_night2_92", { 0.6890807747840881, 0.6782497763633728, 0.2552351951599121 } },
{ "indoor_night2_93", { 0.6865248680114746, 0.6798036694526672, 0.2579739987850189 } },
{ "indoor_night2_96", { 0.6878914833068848, 0.6789301037788391, 0.25663048028945923 } },
{ "indoor_night2_97", { 0.6850938200950623, 0.680454671382904, 0.2600537836551666 } },
{ "indoor_night2_98", { 0.6843785643577576, 0.6806155443191528, 0.26151177287101746 } },
{ "indoor_night2_132", { 0.670845627784729, 0.6875247359275818, 0.2779855728149414 } },
{ "indoor_night2_133", { 0.6733107566833496, 0.6863255500793457, 0.27497249841690063 } },
{ "indoor_night2_134", { 0.6810800433158875, 0.6811215877532959, 0.26870694756507874 } },
{ "indoor_night2_135", { 0.6740415096282959, 0.6852836012840271, 0.2757798135280609 } },
{ "indoor_night2_136", { 0.6735273003578186, 0.6863371133804321, 0.27441272139549255 } },
{ "indoor_night2_137", { 0.676952600479126, 0.684689998626709, 0.27006450295448303 } },
{ "indoor_night2_138", { 0.6818152666091919, 0.6813292503356934, 0.2663051187992096 } },
{ "indoor_night2_139", { 0.6758370995521545, 0.6857231855392456, 0.2702368497848511 } },
{ "indoor_night2_140", { 0.6762531399726868, 0.6843627095222473, 0.27263426780700684 } },
{ "indoor_night2_141", { 0.6794860363006592, 0.6822001338005066, 0.2700030207633972 } },
{ "indoor_night2_142", { 0.6796787977218628, 0.682644248008728, 0.2683907151222229 } },
{ "indoor_night2_149", { 0.6815130114555359, 0.6821028590202332, 0.2650955617427826 } },
{ "indoor_night2_156", { 0.6906166672706604, 0.6728646755218506, 0.26514461636543274 } },
{ "indoor_night2_157", { 0.6908083558082581, 0.6739578247070312, 0.2618485689163208 } },
{ "indoor_night2_158", { 0.6908431649208069, 0.6737330555915833, 0.26233452558517456 } },
{ "indoor_night2_170", { 0.6663857102394104, 0.6889307498931885, 0.2851395606994629 } },
{ "indoor_night2_171", { 0.664860725402832, 0.6917085647583008, 0.2819563150405884 } },
{ "indoor_night2_172", { 0.6662618517875671, 0.6903599500656128, 0.28195443749427795 } },
{ "indoor_night2_173", { 0.6627917289733887, 0.6919699907302856, 0.28615501523017883 } },
{ "indoor_night2_174", { 0.6643959283828735, 0.6914370059967041, 0.2837124764919281 } },
{ "indoor_night2_183", { 0.684053897857666, 0.6769347786903381, 0.2717159688472748 } },
{ "indoor_night2_184", { 0.6829990744590759, 0.6771291494369507, 0.27387651801109314 } },
{ "indoor_night2_185", { 0.6819033026695251, 0.677912712097168, 0.2746672034263611 } },
{ "indoor_night2_199", { 0.6816157698631287, 0.6793980002403259, 0.2716953456401825 } },
{ "indoor_night2_200", { 0.6833376884460449, 0.6780434250831604, 0.27075210213661194 } },
{ "indoor_night2_201", { 0.6838955283164978, 0.6775110363960266, 0.2706761360168457 } },
{ "indoor_night2_203", { 0.6798079609870911, 0.6801803708076477, 0.27425503730773926 } },
{ "indoor_night2_204", { 0.6788337230682373, 0.6795834898948669, 0.27812057733535767 } },
{ "indoor_night2_205", { 0.680338442325592, 0.6785121560096741, 0.27705734968185425 } },
{ "indoor_night2_206", { 0.6788656115531921, 0.6805486083030701, 0.2756720781326294 } },
{ "indoor_night2_207", { 0.6779111623764038, 0.6812145113945007, 0.2763752043247223 } },
{ "indoor_night2_208", { 0.6771993637084961, 0.6818394064903259, 0.27657943964004517 } },
{ "indoor_night2_223", { 0.6456443071365356, 0.7051050066947937, 0.29320693016052246 } },
{ "indoor_night2_224", { 0.6492403745651245, 0.7053072452545166, 0.28465524315834045 } },
{ "indoor_night2_225", { 0.6469570398330688, 0.7081727981567383, 0.28273287415504456 } },
{ "indoor_night2_226", { 0.6364238262176514, 0.712893009185791, 0.2945306599140167 } },
{ "indoor_night2_227", { 0.6497557759284973, 0.707114040851593, 0.27893930673599243 } },
{ "indoor_night2_228", { 0.6528596878051758, 0.7051385641098022, 0.276683509349823 } },
{ "indoor_night2_229", { 0.654917299747467, 0.7041546702384949, 0.27431637048721313 } },
{ "indoor_night2_233", { 0.6636127233505249, 0.6970447897911072, 0.27156367897987366 } },
{ "indoor_night2_234", { 0.664313554763794, 0.6965007781982422, 0.2712455689907074 } },
{ "indoor_night2_235", { 0.6640039086341858, 0.6969779133796692, 0.27077800035476685 } },
{ "indoor_night2_244", { 0.6732836365699768, 0.6869869232177734, 0.27338263392448425 } },
{ "indoor_night2_245", { 0.6726628541946411, 0.6879301071166992, 0.27253788709640503 } },
{ "indoor_night2_247", { 0.67051762342453, 0.6882389187812805, 0.2770077586174011 } },
{ "indoor_night2_248", { 0.6717011332511902, 0.6880384087562561, 0.27462854981422424 } },
{ "indoor_night2_249", { 0.6701805591583252, 0.6891005635261536, 0.27567824721336365 } },
{ "indoor_night2_250", { 0.6699840426445007, 0.6889914274215698, 0.276427686214447 } },
{ "indoor_night2_251", { 0.6708292961120605, 0.688729465007782, 0.27502673864364624 } },
{ "indoor_night2_252", { 0.6711652874946594, 0.6883234977722168, 0.27522343397140503 } },
{ "indoor_night2_253", { 0.6717638969421387, 0.6878702640533447, 0.27489593625068665 } },
{ "indoor_night2_266", { 0.6696531772613525, 0.689489483833313, 0.27598726749420166 } },
{ "indoor_night2_267", { 0.6659851670265198, 0.6914029717445374, 0.2800457775592804 } },
{ "indoor_night2_273", { 0.6765226125717163, 0.6837752461433411, 0.273438423871994 } },
{ "indoor_night2_274", { 0.6776847243309021, 0.6828569769859314, 0.27285483479499817 } },
{ "indoor_night2_275", { 0.6762598752975464, 0.6842523217201233, 0.27289435267448425 } },
{ "indoor_night2_282", { 0.6782724857330322, 0.6819275617599487, 0.2737172245979309 } },
{ "indoor_night2_283", { 0.6786967515945435, 0.6821759343147278, 0.2720419764518738 } },
{ "indoor_night2_284", { 0.6779731512069702, 0.6823204755783081, 0.2734798789024353 } },
{ "indoor_night2_285", { 0.6774376630783081, 0.6826549768447876, 0.27397164702415466 } },
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
    [[_mainView imageLayer] display]; // Crappiness to force the sample to be updated
    
    const Color<ColorSpace::Raw> c = [[_mainView imageLayer] sampleRaw];
    _imgOpts.whiteBalance = { c[1]/c[0], c[1]/c[1], c[1]/c[2] };
    [self _updateImageOptions];
    
    if (_TagCurrentIllum != _TagIllums.end()) {
        Illum& illum = (*_TagCurrentIllum);
        illum.c = c;
        [self _tagNextImage:nil];
    }
}

@end

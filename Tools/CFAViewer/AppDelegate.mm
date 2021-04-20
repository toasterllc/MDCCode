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
//        // Orange
//        Mmap imgData("/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker/indoor_night2_53.cfa");
        // Floor
//        Mmap imgData("/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker/indoor_night2_157.cfa");
        
        Mmap imgData("/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker/outdoor_5pm_45.cfa");
        
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
        
        .debayerLMMSE = {
            .applyGamma = true,
        },
        
        
        
//        illum = 2.4743327397, 2.5535876543, 1
        .whiteBalance = { 0.346606/0.383756, 0.346606/0.523701, 0.346606/0.346606 }, // outdoor_5pm_45
//        .whiteBalance = { 0.691343/0.669886, 0.691343/0.691343, 0.691343/0.270734 },
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

static const fs::path _TagDir("/Users/dave/Desktop/Old/2021:4:3/CFAViewerSession-All-FilteredGood");
Illums _TagIllums = {
{ "indoor_night_3", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.96 degrees)
{ "indoor_night_4", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.91 degrees)
{ "indoor_night_5", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.67 degrees)
{ "indoor_night_6", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.65 degrees)
{ "indoor_night_7", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.64 degrees)
{ "indoor_night_8", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.74 degrees)
{ "indoor_night_15", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.39 degrees)
{ "indoor_night_16", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.36 degrees)
{ "indoor_night_17", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.22 degrees)
{ "indoor_night_18", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.10 degrees)
{ "indoor_night_19", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.03 degrees)
{ "indoor_night_20", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.80 degrees)
{ "indoor_night_24", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.85 degrees)
{ "indoor_night_25", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.77 degrees)
{ "indoor_night_26", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.86 degrees)
{ "indoor_night_27", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.31 degrees)
{ "indoor_night_28", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 3.31 degrees)
{ "indoor_night_34", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.41 degrees)
{ "indoor_night_35", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.29 degrees)
{ "indoor_night_36", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.20 degrees)
{ "indoor_night_37", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.51 degrees)
{ "indoor_night_38", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.36 degrees)
{ "indoor_night_39", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.30 degrees)
{ "indoor_night_40", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.27 degrees)
{ "indoor_night_41", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.26 degrees)
{ "indoor_night_42", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.23 degrees)
{ "indoor_night_43", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.21 degrees)
{ "indoor_night_44", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.21 degrees)
{ "indoor_night_45", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.23 degrees)
{ "indoor_night_46", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.26 degrees)
{ "indoor_night_47", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.78 degrees)
{ "indoor_night_48", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.67 degrees)
{ "indoor_night_49", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.68 degrees)
{ "indoor_night_50", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 3.90 degrees)
{ "indoor_night_51", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.05 degrees)
{ "indoor_night_54", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.69 degrees)
{ "indoor_night_55", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.73 degrees)
{ "indoor_night_56", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.76 degrees)
{ "indoor_night_57", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.69 degrees)
{ "indoor_night_60", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.36 degrees)
{ "indoor_night_61", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.60 degrees)
{ "indoor_night_62", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.60 degrees)
{ "indoor_night_63", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.52 degrees)
{ "indoor_night_64", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.44 degrees)
{ "indoor_night_65", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.47 degrees)
{ "indoor_night_66", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.47 degrees)
{ "indoor_night_67", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.49 degrees)
{ "indoor_night_68", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.44 degrees)
{ "indoor_night_69", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.43 degrees)
{ "indoor_night_72", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.23 degrees)
{ "indoor_night_74", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.62 degrees)
{ "indoor_night_75", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.63 degrees)
{ "indoor_night_76", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.69 degrees)
{ "indoor_night_77", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.66 degrees)
{ "indoor_night_78", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.68 degrees)
{ "indoor_night_79", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.69 degrees)
{ "indoor_night_80", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.74 degrees)
{ "indoor_night_81", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.76 degrees)
{ "indoor_night_82", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.79 degrees)
{ "indoor_night_83", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.78 degrees)
{ "indoor_night_84", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.79 degrees)
{ "indoor_night_85", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.77 degrees)
{ "indoor_night_86", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.28 degrees)
{ "indoor_night_87", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.28 degrees)
{ "indoor_night_88", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.27 degrees)
{ "indoor_night_89", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.27 degrees)
{ "indoor_night_99", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.43 degrees)
{ "indoor_night_100", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.45 degrees)
{ "indoor_night_103", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.40 degrees)
{ "indoor_night_104", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.90 degrees)
{ "indoor_night_105", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.77 degrees)
{ "indoor_night_106", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.59 degrees)
{ "indoor_night_107", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.71 degrees)
{ "indoor_night_108", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.63 degrees)
{ "indoor_night_109", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.59 degrees)
{ "indoor_night_110", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.38 degrees)
{ "indoor_night_111", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.43 degrees)
{ "indoor_night_117", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.69 degrees)
{ "indoor_night_121", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.33 degrees)
{ "indoor_night_122", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.32 degrees)
{ "indoor_night_123", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.29 degrees)
{ "indoor_night_124", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.49 degrees)
{ "indoor_night_125", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.25 degrees)
{ "indoor_night_128", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.74 degrees)
{ "indoor_night_133", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.57 degrees)
{ "indoor_night_136", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.63 degrees)
{ "indoor_night_139", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 0.62 degrees)
{ "indoor_night_148", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.43 degrees)
{ "indoor_night_150", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.18 degrees)
{ "indoor_night_151", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.18 degrees)
{ "indoor_night_157", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.68 degrees)
{ "indoor_night_158", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.71 degrees)
{ "indoor_night_159", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.71 degrees)
{ "indoor_night_160", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.71 degrees)
{ "indoor_night_161", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.71 degrees)
{ "indoor_night_162", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.70 degrees)
{ "indoor_night_163", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.68 degrees)
{ "indoor_night_166", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.65 degrees)
{ "indoor_night_168", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.60 degrees)
{ "indoor_night_169", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.63 degrees)
{ "indoor_night_170", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.61 degrees)
{ "indoor_night_171", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.57 degrees)
{ "indoor_night_172", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.58 degrees)
{ "indoor_night_173", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.61 degrees)
{ "indoor_night_174", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.65 degrees)
{ "indoor_night_175", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.61 degrees)
{ "indoor_night_176", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.64 degrees)
{ "outdoor_4pm_2", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.53 degrees)
{ "outdoor_4pm_3", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.76 degrees)
{ "outdoor_4pm_4", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.49 degrees)
{ "outdoor_4pm_5", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.51 degrees)
{ "outdoor_4pm_6", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.52 degrees)
{ "outdoor_4pm_17", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.98 degrees)
{ "outdoor_4pm_18", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.83 degrees)
{ "outdoor_4pm_19", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.14 degrees)
{ "outdoor_4pm_20", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.01 degrees)
{ "outdoor_4pm_21", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.18 degrees)
{ "outdoor_4pm_23", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.93 degrees)
{ "outdoor_4pm_25", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.62 degrees)
{ "outdoor_4pm_26", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.55 degrees)
{ "outdoor_4pm_27", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.74 degrees)
{ "outdoor_4pm_28", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.06 degrees)
{ "outdoor_4pm_29", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.82 degrees)
{ "outdoor_4pm_30", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.09 degrees)
{ "outdoor_4pm_31", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.53 degrees)
{ "outdoor_4pm_32", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.71 degrees)
{ "outdoor_4pm_33", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.43 degrees)
{ "outdoor_4pm_34", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.17 degrees)
{ "outdoor_4pm_35", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.96 degrees)
{ "outdoor_4pm_36", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.30 degrees)
{ "outdoor_4pm_37", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.83 degrees)
{ "outdoor_4pm_38", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.81 degrees)
{ "outdoor_4pm_39", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.81 degrees)
{ "outdoor_4pm_40", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.51 degrees)
{ "outdoor_4pm_41", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.05 degrees)
{ "outdoor_4pm_42", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.65 degrees)
{ "outdoor_4pm_43", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 7.09 degrees)
{ "outdoor_4pm_44", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.17 degrees)
{ "outdoor_4pm_45", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.83 degrees)
{ "outdoor_4pm_46", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.73 degrees)
{ "outdoor_4pm_47", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.45 degrees)
{ "outdoor_4pm_48", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 3.33 degrees)
{ "outdoor_4pm_51", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.68 degrees)
{ "outdoor_4pm_52", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.79 degrees)
{ "outdoor_4pm_53", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.01 degrees)
{ "outdoor_4pm_54", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 5.38 degrees)
{ "outdoor_4pm_55", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.04 degrees)
{ "outdoor_4pm_56", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.36 degrees)
{ "outdoor_4pm_57", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 5.99 degrees)
{ "outdoor_4pm_58", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.26 degrees)
{ "outdoor_4pm_59", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 5.00 degrees)
{ "outdoor_4pm_60", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.18 degrees)
{ "outdoor_4pm_61", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.87 degrees)
{ "outdoor_4pm_62", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.41 degrees)
{ "outdoor_4pm_63", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.19 degrees)
{ "outdoor_4pm_64", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.52 degrees)
{ "outdoor_4pm_65", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.33 degrees)
{ "outdoor_4pm_66", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.70 degrees)
{ "outdoor_4pm_67", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.84 degrees)
{ "outdoor_4pm_68", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.01 degrees)
{ "outdoor_4pm_69", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.93 degrees)
{ "outdoor_4pm_70", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.76 degrees)
{ "outdoor_4pm_71", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.17 degrees)
{ "outdoor_4pm_72", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.99 degrees)
{ "outdoor_4pm_73", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.51 degrees)
{ "outdoor_4pm_74", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.95 degrees)
{ "outdoor_4pm_75", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.34 degrees)
{ "outdoor_4pm_76", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.13 degrees)
{ "outdoor_4pm_77", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.59 degrees)
{ "outdoor_4pm_78", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.60 degrees)
{ "outdoor_4pm_79", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.98 degrees)
{ "outdoor_4pm_80", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.74 degrees)
{ "outdoor_4pm_81", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.01 degrees)
{ "outdoor_4pm_82", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.34 degrees)
{ "outdoor_4pm_83", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.98 degrees)
{ "outdoor_4pm_84", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.47 degrees)
{ "outdoor_4pm_85", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.46 degrees)
{ "outdoor_4pm_86", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.15 degrees)
{ "outdoor_4pm_87", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.90 degrees)
{ "outdoor_4pm_88", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.81 degrees)
{ "outdoor_4pm_89", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.37 degrees)
{ "outdoor_4pm_90", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.99 degrees)
{ "outdoor_4pm_91", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.34 degrees)
{ "outdoor_4pm_92", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.73 degrees)
{ "outdoor_4pm_93", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.96 degrees)
{ "outdoor_4pm_94", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.04 degrees)
{ "outdoor_4pm_95", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.19 degrees)
{ "outdoor_4pm_96", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.46 degrees)
{ "outdoor_4pm_97", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.11 degrees)
{ "outdoor_4pm_98", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.56 degrees)
{ "outdoor_4pm_99", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.46 degrees)
{ "outdoor_4pm_100", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.36 degrees)
{ "outdoor_4pm_101", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.37 degrees)
{ "outdoor_4pm_102", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.58 degrees)
{ "outdoor_4pm_103", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.73 degrees)
{ "outdoor_4pm_104", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.81 degrees)
{ "outdoor_4pm_105", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.67 degrees)
{ "outdoor_4pm_106", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.40 degrees)
{ "outdoor_4pm_107", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.71 degrees)
{ "outdoor_4pm_108", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.53 degrees)
{ "outdoor_4pm_109", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.66 degrees)
{ "outdoor_4pm_110", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.54 degrees)
{ "outdoor_4pm_111", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.78 degrees)
{ "outdoor_4pm_112", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.92 degrees)
{ "outdoor_4pm_113", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.58 degrees)
{ "outdoor_4pm_114", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.15 degrees)
{ "outdoor_4pm_115", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.78 degrees)
{ "outdoor_4pm_116", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 11.30 degrees)
{ "outdoor_4pm_117", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.69 degrees)
{ "outdoor_4pm_118", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.46 degrees)
{ "outdoor_4pm_119", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.15 degrees)
{ "outdoor_4pm_120", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.86 degrees)
{ "outdoor_4pm_121", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.59 degrees)
{ "outdoor_4pm_122", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.54 degrees)
{ "outdoor_4pm_123", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.66 degrees)
{ "outdoor_4pm_124", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.41 degrees)
{ "outdoor_4pm_125", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.56 degrees)
{ "outdoor_4pm_126", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.16 degrees)
{ "outdoor_4pm_127", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.54 degrees)
{ "outdoor_4pm_128", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.72 degrees)
{ "outdoor_4pm_129", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.04 degrees)
{ "outdoor_4pm_130", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.05 degrees)
{ "outdoor_4pm_131", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.54 degrees)
{ "outdoor_4pm_132", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.88 degrees)
{ "outdoor_4pm_133", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.06 degrees)
{ "outdoor_4pm_134", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.94 degrees)
{ "outdoor_4pm_135", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.79 degrees)
{ "outdoor_4pm_136", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.66 degrees)
{ "outdoor_4pm_137", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.73 degrees)
{ "outdoor_4pm_138", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.52 degrees)
{ "outdoor_4pm_139", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.96 degrees)
{ "outdoor_4pm_140", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.54 degrees)
{ "outdoor_4pm_141", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.74 degrees)
{ "outdoor_4pm_142", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.85 degrees)
{ "outdoor_4pm_143", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.64 degrees)
{ "outdoor_4pm_144", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.43 degrees)
{ "outdoor_4pm_146", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.64 degrees)
{ "outdoor_4pm_147", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.91 degrees)
{ "outdoor_4pm_148", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.64 degrees)
{ "outdoor_4pm_149", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.72 degrees)
{ "outdoor_4pm_150", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 8.04 degrees)
{ "outdoor_4pm_151", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.00 degrees)
{ "outdoor_4pm_152", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.68 degrees)
{ "outdoor_4pm_159", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.66 degrees)
{ "outdoor_4pm_160", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.24 degrees)
{ "outdoor_4pm_163", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.68 degrees)
{ "outdoor_4pm_164", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.51 degrees)
{ "outdoor_4pm_165", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.98 degrees)
{ "outdoor_4pm_166", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.89 degrees)
{ "outdoor_4pm_167", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.26 degrees)
{ "outdoor_4pm_168", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.28 degrees)
{ "outdoor_4pm_172", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.42 degrees)
{ "outdoor_noon_3", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.44 degrees)
{ "outdoor_noon_4", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.10 degrees)
{ "outdoor_noon_6", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.18 degrees)
{ "outdoor_noon_7", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.07 degrees)
{ "outdoor_noon_8", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.37 degrees)
{ "outdoor_noon_9", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.79 degrees)
{ "outdoor_noon_10", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.10 degrees)
{ "outdoor_noon_11", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.31 degrees)
{ "outdoor_noon_12", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.87 degrees)
{ "outdoor_noon_15", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.04 degrees)
{ "outdoor_noon_16", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.85 degrees)
{ "outdoor_noon_17", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.84 degrees)
{ "outdoor_noon_18", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.93 degrees)
{ "outdoor_noon_19", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.95 degrees)
{ "outdoor_noon_20", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.37 degrees)
{ "outdoor_noon_21", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.45 degrees)
{ "outdoor_noon_22", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.09 degrees)
{ "outdoor_noon_23", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.13 degrees)
{ "outdoor_noon_24", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.82 degrees)
{ "outdoor_noon_25", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.60 degrees)
{ "outdoor_noon_26", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 8.57 degrees)
{ "outdoor_noon_27", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.54 degrees)
{ "outdoor_noon_28", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.60 degrees)
{ "outdoor_noon_29", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.14 degrees)
{ "outdoor_noon_30", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.66 degrees)
{ "outdoor_noon_31", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.66 degrees)
{ "outdoor_noon_32", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.28 degrees)
{ "outdoor_noon_33", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.41 degrees)
{ "outdoor_noon_34", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.26 degrees)
{ "outdoor_noon_35", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.95 degrees)
{ "outdoor_noon_36", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.91 degrees)
{ "outdoor_noon_37", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.97 degrees)
{ "outdoor_noon_38", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.48 degrees)
{ "outdoor_noon_39", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 7.59 degrees)
{ "outdoor_noon_40", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.56 degrees)
{ "outdoor_noon_41", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.01 degrees)
{ "outdoor_noon_42", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.07 degrees)
{ "outdoor_noon_43", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.00 degrees)
{ "outdoor_noon_44", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.04 degrees)
{ "outdoor_noon_45", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.14 degrees)
{ "outdoor_noon_46", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 3.95 degrees)
{ "outdoor_noon_47", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.53 degrees)
{ "outdoor_noon_48", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.97 degrees)
{ "outdoor_noon_49", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.81 degrees)
{ "outdoor_noon_50", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.03 degrees)
{ "outdoor_noon_51", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.15 degrees)
{ "outdoor_noon_52", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.10 degrees)
{ "outdoor_noon_53", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.77 degrees)
{ "outdoor_noon_54", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.03 degrees)
{ "outdoor_noon_55", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.52 degrees)
{ "outdoor_noon_56", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.30 degrees)
{ "outdoor_noon_57", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.04 degrees)
{ "outdoor_noon_58", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.25 degrees)
{ "outdoor_noon_59", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.94 degrees)
{ "outdoor_noon_60", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.09 degrees)
{ "outdoor_noon_61", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.69 degrees)
{ "outdoor_noon_62", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.81 degrees)
{ "outdoor_noon_63", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 1.74 degrees)
{ "outdoor_noon_64", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 2.43 degrees)
{ "outdoor_noon_65", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 6.36 degrees)
{ "outdoor_noon_66", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 5.99 degrees)
{ "outdoor_noon_67", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.28 degrees)
{ "outdoor_noon_68", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.22 degrees)
{ "outdoor_noon_69", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.53 degrees)
{ "outdoor_noon_70", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 14.19 degrees)
{ "outdoor_noon_71", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 10.92 degrees)
{ "outdoor_noon_72", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.38 degrees)
{ "outdoor_noon_73", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.12 degrees)
{ "outdoor_noon_74", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.15 degrees)
{ "outdoor_noon_75", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.61 degrees)
{ "outdoor_noon_76", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 7.13 degrees)
{ "outdoor_noon_77", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.17 degrees)
{ "outdoor_noon_78", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.38 degrees)
{ "outdoor_noon_79", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.95 degrees)
{ "outdoor_noon_80", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.94 degrees)
{ "outdoor_noon_81", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.48 degrees)
{ "outdoor_noon_82", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.34 degrees)
{ "outdoor_noon_83", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.93 degrees)
{ "outdoor_noon_84", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.21 degrees)
{ "outdoor_noon_85", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.57 degrees)
{ "outdoor_noon_86", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.71 degrees)
{ "outdoor_noon_87", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.63 degrees)
{ "outdoor_noon_88", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.64 degrees)
{ "outdoor_noon_89", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.15 degrees)
{ "outdoor_noon_90", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.55 degrees)
{ "outdoor_noon_91", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.70 degrees)
{ "outdoor_noon_92", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.39 degrees)
{ "outdoor_noon_93", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.76 degrees)
{ "outdoor_noon_94", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.46 degrees)
{ "outdoor_noon_95", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.94 degrees)
{ "outdoor_noon_96", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.05 degrees)
{ "outdoor_noon_97", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.56 degrees)
{ "outdoor_noon_98", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.45 degrees)
{ "outdoor_noon_99", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.45 degrees)
{ "outdoor_noon_100", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.02 degrees)
{ "outdoor_noon_101", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.45 degrees)
{ "outdoor_noon_102", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.32 degrees)
{ "outdoor_noon_103", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.64 degrees)
{ "outdoor_noon_104", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.37 degrees)
{ "outdoor_noon_105", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.94 degrees)
{ "outdoor_noon_106", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.23 degrees)
{ "outdoor_noon_107", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.11 degrees)
{ "outdoor_noon_108", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.68 degrees)
{ "outdoor_noon_109", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.27 degrees)
{ "outdoor_noon_110", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.94 degrees)
{ "outdoor_noon_111", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 0.61 degrees)
{ "outdoor_noon_112", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.30 degrees)
{ "outdoor_noon_113", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.75 degrees)
{ "outdoor_noon_114", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.40 degrees)
{ "outdoor_noon_115", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.69 degrees)
{ "outdoor_noon_116", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 5.00 degrees)
{ "outdoor_noon_117", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.51 degrees)
{ "outdoor_noon_118", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.13 degrees)
{ "outdoor_noon_119", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.83 degrees)
{ "outdoor_noon_120", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.97 degrees)
{ "outdoor_noon_121", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.90 degrees)
{ "outdoor_noon_122", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.10 degrees)
{ "outdoor_noon_129", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.39 degrees)
{ "outdoor_noon_130", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.68 degrees)
{ "outdoor_noon_131", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.54 degrees)
{ "outdoor_noon_132", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.45 degrees)
{ "outdoor_noon_133", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.10 degrees)
{ "outdoor_noon_134", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.37 degrees)
{ "outdoor_noon_135", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.02 degrees)
{ "outdoor_noon_136", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.20 degrees)
{ "outdoor_noon_137", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.03 degrees)
{ "outdoor_noon_138", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.18 degrees)
{ "outdoor_noon_139", { 0.991380, 1.000000, 0.382732 } }, // IndoorWarm (gray-world vs preset Δ = 4.29 degrees)
{ "outdoor_noon_140", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.80 degrees)
{ "outdoor_noon_142", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 8.56 degrees)
{ "outdoor_noon_145", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.21 degrees)
{ "outdoor_noon_146", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.25 degrees)
{ "outdoor_noon_148", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.47 degrees)
{ "outdoor_noon_150", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.17 degrees)
{ "outdoor_noon_151", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.99 degrees)
{ "outdoor_noon_152", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.31 degrees)
{ "outdoor_noon_153", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.00 degrees)
{ "outdoor_noon_155", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.90 degrees)
{ "outdoor_noon_156", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.78 degrees)
{ "outdoor_noon_157", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.53 degrees)
{ "outdoor_noon_158", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.07 degrees)
{ "outdoor_noon_161", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 3.79 degrees)
{ "outdoor_noon_162", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 4.44 degrees)
{ "outdoor_noon_164", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.94 degrees)
{ "outdoor_noon_165", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.96 degrees)
{ "outdoor_noon_166", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.67 degrees)
{ "outdoor_noon_167", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 1.97 degrees)
{ "outdoor_noon_177", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 6.52 degrees)
{ "outdoor_noon_182", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 7.35 degrees)
{ "outdoor_noon_187", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.77 degrees)
{ "outdoor_noon_188", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.13 degrees)
{ "outdoor_noon_189", { 0.731058, 1.000000, 0.662689 } }, // Daylight (gray-world vs preset Δ = 2.21 degrees)
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
//    return;
    
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

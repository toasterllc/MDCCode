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
{ "indoor_night_3", { 0.672726, 0.689255, 0.269011 } },
{ "indoor_night_4", { 0.672375, 0.689479, 0.269316 } },
{ "indoor_night_5", { 0.672711, 0.689154, 0.269308 } },
{ "indoor_night_6", { 0.679128, 0.685372, 0.262775 } },
{ "indoor_night_7", { 0.680194, 0.684395, 0.262563 } },
{ "indoor_night_8", { 0.675971, 0.686941, 0.266788 } },
{ "indoor_night_15", { 0.678696, 0.685632, 0.263213 } },
{ "indoor_night_16", { 0.680521, 0.684620, 0.261125 } },
{ "indoor_night_17", { 0.672118, 0.689579, 0.269702 } },
{ "indoor_night_18", { 0.671942, 0.689744, 0.269715 } },
{ "indoor_night_19", { 0.670641, 0.690791, 0.270275 } },
{ "indoor_night_20", { 0.677422, 0.686651, 0.263839 } },
{ "indoor_night_24", { 0.684229, 0.682254, 0.257607 } },
{ "indoor_night_25", { 0.708257, 0.668843, 0.225878 } },
{ "indoor_night_26", { 0.764254, 0.626619, 0.152529 } },
{ "indoor_night_27", { 0.710602, 0.667614, 0.222118 } },
{ "indoor_night_28", { 0.752544, 0.638352, 0.161817 } },
{ "indoor_night_34", { 0.682804, 0.682790, 0.259953 } },
{ "indoor_night_35", { 0.682736, 0.682752, 0.260232 } },
{ "indoor_night_36", { 0.682730, 0.682758, 0.260232 } },
{ "indoor_night_37", { 0.682882, 0.682813, 0.259690 } },
{ "indoor_night_38", { 0.683058, 0.682703, 0.259516 } },
{ "indoor_night_39", { 0.683535, 0.682513, 0.258759 } },
{ "indoor_night_40", { 0.682995, 0.682810, 0.259402 } },
{ "indoor_night_41", { 0.683397, 0.682443, 0.259308 } },
{ "indoor_night_42", { 0.687446, 0.679667, 0.255871 } },
{ "indoor_night_43", { 0.685194, 0.681189, 0.257857 } },
{ "indoor_night_44", { 0.683720, 0.682282, 0.258879 } },
{ "indoor_night_45", { 0.683037, 0.682724, 0.259516 } },
{ "indoor_night_46", { 0.682865, 0.682739, 0.259929 } },
{ "indoor_night_47", { 0.681837, 0.681876, 0.264846 } },
{ "indoor_night_48", { 0.682025, 0.682039, 0.263942 } },
{ "indoor_night_49", { 0.682184, 0.682163, 0.263209 } },
{ "indoor_night_50", { 0.681187, 0.682017, 0.266153 } },
{ "indoor_night_51", { 0.681209, 0.681753, 0.266771 } },
{ "indoor_night_54", { 0.661539, 0.696384, 0.278237 } },
{ "indoor_night_55", { 0.664075, 0.694869, 0.275974 } },
{ "indoor_night_56", { 0.663324, 0.695321, 0.276643 } },
{ "indoor_night_57", { 0.663651, 0.695126, 0.276345 } },
{ "indoor_night_60", { 0.664365, 0.694696, 0.275710 } },
{ "indoor_night_61", { 0.666143, 0.693620, 0.274125 } },
{ "indoor_night_62", { 0.667686, 0.692678, 0.272751 } },
{ "indoor_night_63", { 0.666251, 0.693556, 0.274024 } },
{ "indoor_night_64", { 0.669983, 0.691261, 0.270705 } },
{ "indoor_night_65", { 0.669953, 0.691280, 0.270732 } },
{ "indoor_night_66", { 0.669779, 0.691388, 0.270887 } },
{ "indoor_night_67", { 0.669759, 0.691400, 0.270904 } },
{ "indoor_night_68", { 0.669973, 0.691267, 0.270714 } },
{ "indoor_night_69", { 0.669932, 0.691292, 0.270750 } },
{ "indoor_night_72", { 0.657172, 0.698973, 0.282065 } },
{ "indoor_night_74", { 0.656811, 0.699148, 0.282473 } },
{ "indoor_night_75", { 0.656801, 0.699154, 0.282482 } },
{ "indoor_night_76", { 0.656797, 0.699156, 0.282486 } },
{ "indoor_night_77", { 0.656797, 0.699156, 0.282485 } },
{ "indoor_night_78", { 0.656797, 0.699157, 0.282485 } },
{ "indoor_night_79", { 0.656797, 0.699156, 0.282485 } },
{ "indoor_night_80", { 0.656797, 0.699157, 0.282485 } },
{ "indoor_night_81", { 0.656797, 0.699157, 0.282485 } },
{ "indoor_night_82", { 0.656797, 0.699156, 0.282485 } },
{ "indoor_night_83", { 0.656797, 0.699156, 0.282485 } },
{ "indoor_night_84", { 0.656797, 0.699156, 0.282486 } },
{ "indoor_night_85", { 0.656797, 0.699156, 0.282485 } },
{ "indoor_night_86", { 0.657457, 0.698774, 0.281895 } },
{ "indoor_night_87", { 0.659507, 0.697580, 0.280059 } },
{ "indoor_night_88", { 0.657837, 0.698549, 0.281565 } },
{ "indoor_night_89", { 0.657623, 0.698676, 0.281751 } },
{ "indoor_night_99", { 0.669700, 0.691436, 0.270956 } },
{ "indoor_night_100", { 0.669944, 0.691285, 0.270740 } },
{ "indoor_night_103", { 0.669987, 0.691258, 0.270702 } },
{ "indoor_night_104", { 0.669896, 0.691323, 0.270761 } },
{ "indoor_night_105", { 0.669970, 0.691271, 0.270710 } },
{ "indoor_night_106", { 0.669985, 0.691260, 0.270702 } },
{ "indoor_night_107", { 0.669961, 0.691276, 0.270720 } },
{ "indoor_night_108", { 0.669981, 0.691263, 0.270705 } },
{ "indoor_night_109", { 0.669979, 0.691264, 0.270706 } },
{ "indoor_night_110", { 0.669987, 0.691258, 0.270702 } },
{ "indoor_night_111", { 0.669983, 0.691261, 0.270705 } },
{ "indoor_night_117", { 0.669165, 0.691772, 0.271420 } },
{ "indoor_night_121", { 0.681319, 0.684014, 0.260633 } },
{ "indoor_night_122", { 0.681955, 0.683588, 0.260087 } },
{ "indoor_night_123", { 0.681778, 0.683696, 0.260267 } },
{ "indoor_night_124", { 0.676912, 0.686884, 0.264539 } },
{ "indoor_night_125", { 0.682629, 0.683179, 0.259392 } },
{ "indoor_night_128", { 0.671546, 0.690352, 0.269146 } },
{ "indoor_night_133", { 0.749277, 0.642480, 0.160633 } },
{ "indoor_night_136", { 0.671505, 0.692767, 0.262974 } },
{ "indoor_night_139", { 0.670029, 0.691298, 0.270496 } },
{ "indoor_night_148", { 0.683940, 0.682405, 0.257973 } },
{ "indoor_night_150", { 0.685358, 0.681649, 0.256201 } },
{ "indoor_night_151", { 0.693076, 0.677512, 0.246219 } },
{ "indoor_night_157", { 0.684078, 0.682122, 0.258354 } },
{ "indoor_night_158", { 0.685695, 0.681151, 0.256624 } },
{ "indoor_night_159", { 0.684210, 0.682093, 0.258081 } },
{ "indoor_night_160", { 0.683411, 0.682494, 0.259135 } },
{ "indoor_night_161", { 0.683289, 0.682671, 0.258989 } },
{ "indoor_night_162", { 0.683071, 0.682799, 0.259230 } },
{ "indoor_night_163", { 0.683022, 0.682870, 0.259171 } },
{ "indoor_night_166", { 0.682882, 0.682774, 0.259793 } },
{ "indoor_night_168", { 0.681850, 0.681853, 0.264872 } },
{ "indoor_night_169", { 0.681957, 0.681971, 0.264293 } },
{ "indoor_night_170", { 0.682867, 0.682867, 0.259585 } },
{ "indoor_night_171", { 0.682613, 0.682623, 0.260893 } },
{ "indoor_night_172", { 0.682605, 0.682620, 0.260923 } },
{ "indoor_night_173", { 0.682249, 0.682274, 0.262754 } },
{ "indoor_night_174", { 0.682694, 0.682697, 0.260489 } },
{ "indoor_night_175", { 0.682644, 0.682643, 0.260759 } },
{ "indoor_night_176", { 0.682500, 0.682530, 0.261431 } },
{ "outdoor_4pm_2", { 0.502796, 0.751022, 0.427974 } },
{ "outdoor_4pm_3", { 0.503977, 0.756100, 0.417517 } },
{ "outdoor_4pm_4", { 0.503765, 0.756190, 0.417608 } },
{ "outdoor_4pm_5", { 0.503765, 0.756185, 0.417618 } },
{ "outdoor_4pm_6", { 0.503756, 0.756194, 0.417612 } },
{ "outdoor_4pm_17", { 0.510887, 0.752473, 0.415667 } },
{ "outdoor_4pm_18", { 0.506859, 0.753217, 0.419235 } },
{ "outdoor_4pm_19", { 0.534836, 0.754369, 0.380628 } },
{ "outdoor_4pm_20", { 0.504431, 0.755848, 0.417425 } },
{ "outdoor_4pm_21", { 0.504960, 0.756183, 0.416176 } },
{ "outdoor_4pm_23", { 0.518170, 0.753934, 0.403836 } },
{ "outdoor_4pm_25", { 0.504143, 0.734229, 0.454696 } },
{ "outdoor_4pm_26", { 0.436432, 0.525537, 0.730300 } },
{ "outdoor_4pm_27", { 0.500231, 0.715833, 0.487189 } },
{ "outdoor_4pm_28", { 0.509694, 0.719196, 0.472195 } },
{ "outdoor_4pm_29", { 0.523825, 0.739850, 0.422172 } },
{ "outdoor_4pm_30", { 0.504517, 0.716019, 0.482473 } },
{ "outdoor_4pm_31", { 0.479584, 0.715487, 0.508014 } },
{ "outdoor_4pm_32", { 0.479878, 0.717094, 0.505463 } },
{ "outdoor_4pm_33", { 0.495969, 0.717186, 0.489549 } },
{ "outdoor_4pm_34", { 0.508493, 0.720003, 0.472260 } },
{ "outdoor_4pm_35", { 0.507670, 0.719203, 0.474361 } },
{ "outdoor_4pm_36", { 0.504797, 0.714839, 0.483927 } },
{ "outdoor_4pm_37", { 0.504105, 0.715753, 0.483297 } },
{ "outdoor_4pm_38", { 0.534180, 0.704926, 0.466616 } },
{ "outdoor_4pm_39", { 0.660908, 0.698812, 0.273610 } },
{ "outdoor_4pm_40", { 0.662526, 0.697596, 0.272797 } },
{ "outdoor_4pm_41", { 0.665110, 0.695391, 0.272138 } },
{ "outdoor_4pm_42", { 0.664593, 0.695777, 0.272414 } },
{ "outdoor_4pm_43", { 0.666570, 0.694160, 0.271712 } },
{ "outdoor_4pm_44", { 0.660990, 0.697998, 0.275483 } },
{ "outdoor_4pm_45", { 0.598726, 0.699522, 0.390123 } },
{ "outdoor_4pm_46", { 0.586301, 0.706411, 0.396527 } },
{ "outdoor_4pm_47", { 0.444828, 0.678871, 0.584177 } },
{ "outdoor_4pm_48", { 0.630085, 0.704705, 0.326164 } },
{ "outdoor_4pm_51", { 0.581639, 0.704910, 0.405954 } },
{ "outdoor_4pm_52", { 0.658882, 0.699750, 0.276089 } },
{ "outdoor_4pm_53", { 0.633340, 0.702475, 0.324668 } },
{ "outdoor_4pm_54", { 0.569018, 0.707963, 0.418338 } },
{ "outdoor_4pm_55", { 0.593527, 0.709580, 0.379766 } },
{ "outdoor_4pm_56", { 0.660060, 0.699355, 0.274268 } },
{ "outdoor_4pm_57", { 0.584140, 0.702138, 0.407163 } },
{ "outdoor_4pm_58", { 0.495121, 0.684775, 0.534732 } },
{ "outdoor_4pm_59", { 0.437069, 0.674613, 0.594868 } },
{ "outdoor_4pm_60", { 0.642214, 0.709706, 0.289618 } },
{ "outdoor_4pm_61", { 0.661177, 0.698416, 0.273970 } },
{ "outdoor_4pm_62", { 0.502831, 0.716418, 0.483638 } },
{ "outdoor_4pm_63", { 0.480097, 0.708448, 0.517309 } },
{ "outdoor_4pm_64", { 0.510436, 0.717622, 0.473786 } },
{ "outdoor_4pm_65", { 0.512453, 0.728222, 0.455065 } },
{ "outdoor_4pm_66", { 0.512795, 0.723292, 0.462483 } },
{ "outdoor_4pm_67", { 0.512218, 0.725615, 0.459474 } },
{ "outdoor_4pm_68", { 0.508905, 0.723451, 0.466513 } },
{ "outdoor_4pm_69", { 0.503513, 0.731672, 0.459490 } },
{ "outdoor_4pm_70", { 0.508820, 0.724121, 0.465566 } },
{ "outdoor_4pm_71", { 0.500585, 0.726616, 0.470578 } },
{ "outdoor_4pm_72", { 0.500866, 0.727100, 0.469530 } },
{ "outdoor_4pm_73", { 0.497341, 0.747243, 0.440773 } },
{ "outdoor_4pm_74", { 0.517078, 0.727307, 0.451281 } },
{ "outdoor_4pm_75", { 0.514773, 0.710362, 0.479994 } },
{ "outdoor_4pm_76", { 0.509314, 0.700204, 0.500313 } },
{ "outdoor_4pm_77", { 0.522517, 0.717160, 0.461147 } },
{ "outdoor_4pm_78", { 0.524731, 0.717388, 0.458270 } },
{ "outdoor_4pm_79", { 0.523534, 0.715972, 0.461840 } },
{ "outdoor_4pm_80", { 0.526642, 0.719955, 0.452011 } },
{ "outdoor_4pm_81", { 0.525450, 0.719416, 0.454249 } },
{ "outdoor_4pm_82", { 0.525954, 0.719704, 0.453209 } },
{ "outdoor_4pm_83", { 0.521496, 0.721817, 0.454997 } },
{ "outdoor_4pm_84", { 0.529276, 0.723905, 0.442525 } },
{ "outdoor_4pm_85", { 0.526174, 0.721086, 0.450751 } },
{ "outdoor_4pm_86", { 0.520398, 0.722087, 0.455825 } },
{ "outdoor_4pm_87", { 0.510112, 0.719013, 0.472024 } },
{ "outdoor_4pm_88", { 0.499618, 0.718506, 0.483870 } },
{ "outdoor_4pm_89", { 0.491087, 0.716431, 0.495540 } },
{ "outdoor_4pm_90", { 0.483426, 0.716934, 0.502299 } },
{ "outdoor_4pm_91", { 0.486517, 0.717221, 0.498893 } },
{ "outdoor_4pm_92", { 0.434879, 0.674637, 0.596444 } },
{ "outdoor_4pm_93", { 0.438973, 0.675333, 0.592645 } },
{ "outdoor_4pm_94", { 0.462937, 0.701414, 0.541948 } },
{ "outdoor_4pm_95", { 0.420282, 0.670209, 0.611705 } },
{ "outdoor_4pm_96", { 0.472186, 0.711448, 0.520464 } },
{ "outdoor_4pm_97", { 0.485385, 0.717787, 0.499182 } },
{ "outdoor_4pm_98", { 0.509036, 0.717529, 0.475431 } },
{ "outdoor_4pm_99", { 0.514050, 0.720187, 0.465922 } },
{ "outdoor_4pm_100", { 0.485349, 0.706190, 0.515492 } },
{ "outdoor_4pm_101", { 0.479269, 0.705274, 0.522389 } },
{ "outdoor_4pm_102", { 0.470442, 0.704659, 0.531170 } },
{ "outdoor_4pm_103", { 0.481626, 0.704988, 0.520604 } },
{ "outdoor_4pm_104", { 0.482182, 0.705056, 0.519996 } },
{ "outdoor_4pm_105", { 0.456659, 0.703180, 0.544977 } },
{ "outdoor_4pm_106", { 0.469659, 0.704565, 0.531986 } },
{ "outdoor_4pm_107", { 0.479740, 0.704356, 0.523194 } },
{ "outdoor_4pm_108", { 0.469974, 0.704838, 0.531345 } },
{ "outdoor_4pm_109", { 0.481519, 0.707100, 0.517831 } },
{ "outdoor_4pm_110", { 0.477206, 0.716844, 0.508339 } },
{ "outdoor_4pm_111", { 0.478528, 0.718201, 0.505172 } },
{ "outdoor_4pm_112", { 0.475911, 0.717047, 0.509266 } },
{ "outdoor_4pm_113", { 0.458843, 0.705219, 0.540489 } },
{ "outdoor_4pm_114", { 0.455002, 0.703388, 0.546094 } },
{ "outdoor_4pm_115", { 0.452447, 0.701573, 0.550533 } },
{ "outdoor_4pm_116", { 0.453753, 0.702691, 0.548028 } },
{ "outdoor_4pm_117", { 0.453838, 0.702563, 0.548121 } },
{ "outdoor_4pm_118", { 0.454121, 0.704049, 0.545976 } },
{ "outdoor_4pm_119", { 0.477024, 0.716929, 0.508391 } },
{ "outdoor_4pm_120", { 0.477490, 0.716873, 0.508031 } },
{ "outdoor_4pm_121", { 0.467303, 0.720589, 0.512230 } },
{ "outdoor_4pm_122", { 0.437140, 0.677434, 0.591601 } },
{ "outdoor_4pm_123", { 0.476845, 0.723806, 0.498721 } },
{ "outdoor_4pm_124", { 0.468545, 0.712034, 0.522947 } },
{ "outdoor_4pm_125", { 0.478852, 0.718336, 0.504673 } },
{ "outdoor_4pm_126", { 0.473281, 0.710872, 0.520255 } },
{ "outdoor_4pm_127", { 0.511813, 0.736178, 0.442820 } },
{ "outdoor_4pm_128", { 0.485469, 0.706326, 0.515192 } },
{ "outdoor_4pm_129", { 0.478416, 0.716111, 0.508235 } },
{ "outdoor_4pm_130", { 0.485249, 0.708345, 0.512622 } },
{ "outdoor_4pm_131", { 0.488792, 0.712508, 0.503403 } },
{ "outdoor_4pm_132", { 0.490987, 0.707164, 0.508773 } },
{ "outdoor_4pm_133", { 0.492413, 0.713123, 0.498985 } },
{ "outdoor_4pm_134", { 0.490425, 0.713524, 0.500366 } },
{ "outdoor_4pm_135", { 0.493985, 0.717343, 0.491322 } },
{ "outdoor_4pm_136", { 0.504755, 0.718062, 0.479175 } },
{ "outdoor_4pm_137", { 0.509844, 0.729155, 0.456500 } },
{ "outdoor_4pm_138", { 0.478112, 0.714772, 0.510402 } },
{ "outdoor_4pm_139", { 0.467580, 0.704789, 0.533519 } },
{ "outdoor_4pm_140", { 0.465105, 0.704289, 0.536334 } },
{ "outdoor_4pm_141", { 0.455039, 0.703127, 0.546399 } },
{ "outdoor_4pm_142", { 0.468572, 0.704627, 0.532861 } },
{ "outdoor_4pm_143", { 0.473945, 0.704164, 0.528705 } },
{ "outdoor_4pm_144", { 0.510814, 0.714768, 0.477678 } },
{ "outdoor_4pm_146", { 0.527775, 0.717095, 0.455223 } },
{ "outdoor_4pm_147", { 0.522305, 0.716783, 0.461974 } },
{ "outdoor_4pm_148", { 0.520274, 0.715601, 0.466080 } },
{ "outdoor_4pm_149", { 0.509292, 0.716546, 0.476638 } },
{ "outdoor_4pm_150", { 0.516043, 0.708314, 0.481654 } },
{ "outdoor_4pm_151", { 0.509005, 0.698098, 0.503561 } },
{ "outdoor_4pm_152", { 0.508616, 0.716160, 0.477938 } },
{ "outdoor_4pm_159", { 0.492701, 0.717480, 0.492410 } },
{ "outdoor_4pm_160", { 0.490054, 0.718800, 0.493126 } },
{ "outdoor_4pm_163", { 0.512491, 0.721398, 0.465766 } },
{ "outdoor_4pm_164", { 0.474468, 0.757647, 0.448165 } },
{ "outdoor_4pm_165", { 0.508661, 0.743068, 0.434872 } },
{ "outdoor_4pm_166", { 0.502921, 0.751137, 0.427625 } },
{ "outdoor_4pm_167", { 0.500170, 0.746546, 0.438748 } },
{ "outdoor_4pm_168", { 0.506563, 0.743308, 0.436906 } },
{ "outdoor_4pm_172", { 0.500952, 0.751881, 0.428628 } },
{ "outdoor_noon_3", { 0.498342, 0.747395, 0.439382 } },
{ "outdoor_noon_4", { 0.499446, 0.746808, 0.439126 } },
{ "outdoor_noon_6", { 0.497764, 0.748033, 0.438951 } },
{ "outdoor_noon_7", { 0.515139, 0.727086, 0.453848 } },
{ "outdoor_noon_8", { 0.514509, 0.727172, 0.454424 } },
{ "outdoor_noon_9", { 0.519348, 0.732846, 0.439561 } },
{ "outdoor_noon_10", { 0.511002, 0.720897, 0.468171 } },
{ "outdoor_noon_11", { 0.511267, 0.721147, 0.467497 } },
{ "outdoor_noon_12", { 0.537003, 0.734871, 0.414237 } },
{ "outdoor_noon_15", { 0.514773, 0.726772, 0.454765 } },
{ "outdoor_noon_16", { 0.508060, 0.723096, 0.467982 } },
{ "outdoor_noon_17", { 0.508716, 0.725017, 0.464283 } },
{ "outdoor_noon_18", { 0.500850, 0.727889, 0.468325 } },
{ "outdoor_noon_19", { 0.501114, 0.728929, 0.466419 } },
{ "outdoor_noon_20", { 0.494277, 0.717563, 0.490708 } },
{ "outdoor_noon_21", { 0.486634, 0.709408, 0.509831 } },
{ "outdoor_noon_22", { 0.489519, 0.712763, 0.502335 } },
{ "outdoor_noon_23", { 0.488872, 0.714478, 0.500525 } },
{ "outdoor_noon_24", { 0.484953, 0.712524, 0.507080 } },
{ "outdoor_noon_25", { 0.484583, 0.706108, 0.516324 } },
{ "outdoor_noon_26", { 0.487357, 0.707912, 0.511217 } },
{ "outdoor_noon_27", { 0.486670, 0.709546, 0.509605 } },
{ "outdoor_noon_28", { 0.493599, 0.718183, 0.490483 } },
{ "outdoor_noon_29", { 0.492261, 0.716599, 0.494130 } },
{ "outdoor_noon_30", { 0.490566, 0.715495, 0.497405 } },
{ "outdoor_noon_31", { 0.494954, 0.720048, 0.486365 } },
{ "outdoor_noon_32", { 0.492979, 0.717928, 0.491479 } },
{ "outdoor_noon_33", { 0.470693, 0.705134, 0.530315 } },
{ "outdoor_noon_34", { 0.467604, 0.704555, 0.533805 } },
{ "outdoor_noon_35", { 0.478667, 0.705151, 0.523106 } },
{ "outdoor_noon_36", { 0.484695, 0.704661, 0.518193 } },
{ "outdoor_noon_37", { 0.487816, 0.706269, 0.513050 } },
{ "outdoor_noon_38", { 0.499074, 0.705519, 0.503157 } },
{ "outdoor_noon_39", { 0.519516, 0.707472, 0.479152 } },
{ "outdoor_noon_40", { 0.449186, 0.686552, 0.571732 } },
{ "outdoor_noon_41", { 0.430368, 0.676633, 0.597454 } },
{ "outdoor_noon_42", { 0.424678, 0.671322, 0.607433 } },
{ "outdoor_noon_43", { 0.548820, 0.703111, 0.452142 } },
{ "outdoor_noon_44", { 0.586117, 0.718542, 0.374385 } },
{ "outdoor_noon_45", { 0.665981, 0.695936, 0.268593 } },
{ "outdoor_noon_46", { 0.664839, 0.696072, 0.271057 } },
{ "outdoor_noon_47", { 0.665386, 0.696213, 0.269350 } },
{ "outdoor_noon_48", { 0.664615, 0.696464, 0.270601 } },
{ "outdoor_noon_49", { 0.659612, 0.699967, 0.273785 } },
{ "outdoor_noon_50", { 0.508162, 0.716429, 0.478017 } },
{ "outdoor_noon_51", { 0.507239, 0.718503, 0.475880 } },
{ "outdoor_noon_52", { 0.522890, 0.715099, 0.463917 } },
{ "outdoor_noon_53", { 0.523616, 0.715920, 0.461828 } },
{ "outdoor_noon_54", { 0.510659, 0.715800, 0.476297 } },
{ "outdoor_noon_55", { 0.505795, 0.718635, 0.477216 } },
{ "outdoor_noon_56", { 0.485965, 0.705179, 0.516295 } },
{ "outdoor_noon_57", { 0.670948, 0.692416, 0.265309 } },
{ "outdoor_noon_58", { 0.674826, 0.690076, 0.261544 } },
{ "outdoor_noon_59", { 0.705619, 0.666642, 0.240189 } },
{ "outdoor_noon_60", { 0.712805, 0.659776, 0.237915 } },
{ "outdoor_noon_61", { 0.706295, 0.667061, 0.237018 } },
{ "outdoor_noon_62", { 0.710279, 0.662453, 0.238034 } },
{ "outdoor_noon_63", { 0.708007, 0.665314, 0.236817 } },
{ "outdoor_noon_64", { 0.702679, 0.669382, 0.241184 } },
{ "outdoor_noon_65", { 0.653015, 0.709319, 0.265400 } },
{ "outdoor_noon_66", { 0.428774, 0.601358, 0.674183 } },
{ "outdoor_noon_67", { 0.509418, 0.717888, 0.474478 } },
{ "outdoor_noon_68", { 0.484917, 0.704977, 0.517555 } },
{ "outdoor_noon_69", { 0.484830, 0.705023, 0.517575 } },
{ "outdoor_noon_70", { 0.476144, 0.705777, 0.524561 } },
{ "outdoor_noon_71", { 0.478298, 0.715054, 0.509832 } },
{ "outdoor_noon_72", { 0.491506, 0.709717, 0.504701 } },
{ "outdoor_noon_73", { 0.503046, 0.703798, 0.501611 } },
{ "outdoor_noon_74", { 0.492454, 0.708314, 0.505747 } },
{ "outdoor_noon_75", { 0.664163, 0.697171, 0.269889 } },
{ "outdoor_noon_76", { 0.664839, 0.696696, 0.269451 } },
{ "outdoor_noon_77", { 0.514179, 0.716850, 0.470899 } },
{ "outdoor_noon_78", { 0.508519, 0.717075, 0.476668 } },
{ "outdoor_noon_79", { 0.505140, 0.725091, 0.468056 } },
{ "outdoor_noon_80", { 0.496130, 0.717959, 0.488252 } },
{ "outdoor_noon_81", { 0.510003, 0.723663, 0.464982 } },
{ "outdoor_noon_82", { 0.670651, 0.659239, 0.340045 } },
{ "outdoor_noon_83", { 0.623097, 0.711215, 0.325459 } },
{ "outdoor_noon_84", { 0.514936, 0.714087, 0.474257 } },
{ "outdoor_noon_85", { 0.486596, 0.701714, 0.520404 } },
{ "outdoor_noon_86", { 0.514334, 0.721129, 0.464147 } },
{ "outdoor_noon_87", { 0.514798, 0.721352, 0.463286 } },
{ "outdoor_noon_88", { 0.536237, 0.733198, 0.418175 } },
{ "outdoor_noon_89", { 0.524594, 0.728059, 0.441284 } },
{ "outdoor_noon_90", { 0.533018, 0.734542, 0.419927 } },
{ "outdoor_noon_91", { 0.513928, 0.721092, 0.464655 } },
{ "outdoor_noon_92", { 0.518653, 0.722339, 0.457412 } },
{ "outdoor_noon_93", { 0.515685, 0.721035, 0.462793 } },
{ "outdoor_noon_94", { 0.505481, 0.718051, 0.478426 } },
{ "outdoor_noon_95", { 0.468584, 0.704654, 0.532815 } },
{ "outdoor_noon_96", { 0.469690, 0.712292, 0.521566 } },
{ "outdoor_noon_97", { 0.465081, 0.707257, 0.532435 } },
{ "outdoor_noon_98", { 0.477756, 0.717194, 0.507328 } },
{ "outdoor_noon_99", { 0.483612, 0.717480, 0.501341 } },
{ "outdoor_noon_100", { 0.490939, 0.716730, 0.495254 } },
{ "outdoor_noon_101", { 0.457295, 0.703772, 0.543679 } },
{ "outdoor_noon_102", { 0.502907, 0.715352, 0.485135 } },
{ "outdoor_noon_103", { 0.430903, 0.688822, 0.582964 } },
{ "outdoor_noon_104", { 0.463959, 0.701670, 0.540742 } },
{ "outdoor_noon_105", { 0.474445, 0.705723, 0.526172 } },
{ "outdoor_noon_106", { 0.505980, 0.716901, 0.479622 } },
{ "outdoor_noon_107", { 0.413716, 0.673166, 0.612933 } },
{ "outdoor_noon_108", { 0.420153, 0.675541, 0.605901 } },
{ "outdoor_noon_109", { 0.483834, 0.707534, 0.515072 } },
{ "outdoor_noon_110", { 0.485869, 0.706173, 0.515026 } },
{ "outdoor_noon_111", { 0.544955, 0.717049, 0.434586 } },
{ "outdoor_noon_112", { 0.558684, 0.717011, 0.416854 } },
{ "outdoor_noon_113", { 0.544118, 0.738741, 0.397739 } },
{ "outdoor_noon_114", { 0.561788, 0.716858, 0.412927 } },
{ "outdoor_noon_115", { 0.560474, 0.719588, 0.409954 } },
{ "outdoor_noon_116", { 0.559378, 0.720284, 0.410228 } },
{ "outdoor_noon_117", { 0.557038, 0.717298, 0.418560 } },
{ "outdoor_noon_118", { 0.558348, 0.718387, 0.414930 } },
{ "outdoor_noon_119", { 0.563103, 0.718935, 0.407489 } },
{ "outdoor_noon_120", { 0.556792, 0.716420, 0.420386 } },
{ "outdoor_noon_121", { 0.556893, 0.713921, 0.424485 } },
{ "outdoor_noon_122", { 0.553942, 0.716192, 0.424520 } },
{ "outdoor_noon_129", { 0.479780, 0.720251, 0.501049 } },
{ "outdoor_noon_130", { 0.509292, 0.719182, 0.472651 } },
{ "outdoor_noon_131", { 0.489673, 0.714635, 0.499518 } },
{ "outdoor_noon_132", { 0.486536, 0.703732, 0.517729 } },
{ "outdoor_noon_133", { 0.524303, 0.714931, 0.462580 } },
{ "outdoor_noon_134", { 0.527283, 0.719107, 0.452611 } },
{ "outdoor_noon_135", { 0.538405, 0.718939, 0.439598 } },
{ "outdoor_noon_136", { 0.528367, 0.716753, 0.455075 } },
{ "outdoor_noon_137", { 0.522660, 0.716789, 0.461563 } },
{ "outdoor_noon_138", { 0.514998, 0.722502, 0.461267 } },
{ "outdoor_noon_139", { 0.632403, 0.688216, 0.355563 } },
{ "outdoor_noon_140", { 0.577231, 0.741510, 0.342006 } },
{ "outdoor_noon_142", { 0.505055, 0.713297, 0.485929 } },
{ "outdoor_noon_145", { 0.512784, 0.723047, 0.462877 } },
{ "outdoor_noon_146", { 0.514313, 0.725315, 0.457603 } },
{ "outdoor_noon_148", { 0.494932, 0.742956, 0.450620 } },
{ "outdoor_noon_150", { 0.495987, 0.727823, 0.473572 } },
{ "outdoor_noon_151", { 0.494743, 0.742749, 0.451169 } },
{ "outdoor_noon_152", { 0.497865, 0.747234, 0.440195 } },
{ "outdoor_noon_153", { 0.503974, 0.744658, 0.437601 } },
{ "outdoor_noon_155", { 0.505675, 0.737633, 0.447426 } },
{ "outdoor_noon_156", { 0.505737, 0.736509, 0.449204 } },
{ "outdoor_noon_157", { 0.503517, 0.733242, 0.456976 } },
{ "outdoor_noon_158", { 0.491605, 0.740400, 0.458401 } },
{ "outdoor_noon_161", { 0.511212, 0.743835, 0.430548 } },
{ "outdoor_noon_162", { 0.528954, 0.747557, 0.401705 } },
{ "outdoor_noon_164", { 0.488720, 0.737575, 0.465979 } },
{ "outdoor_noon_165", { 0.506440, 0.738599, 0.444960 } },
{ "outdoor_noon_166", { 0.508424, 0.739787, 0.440704 } },
{ "outdoor_noon_167", { 0.503600, 0.738302, 0.448661 } },
{ "outdoor_noon_177", { 0.554260, 0.744934, 0.371309 } },
{ "outdoor_noon_182", { 0.558077, 0.743322, 0.368813 } },
{ "outdoor_noon_187", { 0.509556, 0.741397, 0.436673 } },
{ "outdoor_noon_188", { 0.503508, 0.737743, 0.449682 } },
{ "outdoor_noon_189", { 0.494739, 0.742687, 0.451275 } },
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

#import "BaseView.h"
#import <memory>
#import <iostream>
#import <regex>
#import <vector>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import "ImageLayer.h"
#import "HistogramLayer.h"
#import "Mmap.h"
#import "Util.h"
#import "Mat.h"
#import "ColorUtil.h"
#import "MyTime.h"
#import "MainView.h"
#import "HistogramView.h"
#import "ColorChecker.h"
#import "MDCDevice.h"
#import "IOServiceMatcher.h"
#import "IOServiceWatcher.h"

using namespace CFAViewer;
using namespace MetalTypes;
using namespace ImageLayerTypes;
using namespace ColorUtil;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

@interface AppDelegate : NSObject <NSApplicationDelegate, MainViewDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
    
    IBOutlet NSSwitch* _liveSwitch;
    
    IBOutlet NSButton* _colorCheckersEnabledButton;
    IBOutlet NSButton* _resetColorCheckersButton;
    
    IBOutlet HistogramView* _inputHistogramView;
    IBOutlet HistogramView* _outputHistogramView;
    IBOutlet NSTextField* _colorMatrixTextField;
    
    IBOutlet NSButton* _debayerLMMSEGammaEnabledButton;
    
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
    
    struct {
        std::mutex lock; // Protects this struct
        
        ColorMatrix colorMatrix;
        Mmap imageData;
        Image image;
        
        Color_CamRaw_D50 sample_CamRaw_D50;
        Color_XYZ_D50 sample_XYZ_D50;
        Color_SRGB_D65 sample_SRGB_D65;
    } _state;
}

- (void)awakeFromNib {
    constexpr size_t ImageWidth = 2304;
    constexpr size_t ImageHeight = 1296;
    
    _colorCheckerCircleRadius = 10;
    [_mainView setColorCheckerCircleRadius:_colorCheckerCircleRadius];
    
    auto lock = std::unique_lock(_state.lock);
        _state.colorMatrix = {1., 0., 0., 0., 1., 0., 0., 0., 1.};
        _state.imageData = Mmap("/Users/dave/repos/MotionDetectorCamera/Tools/CFAViewer/img.cfa");
        
        _state.image = {
            .width = ImageWidth,
            .height = ImageHeight,
            .pixels = (MetalTypes::ImagePixel*)_state.imageData.data(),
        };
        
        [[_mainView imageLayer] setImage:_state.image];
    lock.unlock();
    
    __weak auto weakSelf = self;
    [[_mainView imageLayer] setDataChangedHandler:^(ImageLayer*) {
        [weakSelf _updateHistograms];
        [weakSelf _updateSampleColors];
    }];
    
    [self _resetColorMatrix];
    
    [self _setDebayerLMMSEGammaEnabled:true];
    
    auto points = [self _prefsColorCheckerPositions];
    if (!points.empty()) {
        [_mainView setColorCheckerPositions:points];
    }
    
    [self _setMDCDevice:MDCDevice()];
    _serviceWatcher = IOServiceMatcher(dispatch_get_main_queue(), MDCDevice::MatchingDictionary(), ^(SendRight&& service) {
        [weakSelf _handleUSBDevice:std::move(service)];
    });
}

#pragma mark - MDCDevice

- (void)_handleUSBDevice:(SendRight&&)service {
    MDCDevice device;
    try {
        device = std::move(service);
    } catch (...) {
        NSLog(@"Failed to create MDCDevice (it probably needs to be bootloaded)");
    }
    [self _setMDCDevice:std::move(device)];
}

- (void)_setMDCDevice:(MDCDevice&&)device {
    _mdcDevice = std::move(device);
    // Watch the MDCDevice so we know when it's terminated
    if (_mdcDevice) {
        __weak auto weakSelf = self;
        _mdcDeviceWatcher = _mdcDevice.createWatcher(dispatch_get_main_queue(), ^(uint32_t msgType, void* msgArg) {
            [weakSelf _handleMDCDeviceNotificationType:msgType arg:msgArg];
        });
    }
    
    [_liveSwitch setState:NSControlStateValueOff];
    [_liveSwitch setEnabled:_mdcDevice];
}

- (void)_handleMDCDeviceNotificationType:(uint32_t)msgType arg:(void*)msgArg {
    if (msgType == kIOMessageServiceIsTerminated) {
        [self _setMDCDevice:MDCDevice()];
    }
}

#pragma mark - Color Matrix

- (void)controlTextDidChange:(NSNotification*)note {
    if ([note object] == _colorMatrixTextField) {
        [self _updateColorMatrixFromString:[[_colorMatrixTextField stringValue] UTF8String]];
    }
}

- (void)_resetColorMatrix {
    auto lock = std::unique_lock(_state.lock);
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
    
    auto lock = std::unique_lock(_state.lock);
    [self _updateColorMatrix:vals.data()];
}

// _state.lock must be held
- (void)_updateColorMatrix:(const ColorMatrix&)colorMatrix {
    _state.colorMatrix = colorMatrix;
    
    [[_mainView imageLayer] setColorMatrix:colorMatrix];
    
    [_colorMatrixTextField setStringValue:[NSString stringWithFormat:
        @"%f %f %f\n"
        @"%f %f %f\n"
        @"%f %f %f\n",
        _state.colorMatrix[0], _state.colorMatrix[1], _state.colorMatrix[2],
        _state.colorMatrix[3], _state.colorMatrix[4], _state.colorMatrix[5],
        _state.colorMatrix[6], _state.colorMatrix[7], _state.colorMatrix[8]
    ]];
}

#pragma mark - Histograms

- (void)_updateHistograms {
    [[_inputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] inputHistogram]];
    [[_outputHistogramView histogramLayer] setHistogram:[[_mainView imageLayer] outputHistogram]];
}

#pragma mark - Sample

- (void)_updateSampleColors {
    auto lock = std::unique_lock(_state.lock);
    _state.sample_CamRaw_D50 = [[_mainView imageLayer] sample_CamRaw_D50];
    _state.sample_XYZ_D50 = [[_mainView imageLayer] sample_XYZ_D50];
    _state.sample_SRGB_D65 = [[_mainView imageLayer] sample_SRGB_D65];
    
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        [self _updateSampleColorsText];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

- (void)_updateSampleColorsText {
    auto lock = std::unique_lock(_state.lock);
    [_colorText_cameraRaw setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _state.sample_CamRaw_D50[0], _state.sample_CamRaw_D50[1], _state.sample_CamRaw_D50[2]]];
    [_colorText_XYZ_D50 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _state.sample_XYZ_D50[0], _state.sample_XYZ_D50[1], _state.sample_XYZ_D50[2]]];
    [_colorText_SRGB_D65 setStringValue:
        [NSString stringWithFormat:@"%f %f %f", _state.sample_SRGB_D65[0], _state.sample_SRGB_D65[1], _state.sample_SRGB_D65[2]]];
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

- (IBAction)_liveSwitchAction:(id)sender {
    NSLog(@"_liveSwitchAction");
}

- (IBAction)_identityButtonAction:(id)sender {
    [self _setColorCheckersEnabled:false];
    [self _resetColorMatrix];
}

- (void)_setColorCheckersEnabled:(bool)en {
    _colorCheckersEnabled = en;
    [_colorCheckersEnabledButton setState:(en ? NSControlStateValueOn : NSControlStateValueOff)];
    [_colorMatrixTextField setEditable:!_colorCheckersEnabled];
    [_mainView setColorCheckersVisible:_colorCheckersEnabled];
    [_resetColorCheckersButton setHidden:!_colorCheckersEnabled];
    
    if (_colorCheckersEnabled) {
        [self mainViewColorCheckerPositionsChanged:nil];
    }
}

- (IBAction)_colorCheckersCheckboxAction:(id)sender {
    [self _setColorCheckersEnabled:([_colorCheckersEnabledButton state]==NSControlStateValueOn)];
}

- (IBAction)_resetColorCheckersButtonAction:(id)sender {
    [_mainView resetColorCheckerPositions];
    [self mainViewColorCheckerPositionsChanged:nil];
}

- (IBAction)_debayerOptionsAction:(id)sender {
    [self _setDebayerLMMSEGammaEnabled:([_debayerLMMSEGammaEnabledButton state]==NSControlStateValueOn)];
}

- (void)_setDebayerLMMSEGammaEnabled:(bool)en {
    [_debayerLMMSEGammaEnabledButton setState:(en ? NSControlStateValueOn : NSControlStateValueOff)];
    [[_mainView imageLayer] setDebayerLMMSEGammaEnabled:en];
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
}

- (void)mainViewColorCheckerPositionsChanged:(MainView*)v {
    auto lock = std::unique_lock(_state.lock);
    auto points = [_mainView colorCheckerPositions];
    assert(points.size() == ColorChecker::Count);
    
    Mat<double,ColorChecker::Count,3> A; // Colors that we have
    size_t i = 0;
    for (const CGPoint& p : points) {
        Color_CamRaw_D50 c = sampleImageCircle(_state.image,
            round(p.x*_state.image.width),
            round(p.y*_state.image.height),
            _colorCheckerCircleRadius);
        A[i+0] = c[0];
        A[i+1] = c[1];
        A[i+2] = c[2];
        i += 3;
    }
    
    Mat<double,ColorChecker::Count,3> b; // Colors that we want
    i = 0;
    for (Color_SRGB_D65 c : ColorChecker::Colors) {
        // Convert the color from SRGB -> XYZ -> XYY
        Color_XYZ_D50 cxyy = ColorUtil::XYYFromXYZ(XYZFromSRGB(c));
//        cxyy[2] /= 3; // Adjust luminance
        
        const Color_XYZ_D50 cxyz = ColorUtil::XYZFromXYY(cxyy);
        b[i+0] = cxyz[0];
        b[i+1] = cxyz[1];
        b[i+2] = cxyz[2];
        i += 3;
    }
    
    // Calculate the color matrix (x = (At*A)^-1 * At * b)
    auto x = (A.pinv() * b).trans();
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

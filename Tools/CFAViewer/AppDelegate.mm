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
#import "Assert.h"
#import "ImagePipelineTypes.h"
#import "Color.h"
#import "ImagePipelineManager.h"
#import "PixelSampler.h"
#import "Img.h"
#import "ChecksumFletcher32.h"
#import "ELF32Binary.h"
using namespace CFAViewer;
using namespace MetalUtil;
using namespace ImagePipeline;
using namespace Toastbox;
using namespace std::chrono;
namespace fs = std::filesystem;

static NSString* const ColorCheckerPositionsKey = @"ColorCheckerPositions";

using ImagePaths = std::vector<fs::path>;
using ImagePathsIter = ImagePaths::iterator;

struct ExposureSettings {
    bool autoExposure = false;
    MDCDevice::ImgExposure exposure;
};

@interface AppDelegate : NSObject <NSApplicationDelegate, MainViewDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MainView* _mainView;
    
    IBOutlet NSSwitch* _streamImagesSwitch;
    
    IBOutlet NSButton* _autoExposureCheckbox;
    
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
    
    ExposureSettings _exposureSettings;
    
    bool _colorCheckersEnabled;
    float _colorCheckerCircleRadius;
    
//    std::optional<IOServiceMatcher> _serviceAppearWatcher;
    std::optional<IOServiceWatcher> _serviceDisappearWatcher;
    std::optional<MDCDevice> _mdcDevice;
    
    ImagePipelineManager* _imagePipelineManager;
    
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        bool running = false;
        bool cancel = false;
        ExposureSettings exposureSettings;
        Img::Pixel pixels[2200*2200];
        uint32_t width = Img::PixelWidth;
        uint32_t height = Img::PixelHeight;
    } _streamImagesThread;
    
    struct {
        Img::Pixel pixels[2200*2200];
        Pipeline::RawImage img = {
            .cfaDesc = {
                CFAColor::Green, CFAColor::Red,
                CFAColor::Blue, CFAColor::Green,
            },
            .width = Img::PixelWidth,
            .height = Img::PixelHeight,
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
//    [self _loadImages:{"/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Indoor-Night2-ColorChecker"}];
    [self _loadImages:{"/Users/dave/Desktop/Old/2021:4:4/C5ImageSets/Outdoor-5pm-ColorChecker"}];
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
    
    [self _setExposureSettings:{
        .autoExposure = true,
    }];
    [self _setMDCDevice:std::nullopt];
    
    [NSThread detachNewThreadWithBlock:^{
        [self _threadHandleNewMDCDevices];
    }];
    
//    static NSDictionary* MatchingDictionary() {
//        NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
//        match[@kIOPropertyMatchKey] = @{
//            @"idVendor": @1155,
//            @"idProduct": @57105,
//        };
//        return match;
//    }
//    
//    NSDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
//    _serviceAppearWatcher = IOServiceMatcher(dispatch_get_main_queue(), match,
//        ^(SendRight&& service) {
//            [weakSelf _handleNewUSBDevice:std::move(service)];
//        });
//    
//    [NSThread detachNewThreadWithBlock:^{
//        [self _threadReadInputCommands];
//    }];
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
    
    const Mmap<uint8_t> imgData(path);
    
    // Support 2 different filetypes:
    // (1) solely raw pixel data
    if (imgData.len() == Img::PixelLen) {
        // Copy the image data into _rawImage
        memcpy(_rawImage.pixels, imgData.data(), Img::PixelLen);
    
    // (2) header + raw pixel data + checksum
    } else if (imgData.len() == Img::Len) {
        // Copy the image data into _rawImage
        memcpy(_rawImage.pixels, imgData.data()+Img::HeaderLen, Img::PixelLen);
        
        const uint32_t checksumExpected = ChecksumFletcher32(imgData.data(), Img::ChecksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, imgData.data()+Img::ChecksumOffset, sizeof(checksumGot));
        assert(checksumExpected == checksumGot);
    
    // invaid image
    } else {
        abort();
    }
    
    [[_mainView imageLayer] setNeedsDisplay];
    
    // Reset the illuminant so auto-white-balance is enabled again
    _imagePipelineManager->options.illum = std::nullopt;
    // Reset the sample rect
    _imagePipelineManager->options.sampleRect = {};
//    // Reset the image scale / position
//    [_mainView reset];
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

static void _nop(void* ctx, io_iterator_t iter) {}

static void _configureDevice(MDCDevice& dev) {
    {
        const char* ICEBinPath = "/Users/dave/repos/MDC/Code/ICE40/ICEAppImgCaptureSTM/Synth/Top.bin";
        Mmap mmap(ICEBinPath);
        
        // Write the ICE40 binary
        dev.iceWrite(mmap.data(), mmap.len());
    }
    
    {
        const char* STMBinPath = "/Users/dave/repos/MDC/Code/STM32/STApp/Release/STApp.elf";
        ELF32Binary bin(STMBinPath);
        auto sections = bin.sections();
        
        uint32_t entryPointAddr = bin.entryPointAddr();
        if (!entryPointAddr) throw std::runtime_error("no entry point");
        
        for (const auto& s : sections) {
            // Ignore NOBITS sections (NOBITS = "occupies no space in the file"),
            if (s.type == ELF32Binary::SectionTypes::NOBITS) continue;
            // Ignore non-ALLOC sections (ALLOC = "occupies memory during process execution")
            if (!(s.flags & ELF32Binary::SectionFlags::ALLOC)) continue;
            const void*const data = bin.sectionData(s);
            const size_t dataLen = s.size;
            const uint32_t dataAddr = s.addr;
            if (!dataLen) continue; // Ignore sections with zero length
            
            dev.stmWrite(dataAddr, data, dataLen);
        }
        
        // Reset the device, triggering it to load the program we just wrote
        dev.stmReset(entryPointAddr);
    }
}

- (void)_threadHandleNewMDCDevices {
    IONotificationPortRef p = IONotificationPortCreate(kIOMasterPortDefault);
    if (!p) throw Toastbox::RuntimeError("IONotificationPortCreate returned null");
    Defer(IONotificationPortDestroy(p));
    
    SendRight serviceIter;
    {
        io_iterator_t iter = MACH_PORT_NULL;
        kern_return_t kr = IOServiceAddMatchingNotification(p, kIOMatchedNotification,
            IOServiceMatching(kIOUSBDeviceClassName), _nop, nullptr, &iter);
        if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddMatchingNotification failed: 0x%x", kr);
        serviceIter = SendRight(SendRight::NoRetain, iter);
    }
    
    CFRunLoopSourceRef rls = IONotificationPortGetRunLoopSource(p);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
    
    std::set<std::string> configuredDevices;
    for (;;) {
        // Drain all services from the iterator
        for (;;) {
            SendRight service(SendRight::NoRetain, IOIteratorNext(serviceIter));
            if (!service) break;
            
            try {
                USBDevice dev(service);
                if (!MDCDevice::USBDeviceMatches(dev)) continue;
                
                __block MDCDevice mdc(std::move(dev));
                
                const STM::Status status = mdc.statusGet();
                switch (status.mode) {
                case STM::Status::Modes::STMLoader:
                    _configureDevice(mdc);
                    configuredDevices.insert(mdc.serial());
                    break;
                
                case STM::Status::Modes::STMApp:
                    // If we previously configured this device, this device is ready!
                    if (configuredDevices.find(mdc.serial()) != configuredDevices.end()) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self _setMDCDevice:std::move(mdc)];
                        });
                        
                        configuredDevices.erase(mdc.serial());
                        
                    // If we didn't previously configure this device, trigger the bootloader so we can configure it
                    } else {
                        mdc.bootloaderInvoke();
                    }
                    break;
                
                default:
                    configuredDevices.erase(mdc.serial());
                    mdc.bootloaderInvoke();
                    break;
                }
            
            } catch (const std::exception& e) {
                // Ignore failures to create USBDevice
                printf("Configure MDCDevice failed: %s\n", e.what());
            }
        }
        
        // Wait for matching services to appear
        CFRunLoopRunResult r = CFRunLoopRunInMode(kCFRunLoopDefaultMode, INFINITY, true);
        assert(r == kCFRunLoopRunHandledSource);
    }
}

//- (void)_handleNewUSBDevice:(SendRight&&)service {
//    try {
//        USBDevice dev(service);
//        if (!MDCDevice::USBDeviceMatches(dev)) return;
//        
//        MDCDevice mdc(std::move(dev));
//        
//        const STM::Status status = mdc.statusGet();
//        // Return the MDC device to the bootloader, if it's not in the bootloader currently
//        if (status.mode != STM::Status::Mode::STMLoader) {
//            mdc.bootloaderInvoke();
//            return;
//        }
//        
//        // 
//        
//        [self _setMDCDevice:std::move(mdc)];
//    
//    } catch (const std::exception& e) {
//        // Ignore failures to create USBDevice
//    }
//}

- (void)_setMDCDevice:(std::optional<MDCDevice>)dev {
    // Stop streaming, set switch to off, and enable or disable switch
    [self _streamImagesStop];
    
    _mdcDevice = std::move(dev);
    [_streamImagesSwitch setEnabled:(bool)_mdcDevice];
    [_streamImagesSwitch setState:NSControlStateValueOff];
    
    if (_mdcDevice) {
        __weak auto weakSelf = self;
        _serviceDisappearWatcher = IOServiceWatcher(_mdcDevice->usbDevice().service(), dispatch_get_main_queue(),
            ^(uint32_t msgType, void* msgArg) {
                [weakSelf _handleMDCDeviceNotificationType:msgType arg:msgArg];
            });
        
        [self _setStreamImagesEnabled:true];
    } else {
        _serviceDisappearWatcher = std::nullopt;
    }
}

- (void)_handleMDCDeviceNotificationType:(uint32_t)msgType arg:(void*)msgArg {
    if (msgType == kIOMessageServiceIsTerminated) {
        [self _setMDCDevice:std::nullopt];
    }
}

- (void)_handleStreamImage {
    assert([NSThread isMainThread]);
    
    // Copy the image from `_streamImagesThread` into `_rawImage`
    auto lock = std::unique_lock(_streamImagesThread.lock);
        _rawImage.img.width = _streamImagesThread.width;
        _rawImage.img.height = _streamImagesThread.height;
        const size_t pixelCount = _streamImagesThread.width*_streamImagesThread.height;
        std::copy(_streamImagesThread.pixels, _streamImagesThread.pixels+pixelCount, _rawImage.pixels);
    lock.unlock();
    
    [[_mainView imageLayer] setNeedsDisplay];
}

static float intTimeClamp(float t) {
    return std::clamp(t, 10.f, (float)Img::CoarseIntTimeMax);
}

- (void)_threadStreamImages {
    assert(_mdcDevice);
    MDCDevice& dev = *_mdcDevice;
    
    Defer(
        // Notify that our thread has exited
        _streamImagesThread.lock.lock();
            _streamImagesThread.running = false;
            _streamImagesThread.signal.notify_all();
        _streamImagesThread.lock.unlock();
    );
    
//    NSString* dirName = [NSString stringWithFormat:@"CFAViewerSession-%f", [NSDate timeIntervalSinceReferenceDate]];
//    NSString* dirPath = [NSString stringWithFormat:@"/Users/dave/Desktop/%@", dirName];
//    assert([[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:false attributes:nil error:nil]);
    
    try {
//        float intTime = .5;
//        const size_t tmpPixelsCap = std::size(_streamImagesThread.pixels);
//        auto tmpPixels = std::make_unique<MDC::Pixel[]>(tmpPixelsCap);
        
        struct {
            bool en = false;
            float intTime = 1000;
        } autoExposure;
        
        MDCDevice::ImgExposure exposure;
        MDCDevice::ImgExposure lastExposure;
        for (uint32_t i=0;; i++) {
            // Set the image exposure if it changed
            const bool setExp = memcmp(&exposure, &lastExposure, sizeof(exposure));
            if (setExp) {
                dev.imgSetExposure(exposure);
                lastExposure = exposure;
                printf("Set exposure\n");
//                usleep(100000);
            }
            
            constexpr uint8_t DstBlock = 0; // Always save to RAM block 0
            const uint8_t skipCount = (setExp ? 1 : 0); // Skip one image if we set the exposure, so that the image we receive has the exposure applied
            const STM::ImgCaptureStats imgStats = dev.imgCapture(DstBlock, skipCount);
            if (imgStats.len != Img::Len) {
                throw Toastbox::RuntimeError("invalid image length (expected: %ju, got: %ju)", (uintmax_t)Img::Len, (uintmax_t)imgStats.len);
            }
            
            std::unique_ptr<uint8_t[]> img = dev.imgReadout();
            
//            // Capture an image, timing-out after 1s so we can check the device status,
//            // in case it reports a streaming error
//            const MDC::ImgHeader pixStatus = dev.imgCapture(tmpPixels.get(), tmpPixelsCap, 1000ms);
//            const size_t pixelCount = pixStatus.width*pixStatus.height;
            
            {
                auto lock = std::unique_lock(_streamImagesThread.lock);
                
                // Check if we've been cancelled
                if (_streamImagesThread.cancel) break;
                
                // Copy the image into the persistent buffer
                memcpy(_streamImagesThread.pixels, img.get()+Img::HeaderLen, Img::PixelLen);
                
                // While we have the lock, copy the exposure settings
                autoExposure.en = _streamImagesThread.exposureSettings.autoExposure;
                if (!autoExposure.en) {
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
            if (autoExposure.en) {
                const uint32_t highlightCount = imgStats.highlightCount*Img::StatsSubsampleFactor;
                const uint32_t shadowCount = imgStats.shadowCount*Img::StatsSubsampleFactor;
                const float highlightFraction = (float)std::max((uint32_t)1,highlightCount)/Img::PixelCount;
                const float shadowFraction = (float)std::max((uint32_t)1,shadowCount)/Img::PixelCount;
                printf("Highlight fraction: %f\nShadow fraction: %f\n\n", highlightFraction, shadowFraction);
//                printf("H/L: %f\n\n", highlightFraction/shadowFraction);
                
                CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
                    [weakSelf _updateAutoExposureUI:exposure];
                });
                CFRunLoopWakeUp(CFRunLoopGetMain());
                
                constexpr float ShadowThreshold = 2;
                constexpr float HighlightThreshold = 10;
                constexpr float LogBase = 8192;
                const float shadowBalance = shadowFraction/highlightFraction;
                const float highlightBalance = highlightFraction/shadowFraction;
                
                if (shadowBalance >= ShadowThreshold) {
                    // Increase exposure
                    const float adjustment = 1.f+(std::log(shadowBalance)/std::log(LogBase));
//                    const float adjustment = std::clamp(std::log10(shadowBalance), 1.01f, 2.f);
                    printf("Increase exposure (balance: %f, adjustment: %f)\n", shadowBalance, adjustment);
                    autoExposure.intTime *= adjustment;
                    
                } else if (highlightBalance >= HighlightThreshold) {
//                    printf("Balance: %f\n\n", highlightBalance);
                    
                    // Decrease exposure
                    const float adjustment = 1.f+(std::log(highlightBalance)/std::log(LogBase));
//                    const float adjustment = std::clamp(std::log10(highlightBalance), 1.01f, 2.f);
                    printf("Decrease exposure (balance: %f, adjustment: %f)\n", highlightBalance, adjustment);
                    autoExposure.intTime /= adjustment;
                }
                
                autoExposure.intTime = std::clamp(autoExposure.intTime, 10.f, (float)Img::CoarseIntTimeMax);
                exposure.coarseIntTime = std::round(autoExposure.intTime);
                
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
    //                    mdc.pixI2CWrite(0x3012, intTime*16384);
    //                    mdc.pixI2CWrite(0x3060, gain*63);
    //                }
    //            }
                
                
                
//                const float ShadowAdjustThreshold = 0.1;
//                const float HighlightAdjustThreshold = 0.1;
//                const float AdjustDelta = 1.1;
//                if (shadowFraction > ShadowAdjustThreshold) {
//                    // Increase exposure
//                    float intTime = intTimeClamp(exposure.coarseIntTime);
//                    intTime *= AdjustDelta;
//                    intTime = intTimeClamp(intTime);
//                    exposure.coarseIntTime = std::round(intTime);
//                    
//                    
//                    std::clamp(t, 10.f, (float)Img::CoarseIntTimeMax);
//                
//                } else if (highlightFraction > HighlightAdjustThreshold) {
//                    // Decrease exposure
//                    exposure.coarseIntTime = std::max(10.f, (float)exposure.coarseIntTime)/AdjustDelta;
//                }
//                
//                intTime = std::clamp(intTime, 0.f, 1.f);
//                const float gain = intTime/3;
//                
//                if (updateIntTime) {
//                    device.pixI2CWrite(0x3012, intTime*16384);
//                    device.pixI2CWrite(0x3060, gain*63);
//                }
            }
        }
    
    } catch (const std::exception& e) {
        printf("Streaming failed: %s\n", e.what());
        
//        PixState pixState = PixState::Idle;
//        try {
//            pixState = mdc.pixStatus().state;
//        } catch (const std::exception& e) {
//            printf("pixStatus() failed: %s\n", e.what());
//        }
//        
//        if (pixState != PixState::Capturing) {
//            printf("pixStatus.state != PixState::Capturing\n");
//        }
    }
    
    // Notify that our thread has exited
    _streamImagesThread.lock.lock();
        _streamImagesThread.running = false;
        _streamImagesThread.signal.notify_all();
    _streamImagesThread.lock.unlock();
}

//- (void)_handleInputCommand:(std::vector<std::string>)cmdStrs {
//    MDCUtil::Args args;
//    try {
//        args = MDCUtil::ParseArgs(cmdStrs);
//    
//    } catch (const std::exception& e) {
//        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
//        MDCUtil::PrintUsage();
//        return;
//    }
//    
//    if (!_mdcDevice) {
//        fprintf(stderr, "No MDC device connected\n\n");
//        return;
//    }
//    
//    // Disable streaming before we talk to the device
//    bool oldStreamImagesEnabled = [self _streamImagesEnabled];
//    [self _setStreamImagesEnabled:false];
//    
//    try {
//        MDCUtil::Run(_mdcDevice, args);
//    
//    } catch (const std::exception& e) {
//        fprintf(stderr, "Error: %s\n\n", e.what());
//        return;
//    }
//    
//    // Re-enable streaming (if it was enabled previously)
//    if (oldStreamImagesEnabled) [self _setStreamImagesEnabled:true];
//}

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
        
        [NSThread detachNewThreadWithBlock:^{
            [self _threadStreamImages];
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
    [self _setExposureSettings:{
        .autoExposure = [_autoExposureCheckbox state]==NSControlStateValueOn,
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
    
    [_autoExposureCheckbox setState:(_exposureSettings.autoExposure ? NSControlStateValueOn : NSControlStateValueOff)];
    
    [_coarseIntegrationTimeSlider setDoubleValue:
        (double)settings.exposure.coarseIntTime/Img::CoarseIntTimeMax];
    [_coarseIntegrationTimeSlider setEnabled:!_exposureSettings.autoExposure];
    [_coarseIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)settings.exposure.coarseIntTime]];
    
    [_fineIntegrationTimeSlider setDoubleValue:
        (double)settings.exposure.fineIntTime/Img::FineIntTimeMax];
    [_fineIntegrationTimeSlider setEnabled:!_exposureSettings.autoExposure];
    [_fineIntegrationTimeLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)settings.exposure.fineIntTime]];
    
    [_analogGainSlider setDoubleValue:
        (double)settings.exposure.analogGain/Img::AnalogGainMax];
    [_analogGainSlider setEnabled:!_exposureSettings.autoExposure];
    [_analogGainLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)settings.exposure.analogGain]];
    
    auto lock = std::unique_lock(_streamImagesThread.lock);
    _streamImagesThread.exposureSettings = _exposureSettings;
}

- (void)_updateAutoExposureUI:(const MDCDevice::ImgExposure&)exposure {
    // Bail if auto exposure is disabled
    if (!_exposureSettings.autoExposure) return;
    [self _setExposureSettings:{
        .autoExposure = _exposureSettings.autoExposure,
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


#pragma mark - Drag & Drop
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

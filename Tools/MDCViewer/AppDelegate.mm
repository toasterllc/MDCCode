#import "MDCMainView.h"
#import <memory>
#import <vector>
#import <iostream>
#import "MDCImageLayer.h"
#import "STAppTypes.h"
#import "MDCDevice.h"
#import "MDCUtil.h"
using namespace MDCImageLayerTypes;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MDCMainView* _mainView;
    MDCDevice _device;
}

//static bool checkPixel(uint32_t x, uint32_t y, ImagePixel expected, ImagePixel got) {
//    if (got != expected) {
//        printf("Pixel {%5ju,%5ju}: expected=%03jx, got=%03jx\n",
//            (uintmax_t)x, (uintmax_t)y, (uintmax_t)expected, (uintmax_t)got);
//        return false;
//    }
//    return true;
//}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
//    Mmap imageData("/Users/dave/repos/MotionDetectorCamera/Tools/cfa2dng/me.cfa");
//    Mmap imageData("/Users/dave/repos/MotionDetectorCamera/Tools/cfa2dng/colorbars.cfa");
//    Mmap imageData("/Users/dave/Desktop/colorbars.cfa");
//    Mmap imageData("/Users/dave/Desktop/colorchecker.cfa");
//    Mmap imageData("/Users/dave/repos/ImageProcessing/PureColor.cfa");
//    constexpr size_t ImageWidth = 2304;
//    constexpr size_t ImageHeight = 1296;
//    Image image = {
//        .width = ImageWidth,
//        .height = ImageHeight,
//        .pixels = (ImagePixel*)imageData.data(),
//    };
//    [[_mainView layer] updateImage:image];
    
    std::vector<MDCDevice> devices = MDCDevice::FindDevices();
    if (devices.empty()) throw std::runtime_error("no matching MDC devices");
    if (devices.size() > 1) throw std::runtime_error("too many matching MDC devices");
    _device = devices[0];
    
    [NSThread detachNewThreadWithBlock:^{
        [self _threadStreamImages];
    }];
}

//  Row0    G1  R  G1  R
//  Row1    B   G2 B   G2
//  Row2    G1  R  G1  R
//  Row3    B   G2 B   G2

constexpr size_t ImageWidth = 2304;
constexpr size_t ImageHeight = 1296;

static double avgChannel(const STApp::Pixel* pixels, uint8_t phaseX, uint8_t phaseY) {
    uint64_t total = 0;
    uint64_t count = 0;
    for (size_t y=phaseY; y<ImageHeight; y+=2) {
        for (size_t x=phaseX; x<ImageWidth; x+=2) {
            total += pixels[(y*ImageWidth)+x];
            count++;
        }
    }
    return (double)total/count;
}

static double avgG1(const STApp::Pixel* pixels) { return avgChannel(pixels, 0, 0); }
static double avgB(const STApp::Pixel* pixels)  { return avgChannel(pixels, 0, 1); }
static double avgR(const STApp::Pixel* pixels)  { return avgChannel(pixels, 1, 0); }
static double avgG2(const STApp::Pixel* pixels) { return avgChannel(pixels, 1, 1); }

- (void)_threadStreamImages {
    using namespace STApp;
    
    MDCImageLayer* layer = [_mainView layer];
    
    // Reset the device to put it back in a pre-defined state
    _device.reset();
    
    // Configure image sensor
    MDCUtil::_PixReset(MDCUtil::Args(), _device);
    MDCUtil::_PixConfig(MDCUtil::Args(), _device);
    _device.pixI2CWrite(0x301E, 0); // data pedestal=0
    
    const PixStatus pixStatus = _device.pixStatus();
    const size_t pixelCount = pixStatus.width*pixStatus.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    
//    uint8_t phaseX = 0;
//    uint8_t phaseY = 0;
//    assert(pixelCount == ImageWidth*ImageHeight);
//    memset(pixels.get(), 0, pixelCount);
//    for (size_t y=phaseY; y<ImageHeight; y+=2) {
//        for (size_t x=phaseX; x<ImageWidth; x+=2) {
//            pixels[(y*ImageWidth)+x] = 12;
//        }
//    }
//    printf("r:%f g1:%f g2:%f b:%f\n", avgR(pixels.get()), avgG1(pixels.get()), avgG2(pixels.get()), avgB(pixels.get()));
//    exit(0);
    
    for (uint16_t coarseIntTime=0; coarseIntTime<130; coarseIntTime+=1) {
        try {
            // Stop streaming (by resetting the STM32) so that we can set the pix integration time
            _device.reset();
            
            // Set integration time
            _device.pixI2CWrite(0x3012, coarseIntTime);
            _device.pixStartStream();
            
            // Throw away some images after changing the integration time
            for (int i=0; i<8; i++) {
                _device.pixReadImage(pixels.get(), pixelCount, 1000);
            }
            
            // Read an image, timing-out after 1s so we can check the device status,
            // in case it reports a streaming error
            _device.pixReadImage(pixels.get(), pixelCount, 1000);
            
            printf("%ju\t%f\t%f\t%f\t%f\n",
                (uintmax_t)coarseIntTime, avgR(pixels.get()), avgG1(pixels.get()), avgG2(pixels.get()), avgB(pixels.get()));
            
            Image image = {
                .width = pixStatus.width,
                .height = pixStatus.height,
                .pixels = pixels.get(),
            };
            [layer updateImage:image];
        
        } catch (...) {
            if (_device.pixStatus().state != PixState::Streaming) {
                printf("pixStatus.state != PixState::Streaming\n");
                break;
            }
        }
    }
}

@end

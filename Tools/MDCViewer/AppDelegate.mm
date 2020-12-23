#import "MDCMainView.h"
#import <memory>
#import "MDCImageLayer.h"
#import "STAppTypes.h"
#import "MDCDevice.h"
#import <iostream>
#import "MDCUtil.h"
using namespace MDCImageLayerTypes;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MDCMainView* _mainView;
    MDCDevice _device;
    struct {
        std::mutex lock; // Protects this struct
        std::condition_variable signal;
        bool streamRunning = false;
        bool streamCancel = false;
    } _state;
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
        [self _threadControl];
    }];
}

- (void)_threadControl {
    for (;;) {
        // Kick off a new streaming thread
        _state.lock.lock();
            _state.streamRunning = true;
            _state.streamCancel = false;
            _state.signal.notify_all();
        _state.lock.unlock();
        
        [NSThread detachNewThreadWithBlock:^{
            [self _threadStreamImages];
        }];
        
        // Read arguments from stdin, repeating until they're valid
        MDCUtil::Args args;
        for (;;) {
            std::string line;
            std::getline(std::cin, line);
            
            std::vector<std::string> argStrs;
            std::stringstream argStream(line);
            std::string argStr;
            while (std::getline(argStream, argStr, ' ')) {
                if (!argStr.empty()) argStrs.push_back(argStr);
            }
            
            // Parse arguments
            try {
                args = MDCUtil::ParseArgs(argStrs);
                break;
            
            } catch (const std::exception& e) {
                fprintf(stderr, "Bad arguments: %s\n\n", e.what());
                MDCUtil::PrintUsage();
            }
        }
        
        // Cancel streaming and wait for it to stop
        for (;;) {
            auto lock = std::unique_lock(_state.lock);
            _state.streamCancel = true;
            if (!_state.streamRunning) break;
            _state.signal.wait(lock);
        }
        
        try {
            MDCUtil::Run(_device, args);
        
        } catch (const std::exception& e) {
            fprintf(stderr, "Error: %s\n\n", e.what());
            continue;
        }
    }
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
    
    const PixStatus pixStatus = _device.pixStatus();
    // Start Pix stream
    _device.pixStartStream();
    
    const size_t pixelCount = pixStatus.width*pixStatus.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    for (int count=0;; count++) {
        try {
            // Check if we've been cancelled
            bool cancel = false;
            _state.lock.lock();
                cancel = _state.streamCancel;
            _state.lock.unlock();
            if (cancel) break;
            
            // Read an image, timing-out after 1s so we can check the device status,
            // in case it reports a streaming error
            _device.pixReadImage(pixels.get(), pixelCount, 1000);
//            printf("Got %ju pixels (%ju x %ju)\n",
//                (uintmax_t)pixelCount, (uintmax_t)pixStatus.width, (uintmax_t)pixStatus.height);
            
//            if (!(count % 16))
//            {
////                Pixel min = std::numeric_limits<Pixel>::max();
////                Pixel max = std::numeric_limits<Pixel>::min();
////                for (size_t i=0; i<pixelCount; i++) {
////                    min = std::min(min, pixels[i]);
////                    max = std::max(max, pixels[i]);
////                }
////                
////                printf("Pixel range: [ %ju, %ju ]\n", (uintmax_t)min, (uintmax_t)max);
//                
//                const double r = avgR(pixels.get());
//                const double g1 = avgG1(pixels.get());
//                const double g2 = avgG2(pixels.get());
//                const double b = avgB(pixels.get());
//                double max = std::max(r, g1);
//                max = std::max(max, g2);
//                max = std::max(max, b);
//                
////                printf("%ju\t%f\t%f\t%f\t%f (%f %f %f %f)\n", (uintmax_t)count,
////                    r, g1, g2, b,
////                    r/max, g1/max, g2/max, b/max);
//                
////                printf("%f\n", r);
////                printf("%f\n", g1);
////                printf("%f\n", g2);
////                printf("%f\n", b);
//            }
            
            static bool wrote = false;
            if (!wrote) {
                wrote = true;
                [[NSData dataWithBytes:pixels.get() length:pixelCount*sizeof(Pixel)] writeToFile:@"/Users/dave/Desktop/img.bin" atomically:true];
            }
            
            Image image = {
                .width = pixStatus.width,
                .height = pixStatus.height,
                .pixels = pixels.get(),
            };
            [layer updateImage:image];
        
        } catch (...) {
            if (_device.pixStatus().state != PixState::Streaming) {
//                printf("pixStatus.state != PixState::Streaming\n");
                break;
            }
        }
    }
    
    // Notify that our thread has exited
    _state.lock.lock();
        _state.streamRunning = false;
        _state.signal.notify_all();
    _state.lock.unlock();
}

@end

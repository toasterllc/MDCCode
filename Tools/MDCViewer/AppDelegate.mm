#import "MDCMainView.h"
#import <memory>
#import "MDCImageLayer.h"
#import "STAppTypes.h"
#import "MDCDevice.h"
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
    std::vector<MDCDevice> devices = MDCDevice::FindDevices();
    if (devices.empty()) throw std::runtime_error("no matching MDC devices");
    if (devices.size() > 1) throw std::runtime_error("too many matching MDC devices");
    _device = devices[0];
    
    [NSThread detachNewThreadWithBlock:^{
        [self _threadStreamImages];
    }];
}

- (void)_threadStreamImages {
    using namespace STApp;
    
    MDCImageLayer* layer = [_mainView layer];
    
    // Reset the device to put it back in a pre-defined state
    _device.reset();
    
    // Get Pix info
    PixInfo pixInfo = _device.pixInfo();
    // Start Pix stream
    _device.pixStartStream();
    
    const size_t pixelCount = pixInfo.width*pixInfo.height;
    auto pixels = std::make_unique<Pixel[]>(pixelCount);
    for (;;) {
        _device.pixReadImage(pixels.get(), pixelCount);
        printf("Got %ju pixels (%ju x %ju)\n",
            (uintmax_t)pixelCount, (uintmax_t)pixInfo.width, (uintmax_t)pixInfo.height);
        
        Image image = {
            .width = pixInfo.width,
            .height = pixInfo.height,
            .pixels = pixels.get(),
        };
        [layer updateImage:image];
    }
}

@end

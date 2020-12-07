#import "MDCMainView.h"
#import "MDCImageLayer.h"
#import <memory>
using namespace MDCImageLayerTypes;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate {
    IBOutlet MDCMainView* _mainView;
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
    
    const uint32_t width = 2304;
    const uint32_t height = 1296;
    const size_t imageLen = width*height*sizeof(ImagePixel);
//    NSString* fileName = @"TestPattern.bin";
//    NSString* fileName = @"Photo1.bin";
    NSString* fileName = @"Photo6.bin";
    NSData* imageData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:fileName ofType:nil]];
    assert([imageData length] >= imageLen);
    auto pixels = std::make_unique<ImagePixel[]>(width*height);
    memcpy(pixels.get(), [imageData bytes], imageLen);
//    uint32_t errorCount = 0;
//    for (uint32_t y=0; y<height; y++) {
//        for (uint32_t x=0; x<width; x++) {
//            ImagePixel px = pixels[(width*y)+x];
//            if (px!=0x0000 && px!=0x0FFF) {
//                printf("Got weird pixel: %jx\n", (uintmax_t)px);
//            }
//            if (!(y % 2)) {
//                // Row: G R G R ...
//                if (!(x % 2))   errorCount += (uint32_t)!checkPixel(x, y, 0xBBB, px);
//                else            errorCount += (uint32_t)!checkPixel(x, y, 0xAAA, px);
//            } else {
//                // Row: B G B G ...
//                if (!(x % 2))   errorCount += (uint32_t)!checkPixel(x, y, 0xCCC, px);
//                else            errorCount += (uint32_t)!checkPixel(x, y, 0xDDD, px);
//            }
//            
//            if (!(y % 2)) {
//                // Row: G R G R ...
//                if (!(x % 2))   errorCount += (uint32_t)!checkPixel(x, y, 0xFFF, px);
//                else            errorCount += (uint32_t)!checkPixel(x, y, 0xFFF, px);
//            } else {
//                // Row: B G B G ...
//                if (!(x % 2))   errorCount += (uint32_t)!checkPixel(x, y, 0xFFF, px);
//                else            errorCount += (uint32_t)!checkPixel(x, y, 0xFFF, px);
//            }
//        }
//    }
//    printf("Error count: %ju\n", (uintmax_t)errorCount);
    
    Image image = {
        .width = width,
        .height = height,
        .pixels = pixels.get(),
    };
    [[_mainView layer] updateImage:image];
    
//    [NSThread detachNewThreadWithBlock:^{
//        for (int iter=0; iter<100; iter++) {
//            uint32_t width = 100;
//            uint32_t height = 200;
//            auto pixels = std::make_unique<ImagePixel[]>(width*height);
//            for (size_t i=0; i<width*height; i++) {
//                pixels[i] = iter*40;
//            }
//            Image image = {
//                .width = width,
//                .height = height,
//                .pixels = pixels.get(),
//            };
//            [[_mainView layer] updateImage:image];
//            usleep(100000);
//        }
//    }];
}

@end

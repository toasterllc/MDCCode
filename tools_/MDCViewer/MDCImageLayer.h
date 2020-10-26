#import <QuartzCore/QuartzCore.h>
#import "MDCImageLayerTypes.h"

namespace MDCImageLayerTypes {
    struct Image {
        uint32_t width = 0;
        uint32_t height = 0;
        ImagePixel* pixels = nullptr;
    };
};

@interface MDCImageLayer : CAMetalLayer
- (void)updateImage:(const MDCImageLayerTypes::Image&)image;
@end

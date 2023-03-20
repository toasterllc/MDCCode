#import "Tools/Shared/CFA.h"
#import "Img.h"

struct RawImage {
    MDCTools::CFADesc cfaDesc;
    size_t width = 0;
    size_t height = 0;
    const Img::Pixel* pixels = nullptr;
};

#import "CFAImage.h"
#import "Mat.h"
#import "ImagePipelineTypes.h"

namespace GrayWorld {
    Mat<double,3,1> Calc(const CFAImage& img) {
        Mat<double,3,1> avgColor;
        size_t avgColorCounts[3] = {};
        for (int y=0; y<CFAImage::Height; y++) {
            for (int x=0; x<CFAImage::Width; x++) {
                if (!img.isMidtone(x,y)) continue; // Only consider midtones
                const auto c = img.color(x,y);
                avgColor[(uint8_t)c] += img.sample(x,y);
                avgColorCounts[(uint8_t)c]++;
            }
        }
        avgColor[0] /= avgColorCounts[0];
        avgColor[1] /= avgColorCounts[1];
        avgColor[2] /= avgColorCounts[2];
        return avgColor;
    }
}

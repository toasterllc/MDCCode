#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "STAppTypes.h"
#import "Mmap.h"

static void printUsage() {
    printf("Usage:\n");
    printf("  cfa2dng <InputFile.cfa> <OutputFile.tiff>\n\n");
}

constexpr size_t ImageWidth = 2304;
constexpr size_t ImageHeight = 1296;

int main(int argc, const char* argv[]) {
    using Pixel = STApp::Pixel;
    if (argc != 3) {
        printUsage();
        return 1;
    }
    
    try {
        const char* inputFilePath = argv[1];
        const char* outputFilePath = argv[2];
        Mmap mmap(inputFilePath);
        
        constexpr size_t bitsPerComponent = 16;
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray(); // TODO: needs to be released
        CGContextRef context = CGBitmapContextCreate((void*)mmap.data(), ImageWidth, ImageHeight, bitsPerComponent,
            ImageWidth*sizeof(Pixel), colorSpace, kCGBitmapByteOrder16Little);
        
        CGImageRef image = CGBitmapContextCreateImage(context);
        NSURL* outputURL = [NSURL fileURLWithPath:@(outputFilePath)];
        
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithURL((CFURLRef)outputURL, kUTTypeTIFF, 1, nil);
        CGImageDestinationAddImage(imageDest, image, nil);
        CGImageDestinationFinalize(imageDest);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    return 0;
}

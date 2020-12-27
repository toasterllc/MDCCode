#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "STAppTypes.h"
#import "Mmap.h"

static void printUsage() {
    printf("Usage:\n");
    printf("  cfa2dng <InputFile.cfa> <ImageWidth> <ImageHeight> <OutputFile.tiff>\n\n");
}

int main(int argc, const char* argv[]) {
    using Pixel = STApp::Pixel;
    if (argc != 5) {
        printUsage();
        return 1;
    }
    
    try {
        const char* inputFilePath = argv[1];
        size_t imageWidth = std::strtoull(argv[2], nullptr, 0);
        size_t imageHeight = std::strtoull(argv[3], nullptr, 0);
        const char* outputFilePath = argv[4];
        Mmap mmap(inputFilePath);
        
        const size_t expectedFileSize = imageWidth*imageHeight*2;
        if (mmap.len() != expectedFileSize) {
            fprintf(stderr, "Invalid file size; expected %ju bytes, got %ju bytes\n\n",
            (uintmax_t)expectedFileSize, (uintmax_t)mmap.len());
            return 1;
        }
        
        constexpr size_t bitsPerComponent = 16;
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray(); // TODO: needs to be released
        CGContextRef context = CGBitmapContextCreate((void*)mmap.data(), imageWidth, imageHeight, bitsPerComponent,
            imageWidth*sizeof(Pixel), colorSpace, kCGBitmapByteOrder16Little);
        
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

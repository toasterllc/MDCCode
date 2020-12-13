#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "STAppTypes.h"
#import "Mmap.h"

static void printUsage() {
    printf("Usage:\n");
    printf("  cfa2dng <InputFile.cfa> <OutputFile.dng>\n\n");
}

constexpr size_t ImageWidth = 2304;
constexpr size_t ImageHeight = 1296;

//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGVersion  IMAGEIO_AVAILABLE_STARTING(10.5, 4.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGBackwardVersion  IMAGEIO_AVAILABLE_STARTING(10.5, 4.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGUniqueCameraModel  IMAGEIO_AVAILABLE_STARTING(10.5, 4.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGLocalizedCameraModel  IMAGEIO_AVAILABLE_STARTING(10.5, 4.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGCameraSerialNumber  IMAGEIO_AVAILABLE_STARTING(10.5, 4.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGLensInfo  IMAGEIO_AVAILABLE_STARTING(10.5, 4.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGBlackLevel  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGWhiteLevel  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGCalibrationIlluminant1  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGCalibrationIlluminant2  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGColorMatrix1  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGColorMatrix2  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGCameraCalibration1  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGCameraCalibration2  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGAsShotNeutral  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGAsShotWhiteXY  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGBaselineExposure  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGBaselineNoise  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGBaselineSharpness  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGPrivateData  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGCameraCalibrationSignature  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGProfileCalibrationSignature  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGNoiseProfile  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGWarpRectilinear  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGWarpFisheye  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//IMAGEIO_EXTERN const CFStringRef  kCGImagePropertyDNGFixVignetteRadial  IMAGEIO_AVAILABLE_STARTING(10.12, 10.0);
//
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGActiveArea  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGAnalogBalance  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGAntiAliasStrength  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGAsShotICCProfile  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGAsShotPreProfileMatrix  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGAsShotProfileName  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGBaselineExposureOffset  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGBayerGreenSplit  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGBestQualityScale  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGBlackLevelDeltaH  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGBlackLevelDeltaV  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGBlackLevelRepeatDim  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGCFALayout  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGCFAPlaneColor  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGChromaBlurRadius  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGColorimetricReference  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGCurrentICCProfile  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGCurrentPreProfileMatrix  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGDefaultBlackRender  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGDefaultCropOrigin  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGDefaultCropSize  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGDefaultScale  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGDefaultUserCrop  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGExtraCameraProfiles  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGForwardMatrix1  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGForwardMatrix2  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGLinearizationTable  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGLinearResponseLimit  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGMakerNoteSafety  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGMaskedAreas  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGNewRawImageDigest  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGNoiseReductionApplied  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOpcodeList1  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOpcodeList2  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOpcodeList3  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOriginalBestQualityFinalSize  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOriginalDefaultCropSize  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOriginalDefaultFinalSize  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOriginalRawFileData  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOriginalRawFileDigest  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGOriginalRawFileName  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGPreviewApplicationName  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGPreviewApplicationVersion  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGPreviewColorSpace  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGPreviewDateTime  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGPreviewSettingsDigest  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGPreviewSettingsName  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileCopyright  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileEmbedPolicy  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileHueSatMapData1  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileHueSatMapData2  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileHueSatMapDims  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileHueSatMapEncoding  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileLookTableData  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileLookTableDims  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileLookTableEncoding  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileName  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGProfileToneCurve  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGRawDataUniqueID  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGRawImageDigest  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGRawToPreviewGain  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGReductionMatrix1  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGReductionMatrix2  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGRowInterleaveFactor  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGShadowScale  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);
//IMAGEIO_EXTERN const CFStringRef kCGImagePropertyDNGSubTileBlockSize  IMAGEIO_AVAILABLE_STARTING(10.14, 12.0);



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
        // kCGImagePropertyOrientation
        
//        CGMutableImageMetadataRef metadata = CGImageMetadataCreateMutable();
//        CGImageMetadataTagRef tag = CGImageMetadataTagCreate(
//            kCGImageMetadataNamespaceTIFF,
//            kCGImageMetadataPrefixExif,
//            kCGImagePropertyDNGVersion,
//            kCGImageMetadataTypeString,
//            (CFTypeRef)@"meowmix"
//        );
//        
//        assert(CGImageMetadataSetTagWithPath(metadata, nil, (CFStringRef)@"tiff:DNGVersion", tag));
        
        NSDictionary* opts = @{
//            (id)kCGImagePropertyOrientation: @(kCGImagePropertyOrientationDown),
//            (id)kCGImagePropertyDNGDictionary: @{
//                (id)kCGImagePropertyDNGUniqueCameraModel: @"meowmix",
//            },
//            (id)kCGImagePropertyDNGUniqueCameraModel: @"meowmix",
//            (id)kCGImageDestinationMetadata: (__bridge id)metadata,
        };
        
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithURL((CFURLRef)outputURL, kUTTypeTIFF, 1, nil);
//        CGImageDestinationAddImage(imageDest, image, nullptr);
        CGImageDestinationAddImage(imageDest, image, (CFDictionaryRef)opts);
//        CGImageDestinationAddImageAndMetadata(imageDest, image, metadata, nullptr);
        CGImageDestinationFinalize(imageDest);
        
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n\n", e.what());
        return 1;
    }
    return 0;
}

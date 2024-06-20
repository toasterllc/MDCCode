#import <Foundation/Foundation.h>

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <filesystem>
#include "Code/Lib/Toastbox/Mmap.h"

#define TINY_DNG_WRITER_IMPLEMENTATION
#include "Code/Lib/tinydng/tiny_dng_writer.h"

int main(int argc, char **argv) {
//    XYZ.D50 <- CameraRaw
//        (XYZD50FromProPhotoRGBD50 * ColorMatrix)
//
//    CameraRaw <- XYZ.D50
//        inv(XYZD50FromProPhotoRGBD50 * ColorMatrix)
    
    const std::filesystem::path dir = std::filesystem::path([[[NSBundle mainBundle] executablePath] UTF8String]).parent_path();
    Toastbox::Mmap imageData(dir / "24.bin");
    
    const uint16_t bitsPerSample[] = { 16 };
    const uint16_t sampleFormat[] = { tinydngwriter::SAMPLEFORMAT_UINT };
    
    const double ccm1[] = {
        2.426472 , -1.008062 , -0.401825 ,
        0.364135 ,  0.729987 , -0.098270 ,
        0.563004 , -0.047291 ,  0.611276 ,
    };
    
    const double ccm2[] = {
         1.7103e+00 , -4.7671e-01 , -2.0888e-01 ,
        -1.6241e-01 ,  1.0936e+00 ,  7.6380e-02 ,
        -5.0032e-03 ,  4.0445e-01 ,  7.2754e-01 ,
    };
    
    
    
//    const double ccm1[] = {
//        1,0,0,
//        0,1,0,
//        0,0,1,
//    };
    
//    const double ccm1[] = {
//       2.452946 , -1.042994 , -0.409949 ,
//       0.357515 ,  0.738724 , -0.096238 ,
//       0.765702 , -0.314770 ,  0.549068 ,
//    };
    
//    const double ccm1[] = {
//        +2.118560, -0.778840, -0.3198240,
//        +0.138040, +0.886655, -0.0239412,
//        +0.318496, +0.147789, +0.6605720,
//    };
    
//    const double ccm1[] = {
//       0.457735 ,  0.292954  , 0.249311 ,
//      -0.110034 ,  1.080498  , 0.029536 ,
//      -0.190691 , -0.796240  , 1.986931 ,
//    };
    
    
//    const double ccm1[] = {
//       2.118560 ,  0.138040  , 0.318496,
//      -0.778840 ,  0.886655  , 0.147789,
//      -0.319824 , -0.023941  , 0.660572,
//    };
    
    
//    [ 2.11856 -0.77884 -0.319824 ;
//    0.13804 0.886655 -0.0239412 ;
//    0.318496 0.147789 0.660572 ]
//
//    [ 0.418169 0.331572 0.214479 ;
//    -0.0701238 1.06546 0.00466428 ;
//    -0.185932 -0.398241 1.40938 ]
    
    
    
//    const double ccm1[] = {
//           4.1817e-01  ,  3.3157e-01  , 2.1448e-01 ,
//          -7.0124e-02  ,  1.0655e+00  , 4.6643e-03 ,
//          -1.8593e-01  , -3.9824e-01  , 1.4094e+00 ,
//    };
    
    
    
//    const double ccm1[] = { 1,0,0,   0,1,0,   0,0,1 };
//    const double ccm2[] = { 1,0,0,   0,1,0,   0,0,1 };
    const double asShotNatural[] = { 0.635942, 0.720814, 0.275690 };
//    const double asShotNatural[] = { 1, 1, 1 };
    
    
//    const double asShotNatural[] = { 1, 1, 1 };
    const uint16_t blackLevel[] = { 0 };
    const uint16_t whiteLevel[] = { 4095 };
    const uint8_t cfaPattern[] = { 1, 0, 2, 1 };
    
    tinydngwriter::DNGImage dng;
    dng.SetDNGVersion(1,3,0,0);
    dng.SetBigEndian(false);
    dng.SetSubfileType(false, false, false); // Full-resolution image
    dng.SetImageWidth(2304);
    dng.SetImageLength(1296);
    dng.SetSamplesPerPixel(1);
    dng.SetBitsPerSample(std::size(bitsPerSample), bitsPerSample);
    dng.SetCompression(tinydngwriter::COMPRESSION_NONE);
    dng.SetPhotometric(tinydngwriter::PHOTOMETRIC_CFA);
    dng.SetPlanarConfig(tinydngwriter::PLANARCONFIG_CONTIG);
    dng.SetSampleFormat(std::size(sampleFormat), sampleFormat);
    dng.SetCFARepeatPatternDim(2, 2);
    dng.SetCFAPattern(std::size(cfaPattern), cfaPattern);
    dng.SetAsShotNeutral(std::size(asShotNatural), asShotNatural);
    
    dng.SetColorMatrix1(3, ccm1);
    dng.SetColorMatrix2(3, ccm2);
    
//    dng.SetCalibrationIlluminant1(tinydngwriter::LIGHTSOURCE_D65);
    
//    dng.SetColorMatrix2(3, ccm2);
    dng.SetCalibrationIlluminant1(tinydngwriter::LIGHTSOURCE_STANDARD_LIGHT_A);
    dng.SetCalibrationIlluminant2(tinydngwriter::LIGHTSOURCE_D65);
    dng.SetBlackLevel(std::size(blackLevel), blackLevel);
    dng.SetWhiteLevel(std::size(whiteLevel), whiteLevel);
    dng.SetImageData(imageData.data(), imageData.len());
    
    tinydngwriter::DNGWriter writer(false);
    bool ret = writer.AddImage(&dng);
    assert(ret);
    
    ret = writer.WriteToFile("output.dng", nullptr);
    assert(ret);
    
    return 0;
}

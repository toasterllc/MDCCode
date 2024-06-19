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
    const double ccm1[] = { 1,0,0,   0,1,0,   0,0,1 };
//    const double ccm2[] = { 1,0,0,   0,1,0,   0,0,1 };
//    const double asShotNatural[] = { 0.632830, 0.721197, 0.281780 };
    const double asShotNatural[] = { 1, 1, 1 };
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
    dng.SetColorMatrix1(3, ccm1);
//    dng.SetColorMatrix2(3, ccm2);
//    dng.SetCalibrationIlluminant1(tinydngwriter::LIGHTSOURCE_STANDARD_LIGHT_A);
//    dng.SetCalibrationIlluminant2(tinydngwriter::LIGHTSOURCE_D65);
    dng.SetAsShotNeutral(std::size(asShotNatural), asShotNatural);
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

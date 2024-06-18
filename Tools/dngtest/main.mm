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
    
    std::string output_filename = (argc>1 ? argv[1] : "output.dng");

    // DNGWriter supports multiple DNG images.
    // First create DNG image data, then pass it to DNGWriter with AddImage API.
    tinydngwriter::DNGImage dng_image;
    dng_image.SetBigEndian(false);
    
    const std::filesystem::path dir = std::filesystem::path([[[NSBundle mainBundle] executablePath] UTF8String]).parent_path();
    Toastbox::Mmap imageData(dir / "18319.bin");
    
    unsigned int image_width = 2304;
    unsigned int image_height = 1296;
    
    dng_image.SetSubfileType(false, false, false);     // Full-resolution image
    dng_image.SetImageWidth(image_width);                         // 3040
    dng_image.SetImageLength(image_height);                        // 6080
    
    const unsigned short bps[] = { 16 };
    dng_image.SetSamplesPerPixel(1);
    dng_image.SetBitsPerSample(std::size(bps), bps);
    
    dng_image.SetCompression(tinydngwriter::COMPRESSION_NONE);                        // Uncompressed
    dng_image.SetPhotometric(tinydngwriter::PHOTOMETRIC_CFA);          // Color Filter Array
    dng_image.SetPlanarConfig(tinydngwriter::PLANARCONFIG_CONTIG);                // Chunky
    
    const unsigned short sf[] = { tinydngwriter::SAMPLEFORMAT_UINT };
    dng_image.SetSampleFormat(std::size(sf), sf);
    
    dng_image.SetCFARepeatPatternDim(2, 2);                // 2 2
    
    uint8_t cfavals[] = { 1, 0, 2, 1 };
    dng_image.SetCFAPattern(std::size(cfavals), cfavals);
    
    dng_image.SetDNGVersion(1,3,0,0);
    
    const double cm1[] = {
       1.7065, -0.5080, -0.1665,
      -0.3383,  1.2074,  0.1439,
      -0.1981,  0.4568,  0.8897,
    };
    
    dng_image.SetColorMatrix1(3, cm1);
    dng_image.SetCalibrationIlluminant1(23); // D50
    
    const double asn[] = { 0.33324006798300848, 0.64255025834598356, 0.68998566839477893 };
    dng_image.SetAsShotNeutral(3, asn);
    
    uint16_t bl[] = { 0 };
    dng_image.SetBlackLevel(std::size(bl), bl);
    
    uint16_t wl[] = { 4095 };
    dng_image.SetWhiteLevel(std::size(wl), wl);
    
    dng_image.SetImageData(imageData.data(), imageData.len());

    tinydngwriter::DNGWriter dng_writer(false);
    bool ret = dng_writer.AddImage(&dng_image);
    assert(ret);

    std::string err;
    ret = dng_writer.WriteToFile(output_filename.c_str(), &err);

    if (!err.empty()) std::cerr << err;
    if (!ret) return EXIT_FAILURE;

    std::cout << "Wrote : " << output_filename << std::endl;

    return EXIT_SUCCESS;
}

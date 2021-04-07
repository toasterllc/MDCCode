#import <Foundation/Foundation.h>
#import <vector>
#import <filesystem>
#import <iostream>
#import <fstream>
#import "Color.h"
namespace fs = std::filesystem;

struct Illum {
    std::string name;
    Color<ColorSpace::Raw> c;
};
using Illums = std::vector<Illum>;

Illums IllumsGroundTruth = {
#include "IllumsGroundTruth.h"
};

int main(int argc, const char* argv[]) {
    argc = 2;
    argv = (const char*[]){"", "/Users/dave/Desktop/FFCCImageSets/Outdoor-5pm-ColorChecker-Small"};
    
    const fs::path dirPath(argv[1]);
    for (const auto& illum : IllumsGroundTruth) {
        const fs::path illumPath = fs::path(dirPath) /= fs::path(illum.name) += ".txt";
        
        std::ofstream f;
        f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
        f.open(illumPath);
        char jsonStr[128];
        const int len = snprintf(jsonStr, sizeof(jsonStr),
            "%.8f\n%.8f\n%.8f\n",
            illum.c[0], illum.c[1], illum.c[2]);
        f.write(jsonStr, len);
    }
    return 0;
}

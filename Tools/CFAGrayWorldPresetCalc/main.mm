#import <Foundation/Foundation.h>
#import <filesystem>
#import "ImagePipelineTypes.h"
#import "CFAImage.h"
#import "GrayWorld.h"
#import "Color.h"
namespace fs = std::filesystem;

struct Illum {
    std::string name;
    Color<ColorSpace::Raw> color;
};

static const Illum IllumPresets[] = {
    {"Daylight",    {0.731058, 1.000000, 0.662689}},
    {"IndoorWarm",  {0.991380, 1.000000, 0.382732}},
};

static double dot(const Color<ColorSpace::Raw>& a, const Color<ColorSpace::Raw>& b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

static double mag(const Color<ColorSpace::Raw>& a) {
    return sqrt(dot(a,a));
}

static double colorAngle(const Color<ColorSpace::Raw>& a, const Color<ColorSpace::Raw>& b) {
    return std::acos(dot(a,b)/(mag(a)*mag(b))) * (360./(2*M_PI));
}

static void handleFile(const fs::path& path) {
    const fs::path name(path.filename().replace_extension());
    CFAImage img(path);
    Color<ColorSpace::Raw> grayWorldIllumColor = GrayWorld::Calc(img);
    
    const Illum* illumPreset = nullptr;
    double illumPresetErr = INFINITY;
    double illumPresetTotal = 0;
    for (const Illum& ip : IllumPresets) {
        printf("colorAngle (gray-world vs %s): %.2f\n", ip.name.c_str(), colorAngle(grayWorldIllumColor, ip.color));
        double err = colorAngle(grayWorldIllumColor, ip.color);
        if (err < illumPresetErr) {
            illumPreset = &ip;
            illumPresetErr = err;
        }
        illumPresetTotal += err;
    }
    
    const double confidence = 1-(illumPresetErr/illumPresetTotal);
    printf("{ \"%s\", { %f, %f, %f } }, // %s (confidence = %.2f, gray-world vs preset Δ = %.2f degrees)\n",
        name.c_str(),
        illumPreset->color[0], illumPreset->color[1], illumPreset->color[2],
        illumPreset->name.c_str(),
        confidence,
        illumPresetErr
    );
    
    printf("\n\n\n");
    
}

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

int main(int argc, const char* argv[]) {
    const char* args[] = {"", "/Users/dave/Desktop/Old/2021:4:3/CFAViewerSession-All-FilteredGood"};
    argc = std::size(args);
    argv = args;
    
    for (int i=1; i<argc; i++) {
        const char* pathArg = argv[i];
        
        // Regular file
        if (isCFAFile(pathArg)) {
            handleFile(pathArg);
        
        // Directory
        } else if (fs::is_directory(pathArg)) {
            for (const auto& f : fs::directory_iterator(pathArg)) {
                if (isCFAFile(f)) {
                    handleFile(f);
                }
            }
        }
    }
    return 0;
}

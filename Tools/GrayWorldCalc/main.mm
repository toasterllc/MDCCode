#import <Foundation/Foundation.h>
#import <filesystem>
#import "ImagePipelineTypes.h"
#import "CFAImage.h"
#import "GrayWorld.h"
namespace fs = std::filesystem;

void handleFile(const fs::path& path) {
    const fs::path name(path.filename().replace_extension());
    CFAImage img(path);
    Mat<double,3,1> c = GrayWorld::Calc(img);
    printf("{ \"%s\", { %f, %f, %f } },\n", name.c_str(), c[0], c[1], c[2]);
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

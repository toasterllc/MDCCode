#import <Cocoa/Cocoa.h>
#import "Debug.h"
#import "/Applications/MATLAB_R2021a.app/extern/include/mat.h"
using namespace CFAViewer;
namespace fs = std::filesystem;

using Mat64 = Mat<double,64,64>;
using Mat64c = Mat<std::complex<double>,64,64>;

void printMat(const Mat64& m) {
    uint32_t i = 0;
    printf("{\n");
    for (auto x : m) {
        static_assert(sizeof(x) == 8);
        const uint64_t u = ((uint64_t*)&x)[0];
        if (i == 0) printf("    ");
        else        printf(" ");
        printf("0x%016jx,", (uintmax_t)u);
        i++;
        if (i == 4) {
            printf("\n");
            i = 0;
        }
    }
    printf("};");
}

void printMat(const Mat64c& m) {
    uint32_t i = 0;
    printf("{\n");
    for (auto x : m) {
        static_assert(sizeof(x) == 16);
        const uint64_t real = ((uint64_t*)&x)[0];
        const uint64_t imag = ((uint64_t*)&x)[1];
        if (i == 0) printf("    ");
        else        printf(" ");
        printf("0x%016jx, 0x%016jx,", (uintmax_t)real, (uintmax_t)imag);
        i++;
        if (i == 2) {
            printf("\n");
            i = 0;
        }
    }
    printf("};");
}

int main(int argc, const char* argv[]) {
    MATFile* ModelFile = matOpen("/Users/dave/repos/ffcc/models/AR0330.mat", "r");
    
    Mat64c F_fft[2];
    Mat64 B;
    
    load(mxGetField(matGetVariable(ModelFile, "model"), 0, "F_fft"), F_fft);
    load(mxGetField(matGetVariable(ModelFile, "model"), 0, "B"), B);
    
    printf("static const inline uint64_t F_fft0Vals[%ju] = ", (uintmax_t)F_fft[0].Count*(sizeof(F_fft[0][0])/sizeof(uint64_t)));
    printMat(F_fft[0]);
    printf("\n\n");
    
    printf("static const inline uint64_t F_fft1Vals[%ju] = ", (uintmax_t)F_fft[1].Count*(sizeof(F_fft[1][0])/sizeof(uint64_t)));
    printMat(F_fft[1]);
    printf("\n\n");
    
    printf("static const inline uint64_t BVals[%ju] = ", (uintmax_t)B.Count*(sizeof(B[0])/sizeof(uint64_t)));
    printMat(B);
    printf("\n\n");
    
    return 0;
}

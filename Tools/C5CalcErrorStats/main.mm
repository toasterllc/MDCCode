#import <Foundation/Foundation.h>
#import <vector>
#import "Color.h"

struct Illum {
    std::string name;
    Color<ColorSpace::Raw> c;
};
using Illums = std::vector<Illum>;

Illums IllumsGroundTruth = {
#include "IllumsGroundTruth.h"
};

Illums IllumsGrayWorld = {
#include "IllumsGrayWorld.h"
};

Illums IllumsC5 = {
#include "IllumsC5.h"
};

Illums IllumsFFCC = {
#include "IllumsFFCC.h"
};

Illums IllumsFFCCMatlab = {
#include "IllumsFFCCMatlab.h"
};

static double dot(const Color<ColorSpace::Raw>& a, const Color<ColorSpace::Raw>& b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
}

static double mag(const Color<ColorSpace::Raw>& a) {
    return sqrt(dot(a,a));
}

static double angularError(const Color<ColorSpace::Raw>& a, const Color<ColorSpace::Raw>& b) {
    return std::acos(dot(a,b)/(mag(a)*mag(b))) * (360./(2*M_PI));
}

struct ErrStats {
    double min = INFINITY;
    std::string minName;
    
    double max = 0;
    std::string maxName;
    
    double avg = 0;
    
    double push(const std::string& name, const Color<ColorSpace::Raw> groundTruth, const Color<ColorSpace::Raw> sample) {
        const double err = angularError(groundTruth, sample);
        if (err < min) {
            min = err;
            minName = name;
        }
        
        if (err > max) {
            max = err;
            maxName = name;
        }
        
        avg += err;
        return err;
    }
    
    void print() {
        printf("  Min: %.2f degrees (%s)\n", min, minName.c_str());
        printf("  Max: %.2f degrees (%s)\n", max, maxName.c_str());
        printf("  Avg: %.2f degrees\n", avg);
        printf("\n\n");
    }
};

int main(int argc, const char* argv[]) {
//    Mat<double,3,3> C5IllumCorrectionMatrix_All(
//        1.25407726323103,       0., -0.245441000321451,
//        0.,                     1., 0.,
//        -0.0687922873207393,    0., 0.868851550191642
//    );
//    
//    Mat<double,3,3> C5IllumCorrectionMatrix_Indoor(
//        0.774585916386025,  0., 0.609814409808070,
//        0.,                 1., 0.,
//        0.387782502908189,  0., 0.0523111035075627
//    );
//    
//    Mat<double,3,3> C5IllumCorrectionMatrix_Outdoor(
//        0.820606627305855,  0.,  0.109498804838320,
//        0.,                 1.,  0.,
//        0.368982945291325,  0.,  0.510003175758347
//    );
    
    Mat<double,3,3> C5IllumCorrectionMatrix_All(
        1., 0., 0.,
        0., 1., 0.,
        0., 0., 1.
    );
    
//    Mat<double,3,3> C5IllumCorrectionMatrix_Indoor(
//        1., 0., 0.,
//        0., 1., 0.,
//        0., 0., 1.
//    );
//    
//    Mat<double,3,3> C5IllumCorrectionMatrix_Outdoor(
//        1., 0., 0.,
//        0., 1., 0.,
//        0., 0., 1.
//    );
    
    ErrStats errStatsGroundTruth;
    ErrStats errStatsGrayWorld;
    ErrStats errStatsC5;
    ErrStats errStatsFFCC;
    ErrStats errStatsFFCCMatlab;
    
    for (size_t i=0; i<IllumsGroundTruth.size(); i++) {
        const Illum& groundTruth = IllumsGroundTruth[i];
        const Illum& grayWorld = IllumsGrayWorld[i];
        const Illum& c5 = IllumsC5[i];
        const Illum& ffcc = IllumsFFCC[i];
        const Illum& ffccMatlab = IllumsFFCCMatlab[i];
        assert(groundTruth.name == grayWorld.name);
        assert(groundTruth.name == c5.name);
        assert(groundTruth.name == ffcc.name);
        assert(groundTruth.name == ffccMatlab.name);
        const std::string& name = groundTruth.name;
        
        const Color<ColorSpace::Raw> illumGroundTruth   (groundTruth.c.m        /       groundTruth.c.m[1] );
        const Color<ColorSpace::Raw> illumGrayWorld     (grayWorld.c.m          /       grayWorld.c.m  [1] );
        const Color<ColorSpace::Raw> illumC5            (c5.c.m                 /       c5.c.m         [1] );
        const Color<ColorSpace::Raw> illumFFCC          (ffcc.c.m               /       ffcc.c.m       [1] );
        const Color<ColorSpace::Raw> illumFFCCMatlab    (ffccMatlab.c.m         /       ffccMatlab.c.m [1] );
        
        const double errGroundTruth = errStatsGroundTruth.push  (groundTruth.name, illumGroundTruth, illumGroundTruth );
        const double errGrayWorld   = errStatsGrayWorld.push    (groundTruth.name, illumGroundTruth, illumGrayWorld   );
        const double errC5          = errStatsC5.push           (groundTruth.name, illumGroundTruth, illumC5          );
        const double errFFCC        = errStatsFFCC.push         (groundTruth.name, illumGroundTruth, illumFFCC        );
        const double errFFCCMatlab  = errStatsFFCCMatlab.push   (groundTruth.name, illumGroundTruth, illumFFCCMatlab  );
        
        printf( "%s\n"
                "GroundTruth illum:[%.4f %.4f %.4f] wb:[%.4f %.4f %.4f] err:%f\n"
                "GrayWorld   illum:[%.4f %.4f %.4f] wb:[%.4f %.4f %.4f] err:%f\n"
                "C5          illum:[%.4f %.4f %.4f] wb:[%.4f %.4f %.4f] err:%f\n"
                "FFCC        illum:[%.4f %.4f %.4f] wb:[%.4f %.4f %.4f] err:%f\n"
                "FFCCMatlab  illum:[%.4f %.4f %.4f] wb:[%.4f %.4f %.4f] err:%f\n",
            name.c_str(),
            
              illumGroundTruth[0],      illumGroundTruth[1],    illumGroundTruth[2],
            1/illumGroundTruth[0],    1/illumGroundTruth[1],  1/illumGroundTruth[2],
            errGroundTruth,
            
              illumGrayWorld[0],        illumGrayWorld[1],      illumGrayWorld[2],
            1/illumGrayWorld[0],      1/illumGrayWorld[1],    1/illumGrayWorld[2],
            errGrayWorld,
            
              illumC5[0],               illumC5[1],             illumC5[2],
            1/illumC5[0],             1/illumC5[1],           1/illumC5[2],
            errC5,
            
              illumFFCC[0],             illumFFCC[1],           illumFFCC[2],
            1/illumFFCC[0],           1/illumFFCC[1],         1/illumFFCC[2],
            errFFCC,
            
              illumFFCCMatlab[0],       illumFFCCMatlab[1],     illumFFCCMatlab[2],
            1/illumFFCCMatlab[0],     1/illumFFCCMatlab[1],   1/illumFFCCMatlab[2],
            errFFCCMatlab
        );
    }
    errStatsGroundTruth.avg /= IllumsGroundTruth.size();
    errStatsGrayWorld.avg   /= IllumsGroundTruth.size();
    errStatsC5.avg          /= IllumsGroundTruth.size();
    errStatsFFCC.avg        /= IllumsGroundTruth.size();
    errStatsFFCCMatlab.avg  /= IllumsGroundTruth.size();
    
    printf("\n\n\n");
    
    printf("GroundTruth error stats:\n");
    errStatsGroundTruth.print();
    
    printf("GrayWorld error stats:\n");
    errStatsGrayWorld.print();
    
    printf("C5 error stats:\n");
    errStatsC5.print();
    
    printf("FFCC error stats:\n");
    errStatsFFCC.print();
    
    printf("FFCCMatlab error stats:\n");
    errStatsFFCCMatlab.print();
    return 0;
}

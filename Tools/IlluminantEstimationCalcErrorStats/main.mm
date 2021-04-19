#import <Foundation/Foundation.h>
#import <vector>
#import "Color.h"

struct Trial {
    std::string name; // Image name
    Color<ColorSpace::Raw> color; // Illuminant color
};

struct Scheme {
    std::string name; // Name of illuminant estimation scheme (GroundTruth, C5, FFCC, ...)
    std::vector<Trial> trials;
};

static const Scheme Schemes[] = {
    {
        .name = "GroundTruth",
        .trials = {
            #include "TrialsGroundTruth.h"
        }
    },
    
    {
        .name = "GrayWorld",
        .trials = {
            #include "TrialsGrayWorld.h"
        }
    },
    
    {
        .name = "C5",
        .trials = {
            #include "TrialsC5.h"
        }
    },
    
    {
        .name = "FFCC",
        .trials = {
            #include "TrialsFFCC.h"
        }
    },
    
    {
        .name = "FFCCMatlab",
        .trials = {
            #include "TrialsFFCCMatlab.h"
        }
    },
    
    {
        .name = "GrayWorldPreset",
        .trials = {
            #include "TrialsGrayWorldPreset.h"
        }
    },
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

struct ErrStats {
    double min = INFINITY;
    std::string minName;
    
    double max = 0;
    std::string maxName;
    
    double avg = 0;
    
    double push(const std::string& name, const Color<ColorSpace::Raw> groundTruth, const Color<ColorSpace::Raw> sample) {
        const double err = colorAngle(groundTruth, sample);
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

static Color<ColorSpace::Raw> normalizeColor(const Color<ColorSpace::Raw>& c) {
    const double factor = std::min(std::min(c[0], c[1]), c[2]);
    return c.m/factor;
}

int main(int argc, const char* argv[]) {
    ErrStats errStats[std::size(Schemes)];
    
    const Scheme& schemeGroundTruth = Schemes[0];
    for (size_t itrial=0; itrial<schemeGroundTruth.trials.size(); itrial++) {
        const Trial& trialGroundTruth = schemeGroundTruth.trials[itrial];
        const Color<ColorSpace::Raw> illumGroundTruth = normalizeColor(trialGroundTruth.color);
        printf("* %s\n", trialGroundTruth.name.c_str());
        
        for (size_t ischeme=0; ischeme<std::size(Schemes); ischeme++) {
            const Scheme& s = Schemes[ischeme];
            const Trial& t = s.trials[itrial];
            const Color<ColorSpace::Raw> i = normalizeColor(t.color);
            ErrStats& e = errStats[ischeme];
            
            // Verify that every scheme has the same number of trials
            assert(s.trials.size() == schemeGroundTruth.trials.size());
            // Verify that the trials for each scheme have the same name
            // (Ie, all image names match.)
            assert(t.name == trialGroundTruth.name);
            
            const double err = e.push(trialGroundTruth.name, illumGroundTruth, i);
            
            printf("%-16s illum:[%.4f %.4f %.4f] wb:[%.4f %.4f %.4f] err:%f\n",
                s.name.c_str(),
                  i[0],   i[1],   i[2],
                1/i[0], 1/i[1], 1/i[2],
                err
            );
        }
        printf("\n");
    }
    printf("\n\n\n");
    
    // Finish calculating average error for each scheme
    for (ErrStats& e : errStats) {
        e.avg /= schemeGroundTruth.trials.size();
    }
    
    for (size_t ischeme=0; ischeme<std::size(Schemes); ischeme++) {
        const Scheme& s = Schemes[ischeme];
        ErrStats& e = errStats[ischeme];
        printf("%s error stats:\n", s.name.c_str());
        e.print();
    }
    
    return 0;
}

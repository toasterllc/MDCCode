#import <Foundation/Foundation.h>
#include <fstream>
#include <optional>
#include "Toastbox/String.h"
#include "Toastbox/NumForStr.h"

int main(int argc, const char* argv[]) {
    
    try {
        if (argc != 2) {
            throw std::runtime_error(std::string("Usage: ") + argv[0] + " <file.txt>");
        }
        
        const std::string filePath = argv[1];
        std::ifstream file(filePath);
        
        intmax_t bits[24] = {};
        uintmax_t totalIterationCount = 0;
        
        std::string line;
        std::optional<uint32_t> tuneVal;
        while (std::getline(file, line)) {
            
            if (line.starts_with("USB_HS_PHYC_TUNE_VALUE")) {
                auto parts = Toastbox::String::Split(line, " ");
                const std::string str = parts.back();
                assert(str.starts_with("0x"));
                uint32_t x = 0;
                Toastbox::IntForStr(x, str.c_str()+2, 16);
                tuneVal = x;
            
            } else if (line.starts_with("Successful control request count:")) {
                auto parts = Toastbox::String::Split(line, " ");
                uintmax_t tuneValIterationCount = 0;
                Toastbox::IntForStr(tuneValIterationCount, parts.back());
                totalIterationCount += tuneValIterationCount;
                
                assert(tuneVal);
                for (size_t i=0; i<std::size(bits); i++) {
                    // If the bit is set, increment bits[i].
                    // Otherwise, decrement bits[i].
                    if ((*tuneVal) & ((uint32_t)1<<i)) {
                        bits[i] += tuneValIterationCount;
//                    } else {
//                        bits[i] -= tuneValIterationCount;
                    }
                }
                tuneVal = std::nullopt;
            }
            
            
//            printf("%s\n", line.c_str());
        }
        
        for (ssize_t i=std::size(bits)-1; i>=0; i--) {
            const float f = (float)bits[i] / totalIterationCount;
            printf("%.6f \t", f);
        }
        printf("\n");
    
    } catch (const std::exception& e) {
        // Ensure that the error gets printed after all our regular output,
        // in case stderr is redirected to stdout
        fflush(stdout);
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

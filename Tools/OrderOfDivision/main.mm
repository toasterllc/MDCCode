#import <Foundation/Foundation.h>
#import <cstdlib>
#import <algorithm>

constexpr uint16_t VoltageDividerNumer = 4;
constexpr uint16_t VoltageDividerDenom = 3;

static uint16_t Millivolts64(uint16_t sample1V5, uint16_t sampleBat, uint16_t adc1V5RefFactor) {
    return (UINT64_C(1500) * sampleBat * adc1V5RefFactor * VoltageDividerNumer) /
        ((uint64_t)sample1V5 * 0x8000 * VoltageDividerDenom);
}

static uint16_t Millivolts32a(uint16_t sample1V5, uint16_t sampleBat, uint16_t adc1V5RefFactor) {
    const auto _ADC1V5RefFactor = adc1V5RefFactor;
    
    // Calculate the battery voltage in millivolts, correcting the sample using the 1.5V reference
    // voltage, and the voltage divider ratio.
    uint32_t x = sampleBat;
    // Correct using 1V5 calibration reference factor
    x *= _ADC1V5RefFactor;
    x /= 0x8000;
    // Convert to millivolts, correcting for the voltage divider
    x *= 1500 * VoltageDividerNumer;
    x /= sample1V5 * VoltageDividerDenom;
    return x;
    
//    const uint32_t x = ((uint32_t)sampleBat * (uint32_t)adc1V5RefFactor) / 0x8000;
//    return (UINT32_C(1500) * x * VoltageDividerNumer) /
//        ((uint32_t)sample1V5 * VoltageDividerDenom);
}

static uint16_t Millivolts32b(uint16_t sample1V5, uint16_t sampleBat, uint16_t adc1V5RefFactor) {
    const uint32_t x = ((UINT32_C(1500) * sampleBat * VoltageDividerNumer) /
        ((uint32_t)sample1V5 * VoltageDividerDenom));
    return (x * adc1V5RefFactor) / 0x8000;
}

static uint16_t AddNoise(uint16_t nominal, uint8_t noisePercent) {
    const uint32_t NoiseMagnitude = (nominal*noisePercent)/100;
    const int32_t noise = (int32_t)arc4random_uniform(2*NoiseMagnitude) - NoiseMagnitude;
    return std::clamp(nominal+noise, 0, UINT16_MAX);
}

int main(int argc, const char* argv[]) {
    constexpr size_t TrialCount = 1000000;
    double errora = 0;
    double errorb = 0;
    for (size_t i=0; i<TrialCount; i++) {
        constexpr uint16_t Sample1V5Nominal = (1500*65535)/3300; // 1.5/3.3, normalized to u16
//        constexpr uint16_t SampleBatNominal = (((3*4300/4)*65535)/3300); // 4.3V, after voltage divider, normalized to u16
        constexpr uint16_t SampleBatNominal = (((3*3600/4)*65535)/3300); // 3.6V, after voltage divider, normalized to u16
        constexpr uint16_t Adc1V5RefFactorNominal = 0x8000;
        
        const uint16_t sample1V5 = AddNoise(Sample1V5Nominal, 10);
        const uint16_t sampleBat = AddNoise(SampleBatNominal, 10);
        const uint16_t adc1V5RefFactor = AddNoise(Adc1V5RefFactorNominal, 10);
        
        const uint16_t mv64 = Millivolts64(sample1V5, sampleBat, adc1V5RefFactor);
        const uint16_t mv32a = Millivolts32a(sample1V5, sampleBat, adc1V5RefFactor);
        const uint16_t mv32b = Millivolts32b(sample1V5, sampleBat, adc1V5RefFactor);
        const uint16_t diffa = (mv64>mv32a ? mv64-mv32a : mv32a-mv64);
        const uint16_t diffb = (mv64>mv32b ? mv64-mv32b : mv32b-mv64);
        
        errora += ((double)diffa / mv64);
        errorb += ((double)diffb / mv64);
        
        printf("%ju | %ju (%ju / %.1f%%) | %ju (%ju / %.1f%%) \n", (uintmax_t)mv64,
            (uintmax_t)mv32a, (uintmax_t)diffa, ((float)diffa / mv64)*100,
            (uintmax_t)mv32b, (uintmax_t)diffb, ((float)diffb / mv64)*100
        );
    }
    
    printf("Average error, Millivolts32a: %f\n", errora/TrialCount);
    printf("Average error, Millivolts32b: %f\n", errorb/TrialCount);
    
    return 0;
}

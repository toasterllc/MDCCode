#import <Foundation/Foundation.h>
#import <cstdlib>
#import <algorithm>

constexpr uint16_t VoltageDividerNumer = 4;
constexpr uint16_t VoltageDividerDenom = 3;

static uint16_t Millivolts_Original(uint16_t sample1V5, uint16_t sampleBat, uint16_t adc1V5RefFactor) {
    return (UINT64_C(1500) * sampleBat * adc1V5RefFactor * VoltageDividerNumer) /
        ((uint64_t)sample1V5 * 0x8000 * VoltageDividerDenom);
}

static uint16_t Millivolts_Compact1(uint16_t sample1V5, uint16_t sampleBat, uint16_t adc1V5RefFactor) {
    const uint32_t x = ((uint32_t)sampleBat * (uint32_t)adc1V5RefFactor) / 0x8000;
    return (UINT32_C(1500) * x * VoltageDividerNumer) /
        ((uint32_t)sample1V5 * VoltageDividerDenom);
}

static uint16_t Millivolts_Compact2(uint16_t sample1V5, uint16_t sampleBat, uint16_t adc1V5RefFactor) {
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
    for (;;) {
        constexpr uint16_t Sample1V5Nominal = (1500*65535)/3300; // 1.5/3.3, normalized to u16
//        constexpr uint16_t SampleBatNominal = (((3*4300/4)*65535)/3300); // 4.3V, after voltage divider, normalized to u16
        constexpr uint16_t SampleBatNominal = (((3*3600/4)*65535)/3300); // 3.6V, after voltage divider, normalized to u16
        constexpr uint16_t Adc1V5RefFactorNominal = 0x8000;
        
        const uint16_t sample1V5 = AddNoise(Sample1V5Nominal, 10);
        const uint16_t sampleBat = AddNoise(SampleBatNominal, 10);
        const uint16_t adc1V5RefFactor = AddNoise(Adc1V5RefFactorNominal, 10);
        
        const uint16_t original = Millivolts_Original(sample1V5, sampleBat, adc1V5RefFactor);
        const uint16_t compact1 = Millivolts_Compact1(sample1V5, sampleBat, adc1V5RefFactor);
        const uint16_t compact2 = Millivolts_Compact2(sample1V5, sampleBat, adc1V5RefFactor);
        const uint16_t diff1 = (original>compact1 ? original-compact1 : compact1-original);
        const uint16_t diff2 = (original>compact2 ? original-compact2 : compact2-original);
        
        printf("%ju | %ju (%ju / %.1f%%) | %ju (%ju / %.1f%%) \n", (uintmax_t)original,
            (uintmax_t)compact1, (uintmax_t)diff1, ((float)diff1 / original)*100,
            (uintmax_t)compact2, (uintmax_t)diff2, ((float)diff2 / original)*100
        );
//        usleep(100000);
    }
    return 0;
}

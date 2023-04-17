#pragma once
#include <msp430.h>
#include "MSP.h"
#include "RegLocker.h"
#include "Assert.h"

template <
auto T_Domain,
typename T_Scheduler,
typename T_BatChrgLvlPin,
typename T_BatChrgLvlEn_Pin
>
class BatterySamplerType {
public:
    static constexpr auto AssertDomain = T_Domain;
    
    struct Pin {
        using BatChrgLvlPin = typename T_BatChrgLvlPin::template Opts<GPIO::Option::Input>;
        #warning TODO: Keep BatChrgLvlEn_ asserted because it makes BAT_CHRG_STAT work for some reason.
        #warning TODO: We need to debug and see if once we correct U5 to be a buffer (instead of an inverter),
        #warning TODO: and we switch BatChrgLvlEn_ polarity back (BatChrgLvlEn_ -> BatChrgLvlEn), does
        #warning TODO: BAT_CHRG_STAT work? Does it oscillate or does the high-z state work as expected?
        using BatChrgLvlEn_Pin = typename T_BatChrgLvlEn_Pin::template Opts<GPIO::Option::Output0>;
    };
    
    static void Init() {
        // Configure ADC pin
        static_assert(Pin::BatChrgLvlPin::PinIdx < 8);
        SYSCFG2 |= Pin::BatChrgLvlPin::Bit;
        
        // Configure ADC10
        {
            // ADCSHT=15: ADC sample-and-hold time = 1024 clocks
            // ADCMSC=1: multiple samples+conversions
            // ADCON=0: ADC off
            // ADCENC=0: ADC disabled
            // ADCSC=0: don't start a conversion
            ADCCTL0 = ADCSHT_15 | ADCMSC | (ADCON&0) | (ADCENC&0) | (ADCSC&0);
            
            // ADCSHS=0: sample-and-hold source = ADCSC signal
            // ADCSHP=1: SAMPCON source = sampling timer
            // ADCISSH=0: ADC invert sample-and-hold signal = not inverted
            // ADCDIV=0: ADC clock divider = divide by 1
            // ADCSSEL=0: ADC clock = MODCLK
            // ADCCONSEQ=2: ADC mode = repeat-single-channel
            ADCCTL1 = ADCSHS_0 | ADCSHP | (ADCISSH&0) | ADCDIV_0 | ADCSSEL_0 | ADCCONSEQ_2;
            
            // ADCPDIV=0: ADC predivider = 1
            // ADCRES=1: ADC resolution = 10-bit
            // ADCDF=0: ADC data read-back format = unsigned
            // ADCSR=0: ADC sampling rate = 200k samples/sec
            ADCCTL2 = ADCRES_1;
            
            // Enable interrupts:
            //   ADCTOVIE: conversion-time overflow
            //   ADCOVIE: ADCMEM0 overflow
            //   ADCIE0: conversion complete
            ADCIE = ADCTOVIE | ADCOVIE | ADCIE0;
            
            // ADCSREF=0: VR=AVCC/AVSS
            // ADCINCH=0: disable all channels
            ADCMCTL0 = ADCSREF_0;
        }
    }
    
    static MSP::BatteryChargeLevel Sample() {
        _ADCEnable(true);
        
        // Sample internal reference
        uint16_t sample1V5 = 0;
        {
            // Enable internal reference
            {
                PMMUnlock pmm; // Unlock PMM registers
                PMMCTL2 |= INTREFEN;
            }
            
            // Wait 30us for the internal reference to settle
            // Datasheet: "The on-chip reference from the PMM module must be enabled by
            // software. Its settling time is ≤30 µs."
            T_Scheduler::Sleep(T_Scheduler::Us(30));
            
            sample1V5 = _ChannelSample(_Channel::IntRef1V5);
            
            // Disable internal reference (to save power)
            {
                PMMUnlock pmm; // Unlock PMM registers
                PMMCTL2 &= ~INTREFEN;
            }
        }
        
        // Sample battery voltage
        uint16_t sampleBat = 0;
        {
            #warning TODO: for the Rev8 board: uncomment our pin enabling/sleep/disabling code here, because BAT_CHRG_LVL_EN should work as intended on Rev8.
            #warning TODO: on Rev7 it doesn't work as intended because U5 is an inverter instead of a buffer, so we decided to leave BAT_CHRG_LVL_EN enabled all the time, instead of enabling it only when sampling.
//            // Enable BAT_CHRG_LVL buffer
//            Pin::BatChrgLvlEn_Pin::Write(0);
//            
//            // Wait 5 time constants for BAT_CHRG_LVL to settle:
//            //   5 time constants = 5*R*C (where R=1k, C=100n) = 500us
//            T_Scheduler::Sleep(T_Scheduler::Us(500));
            
            sampleBat = _ChannelSample(_Channel::BatChrgLvl);
            
//            // Disable BAT_CHRG_LVL buffer (to save power)
//            Pin::BatChrgLvlEn_Pin::Write(1);
        }
        
        _ADCEnable(false);
        
        // Calculate the battery voltage in millivolts, correcting the sample using the 1.5V reference
        // voltage, and the voltage divider ratio.
        // We did a quick analysis (see Tools/OrderOfDivision project) to determine the average error
        // and optimal order of operations when using 32-bit math instead of 64-bit math (which
        // is very expensive space-wise). With our random test data, the following 32-bit
        // implementation results in 0.0009% average error in the resulting millivolts value compared
        // to the 64-bit implementation.
        constexpr uint16_t VoltageDividerNumer = 4;
        constexpr uint16_t VoltageDividerDenom = 3;
        uint32_t mv = sampleBat;
        // Correct using 1V5 calibration reference factor
        mv *= _ADC1V5RefFactor;
        mv /= 0x8000;
        // Convert to millivolts, correcting for the effect of the voltage divider
        mv *= 1500 * VoltageDividerNumer;
        mv /= sample1V5 * VoltageDividerDenom;
        return _BatteryChargeLevelForMillivolts(mv);
    }
    
    static void ISR(uint16_t iv) {
        switch (__even_in_range(iv, ADCIV_ADCIFG)) {
        case ADCIV_ADCOVIFG:    Assert(false); break;
        case ADCIV_ADCTOVIFG:   Assert(false); break;
        case ADCIV_ADCIFG:      _SampleHandle(ADCMEM0); break;
        default:                Assert(false); break;
        }
    }
    
private:
    struct _Channel {
        static constexpr uint16_t BatChrgLvl = Pin::BatChrgLvlPin::PinIdx;
        static constexpr uint16_t IntRef1V5  = 13; // Internal 1.5V reference is connected to ADC channel 13
    };
    
    static void _ADCEnable(bool en) {
        if (en) {
            // Turn on ADC
            ADCCTL0 |= ADCON;
            // Wait tADCON=100ns, which is 2 cycles at our max frequency (16 MHz)
            __delay_cycles(2);
        
        } else {
            // Turn off ADC
            ADCCTL0 &= ~ADCON;
        }
    }
    
    static uint16_t _ChannelSample(uint16_t ch) {
        // Reset state
        _Sample.done = false;
        _Sample.count = 0;
        _Sample.val = 0;
        // Trigger sampling to start
        _SampleStart(ch);
        // Wait until we're done sampling
        T_Scheduler::Wait([] { return _Sample.done; });
        return _Sample.val;
    }
    
    static void _SampleStart(uint16_t ch) {
        // Set the channel to be sampled
        ADCMCTL0 = (ADCMCTL0 & ~ADCINCH_15) | ch;
        // Start repeated ADC sampling
        ADCCTL0 |= ADCENC | ADCSC;
    }
    
    static void _SampleStop() {
        ADCCTL0 &= ~ADCENC;
    }
    
    static void _SampleHandle(uint16_t sample) {
        Assert(!_Sample.done);
        
        _Sample.count++;
        Assert(_Sample.count <= _SampleCount);
        // Stop ADC sampling upon receiving the second-to-last sample, during which the
        // last sample is underway.
        // This stops ADC sampling "at the end of the current conversion", ie at the
        // end of the final sample.
        if (_Sample.count == _SampleCount-1) {
            _SampleStop();
        } else if (_Sample.count == _SampleCount) {
            _Sample.done = true;
        }
        
        _Sample.val += _SampleCorrect(sample);
    }
    
    static uint16_t _SampleCorrect(uint16_t sample) {
        // Correct the sample using the calibration values stored in the MSP430 TLV
        return (((uint32_t)sample * _ADCGain) / 0x8000) + _ADCOffset;
    }
    
    // _BatteryChargeLevelForMillivolts(): converts a voltage (in millivolts) into a linear
    // range between [0,100]
    static MSP::BatteryChargeLevel _BatteryChargeLevelForMillivolts(uint16_t mv) {
        struct Entry {
            uint16_t mv;
            uint16_t level;
        };
        
        // Table: generated by MDCAnalysis/BatteryChargeLevelTableGenerate.py
        // Let f(t) = battery voltage versus time, where time is normalized
        // between [0x0, 0xFFFF].
        // This table is a piecewise-linear representation of inverse[f(t)]:
        // it accepts a voltage, and returns the 'normalized time' corresponding
        // to that voltage, which can be thought of as the battery charge level.
        // If this table models the battery correctly, the returned result should
        // progress linearly, in contrast to the battery's non-linear
        // charge/discharge curve.
        // In user-facing terms: this table should behave such that capturing N
        // photos per day should deplete the battery X% per day, regardless of
        // how charged the battery is.
        static Entry Table[] = {
            { 3000,   228 },
            { 3150,   585 },
            { 3300,  1183 },
            { 3375,  1638 },
            { 3450,  2262 },
            { 3525,  3142 },
            { 3600,  4421 },
            { 3638,  5283 },
            { 3675,  6351 },
            { 3712,  7689 },
            { 3750,  9385 },
            { 3769, 10404 },
            { 3788, 11559 },
            { 3806, 12874 },
            { 3825, 14374 },
            { 3844, 16087 },
            { 3863, 18045 },
            { 3881, 20283 },
            { 3900, 22834 },
            { 3919, 25729 },
            { 3938, 28990 },
            { 3956, 32615 },
            { 3975, 36572 },
            { 4013, 45099 },
            { 4031, 49339 },
            { 4050, 53282 },
            { 4059, 55078 },
            { 4069, 56729 },
            { 4078, 58221 },
            { 4088, 59546 },
            { 4097, 60702 },
            { 4106, 61693 },
            { 4116, 62529 },
            { 4125, 63220 },
            { 4144, 64234 },
            { 4162, 64860 },
            { 4181, 65219 },
            { 4200, 65408 },
        };
        
        auto it = std::lower_bound(std::begin(Table), std::end(Table), 0,
            [&](const Entry& entry, auto) -> bool {
                return entry.mv < mv;
            });
        
        // If the result is the first element, then we can't get the element before it
        // to perform interpolation with, so consider ourself at the minimum charge
        // level.
        if (it == std::begin(Table)) {
            return MSP::BatteryChargeLevelMin;
        // If we couldn't find a matching element, then there's no element >= `mv`,
        // so `mv` must be greater than all of our Table entries, so consider ourself
        // at the maximum charge level.
        } else if (it == std::end(Table)) {
            return MSP::BatteryChargeLevelMax;
        }
        
        const Entry& left = *std::prev(it);
        const Entry& right = *it;
        
        // Interpolate between `left` and `right`, where the result is normalized between [0x0, 0xFFFF]
        const uint16_t levelFFFF =
            left.level + (((uint32_t)(mv-left.mv) * (uint32_t)(right.level-left.level)) / (right.mv-left.mv));
        // Convert `levelFFFF` from the range [0x0, 0xFFFF] -> [0, 100]
        const uint16_t level100 = ((uint32_t)levelFFFF * MSP::BatteryChargeLevelMax) / UINT16_MAX;
        return level100;
    }
    
    // Collect as many 10-bit samples as will fit in a uint16_t without overflowing
    static constexpr uint16_t _SampleCount = 0xFFFF / 0x03FF;
    static_assert(_SampleCount == 64);
    
    static const inline uint16_t& _ADCGain = *((const uint16_t*)0x1A16);
    static const inline int16_t& _ADCOffset = *((const int16_t*)0x1A18);
    static const inline uint16_t& _ADC1V5RefFactor = *((const uint16_t*)0x1A20);
    
    static inline struct {
        volatile bool done = false;
        volatile uint16_t count = 0;
        volatile uint16_t val = 0;
    } _Sample;
};

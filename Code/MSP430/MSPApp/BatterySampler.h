#pragma once
#include <msp430.h>
#include "MSP.h"
#include "RegLocker.h"

template <
typename T_Scheduler,
typename T_BatChrgLvlPin,
typename T_BatChrgLvlEn_Pin,
[[noreturn]] void T_Error(uint16_t)
>
class BatterySamplerType {
#define Assert(x) if (!(x)) T_Error(__LINE__)
    
public:
    struct Pin {
        using BatChrgLvlPin = typename T_BatChrgLvlPin::template Opts<GPIO::Option::Input>;
        using BatChrgLvlEn_Pin = typename T_BatChrgLvlEn_Pin::template Opts<GPIO::Option::Output1>;
    };
    
    using LED_GREEN_ = GPIO::PortA::Pin<0x1, GPIO::Option::Output1>;
    
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
    
    static MSP::BatterySample Sample() {
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
            // Enable BAT_CHRG_LVL buffer
            Pin::BatChrgLvlEn_Pin::Write(0);
            
            // Wait 5 time constants for BAT_CHRG_LVL to settle:
            //   5 time constants -> 5*R*C (where R=1k, C=100n) -> 500us 
            T_Scheduler::Sleep(T_Scheduler::Us(500));
            
            sampleBat = _ChannelSample(_Channel::BatChrgLvl);
            
            // Disable BAT_CHRG_LVL buffer (to save power)
            Pin::BatChrgLvlEn_Pin::Write(1);
        }
        
        _ADCEnable(false);
        
        // Calculate the battery voltage in millivolts, correcting the sample using the 1.5V reference
        // voltage, and the voltage divider ratio.
        constexpr uint16_t VoltageDividerNumer = 4;
        constexpr uint16_t VoltageDividerDenom = 3;
        const uint32_t mv = (UINT32_C(1500) * sampleBat * VoltageDividerNumer) / ((uint32_t)sample1V5 * VoltageDividerDenom);
        return mv;
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
        T_Scheduler::Wait([&] { return _Sample.done; });
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
    
//    static void _SampleStop() {
//        // Users Guide: "Any conversion mode can be stopped immediately by setting CONSEQx = 0 and setting ADCENC = 0."
//        // We're not sure what 'immediately' means, but hopefully 10 ADC clock cycles with ADCCONSEQ=0 is enough.
//        // The fADCOSC,min = 3.8 MHz, while MCLK=16MHz, so:
//        //   (10*(1/3.8e6))/(1/16e6) = 42 MCLK cycles to meet 10 ADC clock cycles
//        // Rounding up to 50 MCLK cycles.
//        const uint16_t ADCCTL1saved = ADCCTL1;
//        ADCCTL1 &= ~ADCCONSEQ;
//        ADCCTL0 &= ~ADCENC;
//        __delay_cycles(50);
//        ADCCTL1 = ADCCTL1saved;
//    }
    
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
    
    // Collect as many 10-bit samples as will fit in a uint16_t without overflowing
    static constexpr uint16_t _SampleCount = 0xFFFF / 0x03FF;
    static_assert(_SampleCount == 64);
    
    static const inline uint16_t& _ADCGain = *((const uint16_t*)0x1A16);
    static const inline int16_t& _ADCOffset = *((const int16_t*)0x1A18);
    
    static inline struct {
        volatile bool done = false;
        volatile uint16_t count = 0;
        volatile uint16_t val = 0;
    } _Sample;
    
#undef Assert
};

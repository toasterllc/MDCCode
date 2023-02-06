//#define GPIOPort(name, addr)                            \
//    extern "C" GPIO_TypeDef name;                       \
//    __asm__(                                            \
//        ".global " #name                        "\n"    \
//        ".equ    " #name ", " Stringify(addr)   "\n"    \
//    )
//
//GPIOPort(GPIOPortA, GPIOA_BASE);
//GPIOPort(GPIOPortB, GPIOB_BASE);
//GPIOPort(GPIOPortC, GPIOC_BASE);
//GPIOPort(GPIOPortD, GPIOD_BASE);
//GPIOPort(GPIOPortE, GPIOE_BASE);
//GPIOPort(GPIOPortF, GPIOF_BASE);
//GPIOPort(GPIOPortG, GPIOG_BASE);
//GPIOPort(GPIOPortH, GPIOH_BASE);
//GPIOPort(GPIOPortI, GPIOI_BASE);






#pragma once
#include "Toastbox/Scheduler.h"
#include "stm32f7xx.h"
#include "Util.h"

namespace GPIO {

enum class Option : uint8_t {
    // Mode
    Input,
    Output0,
    Output1,
    Analog,
    
    // Special options
    OpenDrain,
    
    // Speed
    Speed0,     // Low
    Speed1,     // Medium
    Speed2,     // High
    Speed3,     // Very high
    
    // Pullup/pulldown resistor
    Resistor0,
    Resistor1,
    
    // Interrupts
    IntRise,
    IntFall,
    IntRiseFall,
    
    // Alternate functions
    AltFn0,
    AltFn1,
    AltFn2,
    AltFn3,
    AltFn4,
    AltFn5,
    AltFn6,
    AltFn7,
    AltFn8,
    AltFn9,
    AltFn10,
    AltFn11,
    AltFn12,
    AltFn13,
    AltFn14,
    AltFn15,
};

enum class PortIndex { A, B, C, D, E, F, G, H, I };

struct GPIORegs {
    uint32_t MODER      = 0x00000000;
    uint32_t OTYPER     = 0x00000000;
    uint32_t OSPEEDR    = 0x00000000;
    uint32_t PUPDR      = 0x00000000;
    uint32_t ODR        = 0x00000000;
    uint32_t AFRL       = 0x00000000;
    uint32_t AFRH       = 0x00000000;
};

struct SYSCFGRegs {
    uint32_t EXTICR1    = 0x00000000;
    uint32_t EXTICR2    = 0x00000000;
    uint32_t EXTICR3    = 0x00000000;
    uint32_t EXTICR4    = 0x00000000;
};

struct EXTIRegs {
    uint32_t IMR        = 0x00000000;
    uint32_t EMR        = 0x00000000;
    uint32_t RTSR       = 0x00000000;
    uint32_t FTSR       = 0x00000000;
};

template <PortIndex T_PortIdx>
class Port {
public:
    template <uint8_t T_PinIdx, Option... T_Opts>
    class Pin {
    public:
        static constexpr PortIndex PortIdx  = T_PortIdx;
        static constexpr uint8_t PinIdx     = T_PinIdx;
//        static constexpr uint16_t Bit       = UINT16_C(1)<<PinIdx;
        
        template <Option... T_NewOpts>
        using Opts = Port::Pin<PinIdx, T_NewOpts...>;
        
        // MARK: - GPIO Registers
        
        static constexpr uint32_t MODER() {
            if constexpr (_Getter(Option::Output0)) return 0x01<<(2*PinIdx);
            if constexpr (_Getter(Option::Output1)) return 0x01<<(2*PinIdx);
            if constexpr (_AltFnEn())               return 0x02<<(2*PinIdx);
            if constexpr (_Getter(Option::Analog))  return 0x03<<(2*PinIdx);
            return 0;
        }
        
        static constexpr uint32_t MODERMask() {
            return 0x03<<(2*PinIdx);
        }
        
        static constexpr uint32_t OTYPER() {
            if constexpr (_Getter(Option::OpenDrain)) return 1<<PinIdx;
            return 0;
        }
        
        static constexpr uint32_t OTYPERMask() {
            return 1<<PinIdx;
        }
        
        static constexpr uint32_t OSPEEDR() {
            if constexpr (_Getter(Option::Speed1)) return 0x01<<(2*PinIdx);
            if constexpr (_Getter(Option::Speed2)) return 0x02<<(2*PinIdx);
            if constexpr (_Getter(Option::Speed3)) return 0x03<<(2*PinIdx);
            return 0;
        }
        
        static constexpr uint32_t OSPEEDRMask() {
            return 0x03<<(2*PinIdx);
        }
        
        static constexpr uint32_t PUPDR() {
            if constexpr (_Getter(Option::Resistor1)) return 0x01<<(2*PinIdx);
            if constexpr (_Getter(Option::Resistor0)) return 0x02<<(2*PinIdx);
            return 0;
        }
        
        static constexpr uint32_t PUPDRMask() {
            return 0x03<<(2*PinIdx);
        }
        
        static constexpr uint32_t ODR() {
            if constexpr (_Getter(Option::Output1)) return 1<<PinIdx;
            return 0;
        }
        
        static constexpr uint32_t ODRMask() {
            return 1<<PinIdx;
        }
        
        // Writing IDR doesn't make sense, so we don't supply IDR()
//        static constexpr uint32_t IDR() {
//            return 0x00;
//        }
        
        static constexpr uint32_t IDRMask() {
            return 1<<PinIdx;
        }
        
        static constexpr uint32_t BSRRSetMask() {
            return 1<<PinIdx;
        }
        
        static constexpr uint32_t BSRRResetMask() {
            return 1<<(16 + PinIdx);
        }
        
        static constexpr uint32_t AFRL() {
            if constexpr (PinIdx < 8) return _AltFn()<<(4*PinIdx);
            return 0;
        }
        
        static constexpr uint32_t AFRLMask() {
            if constexpr (PinIdx < 8) return 0x0F<<(4*PinIdx);
            return 0;
        }
        
        static constexpr uint32_t AFRH() {
            if constexpr (PinIdx >= 8) return _AltFn()<<(4*(PinIdx-8));
            return 0;
        }
        
        static constexpr uint32_t AFRHMask() {
            if constexpr (PinIdx >= 8) return 0x0F<<(4*(PinIdx-8));
            return 0;
        }
        
        // MARK: - SYSCFG Registers
        static constexpr uint32_t EXTICR1() {
            if constexpr ((PinIdx/4) == 0) return ((uint32_t)PortIdx << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR1Mask() {
            if constexpr ((PinIdx/4) == 0) return (0x0F << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR2() {
            if constexpr ((PinIdx/4) == 1) return ((uint32_t)PortIdx << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR2Mask() {
            if constexpr ((PinIdx/4) == 1) return (0x0F << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR3() {
            if constexpr ((PinIdx/4) == 2) return ((uint32_t)PortIdx << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR3Mask() {
            if constexpr ((PinIdx/4) == 2) return (0x0F << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR4() {
            if constexpr ((PinIdx/4) == 3) return ((uint32_t)PortIdx << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        static constexpr uint32_t EXTICR4Mask() {
            if constexpr ((PinIdx/4) == 3) return (0x0F << (4 * (PinIdx & 0x03)));
            return 0;
        }
        
        // MARK: - EXTI Registers
        
        static constexpr uint32_t IMR() {
            if constexpr (_IntEn()) return 1<<PinIdx;
            return 0;
        }
        
        static constexpr uint32_t IMRMask() {
            return 1<<PinIdx;
        }
        
        static constexpr uint32_t EMR() {
            // We don't support events yet (only interrupts)
            return 0;
        }
        
        static constexpr uint32_t EMRMask() {
            return 1<<PinIdx;
        }
        
        static constexpr uint32_t RTSR() {
            if constexpr (_Getter(Option::IntRise))     return 1<<PinIdx;
            if constexpr (_Getter(Option::IntRiseFall)) return 1<<PinIdx;
            return 0;
        }
        
        static constexpr uint32_t RTSRMask() {
            return 1<<PinIdx;
        }
        
        static constexpr uint32_t FTSR() {
            if constexpr (_Getter(Option::IntFall))     return 1<<PinIdx;
            if constexpr (_Getter(Option::IntRiseFall)) return 1<<PinIdx;
            return 0;
        }
        
        static constexpr uint32_t FTSRMask() {
            return 1<<PinIdx;
        }
        
        // Init(): configure the pin
        static constexpr void Init() {
        }
        
        // Init(): configure the pin, but only emit instructions for the changes relative to `T_Prev`
        template <typename T_Prev>
        static constexpr void Init() {
        }
        
        static bool Read() {
            return RegsRef().IDR & IDRMask();
        }
        
        static void Write(bool x) {
            if (x) RegsRef().BSRR |= BSRRSetMask();
            else   RegsRef().BSRR |= BSRRResetMask();
        }
        
        // State: accessors for reading/writing pin configuration at runtime
        struct State {
        };
        
    private:
        static constexpr bool _AltFnEn() {
            if constexpr (_Getter(Option::AltFn0))  return true;
            if constexpr (_Getter(Option::AltFn1))  return true;
            if constexpr (_Getter(Option::AltFn2))  return true;
            if constexpr (_Getter(Option::AltFn3))  return true;
            if constexpr (_Getter(Option::AltFn4))  return true;
            if constexpr (_Getter(Option::AltFn5))  return true;
            if constexpr (_Getter(Option::AltFn6))  return true;
            if constexpr (_Getter(Option::AltFn7))  return true;
            if constexpr (_Getter(Option::AltFn8))  return true;
            if constexpr (_Getter(Option::AltFn9))  return true;
            if constexpr (_Getter(Option::AltFn10)) return true;
            if constexpr (_Getter(Option::AltFn11)) return true;
            if constexpr (_Getter(Option::AltFn12)) return true;
            if constexpr (_Getter(Option::AltFn13)) return true;
            if constexpr (_Getter(Option::AltFn14)) return true;
            if constexpr (_Getter(Option::AltFn15)) return true;
            return false;
        }
        
        static constexpr uint32_t _AltFn() {
            if constexpr (_Getter(Option::AltFn0))  return 0x00;
            if constexpr (_Getter(Option::AltFn1))  return 0x01;
            if constexpr (_Getter(Option::AltFn2))  return 0x02;
            if constexpr (_Getter(Option::AltFn3))  return 0x03;
            if constexpr (_Getter(Option::AltFn4))  return 0x04;
            if constexpr (_Getter(Option::AltFn5))  return 0x05;
            if constexpr (_Getter(Option::AltFn6))  return 0x06;
            if constexpr (_Getter(Option::AltFn7))  return 0x07;
            if constexpr (_Getter(Option::AltFn8))  return 0x08;
            if constexpr (_Getter(Option::AltFn9))  return 0x09;
            if constexpr (_Getter(Option::AltFn10)) return 0x0A;
            if constexpr (_Getter(Option::AltFn11)) return 0x0B;
            if constexpr (_Getter(Option::AltFn12)) return 0x0C;
            if constexpr (_Getter(Option::AltFn13)) return 0x0D;
            if constexpr (_Getter(Option::AltFn14)) return 0x0E;
            if constexpr (_Getter(Option::AltFn15)) return 0x0F;
            return 0;
        }
        
        static constexpr bool _IntEn() {
            if constexpr (_Getter(Option::IntRise))     return true;
            if constexpr (_Getter(Option::IntFall))     return true;
            if constexpr (_Getter(Option::IntRiseFall)) return true;
            return false;
        }
        
        static constexpr bool _Getter(Option opt) {
            for (const Option o : (Option[]){T_Opts...}) {
                if (o == opt) return true;
            }
            return false;
        }
    };
    
    static constexpr GPIO_TypeDef& RegsRef() {
        if constexpr (T_PortIdx == PortIndex::A) return *GPIOA;
        if constexpr (T_PortIdx == PortIndex::B) return *GPIOB;
        if constexpr (T_PortIdx == PortIndex::C) return *GPIOC;
        if constexpr (T_PortIdx == PortIndex::D) return *GPIOD;
        if constexpr (T_PortIdx == PortIndex::E) return *GPIOE;
        if constexpr (T_PortIdx == PortIndex::F) return *GPIOF;
        if constexpr (T_PortIdx == PortIndex::G) return *GPIOG;
        if constexpr (T_PortIdx == PortIndex::H) return *GPIOH;
        if constexpr (T_PortIdx == PortIndex::I) return *GPIOI;
    }
};

template <typename T_Port>
static void GPIORegsSet(const GPIORegs& x) {
    GPIO_TypeDef& r = T_Port::RegsRef();
    r.MODER   = x.MODER;
    r.OTYPER  = x.OTYPER;
    r.OSPEEDR = x.OSPEEDR;
    r.PUPDR   = x.PUPDR;
    r.ODR     = x.ODR;
    r.AFR[0]  = x.AFRL;
    r.AFR[1]  = x.AFRH;
}

static void SYSCFGRegsSet(const SYSCFGRegs& x) {
    SYSCFG->EXTICR[1-1] = x.EXTICR1;
    SYSCFG->EXTICR[2-1] = x.EXTICR2;
    SYSCFG->EXTICR[3-1] = x.EXTICR3;
    SYSCFG->EXTICR[4-1] = x.EXTICR4;
}

static void EXTIRegsSet(const EXTIRegs& x) {
    EXTI->IMR  = x.IMR;
    EXTI->EMR  = x.EMR;
    EXTI->RTSR = x.RTSR;
    EXTI->FTSR = x.FTSR;
}





template <PortIndex T_PortIdx>
static constexpr GPIORegs _GPIORegsCollect(GPIORegs r) {
    return r;
}

template <PortIndex T_PortIdx, typename T_Pin, typename... T_Pins>
static constexpr GPIORegs _GPIORegsCollect(GPIORegs r) {
    // Only consider pins for the specified port index (T_PortIdx)
    if constexpr (T_Pin::PortIdx == T_PortIdx) {
        r.MODER   &= ~T_Pin::MODERMask();
        r.OTYPER  &= ~T_Pin::OTYPERMask();
        r.OSPEEDR &= ~T_Pin::OSPEEDRMask();
        r.PUPDR   &= ~T_Pin::PUPDRMask();
        r.ODR     &= ~T_Pin::ODRMask();
        r.AFRL    &= ~T_Pin::AFRLMask();
        r.AFRH    &= ~T_Pin::AFRHMask();
        
        r.MODER   |=  T_Pin::MODER();
        r.OTYPER  |=  T_Pin::OTYPER();
        r.OSPEEDR |=  T_Pin::OSPEEDR();
        r.PUPDR   |=  T_Pin::PUPDR();
        r.ODR     |=  T_Pin::ODR();
        r.AFRL    |=  T_Pin::AFRL();
        r.AFRH    |=  T_Pin::AFRH();
    }
    
    if constexpr (sizeof...(T_Pins)) return _GPIORegsCollect<T_PortIdx, T_Pins...>(r);
    else return r;
}







static constexpr SYSCFGRegs _SYSCFGRegsCollect(SYSCFGRegs r) {
    return r;
}

template <typename T_Pin, typename... T_Pins>
static constexpr SYSCFGRegs _SYSCFGRegsCollect(SYSCFGRegs r) {
    r.EXTICR1 &= ~T_Pin::EXTICR1Mask();
    r.EXTICR2 &= ~T_Pin::EXTICR2Mask();
    r.EXTICR3 &= ~T_Pin::EXTICR3Mask();
    r.EXTICR4 &= ~T_Pin::EXTICR4Mask();
    
    r.EXTICR1 |=  T_Pin::EXTICR1();
    r.EXTICR2 |=  T_Pin::EXTICR2();
    r.EXTICR3 |=  T_Pin::EXTICR3();
    r.EXTICR4 |=  T_Pin::EXTICR4();
    
    if constexpr (sizeof...(T_Pins)) return _SYSCFGRegsCollect<T_Pins...>(r);
    else return r;
}






static constexpr EXTIRegs _EXTIRegsCollect(EXTIRegs r) {
    return r;
}

template <typename T_Pin, typename... T_Pins>
static constexpr EXTIRegs _EXTIRegsCollect(EXTIRegs r) {
    r.IMR  &= ~T_Pin::IMRMask();
    r.EMR  &= ~T_Pin::EMRMask();
    r.RTSR &= ~T_Pin::RTSRMask();
    r.FTSR &= ~T_Pin::FTSRMask();
    
    r.IMR  |=  T_Pin::IMR();
    r.EMR  |=  T_Pin::EMR();
    r.RTSR |=  T_Pin::RTSR();
    r.FTSR |=  T_Pin::FTSR();
    
    if constexpr (sizeof...(T_Pins)) return _EXTIRegsCollect<T_Pins...>(r);
    else return r;
}






using PortA = Port<PortIndex::A>;
using PortB = Port<PortIndex::B>;
using PortC = Port<PortIndex::C>;
using PortD = Port<PortIndex::D>;
using PortE = Port<PortIndex::E>;
using PortF = Port<PortIndex::F>;
using PortG = Port<PortIndex::G>;
using PortH = Port<PortIndex::H>;
using PortI = Port<PortIndex::I>;

template <typename... T_Pins>
static void Init() {
    // Disable interrupts
    Toastbox::IntState ints(false);
    
    #warning TODO: call __HAL_RCC_GPIOX_CLK_ENABLE if we have relevent pins
    GPIORegsSet<PortA>(_GPIORegsCollect<PortIndex::A, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortB>(_GPIORegsCollect<PortIndex::B, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortC>(_GPIORegsCollect<PortIndex::C, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortD>(_GPIORegsCollect<PortIndex::D, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortE>(_GPIORegsCollect<PortIndex::E, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortF>(_GPIORegsCollect<PortIndex::F, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortG>(_GPIORegsCollect<PortIndex::G, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortH>(_GPIORegsCollect<PortIndex::H, T_Pins...>(GPIORegs{}));
    GPIORegsSet<PortI>(_GPIORegsCollect<PortIndex::I, T_Pins...>(GPIORegs{}));
}

} // namespace GPIO

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

template <PortIndex T_PortIdx>
class Port {
public:
    template <uint8_t T_PinIdx, Option... T_Opts>
    class Pin {
    public:
        static constexpr PortIndex PortIdx  = T_PortIdx;
        static constexpr uint8_t PinIdx     = T_PinIdx;
        static constexpr uint16_t Bit       = UINT16_C(1)<<PinIdx;
        
        template <Option... T_NewOpts>
        using Opts = Port::Pin<PinIdx, T_NewOpts...>;
        
        static constexpr uint8_t MODER() {
            if constexpr (_Getter(Option::Output0)) return 0x01;
            if constexpr (_Getter(Option::Output1)) return 0x01;
            if constexpr (_AltFnEn())               return 0x02;
            if constexpr (_Getter(Option::Analog))  return 0x03;
            return 0x00;
        }
        
        static constexpr uint8_t OTYPER() {
            if constexpr (_Getter(Option::OpenDrain)) return 0x01;
            return 0x00;
        }
        
        static constexpr uint8_t OSPEEDR() {
            if constexpr (_Getter(Option::Speed1)) return 0x01;
            if constexpr (_Getter(Option::Speed2)) return 0x02;
            if constexpr (_Getter(Option::Speed3)) return 0x03;
            return 0x00;
        }
        
        static constexpr uint8_t PUPDR() {
            if constexpr (_Getter(Option::Resistor1)) return 0x01;
            if constexpr (_Getter(Option::Resistor0)) return 0x02;
            return 0x00;
        }
        
        static constexpr uint8_t ODR() {
            if constexpr (_Getter(Option::Output1)) return 0x01;
            return 0x00;
        }
        
        static constexpr uint8_t AFRL() {
            if constexpr (PinIdx < 8) {
                return _AltFn();
            }
            return 0x00;
        }
        
        static constexpr uint8_t AFRH() {
            if constexpr (PinIdx >= 8) {
                return _AltFn();
            }
            return 0x00;
        }
        
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
        
        static constexpr uint8_t _AltFn() {
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
            return 0x00;
        }
        
        // Init(): configure the pin
        static constexpr void Init() {
        }
        
        // Init(): configure the pin, but only emit instructions for the changes relative to `T_Prev`
        template <typename T_Prev>
        static constexpr void Init() {
        }
        
        static bool Read() {
            
        }
        
        static void Write(bool x) {
            State::Out(x);
        }
        
        // State: accessors for reading/writing pin configuration at runtime
        struct State {
        };
        
    private:
        static constexpr bool _Getter(Option opt) {
            for (const Option o : (Option[]){T_Opts...}) {
                if (o == opt) return true;
            }
            return false;
        }
    };
    
    struct Regs {
        uint32_t MODER   = 0x00000000;
        uint32_t OTYPER  = 0x00000000;
        uint32_t OSPEEDR = 0x00000000;
        uint32_t PUPDR   = 0x00000000;
        uint32_t ODR     = 0x00000000;
        uint32_t AFRL    = 0x00000000;
        uint32_t AFRH    = 0x00000000;
    };
    
    static constexpr GPIO_TypeDef& _RegsRef() {
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
    
    static void RegsSet(const Regs& regs) {
        GPIO_TypeDef& r = _RegsRef();
        r.MODER   = regs.MODER;
        r.OTYPER  = regs.OTYPER;
        r.OSPEEDR = regs.OSPEEDR;
        r.PUPDR   = regs.PUPDR;
        r.IDR     = regs.IDR;
        r.ODR     = regs.ODR;
        r.AFR[0]  = regs.AFRL;
        r.AFR[1]  = regs.AFRH;
    }
};

template <PortIndex T_PortIdx>
static constexpr _Regs _Collect(_Regs regs) {
    return regs;
}

template <PortIndex T_PortIdx, typename T_Pin, typename... T_Pins>
static constexpr _Regs _Collect(_Regs regs) {
    // Only consider pins for the specified port index (T_PortIdx)
    if constexpr (T_Pin::PortIdx == T_PortIdx) {
        r.MODER   &= regs.MODER;
        r.OTYPER  &= regs.OTYPER;
        r.OSPEEDR &= regs.OSPEEDR;
        r.PUPDR   &= regs.PUPDR;
        r.IDR     &= regs.IDR;
        r.ODR     &= regs.ODR;
        r.AFR[0]  &= regs.AFRL;
        r.AFR[1]  &= regs.AFRH;
        
        0x3<<(2*T_Pin::PinIdx)
        
        
        r.MODER     &= T_Pin::MODERMask();
        
        
        r.MODER     |= T_Pin::MODER();
        
        
        // Clear the bit for the GPIO
        regs.Out    &= ~T_Pin::Bit;
        regs.Dir    &= ~T_Pin::Bit;
        regs.Sel0   &= ~T_Pin::Bit;
        regs.Sel1   &= ~T_Pin::Bit;
        regs.REn    &= ~T_Pin::Bit;
        regs.IE     &= ~T_Pin::Bit;
        regs.IES    &= ~T_Pin::Bit;
        
        // Set the bit for the GPIO, if it's set
        regs.Out    |= (T_Pin::Out()  ? T_Pin::Bit : 0);
        regs.Dir    |= (T_Pin::Dir()  ? T_Pin::Bit : 0);
        regs.Sel0   |= (T_Pin::Sel0() ? T_Pin::Bit : 0);
        regs.Sel1   |= (T_Pin::Sel1() ? T_Pin::Bit : 0);
        regs.REn    |= (T_Pin::REn()  ? T_Pin::Bit : 0);
        regs.IE     |= (T_Pin::IE()   ? T_Pin::Bit : 0);
        regs.IES    |= (T_Pin::IES()  ? T_Pin::Bit : 0);
    }
    
    if constexpr (sizeof...(T_Pins)) return _Collect<T_PortIdx, T_Pins...>(regs);
    else return regs;
}

//template <uint8_t T_PortIdx>
//static constexpr GPIO_TypeDef& _GPIOBase() {
//    
//}

//template <PortIndex& T_Port>
//static void _PortRegsSet(const _Regs& regs) {
//    T_Port.MODER   = regs.MODER;
//    T_Port.OTYPER  = regs.OTYPER;
//    T_Port.OSPEEDR = regs.OSPEEDR;
//    T_Port.PUPDR   = regs.PUPDR;
//    T_Port.IDR     = regs.IDR;
//    T_Port.ODR     = regs.ODR;
//    T_Port.AFR[0]  = regs.AFRL;
//    T_Port.AFR[1]  = regs.AFRH;
//}

template <typename... T_Pins>
static void Init() {
    // Disable interrupts
    Toastbox::IntState ints(false);
    
    _RegsSet(_Collect<PortIndex::A, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::B, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::C, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::D, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::E, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::F, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::G, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::H, T_Pins...>(_Regs{}));
    _RegsSet(_Collect<PortIndex::I, T_Pins...>(_Regs{}));
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

} // namespace GPIO

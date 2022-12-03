#pragma once
#include <msp430.h>
#include <type_traits>
#include <initializer_list>
#include "Toastbox/IntState.h"
#include "Startup.h"

namespace GPIO {

enum class Option : uint8_t {
    // Direction + output value
    Input,
    Output0,
    Output1,
    
    // Pullup/pulldown resistor
    Resistor0,
    Resistor1,
    
    // Function selection
    Sel01,
    Sel10,
    Sel11,
    
    // Interrupts
    Interrupt01,
    Interrupt10,
};

enum class PortIndex { A, B };

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
        using Opts = Port::Pin<T_PinIdx, T_NewOpts...>;
        
        struct InitConfig {
            static constexpr bool Out()     { return _InitGetter(Option::Output1)       || _InitGetter(Option::Resistor1);      }
            static constexpr bool Dir()     { return _InitGetter(Option::Output0)       || _InitGetter(Option::Output1);        }
            static constexpr bool Sel0()    { return _InitGetter(Option::Sel01)         || _InitGetter(Option::Sel11);          }
            static constexpr bool Sel1()    { return _InitGetter(Option::Sel10)         || _InitGetter(Option::Sel11);          }
            static constexpr bool REn()     { return _InitGetter(Option::Resistor0)     || _InitGetter(Option::Resistor1);      }
            static constexpr bool IE()      { return _InitGetter(Option::Interrupt01)   || _InitGetter(Option::Interrupt10);    }
            static constexpr bool IES()     { return _InitGetter(Option::Interrupt10);                                          }
        };
        
        static constexpr void Init() {
            Out(    InitConfig::Out()   );
            Dir(    InitConfig::Dir()   );
            Sel0(   InitConfig::Sel0()  );
            Sel1(   InitConfig::Sel1()  );
            REn(    InitConfig::REn()   );
            IE(     InitConfig::IE()    );
            IES(    InitConfig::IES()   );
        }
        
        static constexpr bool Out() {
            if constexpr (PortIdx == PortIndex::A)      return _Getter(PAOUT);
            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBOUT);
        }
        
        static constexpr bool Dir() {
            if constexpr (PortIdx == PortIndex::A)      return _Getter(PADIR);
            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBDIR);
        }
        
        static constexpr bool Sel0() {
            if constexpr (PortIdx == PortIndex::A)      return _Getter(PASEL0);
            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBSEL0);
        }
        
        static constexpr bool Sel1() {
            if constexpr (PortIdx == PortIndex::A)      return _Getter(PASEL1);
            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBSEL1);
        }
        
        static constexpr bool REn() {
            if constexpr (PortIdx == PortIndex::A)      return _Getter(PAREN);
            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBREN);
        }
        
        template <std::enable_if_t<PortIdx==PortIndex::A, int> = 0>
        static constexpr bool IE() {
            return _Getter(PAIE);
        }
        
        template <std::enable_if_t<PortIdx==PortIndex::A, int> = 0>
        static constexpr bool IES() {
            return _Getter(PAIES);
        }
        
        static constexpr void Out(bool x) {
            if constexpr (PortIdx == PortIndex::A)      _Setter(PAOUT, x);
            else if constexpr (PortIdx == PortIndex::B) _Setter(PBOUT, x);
        }
        
        static constexpr void Dir(bool x) {
            if constexpr (PortIdx == PortIndex::A)      _Setter(PADIR, x);
            else if constexpr (PortIdx == PortIndex::B) _Setter(PBDIR, x);
        }
        
        static constexpr void Sel0(bool x) {
            if constexpr (PortIdx == PortIndex::A)      _Setter(PASEL0, x);
            else if constexpr (PortIdx == PortIndex::B) _Setter(PBSEL0, x);
        }
        
        static constexpr void Sel1(bool x) {
            if constexpr (PortIdx == PortIndex::A)      _Setter(PASEL1, x);
            else if constexpr (PortIdx == PortIndex::B) _Setter(PBSEL1, x);
        }
        
        static constexpr void REn(bool x) {
            if constexpr (PortIdx == PortIndex::A)      _Setter(PAREN, x);
            else if constexpr (PortIdx == PortIndex::B) _Setter(PBREN, x);
        }
        
        template <std::enable_if_t<PortIdx==PortIndex::A, int> = 0>
        static constexpr void IE(bool x) {
            _Setter(PAIE, x);
        }
        
        template <std::enable_if_t<PortIdx==PortIndex::A, int> = 0>
        static constexpr void IES(bool x) {
            _Setter(PAIES, x);
        }
        
        static bool Read() {
            if constexpr (PortIdx == PortIndex::A)      return PAIN & Bit;
            else if constexpr (PortIdx == PortIndex::B) return PBIN & Bit;
        }
        
        static void Write(bool x) {
            Out(x);
        }
        
    private:
        static constexpr bool _InitGetter(Option opt) {
            for (const Option o : (Option[]){T_Opts...}) {
                if (o == opt) return true;
            }
            return false;
        }
        
        template <typename T>
        static constexpr bool _Getter(T& reg) {
            return reg & Bit;
        }
        
        template <typename T>
        static constexpr void _Setter(T& reg, bool x) {
            if (x)  reg |= Bit;
            else    reg &= ~Bit;
        }
    };
};

struct _Regs {
    // Default state for all pins: output strong 0
    uint16_t Out  = 0x0000;
    uint16_t Dir  = 0xFFFF;
    uint16_t Sel0 = 0x0000;
    uint16_t Sel1 = 0x0000;
    uint16_t REn  = 0x0000;
    uint16_t IE   = 0x0000;
    uint16_t IES  = 0x0000;
};

template <PortIndex T_PortIdx>
static constexpr _Regs _GetRegs(_Regs regs) {
    return regs;
}

template <PortIndex T_PortIdx, typename T_Pin, typename... T_Pins>
static constexpr _Regs _GetRegs(_Regs regs) {
    // Only consider pins for the specified port index (T_PortIdx)
    if constexpr (T_Pin::PortIdx == T_PortIdx) {
        // Clear the bit for the GPIO
        regs.Out    &= ~T_Pin::Bit;
        regs.Dir    &= ~T_Pin::Bit;
        regs.Sel0   &= ~T_Pin::Bit;
        regs.Sel1   &= ~T_Pin::Bit;
        regs.REn    &= ~T_Pin::Bit;
        regs.IE     &= ~T_Pin::Bit;
        regs.IES    &= ~T_Pin::Bit;
        
        // Set the bit for the GPIO, if it's set
        regs.Out    |= (T_Pin::InitConfig::Out()  ? T_Pin::Bit : 0);
        regs.Dir    |= (T_Pin::InitConfig::Dir()  ? T_Pin::Bit : 0);
        regs.Sel0   |= (T_Pin::InitConfig::Sel0() ? T_Pin::Bit : 0);
        regs.Sel1   |= (T_Pin::InitConfig::Sel1() ? T_Pin::Bit : 0);
        regs.REn    |= (T_Pin::InitConfig::REn()  ? T_Pin::Bit : 0);
        regs.IE     |= (T_Pin::InitConfig::IE()   ? T_Pin::Bit : 0);
        regs.IES    |= (T_Pin::InitConfig::IES()  ? T_Pin::Bit : 0);
    }
    
    if constexpr (sizeof...(T_Pins)) return _GetRegs<T_PortIdx, T_Pins...>(regs);
    else return regs;
}

template <typename... T_Pins>
static void Init() {
    // Follow the initialization procedure from the MSP430FR24xx user guide
    // From "8.3.1 Configuration After Reset":
    //   1. Initialize Ports: PxDIR, PxREN, PxOUT, and PxIES
    //   2. Clear LOCKLPM5
    //   3. If not waking up from LPMx.5: clear all PxIFGs to avoid erroneous port interrupts
    //   4. Enable port interrupts in PxIE
    //
    // This order is required because the MSP430FR24xx user guide says:
    //   "Note that the PxIFG flag cannot be cleared until the LOCKLPM5 bit has been cleared."
    
    // Disable interrupts
    Toastbox::IntState ints(false);
    
    // Config pins
    
    // Port A
    constexpr _Regs regsA = _GetRegs<PortIndex::A, T_Pins...>(_Regs{});
    PAOUT   = regsA.Out;
    PADIR   = regsA.Dir;
    PASEL0  = regsA.Sel0;
    PASEL1  = regsA.Sel1;
    PAREN   = regsA.REn;
    PAIES   = regsA.IES;
    
    // Port B
    constexpr _Regs regsB = _GetRegs<PortIndex::B, T_Pins...>(_Regs{});
    PBOUT   = regsB.Out;
    PBDIR   = regsB.Dir;
    PBSEL0  = regsB.Sel0;
    PBSEL1  = regsB.Sel1;
    PBREN   = regsB.REn;
    
    // Unlock GPIOs
    PM5CTL0 &= ~LOCKLPM5;
    
    // Clear PxIFG (but only if this was a cold start)
    // We don't want to do this when waking from LPMx.5, because PxIFG may contain
    // the reason for waking, if a GPIO woke us.
    if (Startup::ColdStart()) {
        PAIFG = 0;
    }
    
    // Enable interrupts
    PAIE = regsA.IE;
}

using PortA = Port<PortIndex::A>;
using PortB = Port<PortIndex::B>;

} // namespace GPIO

#pragma once
#include <msp430.h>
#include <type_traits>
#include <initializer_list>
#include <cstdint>

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

template<PortIndex T_PortIdx>
class Port {
public:
#define OnlyPortA                                                   \
    template<                                                      \
    PortIndex _T_PortIdx = PortIdx,                                 \
    typename std::enable_if_t<_T_PortIdx == PortIndex::A, int> = 0  \
    >

#define OnlyPort1                       \
    template<                           \
    PortIndex _T_PortIdx = PortIdx,     \
    uint8_t _T_PinIdx = PinIdx,         \
    typename std::enable_if_t<          \
        _T_PortIdx==PortIndex::A &&     \
        _T_PinIdx>=0 &&                 \
        _T_PinIdx<8                     \
    , int> = 0>

#define OnlyPort2                       \
    template<                           \
    PortIndex _T_PortIdx = PortIdx,     \
    uint8_t _T_PinIdx = PinIdx,         \
    typename std::enable_if_t<          \
        _T_PortIdx==PortIndex::A &&     \
        _T_PinIdx>=8 &&                 \
        _T_PinIdx<16                    \
    , int> = 0>

    template<uint8_t T_PinIdx, Option... T_Opts>
    class Pin {
    public:
        static constexpr PortIndex PortIdx  = T_PortIdx;
        static constexpr uint8_t PinIdx     = T_PinIdx;
        static constexpr uint16_t Bit       = UINT16_C(1)<<PinIdx;
        
        template<Option... T_NewOpts>
        using Opts = Port::Pin<PinIdx, T_NewOpts...>;
        
        static constexpr bool Out()     { return _Getter(Option::Output1)       || _Getter(Option::Resistor1);      }
        static constexpr bool Dir()     { return _Getter(Option::Output0)       || _Getter(Option::Output1);        }
        static constexpr bool Sel0()    { return _Getter(Option::Sel01)         || _Getter(Option::Sel11);          }
        static constexpr bool Sel1()    { return _Getter(Option::Sel10)         || _Getter(Option::Sel11);          }
        static constexpr bool REn()     { return _Getter(Option::Resistor0)     || _Getter(Option::Resistor1);      }
        static constexpr bool IE()      { return _Getter(Option::Interrupt01)   || _Getter(Option::Interrupt10);    }
        static constexpr bool IES()     { return _Getter(Option::Interrupt10);                                      }
        
        // Init(): configure the pin
        //
        // Interrupts must be disabled (so that the pin interrupt state can be updated atomically)
        static constexpr void Init() {
            State::Out(Out());
            State::Dir(Dir());
            State::Sel0(Sel0());
            State::Sel1(Sel1());
            State::REn(REn());
            
            if constexpr (PortIdx == PortIndex::A)
            State::IE(IE());
            
            if constexpr (PortIdx == PortIndex::A)
            State::IES(IES());
            
            // If IE is enabled (0->1), ensure that IFG reflects the state of the
            // pin. This is necessary because we may have missed a transition due
            // to the inherent race between configuring IE/IES and the pin
            // changing state.
            if constexpr (PortIdx == PortIndex::A)
            if constexpr (IE())
            State::IFG(Read() != IES());
        }
        
        // Init(): configure the pin, but only emit instructions for the changes relative to `T_Prev`.
        // The pin is assumed to have one of the configurations supplied by T_Prev.
        //
        // Interrupts must be disabled (so that the pin interrupt state can be updated atomically)
        template<typename... T_Prev>
        static constexpr void Init() {
            if constexpr (((Out() != T_Prev::Out()) || ...))
            State::Out(Out());
            
            if constexpr (((Dir() != T_Prev::Dir()) || ...))
            State::Dir(Dir());
            
            if constexpr (((Sel0() != T_Prev::Sel0()) || ...))
            State::Sel0(Sel0());
            
            if constexpr (((Sel1() != T_Prev::Sel1()) || ...))
            State::Sel1(Sel1());
            
            if constexpr (((REn() != T_Prev::REn()) || ...))
            State::REn(REn());
            
            if constexpr (PortIdx == PortIndex::A)
            if constexpr (((IE() != T_Prev::IE()) || ...))
            State::IE(IE());
            
            if constexpr (PortIdx == PortIndex::A)
            if constexpr (((IES() != T_Prev::IES()) || ...))
            State::IES(IES());
            
            // If IE was enabled (0->1) or IES changed, ensure that IFG reflects the
            // state of the pin. This is necessary because we may have missed a
            // transition due to the inherent race between configuring IE/IES and
            // the pin changing state.
            if constexpr (PortIdx == PortIndex::A)
            if constexpr ((IE() && ((!T_Prev::IE() || ...))) || (((IES() != T_Prev::IES()) || ...)))
            State::IFG(Read() != IES());
        }
        
        // IVPort1(): returns the interrupt vector for Port1 pins
        // We intentionally separate IVPort1() / IVPort2(), instead of having a single IV(),
        // because we want to get a compiler error if we call IVPort1() on a pin that only
        // has a Port2 IV.
        OnlyPort1
        static constexpr uint16_t IVPort1() {
            return (PinIdx+1)<<1;
        }
        
        // IVPort2(): returns the interrupt vector for Port2 pins
        // We intentionally separate IVPort1() / IVPort2(), instead of having a single IV(),
        // because we want to get a compiler error if we call IVPort1() on a pin that only
        // has a Port2 IV.
        OnlyPort2
        static constexpr uint16_t IVPort2() {
            return (PinIdx-8+1)<<1;
        }
        
        static bool Read() {
            if constexpr (PortIdx == PortIndex::A)      return PAIN & Bit;
            else if constexpr (PortIdx == PortIndex::B) return PBIN & Bit;
        }
        
        static void Write(bool x) {
            State::Out(x);
        }
        
        // State: accessors for reading/writing pin configuration at runtime
        struct State {
            // Getters
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
            
            OnlyPortA
            static constexpr bool IE() {
                return _Getter(PAIE);
            }
            
            OnlyPortA
            static constexpr bool IES() {
                return _Getter(PAIES);
            }
            
            OnlyPortA
            static constexpr bool IFG() {
                return _Getter(PAIFG);
            }
            
            // Setters
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
            
            OnlyPortA
            static constexpr void IE(bool x) {
                _Setter(PAIE, x);
            }
            
            OnlyPortA
            static constexpr void IES(bool x) {
                _Setter(PAIES, x);
            }
            
            OnlyPortA
            static constexpr void IFG(bool x) {
                _Setter(PAIFG, x);
            }
            
        private:
            template<typename T>
            static constexpr bool _Getter(T& reg) {
                return reg & Bit;
            }
            
            template<typename T>
            static constexpr void _Setter(T& reg, bool x) {
                if (x)  reg |= Bit;
                else    reg &= ~Bit;
            }
        };
        
    private:
        static constexpr bool _Getter(Option opt) {
            for (const Option o : (Option[]){T_Opts...}) {
                if (o == opt) return true;
            }
            return false;
        }
    };
#undef OnlyPortA
#undef OnlyPort1
#undef OnlyPort2
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

template<PortIndex T_PortIdx>
static constexpr _Regs _GetRegs(_Regs regs) {
    return regs;
}

template<PortIndex T_PortIdx, typename T_Pin, typename... T_Pins>
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
        regs.Out    |= (T_Pin::Out()  ? T_Pin::Bit : 0);
        regs.Dir    |= (T_Pin::Dir()  ? T_Pin::Bit : 0);
        regs.Sel0   |= (T_Pin::Sel0() ? T_Pin::Bit : 0);
        regs.Sel1   |= (T_Pin::Sel1() ? T_Pin::Bit : 0);
        regs.REn    |= (T_Pin::REn()  ? T_Pin::Bit : 0);
        regs.IE     |= (T_Pin::IE()   ? T_Pin::Bit : 0);
        regs.IES    |= (T_Pin::IES()  ? T_Pin::Bit : 0);
    }
    
    if constexpr (sizeof...(T_Pins)) return _GetRegs<T_PortIdx, T_Pins...>(regs);
    else return regs;
}

// Init(): init all pins on a device
// Interrupts must be disabled
template<typename... T_Pins>
static void Init(bool coldStart) {
    // Follow the initialization procedure from the MSP430FR24xx user guide
    // From "8.3.1 Configuration After Reset":
    //   1. Initialize Ports: PxDIR, PxREN, PxOUT, and PxIES
    //   2. Clear LOCKLPM5
    //   3. If not waking up from LPMx.5: clear all PxIFGs to avoid erroneous port interrupts
    //   4. Enable port interrupts in PxIE
    //
    // This order is required because the MSP430FR24xx user guide says:
    //   "Note that the PxIFG flag cannot be cleared until the LOCKLPM5 bit has been cleared."
    
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
    
    // Initialize PxIFG to reflect the current state of the pin, if this was a cold start.
    // This is so we get an initial interrupt for any pin that's in the state for which its
    // interrupt fires.
    // We don't want to do this when waking from LPMx.5, because PxIFG will contain the
    // reason for waking if a GPIO woke us.
    if (coldStart) {
        PAIFG = PAIN ^ PAIES;
    }
    
    // Enable interrupts
    PAIE = regsA.IE;
}

using PortA = Port<PortIndex::A>;
using PortB = Port<PortIndex::B>;

} // namespace GPIO

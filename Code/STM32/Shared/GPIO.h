//#pragma once
//#include "stm32f7xx.h"
//#include "Util.h"
//
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
//
//template <GPIO_TypeDef& Port, uint16_t PinIdx>
//class GPIO {
//public:
//    static constexpr uint16_t Bit = UINT16_C(1)<<PinIdx;
//    
//    static void Config(uint32_t mode, uint32_t pull, uint32_t speed, uint32_t alt) {
//        GPIO_InitTypeDef cfg = {
//            .Pin = Bit,
//            .Mode = mode,
//            .Pull = pull,
//            .Speed = speed,
//            .Alternate = alt,
//        };
//        
//        // Call HAL_GPIO_DeInit in case the interrupt was previously configured as an interrupt source.
//        // If we didn't call HAL_GPIO_DeInit(), then interrupts would remain enabled.
//        #warning TODO: reduce overhead of configuring GPIOs. we shouldn't need to de-init/init everytime,
//        #warning TODO: and we should be able to init all GPIOs simultaneously, like with MSPApp.
//        
//        #warning TODO: also, automatically call __HAL_RCC_GPIOX_CLK_ENABLE
////        HAL_GPIO_DeInit(&Port, Bit);
//        HAL_GPIO_Init(&Port, &cfg);
//    }
//    
//    static bool Read() {
//        return HAL_GPIO_ReadPin(&Port, Bit)==GPIO_PIN_SET;
//    }
//    
//    static void Write(bool x) {
//        HAL_GPIO_WritePin(&Port, Bit, (x ? GPIO_PIN_SET : GPIO_PIN_RESET));
//    }
//    
//    static bool InterruptClear() {
//        if (!(EXTI->PR & Bit)) return false;
//        // Clear interrupt
//        EXTI->PR = Bit;
//        return true;
//    }
//};



























//namespace GPIO {
//
//
//
//template <GPIO_TypeDef& Port>
//class Port {
//public:
//    template <uint8_t T_PinIdx, Option... T_Opts>
//    class Pin {
//    public:
//        static constexpr PortIndex PortIdx  = T_PortIdx;
//        static constexpr uint8_t PinIdx     = T_PinIdx;
//        static constexpr uint16_t Bit       = UINT16_C(1)<<PinIdx;
//        
//        template <Option... T_NewOpts>
//        using Opts = Port::Pin<PinIdx, T_NewOpts...>;
//        
//        struct InitCfg {
//            
//            
//  __IO uint32_t MODER;    /*!< GPIO port mode register,               Address offset: 0x00      */
//  __IO uint32_t OTYPER;   /*!< GPIO port output type register,        Address offset: 0x04      */
//  __IO uint32_t OSPEEDR;  /*!< GPIO port output speed register,       Address offset: 0x08      */
//  __IO uint32_t PUPDR;    /*!< GPIO port pull-up/pull-down register,  Address offset: 0x0C      */
//  __IO uint32_t IDR;      /*!< GPIO port input data register,         Address offset: 0x10      */
//  __IO uint32_t ODR;      /*!< GPIO port output data register,        Address offset: 0x14      */
//  __IO uint32_t BSRR;     /*!< GPIO port bit set/reset register,      Address offset: 0x18      */
//  __IO uint32_t LCKR;     /*!< GPIO port configuration lock register, Address offset: 0x1C      */
//  __IO uint32_t AFR[2];   /*!< GPIO alternate function registers,     Address offset: 0x20-0x24 */
//            
//            
//            
//            static constexpr bool Out()     { return _InitGetter(Option::Output1)       || _InitGetter(Option::Resistor1);      }
//            static constexpr bool Dir()     { return _InitGetter(Option::Output0)       || _InitGetter(Option::Output1);        }
//            static constexpr bool Sel0()    { return _InitGetter(Option::Sel01)         || _InitGetter(Option::Sel11);          }
//            static constexpr bool Sel1()    { return _InitGetter(Option::Sel10)         || _InitGetter(Option::Sel11);          }
//            static constexpr bool REn()     { return _InitGetter(Option::Resistor0)     || _InitGetter(Option::Resistor1);      }
//            static constexpr bool IE()      { return _InitGetter(Option::Interrupt01)   || _InitGetter(Option::Interrupt10);    }
//            static constexpr bool IES()     { return _InitGetter(Option::Interrupt10);                                          }
//        };
//        
//        // Init(): configure the pin
//        static constexpr void Init() {
//            Out  (InitCfg::Out() );
//            Dir  (InitCfg::Dir() );
//            Sel0 (InitCfg::Sel0());
//            Sel1 (InitCfg::Sel1());
//            REn  (InitCfg::REn() );
//            
//            if constexpr (PortIdx == PortIndex::A)
//            IE   (InitCfg::IE()  );
//            
//            if constexpr (PortIdx == PortIndex::A)
//            IES  (InitCfg::IES() );
//        }
//        
//        // Init(): configure the pin, but only emit instructions for the changes relative to `T_Prev`
//        template <typename T_Prev>
//        static constexpr void Init() {
//            if constexpr (InitCfg::Out() != T_Prev::InitCfg::Out())
//            Out  (InitCfg::Out() );
//            
//            if constexpr (InitCfg::Dir() != T_Prev::InitCfg::Dir())
//            Dir  (InitCfg::Dir() );
//            
//            if constexpr (InitCfg::Sel0() != T_Prev::InitCfg::Sel0())
//            Sel0 (InitCfg::Sel0());
//            
//            if constexpr (InitCfg::Sel1() != T_Prev::InitCfg::Sel1())
//            Sel1 (InitCfg::Sel1());
//            
//            if constexpr (InitCfg::REn() != T_Prev::InitCfg::REn())
//            REn  (InitCfg::REn() );
//            
//            if constexpr (PortIdx == PortIndex::A)
//            if constexpr (InitCfg::IE() != T_Prev::InitCfg::IE())
//            IE   (InitCfg::IE()  );
//            
//            if constexpr (PortIdx == PortIndex::A)
//            if constexpr (InitCfg::IES() != T_Prev::InitCfg::IES())
//            IES  (InitCfg::IES() );
//        }
//        
//        static constexpr bool Out() {
//            if constexpr (PortIdx == PortIndex::A)      return _Getter(PAOUT);
//            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBOUT);
//        }
//        
//        static constexpr bool Dir() {
//            if constexpr (PortIdx == PortIndex::A)      return _Getter(PADIR);
//            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBDIR);
//        }
//        
//        static constexpr bool Sel0() {
//            if constexpr (PortIdx == PortIndex::A)      return _Getter(PASEL0);
//            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBSEL0);
//        }
//        
//        static constexpr bool Sel1() {
//            if constexpr (PortIdx == PortIndex::A)      return _Getter(PASEL1);
//            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBSEL1);
//        }
//        
//        static constexpr bool REn() {
//            if constexpr (PortIdx == PortIndex::A)      return _Getter(PAREN);
//            else if constexpr (PortIdx == PortIndex::B) return _Getter(PBREN);
//        }
//        
//        static constexpr bool IE() {
//            return _Getter(PAIE);
//        }
//        
//        static constexpr bool IES() {
//            return _Getter(PAIES);
//        }
//        
//        static constexpr bool IFG() {
//            return _Getter(PAIFG);
//        }
//        
//        // IVPort1(): returns the interrupt vector for Port1 pins
//        // We intentionally separate IVPort1() / IVPort2(), instead of having a single IV(),
//        // because we want to get a compiler error if we call IVPort1() on a pin that only
//        // has a Port2 IV.
//        static constexpr uint16_t IVPort1() {
//            return (PinIdx+1)<<1;
//        }
//        
//        // IVPort2(): returns the interrupt vector for Port2 pins
//        // We intentionally separate IVPort1() / IVPort2(), instead of having a single IV(),
//        // because we want to get a compiler error if we call IVPort1() on a pin that only
//        // has a Port2 IV.
//        static constexpr uint16_t IVPort2() {
//            return (PinIdx-8+1)<<1;
//        }
//        
//        static constexpr void Out(bool x) {
//            if constexpr (PortIdx == PortIndex::A)      _Setter(PAOUT, x);
//            else if constexpr (PortIdx == PortIndex::B) _Setter(PBOUT, x);
//        }
//        
//        static constexpr void Dir(bool x) {
//            if constexpr (PortIdx == PortIndex::A)      _Setter(PADIR, x);
//            else if constexpr (PortIdx == PortIndex::B) _Setter(PBDIR, x);
//        }
//        
//        static constexpr void Sel0(bool x) {
//            if constexpr (PortIdx == PortIndex::A)      _Setter(PASEL0, x);
//            else if constexpr (PortIdx == PortIndex::B) _Setter(PBSEL0, x);
//        }
//        
//        static constexpr void Sel1(bool x) {
//            if constexpr (PortIdx == PortIndex::A)      _Setter(PASEL1, x);
//            else if constexpr (PortIdx == PortIndex::B) _Setter(PBSEL1, x);
//        }
//        
//        static constexpr void REn(bool x) {
//            if constexpr (PortIdx == PortIndex::A)      _Setter(PAREN, x);
//            else if constexpr (PortIdx == PortIndex::B) _Setter(PBREN, x);
//        }
//        
//        static constexpr void IE(bool x) {
//            _Setter(PAIE, x);
//        }
//        
//        static constexpr void IES(bool x) {
//            _Setter(PAIES, x);
//        }
//        
//        static constexpr void IFG(bool x) {
//            _Setter(PAIFG, x);
//        }
//        
//        // IESConfig(): convenience for changing IES to switch between monitoring 0->1 and 1->0 transitions.
//        // This function ensures that transitions won't be missed (due to the inherent race of configuring
//        // IES and the pin changing state), by explicitly setting IFG to reflect the state of the pin,
//        // after configuring IES.
//        static constexpr void IESConfig() {
//            // Disable interrupts while we change the IES config
//            Toastbox::IntState ints(false);
//            
//            constexpr bool ies = InitCfg::IES();
//            IES(ies);
//            
//            // After configuring IES, ensure that IFG reflects the state of the pin.
//            // This is necessary because we may have missed a transition due to the
//            // inherent race between configuring IES and the pin changing state.
//            IFG(Read() != ies);
//        }
//        
//        static bool Read() {
//            if constexpr (PortIdx == PortIndex::A)      return PAIN & Bit;
//            else if constexpr (PortIdx == PortIndex::B) return PBIN & Bit;
//        }
//        
//        static void Write(bool x) {
//            Out(x);
//        }
//        
//    private:
//        static constexpr bool _InitGetter(Option opt) {
//            for (const Option o : (Option[]){T_Opts...}) {
//                if (o == opt) return true;
//            }
//            return false;
//        }
//        
//        template <typename T>
//        static constexpr bool _Getter(T& reg) {
//            return reg & Bit;
//        }
//        
//        template <typename T>
//        static constexpr void _Setter(T& reg, bool x) {
//            if (x)  reg |= Bit;
//            else    reg &= ~Bit;
//        }
//    };
//};
//
//struct _Regs {
//    // Default state for all pins: output strong 0
//    uint16_t Out  = 0x0000;
//    uint16_t Dir  = 0xFFFF;
//    uint16_t Sel0 = 0x0000;
//    uint16_t Sel1 = 0x0000;
//    uint16_t REn  = 0x0000;
//    uint16_t IE   = 0x0000;
//    uint16_t IES  = 0x0000;
//};
//
//template <PortIndex T_PortIdx>
//static constexpr _Regs _GetRegs(_Regs regs) {
//    return regs;
//}
//
//template <PortIndex T_PortIdx, typename T_Pin, typename... T_Pins>
//static constexpr _Regs _GetRegs(_Regs regs) {
//    // Only consider pins for the specified port index (T_PortIdx)
//    if constexpr (T_Pin::PortIdx == T_PortIdx) {
//        // Clear the bit for the GPIO
//        regs.Out    &= ~T_Pin::Bit;
//        regs.Dir    &= ~T_Pin::Bit;
//        regs.Sel0   &= ~T_Pin::Bit;
//        regs.Sel1   &= ~T_Pin::Bit;
//        regs.REn    &= ~T_Pin::Bit;
//        regs.IE     &= ~T_Pin::Bit;
//        regs.IES    &= ~T_Pin::Bit;
//        
//        // Set the bit for the GPIO, if it's set
//        regs.Out    |= (T_Pin::InitCfg::Out()  ? T_Pin::Bit : 0);
//        regs.Dir    |= (T_Pin::InitCfg::Dir()  ? T_Pin::Bit : 0);
//        regs.Sel0   |= (T_Pin::InitCfg::Sel0() ? T_Pin::Bit : 0);
//        regs.Sel1   |= (T_Pin::InitCfg::Sel1() ? T_Pin::Bit : 0);
//        regs.REn    |= (T_Pin::InitCfg::REn()  ? T_Pin::Bit : 0);
//        regs.IE     |= (T_Pin::InitCfg::IE()   ? T_Pin::Bit : 0);
//        regs.IES    |= (T_Pin::InitCfg::IES()  ? T_Pin::Bit : 0);
//    }
//    
//    if constexpr (sizeof...(T_Pins)) return _GetRegs<T_PortIdx, T_Pins...>(regs);
//    else return regs;
//}
//
//template <typename... T_Pins>
//static void Init() {
//    // Follow the initialization procedure from the MSP430FR24xx user guide
//    // From "8.3.1 Configuration After Reset":
//    //   1. Initialize Ports: PxDIR, PxREN, PxOUT, and PxIES
//    //   2. Clear LOCKLPM5
//    //   3. If not waking up from LPMx.5: clear all PxIFGs to avoid erroneous port interrupts
//    //   4. Enable port interrupts in PxIE
//    //
//    // This order is required because the MSP430FR24xx user guide says:
//    //   "Note that the PxIFG flag cannot be cleared until the LOCKLPM5 bit has been cleared."
//    
//    // Disable interrupts
//    Toastbox::IntState ints(false);
//    
//    // Config pins
//    
//    // Port A
//    constexpr _Regs regsA = _GetRegs<PortIndex::A, T_Pins...>(_Regs{});
//    PAOUT   = regsA.Out;
//    PADIR   = regsA.Dir;
//    PASEL0  = regsA.Sel0;
//    PASEL1  = regsA.Sel1;
//    PAREN   = regsA.REn;
//    PAIES   = regsA.IES;
//    
//    // Port B
//    constexpr _Regs regsB = _GetRegs<PortIndex::B, T_Pins...>(_Regs{});
//    PBOUT   = regsB.Out;
//    PBDIR   = regsB.Dir;
//    PBSEL0  = regsB.Sel0;
//    PBSEL1  = regsB.Sel1;
//    PBREN   = regsB.REn;
//    
//    // Unlock GPIOs
//    PM5CTL0 &= ~LOCKLPM5;
//    
//    // Clear PxIFG (but only if this was a cold start)
//    // We don't want to do this when waking from LPMx.5, because PxIFG may contain
//    // the reason for waking, if a GPIO woke us.
//    if (Startup::ColdStart()) {
//        PAIFG = 0;
//    }
//    
//    // Enable interrupts
//    PAIE = regsA.IE;
//}
//
//using PortA = Port<PortIndex::A>;
//using PortB = Port<PortIndex::B>;
//
//} // namespace GPIO
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//











#pragma once
#include "Toastbox/Scheduler.h"
#include "stm32f7xx.h"

#define GPIOPort(name, addr)                            \
    extern "C" GPIO_TypeDef name;                       \
    __asm__(                                            \
        ".global " #name                        "\n"    \
        ".equ    " #name ", " Stringify(addr)   "\n"    \
    )

GPIOPort(GPIOPortA, GPIOA_BASE);
GPIOPort(GPIOPortB, GPIOB_BASE);
GPIOPort(GPIOPortC, GPIOC_BASE);
GPIOPort(GPIOPortD, GPIOD_BASE);
GPIOPort(GPIOPortE, GPIOE_BASE);
GPIOPort(GPIOPortF, GPIOF_BASE);
GPIOPort(GPIOPortG, GPIOG_BASE);
GPIOPort(GPIOPortH, GPIOH_BASE);
GPIOPort(GPIOPortI, GPIOI_BASE);

namespace GPIO {

enum class Option : uint8_t {
    // Direction + output value
    Input,
    Output0,
    Output1,
    
    // Special options
    OpenDrain,
    AltFn,
    Analog,
    
    // Speed
    Speed0,     // Low
    Speed1,     // Medium
    Speed2,     // High
    Speed3,     // Very high
    
    // Pullup/pulldown resistor
    Resistor0,
    Resistor1,
    
    // Interrupts
    Interrupt01,    // Rising
    Interrupt10,    // Falling
    InterruptXX,    // Either
    
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




  __IO uint32_t MODER;    /*!< GPIO port mode register,               Address offset: 0x00      */
  __IO uint32_t OTYPER;   /*!< GPIO port output type register,        Address offset: 0x04      */
  __IO uint32_t OSPEEDR;  /*!< GPIO port output speed register,       Address offset: 0x08      */
  __IO uint32_t PUPDR;    /*!< GPIO port pull-up/pull-down register,  Address offset: 0x0C      */
  __IO uint32_t IDR;      /*!< GPIO port input data register,         Address offset: 0x10      */
  __IO uint32_t ODR;      /*!< GPIO port output data register,        Address offset: 0x14      */
  __IO uint32_t BSRR;     /*!< GPIO port bit set/reset register,      Address offset: 0x18      */
  __IO uint32_t LCKR;     /*!< GPIO port configuration lock register, Address offset: 0x1C      */
  __IO uint32_t AFR[2];   /*!< GPIO alternate function registers,     Address offset: 0x20-0x24 */




template <GPIO_TypeDef& Port>
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
            if constexpr (_Getter(Option::AltFn))   return 0x02;
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
            if constexpr (PinIdx ) {
                return 
            }
            return 0x00;
        }
        
        static constexpr uint8_t AFRH() {
            return 0x00;
        }
        
        
        // Init(): configure the pin
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
        }
        
        // Init(): configure the pin, but only emit instructions for the changes relative to `T_Prev`
        template <typename T_Prev>
        static constexpr void Init() {
        }
        
        // IVPort1(): returns the interrupt vector for Port1 pins
        // We intentionally separate IVPort1() / IVPort2(), instead of having a single IV(),
        // because we want to get a compiler error if we call IVPort1() on a pin that only
        // has a Port2 IV.
        static constexpr uint16_t IVPort1() {
            return (PinIdx+1)<<1;
        }
        
        // IVPort2(): returns the interrupt vector for Port2 pins
        // We intentionally separate IVPort1() / IVPort2(), instead of having a single IV(),
        // because we want to get a compiler error if we call IVPort1() on a pin that only
        // has a Port2 IV.
        static constexpr uint16_t IVPort2() {
            return (PinIdx-8+1)<<1;
        }
        
        // IESConfig(): convenience for changing IES to switch between monitoring 0->1 and 1->0 transitions.
        // This function ensures that transitions won't be missed (due to the inherent race of configuring
        // IES and the pin changing state), by explicitly setting IFG to reflect the state of the pin,
        // after configuring IES.
        static constexpr void IESConfig() {
            // Disable interrupts while we change the IES config
            Toastbox::IntState ints(false);
            
            constexpr bool ies = IES();
            State::IES(ies);
            
            // After configuring IES, ensure that IFG reflects the state of the pin.
            // This is necessary because we may have missed a transition due to the
            // inherent race between configuring IES and the pin changing state.
            State::IFG(Read() != ies);
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
            
            static constexpr bool IE() {
                return _Getter(PAIE);
            }
            
            static constexpr bool IES() {
                return _Getter(PAIES);
            }
            
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
            
            static constexpr void IE(bool x) {
                _Setter(PAIE, x);
            }
            
            static constexpr void IES(bool x) {
                _Setter(PAIES, x);
            }
            
            static constexpr void IFG(bool x) {
                _Setter(PAIFG, x);
            }
            
        private:
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
        
    private:
        static constexpr bool _Getter(Option opt) {
            for (const Option o : (Option[]){T_Opts...}) {
                if (o == opt) return true;
            }
            return false;
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

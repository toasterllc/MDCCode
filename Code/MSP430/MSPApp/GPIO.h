#pragma once
#include <msp430.h>
#include <type_traits>
#include <initializer_list>

enum class GPIOPort {
    A,
    B,
};

enum class GPIOOption : uint8_t {
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

struct _GPIORegs {
    uint16_t Out  = 0;
    uint16_t Dir  = 0;
    uint16_t Sel0 = 0;
    uint16_t Sel1 = 0;
    uint16_t REn  = 0;
    uint16_t IE   = 0;
    uint16_t IES  = 0;
};

template <GPIOPort Port>
static constexpr void _GPIOInit(_GPIORegs regs) {
    static_assert(Port == GPIOPort::A, "");
    
    #warning modifying PAIE / PAIES can trigger an interrupt, so if we do that we should: disable interrupts, update regs, clear relevent interrupts, enable interrupts
    PAOUT   = regs.Out;
    PADIR   = regs.Dir;
    PASEL0  = regs.Sel0;
    PASEL1  = regs.Sel1;
    PAREN   = regs.REn;
    PAIE    = regs.IE;
    PAIES   = regs.IES;
    
//    PAOUT   = 0xAAAA;
//    PADIR   = 0xBBBB;
//    PASEL0  = 0xCCCC;
//    PASEL1  = 0xDDDD;
//    PAREN   = 0xEEEE;
//    PAIE    = 0xFFFF;
//    PAIES   = 0x4243;
    
//    printf("PAOUT   = 0x%04x\n", regs.Out);
//    printf("PADIR   = 0x%04x\n", regs.Dir);
//    printf("PASEL0  = 0x%04x\n", regs.Sel0);
//    printf("PASEL1  = 0x%04x\n", regs.Sel1);
//    printf("PAREN   = 0x%04x\n", regs.REn);
//    printf("PAIE    = 0x%04x\n", regs.IE);
//    printf("PAIES   = 0x%04x\n", regs.IES);
}

template<GPIOPort Port, typename GPIO, typename... GPIOs>
static constexpr void _GPIOInit(_GPIORegs regs) {
    static_assert(Port == GPIO::Port, "");
    
    // Clear the bit for the GPIO
    regs.Out    &= ~GPIO::Bit;
    regs.Dir    &= ~GPIO::Bit;
    regs.Sel0   &= ~GPIO::Bit;
    regs.Sel1   &= ~GPIO::Bit;
    regs.REn    &= ~GPIO::Bit;
    regs.IE     &= ~GPIO::Bit;
    regs.IES    &= ~GPIO::Bit;
    
    // Set the bit for the GPIO, if it's set
    regs.Out    |= (GPIO::InitConfig::Out()  ? GPIO::Bit : 0);
    regs.Dir    |= (GPIO::InitConfig::Dir()  ? GPIO::Bit : 0);
    regs.Sel0   |= (GPIO::InitConfig::Sel0() ? GPIO::Bit : 0);
    regs.Sel1   |= (GPIO::InitConfig::Sel1() ? GPIO::Bit : 0);
    regs.REn    |= (GPIO::InitConfig::REn()  ? GPIO::Bit : 0);
    regs.IE     |= (GPIO::InitConfig::IE()   ? GPIO::Bit : 0);
    regs.IES    |= (GPIO::InitConfig::IES()  ? GPIO::Bit : 0);
    
    _GPIOInit<Port, GPIOs...>(regs);
}

template<typename GPIO, typename... GPIOs>
static constexpr void _GPIOInit(_GPIORegs regs) {
    _GPIOInit<GPIO::Port, GPIO, GPIOs...>(regs);
}

template<typename... GPIOs>
static constexpr void GPIOInit() {
    // Default state for all pins: output strong 0
    _GPIOInit<GPIOs...>(_GPIORegs{
        .Out  = 0x0000,
        .Dir  = 0xFFFF,
        .Sel0 = 0x0000,
        .Sel1 = 0x0000,
        .REn  = 0x0000,
        .IE   = 0x0000,
        .IES  = 0x0000,
    });
    
    // Unlock GPIOs
    PM5CTL0 &= ~LOCKLPM5;
}

template <GPIOPort _Port, uint16_t _Pin, GPIOOption... Opts>
class GPIO {
public:
    static constexpr GPIOPort Port  = _Port;
    static constexpr uint16_t Pin   = _Pin;
    static constexpr uint16_t Bit   = UINT16_C(1)<<Pin;
    
    struct InitConfig {
        static constexpr bool Out()     { return _InitGetter(GPIOOption::Output1)       || _InitGetter(GPIOOption::Resistor1);      }
        static constexpr bool Dir()     { return _InitGetter(GPIOOption::Output0)       || _InitGetter(GPIOOption::Output1);        }
        static constexpr bool Sel0()    { return _InitGetter(GPIOOption::Sel01)         || _InitGetter(GPIOOption::Sel11);          }
        static constexpr bool Sel1()    { return _InitGetter(GPIOOption::Sel10)         || _InitGetter(GPIOOption::Sel11);          }
        static constexpr bool REn()     { return _InitGetter(GPIOOption::Resistor0)     || _InitGetter(GPIOOption::Resistor1);      }
        static constexpr bool IE()      { return _InitGetter(GPIOOption::Interrupt01)   || _InitGetter(GPIOOption::Interrupt10);    }
        static constexpr bool IES()     { return _InitGetter(GPIOOption::Interrupt10);                                              }
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
    
    static constexpr bool Out()         { if (Port == GPIOPort::A) return _Getter(PAOUT);   }
    static constexpr bool Dir()         { if (Port == GPIOPort::A) return _Getter(PADIR);   }
    static constexpr bool Sel0()        { if (Port == GPIOPort::A) return _Getter(PASEL0);  }
    static constexpr bool Sel1()        { if (Port == GPIOPort::A) return _Getter(PASEL1);  }
    static constexpr bool REn()         { if (Port == GPIOPort::A) return _Getter(PAREN);   }
    static constexpr bool IE()          { if (Port == GPIOPort::A) return _Getter(PAIE);    }
    static constexpr bool IES()         { if (Port == GPIOPort::A) return _Getter(PAIES);   }
    
    static constexpr void Out(bool x)   { if (Port == GPIOPort::A) _Setter(PAOUT, x);   }
    static constexpr void Dir(bool x)   { if (Port == GPIOPort::A) _Setter(PADIR, x);   }
    static constexpr void Sel0(bool x)  { if (Port == GPIOPort::A) _Setter(PASEL0, x);  }
    static constexpr void Sel1(bool x)  { if (Port == GPIOPort::A) _Setter(PASEL1, x);  }
    static constexpr void REn(bool x)   { if (Port == GPIOPort::A) _Setter(PAREN, x);   }
    static constexpr void IE(bool x)    { if (Port == GPIOPort::A) _Setter(PAIE, x);    }
    static constexpr void IES(bool x)   { if (Port == GPIOPort::A) _Setter(PAIES, x);   }
    
    static bool Read() {
        if (Port == GPIOPort::A) return PAIN & Bit;
    }
    
    static void Write(bool x) {
        Out(x);
    }
    
private:
    static constexpr bool _InitGetter(GPIOOption opt) {
        for (const GPIOOption o : (GPIOOption[]){Opts...}) {
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

template <uint16_t Pin, GPIOOption... Opts>
using GPIOA = GPIO<GPIOPort::A, Pin, Opts...>;

template <uint16_t Pin, GPIOOption... Opts>
using GPIOB = GPIO<GPIOPort::B, Pin, Opts...>;

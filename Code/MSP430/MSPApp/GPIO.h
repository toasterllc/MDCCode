#pragma once
#include <msp430.h>
#include <type_traits>
#include <initializer_list>

enum class GPIOPort {
    A,
    B,
};

enum class GPIOOption : uint8_t {
    Out,
    Dir,
    Sel0,
    Sel1,
    REn,
    IE,
    IES,
};

struct _GPIORegs {
    uint16_t out  = 0;
    uint16_t dir  = 0;
    uint16_t sel0 = 0;
    uint16_t sel1 = 0;
    uint16_t ren  = 0;
    uint16_t ie   = 0;
    uint16_t ies  = 0;
};

template <GPIOPort Port>
static constexpr void _GPIOInit(_GPIORegs regs) {
    static_assert(Port == GPIOPort::A, "");
    
    #warning modifying PAIE / PAIES can trigger an interrupt, so if we do that we should: disable interrupts, update regs, clear relevent interrupts, enable interrupts
    PAOUT   = regs.out;
    PADIR   = regs.dir;
    PASEL0  = regs.sel0;
    PASEL1  = regs.sel1;
    PAREN   = regs.ren;
    PAIE    = regs.ie;
    PAIES   = regs.ies;
    
//    PAOUT   = 0xAAAA;
//    PADIR   = 0xBBBB;
//    PASEL0  = 0xCCCC;
//    PASEL1  = 0xDDDD;
//    PAREN   = 0xEEEE;
//    PAIE    = 0xFFFF;
//    PAIES   = 0x4243;
    
//    printf("PAOUT   = 0x%04x\n", regs.out);
//    printf("PADIR   = 0x%04x\n", regs.dir);
//    printf("PASEL0  = 0x%04x\n", regs.sel0);
//    printf("PASEL1  = 0x%04x\n", regs.sel1);
//    printf("PAREN   = 0x%04x\n", regs.ren);
//    printf("PAIE    = 0x%04x\n", regs.ie);
//    printf("PAIES   = 0x%04x\n", regs.ies);
}

template<GPIOPort Port, typename GPIO, typename... GPIOs>
static constexpr void _GPIOInit(_GPIORegs regs) {
    static_assert(Port == GPIO::Port, "");
    
    // Clear the bit for the GPIO
    regs.out    &= ~GPIO::Bit;
    regs.dir    &= ~GPIO::Bit;
    regs.sel0   &= ~GPIO::Bit;
    regs.sel1   &= ~GPIO::Bit;
    regs.ren    &= ~GPIO::Bit;
    regs.ie     &= ~GPIO::Bit;
    regs.ies    &= ~GPIO::Bit;
    
    // Set the bit for the GPIO, if it's set
    regs.out    |= (GPIO::InitConfig::Out()  ? GPIO::Bit : 0);
    regs.dir    |= (GPIO::InitConfig::Dir()  ? GPIO::Bit : 0);
    regs.sel0   |= (GPIO::InitConfig::Sel0() ? GPIO::Bit : 0);
    regs.sel1   |= (GPIO::InitConfig::Sel1() ? GPIO::Bit : 0);
    regs.ren    |= (GPIO::InitConfig::REn()  ? GPIO::Bit : 0);
    regs.ie     |= (GPIO::InitConfig::IE()   ? GPIO::Bit : 0);
    regs.ies    |= (GPIO::InitConfig::IES()  ? GPIO::Bit : 0);
    
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
        .out  = 0x0000,
        .dir  = 0xFFFF,
        .sel0 = 0x0000,
        .sel1 = 0x0000,
        .ren  = 0x0000,
        .ie   = 0x0000,
        .ies  = 0x0000,
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
        static constexpr bool Out()     { return _InitGetter(GPIOOption::Out);   }
        static constexpr bool Dir()     { return _InitGetter(GPIOOption::Dir);   }
        static constexpr bool Sel0()    { return _InitGetter(GPIOOption::Sel0);  }
        static constexpr bool Sel1()    { return _InitGetter(GPIOOption::Sel1);  }
        static constexpr bool REn()     { return _InitGetter(GPIOOption::REn);   }
        static constexpr bool IE()      { return _InitGetter(GPIOOption::IE);    }
        static constexpr bool IES()     { return _InitGetter(GPIOOption::IES);   }
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
    
    static constexpr bool Out()         { return _Getter(PAOUT);        }
    static constexpr bool Dir()         { return _Getter(PADIR);        }
    static constexpr bool Sel0()        { return _Getter(PASEL0);       }
    static constexpr bool Sel1()        { return _Getter(PASEL1);       }
    static constexpr bool REn()         { return _Getter(PAREN);        }
    static constexpr bool IE()          { return _Getter(PAIE);         }
    static constexpr bool IES()         { return _Getter(PAIES);        }
    
    static constexpr void Out(bool x)   { return _Setter(PAOUT, x);     }
    static constexpr void Dir(bool x)   { return _Setter(PADIR, x);     }
    static constexpr void Sel0(bool x)  { return _Setter(PASEL0, x);    }
    static constexpr void Sel1(bool x)  { return _Setter(PASEL1, x);    }
    static constexpr void REn(bool x)   { return _Setter(PAREN, x);     }
    static constexpr void IE(bool x)    { return _Setter(PAIE, x);      }
    static constexpr void IES(bool x)   { return _Setter(PAIES, x);     }
    
    static bool Read() {
        if (Port == GPIOPort::A) return PAIN & Bit;
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
        if (Port == GPIOPort::A) return reg & Bit;
    }
    
    template <typename T>
    static constexpr void _Setter(T& reg, bool x) {
        if (x) {
            if (Port == GPIOPort::A) {
                reg |= Bit;
            }
        
        } else {
            if (Port == GPIOPort::A) {
                reg &= ~Bit;
            }
        }
    }
};

template <uint16_t Pin, GPIOOption... Opts>
using GPIOA = GPIO<GPIOPort::A, Pin, Opts...>;

template <uint16_t Pin, GPIOOption... Opts>
using GPIOB = GPIO<GPIOPort::B, Pin, Opts...>;

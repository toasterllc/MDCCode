#pragma once
#include <msp430.h>
#include <type_traits>
#include <initializer_list>

enum class GPIOPort {
    A,
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

template<typename GPIO>
static constexpr void _GPIOInitLoad(uint16_t& out, uint16_t& dir, uint16_t& sel0, uint16_t& sel1, uint16_t& ren, uint16_t& ie, uint16_t& ies) {
    // Clear the bit for the GPIO
    out     &= ~GPIO::Bit;
    dir     &= ~GPIO::Bit;
    sel0    &= ~GPIO::Bit;
    sel1    &= ~GPIO::Bit;
    ren     &= ~GPIO::Bit;
    ie      &= ~GPIO::Bit;
    ies     &= ~GPIO::Bit;
    
    // Set the bit for the GPIO, if it's set
    out     |= (GPIO::InitConfig::Out()  ? GPIO::Bit : 0);
    dir     |= (GPIO::InitConfig::Dir()  ? GPIO::Bit : 0);
    sel0    |= (GPIO::InitConfig::Sel0() ? GPIO::Bit : 0);
    sel1    |= (GPIO::InitConfig::Sel1() ? GPIO::Bit : 0);
    ren     |= (GPIO::InitConfig::REn()  ? GPIO::Bit : 0);
    ie      |= (GPIO::InitConfig::IE()   ? GPIO::Bit : 0);
    ies     |= (GPIO::InitConfig::IES()  ? GPIO::Bit : 0);
}

template <GPIOPort Port>
static constexpr void _GPIOInit(uint16_t out, uint16_t dir, uint16_t sel0, uint16_t sel1, uint16_t ren, uint16_t ie, uint16_t ies) {
    static_assert(Port == GPIOPort::A, "");
    
    // Base case: set register values
    #warning modifying PAIE / PAIES can trigger an interrupt, so if we do that we should: disable interrupts, update regs, clear relevent interrupts, enable interrupts
    PAOUT   = out;
    PADIR   = dir;
    PASEL0  = sel0;
    PASEL1  = sel1;
    PAREN   = ren;
    PAIE    = ie;
    PAIES   = ies;
    
//    PAOUT   = 0xAAAA;
//    PADIR   = 0xBBBB;
//    PASEL0  = 0xCCCC;
//    PASEL1  = 0xDDDD;
//    PAREN   = 0xEEEE;
//    PAIE    = 0xFFFF;
//    PAIES   = 0x4242;
    
//    printf("PAOUT   = 0x%04x\n", out);
//    printf("PADIR   = 0x%04x\n", dir);
//    printf("PASEL0  = 0x%04x\n", sel0);
//    printf("PASEL1  = 0x%04x\n", sel1);
//    printf("PAREN   = 0x%04x\n", ren);
//    printf("PAIE    = 0x%04x\n", ie);
//    printf("PAIES   = 0x%04x\n", ies);
}

template<typename GPIO>
static constexpr void _GPIOInit(uint16_t out, uint16_t dir, uint16_t sel0, uint16_t sel1, uint16_t ren, uint16_t ie, uint16_t ies) {
    _GPIOInitLoad<GPIO>(out, dir, sel0, sel1, ren, ie, ies);
    _GPIOInit<GPIO::Port>(out, dir, sel0, sel1, ren, ie, ies);
}

template<typename GPIO, typename GPIO2, typename... GPIOs>
static constexpr void _GPIOInit(uint16_t out, uint16_t dir, uint16_t sel0, uint16_t sel1, uint16_t ren, uint16_t ie, uint16_t ies) {
    static_assert(GPIO::Port == GPIO2::Port, "");
    _GPIOInitLoad<GPIO>(out, dir, sel0, sel1, ren, ie, ies);
    _GPIOInit<GPIO2, GPIOs...>(out, dir, sel0, sel1, ren, ie, ies);
}

template<typename... GPIOs>
static constexpr void GPIOInit() {
    // Default state for all pins: output strong 0
    constexpr uint16_t out  = 0x0000;
    constexpr uint16_t dir  = 0xFFFF;
    constexpr uint16_t sel0 = 0x0000;
    constexpr uint16_t sel1 = 0x0000;
    constexpr uint16_t ren  = 0x0000;
    constexpr uint16_t ie   = 0x0000;
    constexpr uint16_t ies  = 0x0000;
    _GPIOInit<GPIOs...>(out, dir, sel0, sel1, ren, ie, ies);
    
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

#pragma once
#include <msp430.h>
#include <type_traits>
#include <initializer_list>

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

enum class PortIdx { A, B };

template <PortIdx T_PortIdx>
class Port {
public:
    static constexpr PortIdx Idx = T_PortIdx;
    
    template <uint8_t T_PinIdx, Option... T_Opts>
    class Pin {
    public:
//        using Port = Port;
        static constexpr uint8_t Idx    = T_PinIdx;
        static constexpr uint16_t Bit   = UINT16_C(1)<<Idx;
        
        template <Option... T_NewOpts>
        using Opts = Port::Pin<T_PinIdx, T_NewOpts...>;
        
        struct InitConfig {
            static constexpr bool Out()     { return _InitGetter(Option::Output1)       || _InitGetter(Option::Resistor1);      }
            static constexpr bool Dir()     { return _InitGetter(Option::Output0)       || _InitGetter(Option::Output1);        }
            static constexpr bool Sel0()    { return _InitGetter(Option::Sel01)         || _InitGetter(Option::Sel11);          }
            static constexpr bool Sel1()    { return _InitGetter(Option::Sel10)         || _InitGetter(Option::Sel11);          }
            static constexpr bool REn()     { return _InitGetter(Option::Resistor0)     || _InitGetter(Option::Resistor1);      }
            static constexpr bool IE()      { return _InitGetter(Option::Interrupt01)   || _InitGetter(Option::Interrupt10);    }
            static constexpr bool IES()     { return _InitGetter(Option::Interrupt10);                                              }
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
        
        static constexpr bool Out()         { if constexpr (Port::Idx == PortIdx::A) return _Getter(PAOUT);   }
        static constexpr bool Dir()         { if constexpr (Port::Idx == PortIdx::A) return _Getter(PADIR);   }
        static constexpr bool Sel0()        { if constexpr (Port::Idx == PortIdx::A) return _Getter(PASEL0);  }
        static constexpr bool Sel1()        { if constexpr (Port::Idx == PortIdx::A) return _Getter(PASEL1);  }
        static constexpr bool REn()         { if constexpr (Port::Idx == PortIdx::A) return _Getter(PAREN);   }
        static constexpr bool IE()          { if constexpr (Port::Idx == PortIdx::A) return _Getter(PAIE);    }
        static constexpr bool IES()         { if constexpr (Port::Idx == PortIdx::A) return _Getter(PAIES);   }
        
        static constexpr void Out(bool x)   { if constexpr (Port::Idx == PortIdx::A) _Setter(PAOUT, x);   }
        static constexpr void Dir(bool x)   { if constexpr (Port::Idx == PortIdx::A) _Setter(PADIR, x);   }
        static constexpr void Sel0(bool x)  { if constexpr (Port::Idx == PortIdx::A) _Setter(PASEL0, x);  }
        static constexpr void Sel1(bool x)  { if constexpr (Port::Idx == PortIdx::A) _Setter(PASEL1, x);  }
        static constexpr void REn(bool x)   { if constexpr (Port::Idx == PortIdx::A) _Setter(PAREN, x);   }
        static constexpr void IE(bool x)    { if constexpr (Port::Idx == PortIdx::A) _Setter(PAIE, x);    }
        static constexpr void IES(bool x)   { if constexpr (Port::Idx == PortIdx::A) _Setter(PAIES, x);   }
        
        static bool Read() {
            if (Port::Idx == PortIdx::A) return PAIN & Bit;
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
    
    template <typename... T_Pins>
    static constexpr void Init() {
        _Init<T_Pins...>(_Regs{});
        
        #warning the caller should probably do this, since multiple ports may need initialization
        // Unlock GPIOs
        PM5CTL0 &= ~LOCKLPM5;
    }
    
private:
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
    
    static constexpr void _Init(_Regs regs) {
        if constexpr (Port::Idx == PortIdx::A) {
            PAOUT   = regs.Out;
            PADIR   = regs.Dir;
            PASEL0  = regs.Sel0;
            PASEL1  = regs.Sel1;
            PAREN   = regs.REn;
            PAIE    = regs.IE;
            PAIES   = regs.IES;
        }
        
        #warning modifying PAIE / PAIES can trigger an interrupt, so if we do that we should: disable interrupts, update regs, clear relevent interrupts, enable interrupts
        
    //    PAOUT   = 0xAAAA;
    //    PADIR   = 0xBBBB;
    //    PASEL0  = 0xCCCC;
    //    PASEL1  = 0xDDDD;
    //    PAREN   = 0xEEEE;
    //    PAIE    = 0xFFFF;
    //    PAIES   = 0x4243;
        
//        printf("PAOUT   = 0x%04x\n", regs.Out);
//        printf("PADIR   = 0x%04x\n", regs.Dir);
//        printf("PASEL0  = 0x%04x\n", regs.Sel0);
//        printf("PASEL1  = 0x%04x\n", regs.Sel1);
//        printf("PAREN   = 0x%04x\n", regs.REn);
//        printf("PAIE    = 0x%04x\n", regs.IE);
//        printf("PAIES   = 0x%04x\n", regs.IES);
    }
    
    template <typename T_Pin, typename... T_Pins>
    static constexpr void _Init(_Regs regs) {
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
        
        if constexpr (sizeof...(T_Pins)) _Init<T_Pins...>(regs);
        else _Init(regs);
    }
};














//enum class Port { A, B };
//using Pin = uint8_t;
//
//template <Port TPort, Pin TPin>
//class PortPin {
//    static constexpr Port Port = TPort;
//    static constexpr Pin Pin = TPin;
//};
//
//enum class Option : uint8_t {
//    // Direction + output value
//    Input,
//    Output0,
//    Output1,
//    
//    // Pullup/pulldown resistor
//    Resistor0,
//    Resistor1,
//    
//    // Function selection
//    Sel01,
//    Sel10,
//    Sel11,
//    
//    // Interrupts
//    Interrupt01,
//    Interrupt10,
//};
//
//struct _Regs {
//    uint16_t Out  = 0;
//    uint16_t Dir  = 0;
//    uint16_t Sel0 = 0;
//    uint16_t Sel1 = 0;
//    uint16_t REn  = 0;
//    uint16_t IE   = 0;
//    uint16_t IES  = 0;
//};
//
//template <Port Port>
//static constexpr void _Init(_Regs regs) {
//    static_assert(Port == Port::A, "");
//    
//    #warning modifying PAIE / PAIES can trigger an interrupt, so if we do that we should: disable interrupts, update regs, clear relevent interrupts, enable interrupts
//    PAOUT   = regs.Out;
//    PADIR   = regs.Dir;
//    PASEL0  = regs.Sel0;
//    PASEL1  = regs.Sel1;
//    PAREN   = regs.REn;
//    PAIE    = regs.IE;
//    PAIES   = regs.IES;
//    
////    PAOUT   = 0xAAAA;
////    PADIR   = 0xBBBB;
////    PASEL0  = 0xCCCC;
////    PASEL1  = 0xDDDD;
////    PAREN   = 0xEEEE;
////    PAIE    = 0xFFFF;
////    PAIES   = 0x4243;
//    
////    printf("PAOUT   = 0x%04x\n", regs.Out);
////    printf("PADIR   = 0x%04x\n", regs.Dir);
////    printf("PASEL0  = 0x%04x\n", regs.Sel0);
////    printf("PASEL1  = 0x%04x\n", regs.Sel1);
////    printf("PAREN   = 0x%04x\n", regs.REn);
////    printf("PAIE    = 0x%04x\n", regs.IE);
////    printf("PAIES   = 0x%04x\n", regs.IES);
//}
//
//template <Port TPort, typename TGPIO, typename... TGPIOs>
//static constexpr void _GPIOInit(_Regs regs) {
//    static_assert(Port == GPIO::Port, "");
//    
//    // Clear the bit for the GPIO
//    regs.Out    &= ~GPIO::Bit;
//    regs.Dir    &= ~GPIO::Bit;
//    regs.Sel0   &= ~GPIO::Bit;
//    regs.Sel1   &= ~GPIO::Bit;
//    regs.REn    &= ~GPIO::Bit;
//    regs.IE     &= ~GPIO::Bit;
//    regs.IES    &= ~GPIO::Bit;
//    
//    // Set the bit for the GPIO, if it's set
//    regs.Out    |= (GPIO::InitConfig::Out()  ? GPIO::Bit : 0);
//    regs.Dir    |= (GPIO::InitConfig::Dir()  ? GPIO::Bit : 0);
//    regs.Sel0   |= (GPIO::InitConfig::Sel0() ? GPIO::Bit : 0);
//    regs.Sel1   |= (GPIO::InitConfig::Sel1() ? GPIO::Bit : 0);
//    regs.REn    |= (GPIO::InitConfig::REn()  ? GPIO::Bit : 0);
//    regs.IE     |= (GPIO::InitConfig::IE()   ? GPIO::Bit : 0);
//    regs.IES    |= (GPIO::InitConfig::IES()  ? GPIO::Bit : 0);
//    
//    _GPIOInit<Port, GPIOs...>(regs);
//}
//
//template <typename GPIO, typename... GPIOs>
//static constexpr void _GPIOInit(_Regs regs) {
//    _GPIOInit<GPIO::Port, GPIO, GPIOs...>(regs);
//}
//
//template <typename... GPIOs>
//static constexpr void GPIOInit() {
//    // Default state for all pins: output strong 0
//    _GPIOInit<GPIOs...>(_Regs{
//        .Out  = 0x0000,
//        .Dir  = 0xFFFF,
//        .Sel0 = 0x0000,
//        .Sel1 = 0x0000,
//        .REn  = 0x0000,
//        .IE   = 0x0000,
//        .IES  = 0x0000,
//    });
//    
//    // Unlock GPIOs
//    PM5CTL0 &= ~LOCKLPM5;
//}
//
//template <GPIOPort _Port, uint16_t _Pin, GPIOOption... Opts>
//class GPIO {
//public:
//    static constexpr GPIOPort Port  = _Port;
//    static constexpr uint16_t Pin   = _Pin;
//    static constexpr uint16_t Bit   = UINT16_C(1)<<Pin;
//    
//    struct InitConfig {
//        static constexpr bool Out()     { return _InitGetter(GPIOOption::Output1)       || _InitGetter(GPIOOption::Resistor1);      }
//        static constexpr bool Dir()     { return _InitGetter(GPIOOption::Output0)       || _InitGetter(GPIOOption::Output1);        }
//        static constexpr bool Sel0()    { return _InitGetter(GPIOOption::Sel01)         || _InitGetter(GPIOOption::Sel11);          }
//        static constexpr bool Sel1()    { return _InitGetter(GPIOOption::Sel10)         || _InitGetter(GPIOOption::Sel11);          }
//        static constexpr bool REn()     { return _InitGetter(GPIOOption::Resistor0)     || _InitGetter(GPIOOption::Resistor1);      }
//        static constexpr bool IE()      { return _InitGetter(GPIOOption::Interrupt01)   || _InitGetter(GPIOOption::Interrupt10);    }
//        static constexpr bool IES()     { return _InitGetter(GPIOOption::Interrupt10);                                              }
//    };
//    
//    static constexpr void Init() {
//        Out(    InitConfig::Out()   );
//        Dir(    InitConfig::Dir()   );
//        Sel0(   InitConfig::Sel0()  );
//        Sel1(   InitConfig::Sel1()  );
//        REn(    InitConfig::REn()   );
//        IE(     InitConfig::IE()    );
//        IES(    InitConfig::IES()   );
//    }
//    
//    static constexpr bool Out()         { if (Port == GPIOPort::A) return _Getter(PAOUT);   }
//    static constexpr bool Dir()         { if (Port == GPIOPort::A) return _Getter(PADIR);   }
//    static constexpr bool Sel0()        { if (Port == GPIOPort::A) return _Getter(PASEL0);  }
//    static constexpr bool Sel1()        { if (Port == GPIOPort::A) return _Getter(PASEL1);  }
//    static constexpr bool REn()         { if (Port == GPIOPort::A) return _Getter(PAREN);   }
//    static constexpr bool IE()          { if (Port == GPIOPort::A) return _Getter(PAIE);    }
//    static constexpr bool IES()         { if (Port == GPIOPort::A) return _Getter(PAIES);   }
//    
//    static constexpr void Out(bool x)   { if (Port == GPIOPort::A) _Setter(PAOUT, x);   }
//    static constexpr void Dir(bool x)   { if (Port == GPIOPort::A) _Setter(PADIR, x);   }
//    static constexpr void Sel0(bool x)  { if (Port == GPIOPort::A) _Setter(PASEL0, x);  }
//    static constexpr void Sel1(bool x)  { if (Port == GPIOPort::A) _Setter(PASEL1, x);  }
//    static constexpr void REn(bool x)   { if (Port == GPIOPort::A) _Setter(PAREN, x);   }
//    static constexpr void IE(bool x)    { if (Port == GPIOPort::A) _Setter(PAIE, x);    }
//    static constexpr void IES(bool x)   { if (Port == GPIOPort::A) _Setter(PAIES, x);   }
//    
//    static bool Read() {
//        if (Port == GPIOPort::A) return PAIN & Bit;
//    }
//    
//    static void Write(bool x) {
//        Out(x);
//    }
//    
//private:
//    static constexpr bool _InitGetter(GPIOOption opt) {
//        for (const GPIOOption o : (GPIOOption[]){Opts...}) {
//            if (o == opt) return true;
//        }
//        return false;
//    }
//    
//    template <typename T>
//    static constexpr bool _Getter(T& reg) {
//        return reg & Bit;
//    }
//    
//    template <typename T>
//    static constexpr void _Setter(T& reg, bool x) {
//        if (x)  reg |= Bit;
//        else    reg &= ~Bit;
//    }
//};
//
//template <uint16_t Pin, GPIOOption... Opts>
//using GPIOA = GPIO<GPIOPort::A, Pin, Opts...>;
//
//template <uint16_t Pin, GPIOOption... Opts>
//using GPIOB = GPIO<GPIOPort::B, Pin, Opts...>;

using PortA = Port<PortIdx::A>;

} // namespace GPIO

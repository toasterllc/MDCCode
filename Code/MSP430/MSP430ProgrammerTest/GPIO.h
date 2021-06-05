#pragma once
#include <msp430g2553.h>

template <uint8_t Bit>
class GPIO {
private:
    static constexpr uint8_t _b = (uint8_t)1 << Bit;
    
public:
    bool read() {
        return P1IN & _b;
    }
    
    void write(bool x) {
        if (x)  P1OUT   |=  _b;
        else    P1OUT   &= ~_b;
    }
    
    void config(bool out) {
        if (out)    P1DIR   |=  _b;
        else        P1DIR   &= ~_b;
    }
};

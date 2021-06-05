#pragma once

template <uint8_t Bit>
class GPIO {
    bool read() {
        return P1IN & Bit;
    }
    
    void write(bool x) {
        if (x)  P1OUT   |=  Bit;
        else    P1OUT   &= ~Bit;
    }
    
    void config(bool out) {
        if (out)    P1DIR   |=  Bit;
        else        P1DIR   &= ~Bit;
    }
};

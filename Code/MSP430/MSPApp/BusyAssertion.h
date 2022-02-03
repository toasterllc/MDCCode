#pragma once

template <uint8_t& T_Counter>
class BusyAssertionType {
public:
    BusyAssertionType() { T_Counter++; }
    ~BusyAssertionType() { T_Counter--; }
    
    // Copy/move: illegal
    BusyAssertionType(const BusyAssertionType& x)   = delete;
    BusyAssertionType(BusyAssertionType&& x)        = delete;
};

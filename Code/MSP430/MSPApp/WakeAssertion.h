#pragma once

template <uint8_t& T_Counter>
class WakeAssertionType {
public:
    WakeAssertionType() { T_Counter++; }
    ~WakeAssertionType() { T_Counter--; }
    
    // Copy/move: illegal
    WakeAssertionType(const WakeAssertionType& x)   = delete;
    WakeAssertionType(WakeAssertionType&& x)        = delete;
};

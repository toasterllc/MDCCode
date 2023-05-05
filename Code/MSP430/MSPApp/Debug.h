#pragma once
#include <msp430.h>
#include <cstdint>
#include <cstring>
#include "Assert.h"
#include "MSP.h"

template<typename T_Scheduler>
class T_Debug {
public:
    using Packet = MSP::DebugLogPacket;
    
    static void Print(const char* msg)  { _Write(Packet::Type::Chars, msg, std::strlen(msg)); }
    
    static void Print(uint16_t x)       { _Write(Packet::Type::Dec16, &x, sizeof(x)); }
    static void Print(uint32_t x)       { _Write(Packet::Type::Dec32, &x, sizeof(x)); }
    static void Print(uint64_t x)       { _Write(Packet::Type::Dec64, &x, sizeof(x)); }
    
    static void PrintHex(uint16_t x)    { _Write(Packet::Type::Hex16, &x, sizeof(x)); }
    static void PrintHex(uint32_t x)    { _Write(Packet::Type::Hex32, &x, sizeof(x)); }
    static void PrintHex(uint64_t x)    { _Write(Packet::Type::Hex64, &x, sizeof(x)); }
    
    static bool ISR() {
        SYSJMBO0 = _Packets[_RIdx].u16;
        _Pop();
        // Update JMBOUTIFG enabled status
        _Ints(_RLen);
        return true; // Always wake ourself because a Task might be waiting to write into the buffer
    }
    
    static void _Write(Packet::Type type, const void* data, size_t len) {
        // Wait until we have enough space:
        //   +1 packet for the Type packet
        //   +ceil(len/2) packet for payload
        const size_t count = 1+((len+1)/2);
        T_Scheduler::Ctx(count);
        T_Scheduler::Wait([] { return _WCap >= T_Scheduler::template Ctx<size_t>(); });
        
        // Disable JMBOUTIFG interrupt
        _Ints(false);
        
        // Push a Type packet
        _Packets[_WIdx] = { .type = type };
        _Push();
        
        // Fill _Packets
        // Our logic here always reads an even number of bytes from `data`.
        // If `len` is odd (only possible if type==::Chars), then we'll
        // push the null terminator, which is fine.
        const uint8_t* data8 = (const uint8_t*)data;
        for (size_t i=0; i<len; i+=2) {
            Packet& p = _Packets[_WIdx];
            p.u8[0] = data8[i+0];
            p.u8[1] = data8[i+1];
            _Push();
        }
        
        // Update JMBOUTIFG enabled status
        _Ints(_RLen);
    }
    
    static void _Push() {
        Assert(_WCap);
        _WIdx++;
        if (_WIdx == _Cap) _WIdx = 0;
        _WCap--;
        _RLen++;
    }
    
    static void _Pop() {
        Assert(_RLen);
        _RIdx++;
        if (_RIdx == _Cap) _RIdx = 0;
        _RLen--;
        _WCap++;
    }
    
    static void _Ints(bool en) {
        if (en) SFRIE1 |=  JMBOUTIE;
        else    SFRIE1 &= ~JMBOUTIE;
    }
    
    static constexpr uint8_t _Cap = 32;
    static inline Packet _Packets[_Cap];
    static inline uint8_t _WIdx = 0;
    static inline uint8_t _WCap = _Cap;
    static inline uint8_t _RIdx = 0;
    static inline uint8_t _RLen = 0;
};

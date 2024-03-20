#pragma once
#include <msp430.h>
#include <cstdint>
#include <cstring>
#include "Code/Shared/Assert.h"
#include "Code/Shared/MSP.h"
#include "Code/Lib/Scheduler/Scheduler.h"

#define DebugEnable 0

class Debug {
public:
    using Packet = MSP::DebugLogPacket;
    
    static void Print(const char* msg)  { _Write(Packet::Type::Chars, msg, std::strlen(msg)); }
    
    static void Print(bool x)           { Print((uint16_t)x); }
    static void Print(uint8_t x)        { Print((uint16_t)x); }
    static void Print(uint16_t x)       { _Write(Packet::Type::Dec16, &x, sizeof(x)); }
    static void Print(uint32_t x)       { _Write(Packet::Type::Dec32, &x, sizeof(x)); }
    static void Print(uint64_t x)       { _Write(Packet::Type::Dec64, &x, sizeof(x)); }
    
    static void PrintHex(bool x)        { PrintHex((uint16_t)x); }
    static void PrintHex(uint8_t x)     { PrintHex((uint16_t)x); }
    static void PrintHex(uint16_t x)    { _Write(Packet::Type::Hex16, &x, sizeof(x)); }
    static void PrintHex(uint32_t x)    { _Write(Packet::Type::Hex32, &x, sizeof(x)); }
    static void PrintHex(uint64_t x)    { _Write(Packet::Type::Hex64, &x, sizeof(x)); }
    
    static bool Empty() {
#if DebugEnable
        // We're empty when there's no more data to be transferred into SYSJMBO0,
        // and SYSJMBO0 is empty.
        return !_RLen && (SYSJMBC & JMBOUT0FG);
#else
        return true;
#endif
    }
    
    static bool ISR() {
#if DebugEnable
        SYSJMBO0 = _Packets[_RIdx].u16;
        _Pop();
        // Update JMBOUTIFG enabled status
        _Ints(_RLen);
        return true; // Always wake ourself because a Task might be waiting to write into the buffer
#endif // DebugEnable
        return false;
    }
    
    static void _Write(Packet::Type type, const void* data, size_t len) {
#if DebugEnable
        // Disable interrupts so that Prints that occur within the interrupt context can't be
        // interleaved with Prints that occur in the non-interrupt context
        Toastbox::IntState ints(false);
        
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
#endif // DebugEnable
    }
    
    static void _Push() {
        _WIdx++;
        if (_WIdx == _Cap) _WIdx = 0;
        
        // Check whether we're overwriting data
        if (_WCap) {
            // We had free capacity
            _WCap--;
            _RLen++;
        
        } else {
            // We didn't have free capacity so we overwrote data.
            // Therefore we increment the read index, but the read length (which must be equal to our
            // capacity, since we're full) remains the same.
            Assert(_RLen == _Cap);
            _RIdx++;
            if (_RIdx == _Cap) _RIdx = 0;
        }
    }
    
    static void _Pop() {
        Assert(_RLen);
        _RIdx++;
        if (_RIdx == _Cap) _RIdx = 0;
        _RLen--;
        _WCap++;
    }
    
    // _Ints(): disable/enable the JMBOUTIFG interrupt
    // This is an NMI, so GIE doesn't block it, so we have to explicitly disable it if we want to block it.
    static void _Ints(bool en) {
        if (en) SFRIE1 |=  JMBOUTIE;
        else    SFRIE1 &= ~JMBOUTIE;
    }
    
    static constexpr uint8_t _Cap = 32;
    static inline Packet _Packets[_Cap];
    static inline volatile uint8_t _WIdx = 0;
    static inline volatile uint8_t _WCap = _Cap;
    static inline volatile uint8_t _RIdx = 0;
    static inline volatile uint8_t _RLen = 0;
};

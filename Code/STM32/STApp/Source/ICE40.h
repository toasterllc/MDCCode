#pragma once
#include <stdint.h>
#include <string.h>
#include <algorithm>
#include "Assert.h"
#include "QSPI.h"
#include "Enum.h"

class ICE40 {
public:
    struct Pin {
        uint8_t bit = 0;
        uint8_t dir = 0;
        uint8_t val = 0;
        
        uint8_t dirBit() const { return (dir ? bit : 0); }
        uint8_t valBit() const { return (val ? bit : 0); }
    };
    
    struct Pins {
        Pin CLK     {.bit=1<<0, .dir=1, .val=0};
        Pin DO      {.bit=1<<1, .dir=1, .val=1};
        Pin DI      {.bit=1<<2, .dir=0, .val=0};
        // Unused
        Pin CS      {.bit=1<<4, .dir=1, .val=0};
        // Unused
        Pin CDONE   {.bit=1<<6, .dir=0, .val=0};
        Pin CRST_   {.bit=1<<7, .dir=1, .val=1};
        
        uint8_t dirBits() const {
            return  CLK.dirBit()    |
                    DO.dirBit()     |
                    DI.dirBit()     |
                    CS.dirBit()     |
                    CDONE.dirBit()  |
                    CRST_.dirBit()  ;
        }
        
        uint8_t valBits() const {
            return  CLK.valBit()    |
                    DO.valBit()     |
                    DI.valBit()     |
                    CS.valBit()     |
                    CDONE.valBit()  |
                    CRST_.valBit()  ;
        }
    };
    
    struct Msg {
        uint8_t type = 0;
        uint8_t payload[7] = {};
    } __attribute__((packed));
    
    struct Resp {
        uint8_t payload[8];
        bool getBool(uint8_t bit) const {
            return _getBool(payload, sizeof(payload), bit);
        }
        uint64_t getBits(uint8_t start, uint8_t end) const {
            return _getBits(payload, sizeof(payload), start, end);
        }
    };
    
    struct EchoMsg : Msg {
        EchoMsg(const char* msg) {
            type = 0x00;
            memcpy(payload, msg, std::min(sizeof(payload), strlen(msg)));
        }
    };
    
    struct EchoResp : Resp {
        const char* msg() const {
            // Verify that the string is null-terminated
            bool nt = false;
            for (uint8_t b : payload) {
                if (!b) {
                    nt = true;
                    break;
                }
            }
            if (!nt) return nullptr;
            return (const char*)payload;
        }
    };
    
    struct SDSetClkMsg : Msg {
        enum class ClkSrc : uint8_t {
            None    = 0,
            Slow    = 1<<0,
            Fast    = 1<<1,
        };
        
        SDSetClkMsg(ClkSrc src, uint8_t delay) {
            type = 0x01;
            payload[0] = 0x00;
            payload[1] = 0x00;
            payload[2] = 0x00;
            payload[3] = 0x00;
            payload[4] = 0x00;
            payload[5] = 0x00;
            payload[6] = (delay<<2) | (uint8_t)src;
        }
    };
    
    struct SDSendCmdMsg : Msg {
        Enum(uint8_t, RespType, RespTypes,
            None        = 0,
            Normal48    = 1<<0,
            Long136     = 1<<1,
        );
        
        Enum(uint8_t, DatInType, DatInTypes,
            None        = 0,
            Block512    = 1<<2,
        );
        
        SDSendCmdMsg(uint8_t sdCmd, uint32_t sdArg, RespType respType, DatInType datInType) {
            AssertArg((sdCmd&0x3F) == sdCmd); // Ensure SD command fits in 6 bits
            type = 0x02;
            payload[0] = respType|datInType;
            payload[1] = 0x40|sdCmd; // SD command start bit (1'b0), transmission bit (1'b1), SD command (6 bits = sdCmd)
            payload[2] = (sdArg&0xFF000000)>>24;
            payload[3] = (sdArg&0x00FF0000)>>16;
            payload[4] = (sdArg&0x0000FF00)>> 8;
            payload[5] = (sdArg&0x000000FF)>> 0;
            payload[6] = 0x01; // SD command end bit (1'b1)
        }
    };
    
    struct SDGetStatusMsg : Msg {
        SDGetStatusMsg() {
            type = 0x03;
        }
    };
    
    struct SDGetStatusResp : Resp {
        bool sdDat0Idle() const     { return getBool(63); }
        bool sdCmdSent() const      { return getBool(62); }
        bool sdRespRecv() const     { return getBool(61); }
        bool sdDatOutIdle() const   { return getBool(60); }
        bool sdDatInRecv() const    { return getBool(59); }
        bool sdRespCRCErr() const   { return getBool(58); }
        bool sdDatOutCRCErr() const { return getBool(57); }
        bool sdDatInCRCErr() const  { return getBool(56); }
        uint64_t sdResp() const     { return getBits(47, 0); }
    };
    
    struct SDDatOutMsg : Msg {
        SDDatOutMsg() {
            type = 0x04;
        }
    };
    
    ICE40(QSPI& qspi) : _qspi(qspi) {}
    
    void write(const Msg& msg) {
        static_assert(sizeof(msg) == 8);
        // Copy the message into `b`, and populate the trailing dummy byte
        uint8_t b[sizeof(msg)+1];
        memcpy(b, &msg, sizeof(msg));
        b[sizeof(msg)] = 0xFF;
        _qspi.write(b, sizeof(b));
        // Wait for write to complete
        QSPI::Event ev = _qspi.eventChannel.read();
        Assert(ev.type == QSPI::Event::Type::WriteDone);
    }
    
    template <typename T>
    T read() {
        // TODO: We need to ensure that IO0 outputs 1 while reading, otherwise the ICE40 will
        //       interpret the data as an actual command.
        //       Our 0xFF dummy byte at the end of each command, combined with a pullup resistor,
        //       should protect us here, unless the SPI peripheral explicitly outputs a 0
        //       (or random data) on IO0 during reading for some reason.
        T resp;
        static_assert(sizeof(resp) == 8);
        _qspi.read((void*)&resp, sizeof(resp));
        // Wait for read to complete
        QSPI::Event ev = _qspi.eventChannel.read();
        Assert(ev.type == QSPI::Event::Type::ReadDone);
        return resp;
    }
    
private:
    static bool _getBool(const uint8_t* bytes, size_t len, uint8_t bit) {
        AssertArg(bit < len*8);
        const uint8_t byteIdx = len-(bit/8)-1;
        const uint8_t bitIdx = bit%8;
        const uint8_t bitMask = 1<<bitIdx;
        return bytes[byteIdx] & bitMask;
    }
    
    static uint64_t _getBits(const uint8_t* bytes, size_t len, uint8_t start, uint8_t end) {
        AssertArg(start < len*8);
        AssertArg(start >= end);
        const uint8_t leftByteIdx = len-(start/8)-1;
        const uint8_t leftByteMask = (1<<((start%8)+1))-1;
        const uint8_t rightByteIdx = len-(end/8)-1;
        const uint8_t rightByteMask = ~((1<<(end%8))-1);
        uint64_t r = 0;
        for (uint8_t i=leftByteIdx; i<=rightByteIdx; i++) {
            uint8_t tmp = bytes[i];
            // Mask-out bits we don't want
            if (i == leftByteIdx)   tmp &= leftByteMask;
            if (i == rightByteIdx)  tmp &= rightByteMask;
            // Make space for the incoming bits
            if (i == rightByteIdx) {
                tmp >>= end%8; // Shift right the number of unused bits
                r <<= 8-(end%8); // Shift left the number of used bits
            } else {
                r <<= 8;
            }
            // Or the bits into place
            r |= tmp;
        }
        return r;
    }
    
    QSPI& _qspi;
};

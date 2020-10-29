#pragma once
#include <stdint.h>
#include <string.h>
#include <algorithm>
#include "Assert.h"

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
        uint8_t cmd = 0;
        uint8_t payload[7] = {};
    } __attribute__((packed));
    
    struct Resp {
        uint8_t payload[8];
        uint64_t getBits(uint8_t start, uint8_t end) const {
            return _getBits(payload, sizeof(payload), start, end);
        }
    };
    
    struct EchoMsg : Msg {
        EchoMsg(const char* msg) {
            cmd = 0x00;
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
    
    struct SDSetClkSrcMsg : Msg {
        enum class ClkSrc : uint8_t {
            None    = 0,
            Slow    = 1<<0,
            Fast    = 1<<1,
        };
        
        SDSetClkSrcMsg(ClkSrc src) {
            cmd = 0x01;
            payload[0] = 0x00;
            payload[1] = 0x00;
            payload[2] = 0x00;
            payload[3] = 0x00;
            payload[4] = 0x00;
            payload[5] = 0x00;
            payload[6] = (uint8_t)src;
        }
    };
    
    struct SDSendCmdMsg : Msg {
        SDSendCmdMsg(uint8_t sdCmd, uint32_t sdArg) {
            AssertArg((sdCmd&0x3F) == sdCmd); // Ensure SD command fits in 6 bits
            cmd = 0x02;
            payload[0] = 0x00;
            payload[1] = 0x40|sdCmd; // Start bit (1'b0), transmission bit (1'b1), SD command (6 bits = sdCmd)
            payload[2] = (sdArg&0xFF000000)>>24;
            payload[3] = (sdArg&0x00FF0000)>>16;
            payload[4] = (sdArg&0x0000FF00)>> 8;
            payload[5] = (sdArg&0x000000FF)>> 0;
            payload[6] = 0x01; // End bit (1'b1)
        }
    };
    
    struct SDGetStatusMsg : Msg {
        SDGetStatusMsg() {
            cmd = 0x03;
        }
    };
    
    struct SDGetStatusResp : Resp {
        uint8_t sdDat() const       { return getBits(61, 58); }
        bool sdCommandSent() const  { return getBits(57, 57); }
        bool sdRespRecv() const     { return getBits(56, 56); }
        bool sdDatOutIdle() const   { return getBits(55, 55); }
        bool sdRespCRCErr() const   { return getBits(54, 54); }
        bool sdDatOutCRCErr() const { return getBits(53, 53); }
        uint64_t sdResp() const     { return getBits(47, 0); }
    };
    
    struct SDDatOutMsg : Msg {
        SDDatOutMsg() {
            cmd = 0x04;
        }
    };
    
    ICE40(QSPI& qspi) : _qspi(qspi) {}
    
    void write(const Msg& msg) {
        uint8_t b[sizeof(msg)];
        memcpy(b, msg, sizeof(b));
        _lshift(b, sizeof(b), 1);
        b[sizeof(msg)-1] &= 0x7F // Set start bit (0)
        b[0] |= 0x01; // Set end bit (1)
        _write(b, sizeof(b));
    }
    
    template <typename T>
    T read() {
        T resp;
        uint8_t respBuf[sizeof(resp)+1]; // +1 since the response can start at any bit within
                                         // a byte, so we need an extra byte to make sure we
                                         // can fit the full response.
        size_t respBufLen = 0;
        
        // Read until we get the start bit, and fill up `respBuf`
        while (respBufLen < sizeof(respBuf)) {
            uint8_t buf[8];
            _read(buf, sizeof(buf));
            
            size_t bufOff = 0;
            bool bufOffValid = false;
            if (!respBufLen) {
                // Response hasn't started yet
                // Find the byte in `buf` containing the start bit
                for (size_t i=0; i<sizeof(buf); i++) {
                    if (buf[i] != 0xFF) {
                        bufOff = i;
                        bufOffValid = true;
                        break;
                    }
                }
            
            } else {
                // Response already started
                // The continuation of the data is at the beginning of `buf`
                bufOff = 0;
                bufOffValid = true;
            }
            
            // If the response started, copy new bytes into `respBuf`
            if (bufOffValid) {
                const size_t copyLen = std::min(sizeof(respBuf)-respBufLen, sizeof(buf)-bufOff);
                memcpy(respBuf+respBufLen, buf+bufOff, copyLen);
                respBufLen += copyLen;
            }
        }
        
        // Find the index of start bit in `respBuf`
        const int8_t mszIdx = _msz(respBuf[0]);
        Assert(mszIdx >= 0); // Our logic guarantees a zero
        // Calculate the number of bits we need to shift left
        const uint8_t shiftn = 8-mszIdx;
        // Left-shift the buffer to remove the start bit
        _lshift(respBuf, sizeof(respBuf), shiftn);
        // Copy the shifted bits into `resp`
        memcpy(&resp, respBuf, sizeof(resp));
        return resp;
    }
    
    void _read(void* d, size_t len) {
        _qspi.read(d, len);
        // Wait for read to complete
        QSPI::Event ev = _qspi.eventChannel.read();
        Assert(ev.type == QSPI::Event::Type::ReadDone);
    }
    
    void _write(const void* d, const size_t len) {
        _qspi.write(d, len);
        // Wait for write to complete
        QSPI::Event ev = _qspi.eventChannel.read();
        Assert(ev.type == QSPI::Event::Type::WriteDone);
    }
    
private:
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
    
    // Left shift array of bytes by `n` bits
    static void _lshift(uint8_t* bytes, size_t len, uint8_t n) {
        AssertArg(n <= 8);
        const uint8_t mask = ~((1<<(8-n))-1);
        uint8_t l = 0;
        for (size_t i=len; i; i--) {
            uint8_t& b = bytes[i-1];
            // Remember the high bits that we're losing by left-shifting,
            // which will become the next byte's low bits.
            const uint8_t h = b&mask;
            b <<= n;
            b |= l;
            l = h>>(8-n);
        }
    }
    
    // Returns of the index (0-7) of the most significant zero,
    // or -1 if there are no zeroes.
    static int8_t _msz(uint8_t x) {
        for (uint8_t i=0; i<8; i++) {
            const int8_t pos = 7-i;
            if (!(x & (1<<pos))) return pos;
        }
        return -1;
    }
    
    QSPI& _qspi;
};

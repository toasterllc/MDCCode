#pragma once
#include <stdint.h>
#include <string.h>
#include <algorithm>
#include "Toastbox/Enum.h"
#include "Assert.h"

namespace ICE40 {

bool _GetBit(const uint8_t* bytes, size_t len, uint8_t idx) {
    AssertArg(idx < len*8);
    const uint8_t byteIdx = len-(idx/8)-1;
    const uint8_t bitIdx = idx%8;
    const uint8_t bitMask = 1<<bitIdx;
    return bytes[byteIdx] & bitMask;
}

uint64_t _GetBits(const uint8_t* bytes, size_t len, uint8_t start, uint8_t end) {
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

struct Msg {
    uint8_t type = 0;
    uint8_t payload[7] = {};
} __attribute__((packed));

struct Resp {
    uint8_t payload[8];
    bool getBit(uint8_t idx) const {
        return _GetBit(payload, sizeof(payload), idx);
    }
    uint64_t getBits(uint8_t start, uint8_t end) const {
        return _GetBits(payload, sizeof(payload), start, end);
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

struct LEDSetMsg : Msg {
    LEDSetMsg(uint8_t val) {
        type = 0x01;
        payload[0] = 0;
        payload[1] = 0;
        payload[2] = 0;
        payload[3] = 0;
        payload[4] = 0;
        payload[5] = 0;
        payload[6] = val;
    }
};

struct SDInitMsg : Msg {
    enum class Action : uint8_t {
        None,
        Reset,
        Trigger,
    };
    
    enum class ClkSpeed : uint8_t {
        Off     = 0,
        Slow    = 1,
        Fast    = 2,
    };
    
    SDInitMsg(Action act, ClkSpeed speed, uint8_t delay) {
        AssertArg((delay&0xF) == delay); // Ensure delay fits in 4 bits
        const bool reset = (act==Action::Reset);
        const bool trigger = (act==Action::Trigger);
        type = 0x02;
        payload[0] = 0;
        payload[1] = 0;
        payload[2] = 0;
        payload[3] = 0;
        payload[4] = 0;
        payload[5] = 0;
        payload[6] = (((uint8_t)delay   &0xF)<<4) |
                     (((uint8_t)speed   &0x3)<<2) |
                     (((uint8_t)trigger &0x1)<<1) |
                     (((uint8_t)reset   &0x1)<<0) ;
    }
};

struct SDSendCmdMsg : Msg {
    Enum(uint8_t, RespType, RespTypes,
        None        = 0,
        Len48       = 1,
        Len136      = 2,
    );
    
    Enum(uint8_t, DatInType, DatInTypes,
        None        = 0,
        Len512      = 1,
    );
    
    SDSendCmdMsg(uint8_t sdCmd, uint32_t sdArg, RespType respType, DatInType datInType) {
        AssertArg((sdCmd&0x3F) == sdCmd); // Ensure SD command fits in 6 bits
        type = 0x03;
        payload[0] = (respType<<1)|datInType;
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
        type = 0x04;
    }
};

struct SDGetStatusResp : Resp {
    // Init Done
    bool sdInitDone() const                 { return getBit(63);                            }
    
    // Command
    bool sdCmdDone() const                  { return getBit(62);                            }
    
    // Response
    bool sdRespDone() const                 { return getBit(61);                            }
    bool sdRespCRCErr() const               { return getBit(60);                            }
    uint64_t sdResp() const                 { return getBits(_RespIdx+48-1, _RespIdx);      }
    
    // DatOut
    bool sdDatOutDone() const               { return getBit(11);                            }
    bool sdDatOutCRCErr() const             { return getBit(10);                            }
    
    // DatIn
    bool sdDatInDone() const                { return getBit(9);                             }
    bool sdDatInCRCErr() const              { return getBit(8);                             }
    uint8_t sdDatInCMD6AccessMode() const   { return getBits(7,4);                          }
    
    // Other
    bool sdDat0Idle() const                 { return getBit(3);                             }
    
    // Helper methods
    uint64_t sdRespGetBit(uint8_t idx) const {
        return getBit(idx+_RespIdx);
    }
    
    uint64_t sdRespGetBits(uint8_t start, uint8_t end) const {
        return getBits(start+_RespIdx, end+_RespIdx);
    }
    
private:
    static constexpr size_t _RespIdx = 12;
};

struct PixResetMsg : Msg {
    PixResetMsg(bool val) {
        type = 0x05;
        payload[0] = 0;
        payload[1] = 0;
        payload[2] = 0;
        payload[3] = 0;
        payload[4] = 0;
        payload[5] = 0;
        payload[6] = val;
    }
};

struct PixCaptureMsg : Msg {
    PixCaptureMsg(uint8_t dstBlock) {
        type = 0x06;
        payload[0] = 0;
        payload[1] = 0;
        payload[2] = 0;
        payload[3] = 0;
        payload[4] = 0;
        payload[5] = 0;
        payload[6] = dstBlock&0x7;
    }
};

struct PixReadoutMsg : Msg {
    // The word count needs to be supplied to the ICE40 to prevent
    // over-reading, otherwise the end of the QSPI transaction
    // causes one more word to be read than wanted, and we'd drop
    // that word if not for this counter.
    PixReadoutMsg(uint8_t srcBlock, bool captureNext, size_t wordCount) {
        AssertArg(wordCount);
        // Supply the value to load into the ICE40 counter.
        // Put the burden of this calculation on the STM32,
        // to improve the performance of the ICE40 Verilog.
        const uint16_t counter = (wordCount-1)*2;
        type = 0x07;
        payload[0] = 0;
        payload[1] = 0;
        payload[2] = 0;
        payload[3] = (counter&0xFF00)>>8;
        payload[4] = (counter&0x00FF)>>0;
        payload[5] = 0;
        payload[6] = (captureNext ? 0x8 : 0x0) | (srcBlock&0x7);
    }
};

struct PixI2CTransactionMsg : Msg {
    PixI2CTransactionMsg(bool write, uint8_t len, uint16_t addr, uint16_t val) {
        Assert(len==1 || len==2);
        type = 0x08;
        payload[0] = (write ? 0x80 : 0) | (len==2 ? 0x40 : 0);
        payload[1] = 0;
        payload[2] = 0;
        payload[3] = (addr&0xFF00)>>8;
        payload[4] = addr&0x00FF;
        payload[5] = (val&0xFF00)>>8;
        payload[6] = val&0x00FF;
    }
};

struct PixI2CStatusMsg : Msg {
    PixI2CStatusMsg() {
        type = 0x09;
    }
};

struct PixI2CStatusResp : Resp {
    bool done() const               { return getBit(63);        }
    bool err() const                { return getBit(62);        }
    uint16_t readData() const       { return getBits(61,46);    }
};

struct PixCaptureStatusMsg : Msg {
    PixCaptureStatusMsg() {
        type = 0x0A;
    }
};

struct PixCaptureStatusResp : Resp {
    bool done() const               { return getBit(63);        }
    uint16_t imageWidth() const     { return getBits(62,51);    }
    uint16_t imageHeight() const    { return getBits(50,39);    }
    uint32_t highlightCount() const { return getBits(38,21);    }
    uint32_t shadowCount() const    { return getBits(20,3);     }
};

struct NopMsg : Msg {
    NopMsg(uint8_t val) {
        type = 0xFF;
        payload[0] = 0xFF;
        payload[1] = 0xFF;
        payload[2] = 0xFF;
        payload[3] = 0xFF;
        payload[4] = 0xFF;
        payload[5] = 0xFF;
        payload[6] = 0xFF;
    }
};

} // namespace ICE40

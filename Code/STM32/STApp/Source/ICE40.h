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
        bool getBit(uint8_t idx) const {
            return _getBit(payload, sizeof(payload), idx);
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
    
    struct SDClkSrcMsg : Msg {
        enum class ClkSpeed : uint8_t {
            Off     = 0,
            Slow    = 1,
            Fast    = 2,
        };
        
        SDClkSrcMsg(ClkSpeed speed, uint8_t delay) {
            AssertArg((delay&0xF) == delay); // Ensure delay fits in 4 bits
            type = 0x01;
            payload[0] = 0;
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = 0;
            payload[4] = 0;
            payload[5] = 0;
            payload[6] = ((delay&0xF)<<2) | (uint8_t)speed;
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
            type = 0x02;
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
            type = 0x03;
        }
    };
    
    struct SDGetStatusResp : Resp {
        // Command
        bool sdCmdDone() const                  { return getBit(63);                            }
        
        // Response
        bool sdRespDone() const                 { return getBit(62);                            }
        bool sdRespCRCErr() const               { return getBit(61);                            }
        uint64_t sdResp() const                 { return getBits(_RespIdx+48-1, _RespIdx);      }
        
        // DatOut
        bool sdDatOutDone() const               { return getBit(12);                            }
        bool sdDatOutCRCErr() const             { return getBit(11);                            }
        
        // DatIn
        bool sdDatInDone() const                { return getBit(10);                            }
        bool sdDatInCRCErr() const              { return getBit(9);                             }
        uint8_t sdDatInCMD6AccessMode() const   { return getBits(8,5);                          }
        
        // Other
        bool sdDat0Idle() const                 { return getBit(4);                             }
        
        // Helper methods
        uint64_t sdRespGetBit(uint8_t idx) const {
            return getBit(idx+_RespIdx);
        }
        
        uint64_t sdRespGetBits(uint8_t start, uint8_t end) const {
            return getBits(start+_RespIdx, end+_RespIdx);
        }
    
    private:
        static constexpr size_t _RespIdx = 13;
    };
    
    struct PixResetMsg : Msg {
        PixResetMsg(bool val) {
            type = 0x04;
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
            type = 0x05;
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
        PixReadoutMsg(uint8_t srcBlock) {
            type = 0x06;
            payload[0] = 0;
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = 0;
            payload[4] = 0;
            payload[5] = 0;
            payload[6] = srcBlock&0x7;
        }
    };
    
    struct PixI2CTransactionMsg : Msg {
        PixI2CTransactionMsg(bool write, uint8_t len, uint16_t addr, uint16_t data) {
            Assert(len==1 || len==2);
            type = 0x07;
            payload[0] = (write ? 0x80 : 0) | (len==2 ? 0x40 : 0);
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = (addr&0xFF00)>>8;
            payload[4] = addr&0x00FF;
            payload[5] = (data&0xFF00)>>8;
            payload[6] = data&0x00FF;
        }
    };
    
    struct PixGetStatusMsg : Msg {
        PixGetStatusMsg() {
            type = 0x08;
        }
    };
    
    struct PixGetStatusResp : Resp {
        bool i2cDone() const                { return getBit(63);        }
        bool i2cErr() const                 { return getBit(62);        }
        uint16_t i2cReadData() const        { return getBits(61,46);    }
        bool captureDone() const            { return getBit(45);        }
        bool capturePixelDropped() const    { return getBit(44);        }
    };
    
    ICE40(QSPI& qspi) : _qspi(qspi) {}
    
    void sendMsg(const Msg& msg) {
        const QSPI_CommandTypeDef cmd = _qspiCmd(msg, 0);
        _qspi.command(cmd);
        // Wait for the transfer to complete
        QSPI::Event ev = _qspi.eventChannel.read();
        Assert(ev.type == QSPI::Event::Type::CommandDone);
    }
    
    template <typename T>
    T sendMsgWithResp(const Msg& msg) {
        T resp;
        const QSPI_CommandTypeDef cmd = _qspiCmd(msg, sizeof(resp));
        _qspi.read(cmd, &resp, sizeof(resp));
        // Wait for transfer to complete
        QSPI::Event ev = _qspi.eventChannel.read();
        Assert(ev.type == QSPI::Event::Type::ReadDone);
        return resp;
    }
    
private:
    static bool _getBit(const uint8_t* bytes, size_t len, uint8_t idx) {
        AssertArg(idx < len*8);
        const uint8_t byteIdx = len-(idx/8)-1;
        const uint8_t bitIdx = idx%8;
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
    
    static QSPI_CommandTypeDef _qspiCmd(const Msg& msg, size_t respLen) {
        uint8_t b[8];
        static_assert(sizeof(msg) == sizeof(b));
        memcpy(b, &msg, sizeof(b));
        
        // When dual-flash quadspi is enabled, the supplied address is
        // divided by 2, so we left-shift `addr` in anticipation of that.
        // But by doing so, we throw out the high bit of `msg`, so we
        // require it to be 0.
        AssertArg(!(b[0] & 0x80));
        const uint32_t addr = (
            (uint32_t)b[0]<<24  |
            (uint32_t)b[1]<<16  |
            (uint32_t)b[2]<<8   |
            (uint32_t)b[3]<<0
        ) << 1;
        
        const uint32_t altBytes = (
            (uint32_t)b[4]<<24  |
            (uint32_t)b[5]<<16  |
            (uint32_t)b[6]<<8   |
            (uint32_t)b[7]<<0
        );
        
        return QSPI_CommandTypeDef{
            .Instruction = 0,
            .InstructionMode = QSPI_INSTRUCTION_NONE,
            
            .Address = addr,
            .AddressSize = QSPI_ADDRESS_32_BITS,
            .AddressMode = QSPI_ADDRESS_4_LINES,
            
            .AlternateBytes = altBytes,
            .AlternateBytesSize = QSPI_ALTERNATE_BYTES_32_BITS,
            .AlternateByteMode = QSPI_ALTERNATE_BYTES_4_LINES,
            
            .DummyCycles = 6,
            
            .NbData = (uint32_t)respLen,
            .DataMode = (respLen ? QSPI_DATA_4_LINES : QSPI_DATA_NONE),
            
            .DdrMode = QSPI_DDR_MODE_DISABLE,
            .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
            .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
        };
    }
    
    QSPI& _qspi;
};

#pragma once
#include <cstdint>
#include <cstring>
#include <algorithm>
#include <utility>
#include <optional>
#include "Assert.h"
#include "Img.h"
#include "Toastbox/Task.h"

template <
    typename T_Scheduler,
    [[noreturn]] void T_Error(uint16_t)
>
class ICE {
#define Assert(x) if (!(x)) T_Error(__LINE__)

public:
    // MARK: - Types
    
    struct MsgType {
        static constexpr uint8_t StartBit   = 0x80;
        static constexpr uint8_t Resp       = 0x40;
    };
    
    struct Msg {
        uint8_t type = 0;
        uint8_t payload[7] = {};
        
        template <typename... T_Payload>
        constexpr Msg(uint8_t t, T_Payload... p) :
        type(t),
        payload{static_cast<uint8_t>(p)...} {
            static_assert(sizeof...(p)==0 || sizeof...(p)==sizeof(payload));
        }
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
    
    struct EchoMsg : public Msg {
        template <size_t T_N>
        constexpr EchoMsg(const char (&str)[T_N]) : Msg(MsgType::StartBit | MsgType::Resp | 0x00) {
            static_assert(T_N == sizeof(Msg::payload));
            memcpy(Msg::payload, str, sizeof(Msg::payload));
        }
    };
    
    struct EchoResp : Resp {
        bool matches(const EchoMsg& msg) {
            return !memcmp(Resp::payload, msg.payload, sizeof(msg.payload));
        }
    };
    
    struct LEDSetMsg : Msg {
        constexpr LEDSetMsg(uint8_t val) : Msg(MsgType::StartBit | 0x01,
            0,
            0,
            0,
            0,
            0,
            0,
            val
        ) {}
    };
    
    struct SDInitMsg : Msg {
        enum class Action {
            Nop,
            Reset,
            Trigger,
        };
        
        enum class ClkSpeed : uint8_t {
            Off     = 0,
            Slow    = 1,
            Fast    = 2,
        };
        
        constexpr SDInitMsg(Action action, ClkSpeed clkSpeed, uint8_t clkDelay) : Msg(MsgType::StartBit | 0x02,
            0,
            0,
            0,
            0,
            0,
            0,
            (((uint8_t)clkDelay                   &0xF)<<4) |
            (((uint8_t)clkSpeed                   &0x3)<<2) |
            (((uint8_t)(action==Action::Trigger)  &0x1)<<1) |
            (((uint8_t)(action==Action::Reset)    &0x1)<<0)
        ) {}
    };
    
    struct SDSendCmdMsg : Msg {
        enum class RespType : uint8_t {
            None        = 0,
            Len48       = 1,
            Len136      = 2,
        };
        
        enum class DatInType : uint8_t {
            None        = 0,
            Len512x1    = 1,
            Len4096xN   = 2,
        };
        
        constexpr SDSendCmdMsg(uint8_t sdCmd, uint32_t sdArg, RespType respType, DatInType datInType) : Msg(MsgType::StartBit | 0x03,
            ((uint8_t)respType<<2)|(uint8_t)datInType,
            0x40|sdCmd, // SD command start bit (1'b0), transmission bit (1'b1), SD command (6 bits = sdCmd)
            (sdArg&0xFF000000)>>24,
            (sdArg&0x00FF0000)>>16,
            (sdArg&0x0000FF00)>> 8,
            (sdArg&0x000000FF)>> 0,
            0x01 // SD command end bit (1'b1)
        ) {}
    };
    
    struct SDStatusMsg : Msg {
        constexpr SDStatusMsg() : Msg(MsgType::StartBit | MsgType::Resp | 0x04) {}
    };
    
    struct SDStatusResp : Resp {
        // Command
        bool cmdDone() const                                    { return Resp::getBit(63);                              }
        
        // Response
        bool respDone() const                                   { return Resp::getBit(62);                              }
        bool respCRCErr() const                                 { return Resp::getBit(61);                              }
        uint64_t resp() const                                   { return Resp::getBits(_RespIdx+48-1, _RespIdx);        }
        
        // DatOut
        bool datOutDone() const                                 { return Resp::getBit(12);                              }
        bool datOutCRCErr() const                               { return Resp::getBit(11);                              }
        
        // DatIn
        bool datInDone() const                                  { return Resp::getBit(10);                              }
        bool datInCRCErr() const                                { return Resp::getBit(9);                               }
        uint8_t datInCMD6AccessMode() const                     { return Resp::getBits(8,5);                            }
        
        // Other
        bool dat0Idle() const                                   { return Resp::getBit(4);                               }
        
        // Helper methods
        uint64_t respGetBit(uint8_t idx) const                  { return Resp::getBit(idx+_RespIdx);                    }
        uint64_t respGetBits(uint8_t start, uint8_t end) const  { return Resp::getBits(start+_RespIdx, end+_RespIdx);   }
        
    private:
        static constexpr size_t _RespIdx = 13;
    };
    
    struct SDRespMsg : public Msg {
        constexpr SDRespMsg(uint8_t idx) : Msg(MsgType::StartBit | MsgType::Resp | 0x05,
            0,
            0,
            0,
            0,
            0,
            0,
            idx
        ) {}
    };
    
    struct SDRespResp : Resp {
    };
    
    struct ImgResetMsg : Msg {
        constexpr ImgResetMsg(bool val) : Msg(MsgType::StartBit | 0x06,
            0,
            0,
            0,
            0,
            0,
            0,
            val
        ) {}
    };
    
    struct ImgSetHeaderMsg : Msg {
        static constexpr size_t ChunkLen = 6;
        constexpr ImgSetHeaderMsg(uint8_t idx, const uint8_t* h) : Msg(MsgType::StartBit | 0x07,
            h[0],
            h[1],
            h[2],
            h[3],
            h[4],
            h[5],
            idx
        ) {}
    };
    
    struct ImgCaptureMsg : Msg {
        constexpr ImgCaptureMsg(uint8_t dstBlock, uint8_t skipCount) : Msg(MsgType::StartBit | 0x08,
            0,
            0,
            0,
            0,
            0,
            0,
            ((skipCount&0x7)<<3) | (dstBlock&0x7)
        ) {}
    };
    
    struct ImgCaptureStatusMsg : Msg {
        constexpr ImgCaptureStatusMsg() : Msg(MsgType::StartBit | MsgType::Resp | 0x09) {}
    };
    
    struct ImgCaptureStatusResp : Resp {
        bool done() const               { return Resp::getBit(63);                  }
        uint32_t wordCount() const      { return (uint32_t)Resp::getBits(62,39);    }
        uint32_t highlightCount() const { return (uint32_t)Resp::getBits(38,21);    }
        uint32_t shadowCount() const    { return (uint32_t)Resp::getBits(20,3);     }
    };
    
    struct ImgReadoutMsg : Msg {
        constexpr ImgReadoutMsg(uint8_t srcBlock) : Msg(MsgType::StartBit | 0x0A,
            0,
            0,
            0,
            0,
            0,
            0,
            srcBlock&0x7
        ) {}
    };
    
    struct ImgI2CTransactionMsg : Msg {
        constexpr ImgI2CTransactionMsg(bool write, uint8_t len, uint16_t addr, uint16_t val) : Msg(MsgType::StartBit | 0x0B,
            (write ? 0x80 : 0) | (len==2 ? 0x40 : 0),
            0,
            0,
            (addr&0xFF00)>>8,
            addr&0x00FF,
            (val&0xFF00)>>8,
            val&0x00FF
        ) {}
    };
    
    struct ImgI2CStatusMsg : Msg {
        constexpr ImgI2CStatusMsg() : Msg(MsgType::StartBit | MsgType::Resp | 0x0C) {}
    };
    
    struct ImgI2CStatusResp : Resp {
        bool done() const               { return Resp::getBit(63);      }
        bool err() const                { return Resp::getBit(62);      }
        uint16_t readData() const       { return Resp::getBits(61,46);  }
    };
    
    struct ReadoutMsg : Msg {
        // ReadoutLen: the number of bytes in a single chunk
        // After `ReadoutLen` bytes are read, the SPI master must wait
        // until ICE_ST_SPI_D_READY=1 to clock out more data
        static constexpr size_t ReadoutLen = 512*4;
        constexpr ReadoutMsg() : Msg(MsgType::StartBit | 0x0D) {}
    };
    
    struct NopMsg : Msg {
        constexpr NopMsg() : Msg(0x00) {}
    };
    
    // MARK: - Functions Provided By Client
    static void Transfer(const Msg& msg, Resp* resp=nullptr);
    
    // MARK: - Methods
    
    static void Init() {
        // Confirm that we can communicate with ICE40
        EchoMsg msg("halla7");
        EchoResp resp;
        Transfer(msg, &resp);
        Assert(resp.matches(msg));
    }
    
    // MARK: - Img
    
    static void ImgReset() {
        Transfer(ImgResetMsg(0));
        _SleepMs<1>();
        Transfer(ImgResetMsg(1));
    }
    
    #warning TODO: call some failure function if this fails, instead of returning an optional
    #warning TODO: optimize the attempt mechanism -- how long should we sleep each iteration? how many attempts?
    static ImgCaptureStatusResp ImgCapture(const Img::Header& header, uint8_t dstBlock, uint8_t skipCount) {
        // Set the header of the image
        constexpr size_t ChunkCount = 4; // The number of 6-byte header chunks to write
        static_assert(sizeof(header) >= (ChunkCount * ImgSetHeaderMsg::ChunkLen));
        for (uint8_t i=0, off=0; i<ChunkCount; i++, off+=ImgSetHeaderMsg::ChunkLen) {
            Transfer(ImgSetHeaderMsg(i, (const uint8_t*)&header+off));
        }
        
        // Tell ICE40 to start capturing an image
        Transfer(ImgCaptureMsg(dstBlock, skipCount));
        
        // Wait for image to be captured
        constexpr uint16_t MaxAttempts = 1000;
        for (uint16_t i=0; i<MaxAttempts; i++) {
            const auto status = ImgCaptureStatus();
            // Try again if the image hasn't been captured yet
            if (!status.done()) {
                _SleepMs<1>();
                continue;
            }
            const uint32_t imgWordCount = status.wordCount();
            Assert(imgWordCount == Img::Len/sizeof(Img::Word));
            return status;
        }
        // Timeout capturing image
        // This should never happen, since it indicates a Verilog error or a hardware failure.
        Assert(false);
    }
    
    static ImgCaptureStatusResp ImgCaptureStatus() {
        ImgCaptureStatusResp resp;
        Transfer(ImgCaptureStatusMsg(), &resp);
        return resp;
    }
    
    #warning TODO: optimize the attempt mechanism -- how long should we sleep each iteration? how many attempts?
    static ImgI2CStatusResp ImgI2C(bool write, uint16_t addr, uint16_t val) {
        Transfer(ImgI2CTransactionMsg(write, 2, addr, val));
        
        // Wait for the I2C transaction to complete
        constexpr uint32_t MaxAttempts = 1000;
        for (uint32_t i=0; i<MaxAttempts; i++) {
            const ImgI2CStatusResp status = ImgI2CStatus();
            if (!status.err() && !status.done()) {
                _SleepMs<1>();
                continue;
            }
            return status;
        }
        // Timeout getting response from ICE40
        // This should never happen, since it indicates a Verilog error or a hardware failure.
        Assert(false);
    }
    
    static uint16_t ImgI2CRead(uint16_t addr) {
        const ImgI2CStatusResp resp = ImgI2C(false, addr, 0);
        Assert(!resp.err());
        return resp.readData();
    }
    
    static void ImgI2CWrite(uint16_t addr, uint16_t val) {
        const ImgI2CStatusResp resp = ImgI2C(true, addr, val);
        Assert(!resp.err());
    }
    
    static ImgI2CStatusResp ImgI2CStatus() {
        ImgI2CStatusResp resp;
        Transfer(ImgI2CStatusMsg(), &resp);
        return resp;
    }
    
    // MARK: - SD
    #warning TODO: optimize the attempt mechanism -- how long should we sleep each iteration? how many attempts?
    static SDStatusResp SDSendCmd(
        uint8_t sdCmd,
        uint32_t sdArg,
        typename SDSendCmdMsg::RespType respType      = SDSendCmdMsg::RespType::Len48,
        typename SDSendCmdMsg::DatInType datInType    = SDSendCmdMsg::DatInType::None
    ) {
        Transfer(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
        
        // Wait for command to be sent
        constexpr uint16_t MaxAttempts = 1000;
        for (uint16_t i=0; i<MaxAttempts; i++) {
            const auto s = SDStatus();
            if (
                // Try again if the command hasn't been sent yet
                !s.cmdDone() ||
                // Try again if we expect a response but it hasn't been received yet
                ((respType==SDSendCmdMsg::RespType::Len48||respType==SDSendCmdMsg::RespType::Len136) && !s.respDone()) ||
                // Try again if we expect DatIn but it hasn't been received yet
                (datInType==SDSendCmdMsg::DatInType::Len512x1 && !s.datInDone())
            ) {
                _SleepMs<1>();
                continue;
            }
            return s;
        }
        // Timeout sending SD command
        Assert(false);
    }
    
    static SDStatusResp SDStatus() {
        SDStatusResp resp;
        Transfer(SDStatusMsg(), &resp);
        return resp;
    }
    
private:
    template <uint16_t T_Ms>
    static constexpr auto _SleepMs = T_Scheduler::template SleepMs<T_Ms>;
    
    static bool _GetBit(const uint8_t* bytes, size_t len, uint8_t idx) {
        AssertArg(idx < len*8);
        const uint8_t byteIdx = len-(idx/8)-1;
        const uint8_t bitIdx = idx%8;
        const uint8_t bitMask = 1<<bitIdx;
        return bytes[byteIdx] & bitMask;
    }
    
    static uint64_t _GetBits(const uint8_t* bytes, size_t len, uint8_t start, uint8_t end) {
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

#undef Assert
};

#pragma once
#include <cstdint>
#include <cstring>
#include <algorithm>
#include <utility>
#include "Assert.h"
#include "SleepMs.h"
#include "Img.h"

class ICE {
public:
    #pragma mark - Types
    
    struct MsgType {
        static constexpr uint8_t StartBit   = 0x80;
        static constexpr uint8_t Resp       = 0x40;
    };
    
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
            type = MsgType::StartBit | MsgType::Resp | 0x00;
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
            type = MsgType::StartBit | 0x01;
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
        
        SDInitMsg(Action action, ClkSpeed speed, uint8_t clkDelay) {
            AssertArg((clkDelay&0xF) == clkDelay); // Ensure delay fits in 4 bits
            type = MsgType::StartBit | 0x02;
            payload[0] = 0;
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = 0;
            payload[4] = 0;
            payload[5] = 0;
            payload[6] = (((uint8_t)clkDelay                    &0xF)<<4) |
                         (((uint8_t)speed                       &0x3)<<2) |
                         (((uint8_t)(action==Action::Trigger)   &0x1)<<1) |
                         (((uint8_t)(action==Action::Reset)     &0x1)<<0) ;
        }
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
        
        SDSendCmdMsg(uint8_t sdCmd, uint32_t sdArg, RespType respType, DatInType datInType) {
            AssertArg((sdCmd&0x3F) == sdCmd); // Ensure SD command fits in 6 bits
            type = MsgType::StartBit | 0x03;
            payload[0] = ((uint8_t)respType<<2)|(uint8_t)datInType;
            payload[1] = 0x40|sdCmd; // SD command start bit (1'b0), transmission bit (1'b1), SD command (6 bits = sdCmd)
            payload[2] = (sdArg&0xFF000000)>>24;
            payload[3] = (sdArg&0x00FF0000)>>16;
            payload[4] = (sdArg&0x0000FF00)>> 8;
            payload[5] = (sdArg&0x000000FF)>> 0;
            payload[6] = 0x01; // SD command end bit (1'b1)
        }
    };
    
    struct SDStatusMsg : Msg {
        SDStatusMsg() {
            type = MsgType::StartBit | MsgType::Resp | 0x04;
        }
    };
    
    struct SDStatusResp : Resp {
        // Command
        bool cmdDone() const                                    { return getBit(63);                            }
        
        // Response
        bool respDone() const                                   { return getBit(62);                            }
        bool respCRCErr() const                                 { return getBit(61);                            }
        uint64_t resp() const                                   { return getBits(_RespIdx+48-1, _RespIdx);      }
        
        // DatOut
        bool datOutDone() const                                 { return getBit(12);                            }
        bool datOutCRCErr() const                               { return getBit(11);                            }
        
        // DatIn
        bool datInDone() const                                  { return getBit(10);                            }
        bool datInCRCErr() const                                { return getBit(9);                             }
        uint8_t datInCMD6AccessMode() const                     { return getBits(8,5);                          }
        
        // Other
        bool dat0Idle() const                                   { return getBit(4);                             }
        
        // Helper methods
        uint64_t respGetBit(uint8_t idx) const                  { return getBit(idx+_RespIdx);                  }
        uint64_t respGetBits(uint8_t start, uint8_t end) const  { return getBits(start+_RespIdx, end+_RespIdx); }
        
    private:
        static constexpr size_t _RespIdx = 13;
    };
    
    struct ImgResetMsg : Msg {
        ImgResetMsg(bool val) {
            type = MsgType::StartBit | 0x05;
            payload[0] = 0;
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = 0;
            payload[4] = 0;
            payload[5] = 0;
            payload[6] = val;
        }
    };
    
    struct ImgSetHeaderMsg : Msg {
        ImgSetHeaderMsg(uint8_t idx, const uint8_t* h) {
            type = MsgType::StartBit | 0x06;
            payload[0] = h[0];
            payload[1] = h[1];
            payload[2] = h[2];
            payload[3] = h[3];
            payload[4] = h[4];
            payload[5] = h[5];
            payload[6] = idx;
        }
    };
    
    struct ImgCaptureMsg : Msg {
        ImgCaptureMsg(uint8_t dstBlock) {
            type = MsgType::StartBit | 0x07;
            payload[0] = 0;
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = 0;
            payload[4] = 0;
            payload[5] = 0;
            payload[6] = dstBlock&0x7;
        }
    };
    
    struct ImgCaptureStatusMsg : Msg {
        ImgCaptureStatusMsg() {
            type = MsgType::StartBit | MsgType::Resp | 0x08;
        }
    };
    
    struct ImgCaptureStatusResp : Resp {
        bool done() const               { return getBit(63);                }
        uint32_t wordCount() const      { return (uint32_t)getBits(62,39);  }
        uint32_t highlightCount() const { return (uint32_t)getBits(38,21);  }
        uint32_t shadowCount() const    { return (uint32_t)getBits(20,3);   }
    };
    
    struct ImgReadoutMsg : Msg {
        ImgReadoutMsg(uint8_t dstBlock) {
            type = MsgType::StartBit | 0x09;
            payload[0] = 0;
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = 0;
            payload[4] = 0;
            payload[5] = 0;
            payload[6] = dstBlock&0x7;
        }
    };
    
    struct ImgI2CTransactionMsg : Msg {
        ImgI2CTransactionMsg(bool write, uint8_t len, uint16_t addr, uint16_t val) {
            AssertArg(len==1 || len==2);
            type = MsgType::StartBit | 0x0A;
            payload[0] = (write ? 0x80 : 0) | (len==2 ? 0x40 : 0);
            payload[1] = 0;
            payload[2] = 0;
            payload[3] = (addr&0xFF00)>>8;
            payload[4] = addr&0x00FF;
            payload[5] = (val&0xFF00)>>8;
            payload[6] = val&0x00FF;
        }
    };
    
    struct ImgI2CStatusMsg : Msg {
        ImgI2CStatusMsg() {
            type = MsgType::StartBit | MsgType::Resp | 0x0B;
        }
    };
    
    struct ImgI2CStatusResp : Resp {
        bool done() const               { return getBit(63);        }
        bool err() const                { return getBit(62);        }
        uint16_t readData() const       { return getBits(61,46);    }
    };
    
    struct ReadoutMsg : Msg {
        // ReadoutLen: the number of bytes in a single chunk
        // After `ReadoutLen` bytes are read, the SPI master must wait
        // until ICE_ST_SPI_D_READY=1 to clock out more data
        static constexpr size_t ReadoutLen = 512*4;
        ReadoutMsg() {
            type = MsgType::StartBit | 0x0C;
        }
    };
    
    struct NopMsg : Msg {
        NopMsg() {
            type = 0x00;
            payload[0] = 0x00;
            payload[1] = 0x00;
            payload[2] = 0x00;
            payload[3] = 0x00;
            payload[4] = 0x00;
            payload[5] = 0x00;
            payload[6] = 0x00;
        }
    };
    
    #pragma mark - Functions Provided By Client
    static void Transfer(const Msg& msg, Resp* resp=nullptr);
    
    #pragma mark - Methods
    
    static void Init() {
        // Confirm that we can communicate with ICE40
        const char str[] = "halla";
        EchoResp resp;
        Transfer(EchoMsg(str), &resp);
        Assert(!memcmp((char*)resp.payload, str, sizeof(str)));
    }
    
    #pragma mark - Img
    
    static void ImgReset() {
        Transfer(ImgResetMsg(0));
        SleepMs(1);
        Transfer(ImgResetMsg(1));
    }
    
    static std::pair<bool,ImgCaptureStatusResp> ImgCapture() {
        const Img::Header header = {
            // Section idx=0
            .version        = 0x4242,
            .imageWidth     = 2304,
            .imageHeight    = 1296,
            ._pad0          = 0,
            // Section idx=1
            .counter        = 0xCAFEBABE,
            ._pad1          = 0,
            // Section idx=2
            .timestamp      = 0xDEADBEEF,
            ._pad2          = 0,
            // Section idx=3
            .exposure       = 0x1111,
            .gain           = 0x2222,
            ._pad3          = 0,
        };
        
        // Set the header of the image
        for (uint8_t i=0, off=0; i<4; i++, off+=8) {
            Transfer(ImgSetHeaderMsg(i, (const uint8_t*)&header+off));
        }
        
        // Tell ICE40 to start capturing an image
        Transfer(ImgCaptureMsg(0));
        
        // Wait for image to be captured
        constexpr uint16_t MaxAttempts = 1000;
        for (uint16_t i=0; i<MaxAttempts; i++) {
            if (i >= 10) SleepMs(1);
            auto status = ImgCaptureStatus();
            // Try again if the image hasn't been captured yet
            if (!status.done()) continue;
            const uint32_t imgWordCount = status.wordCount();
            Assert(imgWordCount == Img::Len/sizeof(Img::Word));
            return {true, status};
        }
        // Timeout capturing image
        // This should never happen, since it indicates a Verilog error or a hardware failure.
        return {false, {}};
    }
    
    static ImgCaptureStatusResp ImgCaptureStatus() {
        ImgCaptureStatusResp resp;
        Transfer(ImgCaptureStatusMsg(), &resp);
        return resp;
    }
    
    static ImgI2CStatusResp ImgI2C(bool write, uint16_t addr, uint16_t val) {
        Transfer(ImgI2CTransactionMsg(write, 2, addr, val));
        
        // Wait for the I2C transaction to complete
        const uint32_t MaxAttempts = 1000;
        for (uint32_t i=0; i<MaxAttempts; i++) {
            if (i >= 10) SleepMs(1);
            const ImgI2CStatusResp status = ImgI2CStatus();
            if (status.err() || status.done()) return status;
        }
        // Timeout getting response from ICE40
        // This should never happen, since it indicates a Verilog error or a hardware failure.
        abort();
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
    
    #pragma mark - SD
    
    static SDStatusResp SDSendCmd(
        uint8_t sdCmd,
        uint32_t sdArg,
        SDSendCmdMsg::RespType respType      = SDSendCmdMsg::RespType::Len48,
        SDSendCmdMsg::DatInType datInType    = SDSendCmdMsg::DatInType::None
    ) {
        Transfer(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
        
        // Wait for command to be sent
        const uint16_t MaxAttempts = 1000;
        for (uint16_t i=0; i<MaxAttempts; i++) {
            if (i >= 10) SleepMs(1);
            auto s = SDStatus();
            // Try again if the command hasn't been sent yet
            if (!s.cmdDone()) continue;
            // Try again if we expect a response but it hasn't been received yet
            if ((respType==SDSendCmdMsg::RespType::Len48||respType==SDSendCmdMsg::RespType::Len136) && !s.respDone()) continue;
            // Try again if we expect DatIn but it hasn't been received yet
            if (datInType==SDSendCmdMsg::DatInType::Len512x1 && !s.datInDone()) continue;
            return s;
        }
        // Timeout sending SD command
        abort();
    }
    
    static SDStatusResp SDStatus() {
        SDStatusResp resp;
        Transfer(SDStatusMsg(), &resp);
        return resp;
    }
    
private:
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

};

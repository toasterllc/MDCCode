#pragma once
#include <cstdint>
#include <cstring>
#include <algorithm>
#include <utility>
#include <optional>
#include "Toastbox/Task.h"
#include "Assert.h"
#include "Img.h"
#include "GetBits.h"

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
        
        template<uint8_t T_Idx>
        bool getBit() const {
            return GetBit<T_Idx>(payload);
        }
        
        template<uint8_t T_Start, uint8_t T_End>
        uint64_t getBits() const {
            return GetBits<T_Start, T_End>(payload);
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
    
    struct SDConfigMsg : Msg {
        enum class Action : uint8_t {
            Reset   = 0,
            Init    = 1,
            ClkSet  = 2,
        };
        
        enum class ClkSpeed : uint8_t {
            Slow    = 0,
            Fast    = 1,
        };
        
        constexpr SDConfigMsg(Action action, ClkSpeed clkSpeed, uint8_t clkDelay) : Msg(MsgType::StartBit | 0x02,
            0,
            0,
            0,
            0,
            clkDelay,
            (uint8_t)clkSpeed,
            (uint8_t)action
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
        bool cmdDone() const                                    { return Resp::template getBit<63>();                            }
        
        // Response
        bool respDone() const                                   { return Resp::template getBit<62>();                            }
        bool respCRCErr() const                                 { return Resp::template getBit<61>();                            }
        uint64_t resp() const                                   { return Resp::template getBits<_RespIdx+48-1, _RespIdx>();      }
        
        // DatOut
        bool datOutDone() const                                 { return Resp::template getBit<12>();                            }
        bool datOutCRCErr() const                               { return Resp::template getBit<11>();                            }
        
        // DatIn
        bool datInDone() const                                  { return Resp::template getBit<10>();                            }
        bool datInCRCErr() const                                { return Resp::template getBit<9>();                             }
        uint8_t datInCMD6AccessMode() const                     { return Resp::template getBits<8,5>();                          }
        
        // Other
        bool dat0Idle() const                                   { return Resp::template getBit<4>();                             }
        
        // Helper methods
        template<uint8_t T_Idx>
        bool respGetBit() const {
            return Resp::template getBit<T_Idx+_RespIdx>();
        }
        
        template<uint8_t T_Start, uint8_t T_End>
        uint64_t respGetBits() const {
            return Resp::template getBits<T_Start+_RespIdx, T_End+_RespIdx>();
        }
        
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
        constexpr ImgCaptureMsg(uint8_t dstRAMBlock, uint8_t skipCount) : Msg(MsgType::StartBit | 0x08,
            0,
            0,
            0,
            0,
            0,
            0,
            ((skipCount&0x7)<<3) | (dstRAMBlock&0x7)
        ) {}
    };
    
    struct ImgCaptureStatusMsg : Msg {
        constexpr ImgCaptureStatusMsg() : Msg(MsgType::StartBit | MsgType::Resp | 0x09) {}
    };
    
    struct ImgCaptureStatusResp : Resp {
        bool done() const               { return Resp::template getBit<63>();                  }
        uint32_t pixelCount() const     { return (uint32_t)Resp::template getBits<62,39>();    }
        uint32_t highlightCount() const { return (uint32_t)Resp::template getBits<38,21>();    }
        uint32_t shadowCount() const    { return (uint32_t)Resp::template getBits<20,3>();     }
    };
    
    struct ImgReadoutMsg : Msg {
        constexpr ImgReadoutMsg(uint8_t srcRAMBlock, Img::Size imgSize) : Msg(MsgType::StartBit | 0x0A,
            0,
            0,
            0,
            0,
            0,
            0,
            (srcRAMBlock&0x7) | ((uint8_t)(imgSize==Img::Size::Thumb)<<3)
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
        bool done() const               { return Resp::template getBit<63>();        }
        bool err() const                { return Resp::template getBit<62>();        }
        uint16_t readData() const       { return Resp::template getBits<61,46>();    }
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
        _Sleep(_Ms(1));
        Transfer(ImgResetMsg(1));
    }
    
    #warning TODO: call some failure function if this fails, instead of returning an optional
    #warning TODO: optimize the attempt mechanism -- how long should we sleep each iteration? how many attempts?
    static ImgCaptureStatusResp ImgCapture(const Img::Header& header, uint8_t dstRAMBlock, uint8_t skipCount) {
        // Set the header of the image
        constexpr size_t ChunkCount = 4; // The number of 6-byte header chunks to write
        static_assert(sizeof(header) >= (ChunkCount * ImgSetHeaderMsg::ChunkLen));
        for (uint8_t i=0, off=0; i<ChunkCount; i++, off+=ImgSetHeaderMsg::ChunkLen) {
            Transfer(ImgSetHeaderMsg(i, (const uint8_t*)&header+off));
        }
        
        // Tell ICE40 to start capturing an image
        Transfer(ImgCaptureMsg(dstRAMBlock, skipCount));
        
        // Wait for image to be captured
        constexpr uint16_t MaxAttempts = 1000;
        for (uint16_t i=0; i<MaxAttempts; i++) {
            const auto status = ImgCaptureStatus();
            // Try again if the image hasn't been captured yet
            if (!status.done()) {
                _Sleep(_Ms(1));
                continue;
            }
            const uint32_t imgPixelCount = status.pixelCount();
            Assert(imgPixelCount == Img::Full::PixelCount);
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
                _Sleep(_Ms(1));
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
    static SDStatusResp SDStatus() {
        SDStatusResp resp;
        Transfer(SDStatusMsg(), &resp);
        return resp;
    }
    
private:
    static constexpr auto _Ms = T_Scheduler::Ms;
    static constexpr auto _Sleep = T_Scheduler::Sleep;

#undef Assert
};

#pragma once
#include <msp430.h>
#include "ICE.h"
#include "Util.h"
#include "Toastbox/Task.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"

namespace SD {

[[noreturn]]
static void _BOR() {
    PMMCTL0 = PMMPW | PMMSWBOR;
    for (;;);
}

template <
    typename T_Scheduler,
    typename T_ICE,
//    [[noreturn]]
    void T_Error(uint16_t),
    uint8_t T_ClkDelaySlow,
    uint8_t T_ClkDelayFast
>
class Card {
#define Assert(x) if (!(x)) T_Error(__LINE__)
#define AssertArg(x) if (!(x)) T_Error(__LINE__)

public:
    static void Reset() {
        // Reset SDController
        T_ICE::Transfer(_ConfigReset);
        // TODO: switch to sleeping 25us when we get back to 400 kHz
        _Sleep(_Us(100)); // Wait 20 100kHz cycles
    }
    
    static uint16_t Init(CardId* cardId=nullptr, CardData* cardData=nullptr) {
        uint16_t rca = 0;
        
        // Enable slow SDController clock
        T_ICE::Transfer(_ConfigClkSetSlow);
        // TODO: switch to sleeping 25us when we get back to 400 kHz
        _Sleep(_Us(100)); // Wait 20 100kHz cycles
        
        // ====================
        // CMD0 | GO_IDLE_STATE
        //   State: X -> Idle
        //   Go to idle state
        // ====================
        {
            // SD "Initialization sequence": wait max(1ms, 74 cycles @ 400 kHz) == 1ms
            _Sleep(_Ms(1));
            // Send CMD0
            _SendCmd(_CMD0, 0, _RespType::None);
            // There's no response to CMD0
        }
        
        // ====================
        // CMD8 | SEND_IF_COND
        //   State: Idle -> Idle
        //   Send interface condition
        // ====================
        {
            constexpr uint32_t Voltage       = 0x00000001;
            constexpr uint32_t CheckPattern  = 0x000000AA; // "It is recommended to use '10101010b' for the 'check pattern'"
            const _SDStatusResp status = _SendCmd(_CMD8, (Voltage<<8)|(CheckPattern<<0));
            const uint8_t replyVoltage = status.template respGetBits<19,16>();
            Assert(replyVoltage == Voltage);
            const uint8_t replyCheckPattern = status.template respGetBits<15,8>();
            Assert(replyCheckPattern == CheckPattern);
        }
        
        // ====================
        // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
        //   State: Idle -> Ready
        //   Initialize
        // ====================
        for (;;) {
            // CMD55
            _SendCmd(_CMD55, 0);
            
            // CMD41
            {
                const _SDStatusResp status = _SendCmd(_CMD41, 0x51008000);
                // Don't check CRC with .respCRCOK() (the CRC response to ACMD41 is all 1's)
                // Check if card is ready. If it's not, retry ACMD41.
                const bool ready = status.template respGetBit<39>();
                if (!ready) continue;
                // Check S18A; for LVS initialization, it's expected to be 0
                const bool S18A = status.template respGetBit<32>();
                Assert(S18A == 1);
                break;
            }
        }
        
        return rca;
    }
    
private:
    using _SDConfigMsg  = typename T_ICE::SDConfigMsg;
    using _SDSendCmdMsg = typename T_ICE::SDSendCmdMsg;
    using _SDRespMsg    = typename T_ICE::SDRespMsg;
    using _SDRespResp   = typename T_ICE::SDRespResp;
    using _SDStatusResp = typename T_ICE::SDStatusResp;
    using _RespType     = typename T_ICE::SDSendCmdMsg::RespType;
    using _DatInType    = typename T_ICE::SDSendCmdMsg::DatInType;
    
    static constexpr auto _ConfigReset = _SDConfigMsg(_SDConfigMsg::Reset);
    
    static constexpr auto _ConfigClkSetSlow = _SDConfigMsg(
        _SDConfigMsg::Init, _SDConfigMsg::ClkSpeed::Slow, T_ClkDelaySlow, _SDConfigMsg::PinMode::OpenDrain);
        
    static constexpr auto _ConfigClkSetSlowPushPull = _SDConfigMsg(
        _SDConfigMsg::Init, _SDConfigMsg::ClkSpeed::Slow, T_ClkDelaySlow, _SDConfigMsg::PinMode::PushPull);
    
    static constexpr auto _ConfigClkSetFast = _SDConfigMsg(
        _SDConfigMsg::Init, _SDConfigMsg::ClkSpeed::Fast, T_ClkDelayFast, _SDConfigMsg::PinMode::PushPull);
    
    static constexpr auto _Us = T_Scheduler::Us;
    static constexpr auto _Ms = T_Scheduler::Ms;
    static constexpr auto _Sleep = T_Scheduler::Sleep;
    
    static constexpr uint8_t _CMD0  = 0;
    static constexpr uint8_t _CMD2  = 2;
    static constexpr uint8_t _CMD3  = 3;
    static constexpr uint8_t _CMD6  = 6;
    static constexpr uint8_t _CMD7  = 7;
    static constexpr uint8_t _CMD8  = 8;
    static constexpr uint8_t _CMD9  = 9;
    static constexpr uint8_t _CMD10 = 10;
    static constexpr uint8_t _CMD11 = 11;
    static constexpr uint8_t _CMD12 = 12;
    static constexpr uint8_t _CMD18 = 18;
    static constexpr uint8_t _CMD23 = 23;
    static constexpr uint8_t _CMD25 = 25;
    static constexpr uint8_t _CMD41 = 41;
    static constexpr uint8_t _CMD55 = 55;
    
    #warning TODO: optimize the attempt mechanism -- how long should we sleep each iteration? how many attempts?
    static _SDStatusResp _SendCmd(
        uint8_t sdCmd,
        uint32_t sdArg,
        _RespType respType   = _RespType::Len48,
        _DatInType datInType = _DatInType::None
    ) {
        T_ICE::Transfer(_SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
        
        // Wait for command to be sent
        constexpr uint16_t MaxAttempts = 1000;
        for (uint16_t i=0; i<MaxAttempts; i++) {
            const auto s = T_ICE::SDStatus();
            if (
                // Try again if the command hasn't been sent yet
                !s.cmdDone() ||
                // Try again if we expect a response but it hasn't been received yet
                ((respType==_RespType::Len48||respType==_RespType::Len136) && !s.respDone()) ||
                // Try again if we expect DatIn but it hasn't been received yet
                (datInType==_DatInType::Len512x1 && !s.datInDone())
            ) {
                _Sleep(_Ms(1));
                continue;
            }
            
            // Verify CRC for all commands, except CMD0 and CMD41
            switch (sdCmd) {
            case _CMD0:
            case _CMD41:
                break;
            default:
                if (s.respCRCErr()) {
                    T_Error(0xFE00|sdCmd);
                    _BOR();
                }
                break;
            }
            return s;
        }
        
        // Timeout sending SD command
        T_Error(0xFF00|sdCmd);
        
        if (!sdCmd) {
            for (;;) {
                T_ICE::Transfer(typename T_ICE::LEDSetMsg(0xF));
                _Sleep(_Ms(100));
                T_ICE::Transfer(typename T_ICE::LEDSetMsg(0x0));
                _Sleep(_Ms(100));
            }
        }
        
        _BOR();
    }
    
#undef Assert
#undef AssertArg
};

} // namespace SD

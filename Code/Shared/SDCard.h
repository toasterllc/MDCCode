#pragma once
#include "ICE.h"
#include "Util.h"
#include "Toastbox/Task.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"

namespace SD {

template <
    typename T_Scheduler,
    typename T_ICE,
    bool T_SetPowerEnabled(bool),
    [[noreturn]] void T_Error(uint16_t),
    uint8_t T_ClkDelaySlow,
    uint8_t T_ClkDelayFast
>
class Card {
#define Assert(x) if (!(x)) T_Error(__LINE__)
#define AssertArg(x) if (!(x)) T_Error(__LINE__)

public:
    static uint16_t Enable(CardId* cardId=nullptr, CardData* cardData=nullptr) {
        uint16_t rca = 0;
        
        // Turn on SD card power and wait for it to reach 2.8V
        const bool br = T_SetPowerEnabled(true);
        Assert(br);
        
        // Enable slow SDController clock
        T_ICE::Transfer(_ConfigClkSetSlow);
        _Sleep(_Us(1));
        
        // Trigger the SD card low voltage signalling (LVS) init sequence
        T_ICE::Transfer(_ConfigInit);
        // Wait 6ms for the LVS init sequence to complete (LVS spec specifies 5ms, and ICE40 waits 5.5ms)
        _Sleep(_Ms(6));
        
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
            constexpr uint32_t Voltage       = 0x00000002; // 0b0010 == 'Low Voltage Range'
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
                Assert(S18A == 0);
                break;
            }
        }
        
        // ====================
        // CMD2 | ALL_SEND_CID
        //   State: Ready -> Identification
        //   Get card identification number (CID)
        // ====================
        {
            // The response to CMD2 is 136 bits, instead of the usual 48 bits
            _SendCmd(_CMD2, 0, _RespType::Len136);
            if (cardId) _SDRespGet<sizeof(*cardId)>(cardId);
        }
        
        // ====================
        // CMD3 | SEND_RELATIVE_ADDR
        //   State: Identification -> Standby
        //   Publish a new relative address (RCA)
        // ====================
        {
            const _SDStatusResp status = _SendCmd(_CMD3, 0);
            // Get the card's RCA from the response
            rca = status.template respGetBits<39,24>();
        }
        
        // ====================
        // CMD9 | SEND_CSD
        //   State: Standby -> Standby
        //   Get card-specific data (CSD)
        // ====================
        // We do this here because CMD9 is only valid in the standby state,
        // and this is the only time we're in the standby state.
        if (cardData) {
            _SendCmd(_CMD9, ((uint32_t)rca)<<16, _RespType::Len136);
            _SDRespGet<sizeof(*cardData)>(cardData);
        }
        
        // ====================
        // CMD7 | SELECT_CARD/DESELECT_CARD
        //   State: Standby -> Transfer
        //   Select card
        // ====================
        {
            _SendCmd(_CMD7, ((uint32_t)rca)<<16);
        }
        
        // ====================
        // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
        //   State: Transfer -> Transfer
        //   Set bus width to 4 bits
        // ====================
        {
            // CMD55
            {
                _SendCmd(_CMD55, ((uint32_t)rca)<<16);
            }
            
            // CMD6
            {
                _SendCmd(_CMD6, 0x00000002);
            }
        }
        
        // ====================
        // CMD6 | SWITCH_FUNC
        //   State: Transfer -> Data -> Transfer (automatically returns to Transfer state after sending 512 bits of data)
        //   Switch to SDR104
        // ====================
        {
            // Mode = 1 (switch function)  = 0x80
            // Group 6 (Reserved)          = 0xF (no change)
            // Group 5 (Reserved)          = 0xF (no change)
            // Group 4 (Current Limit)     = 0xF (no change)
            // Group 3 (Driver Strength)   = 0xF (no change; 0x0=TypeB[1x], 0x1=TypeA[1.5x], 0x2=TypeC[.75x], 0x3=TypeD[.5x])
            // Group 2 (Command System)    = 0xF (no change)
            // Group 1 (Access Mode)       = 0x3 (SDR104)
            const _SDStatusResp status = _SendCmd(_CMD6, 0x80FFFFF3, _RespType::Len48, _DatInType::Len512x1);
            Assert(!status.datInCRCErr());
            // Verify that the access mode was successfully changed
            // TODO: properly handle this failing, see CMD6 docs
            Assert(status.datInCMD6AccessMode() == 0x03);
        }
        
        // SDClock=Fast
        T_ICE::Transfer(_ConfigClkSetFast);
        _Sleep(_Us(1));
        
        return rca;
    }
    
    static void Disable() {
        T_ICE::Transfer(_ConfigReset);
        _Sleep(_Us(1));
        
        // Turn off SD card power and wait for it to reach 0V
        const bool br = T_SetPowerEnabled(false);
        Assert(br);
    }
    
//    bool enabled() const { return _enabled; }
//    
//    const CardId& cardId() const { return *_cardId; }
//    const CardData& cardData() const { return *_cardData; }
    
    static void ReadStart(SD::BlockIdx blockIdx) {
        // ====================
        // CMD18 | READ_MULTIPLE_BLOCK
        //   State: Transfer -> Send Data
        //   Read blocks of data (1 block == 512 bytes)
        // ====================
        _SendCmd(_CMD18, blockIdx, _RespType::Len48, _DatInType::Len4096xN);
    }
    
    static void ReadStop() {
        _ReadWriteStop();
    }
    
    // `blockCountEst`: the estimated block count that will be written; used to pre-erase SD blocks as a performance
    // optimization. More data can be written than `blockCountEst`, but performance may suffer if the actual count
    // is longer than the estimate.
    static void WriteStart(uint16_t rca, SD::BlockIdx blockIdx, uint32_t blockCountEst=0) {
        // ====================
        // ACMD23 | SET_WR_BLK_ERASE_COUNT
        //   State: Transfer -> Transfer
        //   Set the number of blocks to be
        //   pre-erased before writing
        // ====================
        {
            // CMD55
            {
                _SendCmd(_CMD55, ((uint32_t)rca)<<16);
            }
            
            // CMD23
            {
                // Min block count = 1
                const uint32_t blockCount = std::min(UINT32_C(1), blockCountEst);
                _SendCmd(_CMD23, blockCount);
            }
        }
        
        // ====================
        // CMD25 | WRITE_MULTIPLE_BLOCK
        //   State: Transfer -> Receive Data
        //   Write blocks of data
        // ====================
        {
            _SendCmd(_CMD25, blockIdx);
        }
    }
    
    static void WriteStop() {
        _ReadWriteStop();
    }
    
    static void WriteImage(uint16_t rca, uint8_t srcBlock, SD::BlockIdx dstBlockIdx) {
        WriteStart(rca, dstBlockIdx, ImgSD::ImgBlockCount);
        
        // Clock out the image on the DAT lines
        T_ICE::Transfer(typename T_ICE::ImgReadoutMsg(srcBlock));
        
        #warning TODO: call error handler if this takes too long -- look at SD spec for max time
        // Wait for writing to finish
        for (;;) {
            const _SDStatusResp status = T_ICE::SDStatus();
            if (status.datOutDone()) {
                Assert(!status.datOutCRCErr());
                break;
            }
            // Busy
        }
        
        WriteStop();
        
        #warning TODO: call error handler if this takes too long -- look at SD spec for max time
        // Wait for SD card to indicate that it's ready (DAT0=1)
        for (;;) {
            const _SDStatusResp status = T_ICE::SDStatus();
            if (status.dat0Idle()) break;
        }
    }
    
private:
    using _SDConfigMsg  = typename T_ICE::SDConfigMsg;
    using _SDSendCmdMsg = typename T_ICE::SDSendCmdMsg;
    using _SDRespMsg    = typename T_ICE::SDRespMsg;
    using _SDRespResp   = typename T_ICE::SDRespResp;
    using _SDStatusResp = typename T_ICE::SDStatusResp;
    using _RespType     = typename T_ICE::SDSendCmdMsg::RespType;
    using _DatInType    = typename T_ICE::SDSendCmdMsg::DatInType;
    
    static constexpr auto _ConfigClkSetSlow = _SDConfigMsg(_SDConfigMsg::Action::ClkSet,    _SDConfigMsg::ClkSpeed::Slow,   T_ClkDelaySlow);
    static constexpr auto _ConfigClkSetFast = _SDConfigMsg(_SDConfigMsg::Action::ClkSet,    _SDConfigMsg::ClkSpeed::Fast,   T_ClkDelayFast);
    static constexpr auto _ConfigReset      = _SDConfigMsg(_SDConfigMsg::Action::Reset,     _SDConfigMsg::ClkSpeed::Slow,   0);
    static constexpr auto _ConfigInit       = _SDConfigMsg(_SDConfigMsg::Action::Init,      _SDConfigMsg::ClkSpeed::Slow,   0);
    
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
                Assert(!s.respCRCErr());
                break;
            }
            return s;
        }
        // Timeout sending SD command
        Assert(false);
    }
    
    static void _ReadWriteStop() {
        // ====================
        // CMD12 | STOP_TRANSMISSION
        //   State: Send Data -> Transfer
        //   Finish reading
        // ====================
        _SendCmd(_CMD12, 0);
    }
    
    template <size_t T_Len>
    static void _SDRespGet(void* dst) {
        using Resp = typename T_ICE::Resp;
        static_assert((T_Len % sizeof(Resp)) == 0);
        
        Resp* resp = (Resp*)dst;
        for (size_t i=0; i<(T_Len/sizeof(Resp)); i++) {
            T_ICE::Transfer(_SDRespMsg(i), resp);
            resp++;
        }
    }
    
//    template <size_t T_Len>
//    static void _SDRespGet(void* dst) {
//        using Resp = typename T_ICE::Resp;
//        static_assert((T_Len % sizeof(Resp)) == 0);
//        
//        Resp* resp = (Resp*)dst;
//        for (size_t i=0; i<(T_Len/sizeof(Resp)); i++) {
//            T_ICE::Transfer(_SDRespMsg(i), resp);
//            resp++;
//        }
//    }
    
//    template <typename T>
//    static T _SDResp128Get() {
//        // Get the 128-bit response
//        T dst;
//        _SDRespResp resp;
//        static_assert((sizeof(T) % sizeof(resp.payload)) == 0);
//        for (size_t i=0; i<sizeof(T)/sizeof(resp); i++) {
//            T_ICE::Transfer(_SDRespMsg(i), &resp);
//            memcpy(((uint8_t*)&dst) + sizeof(resp.payload)*i, resp.payload, sizeof(resp.payload));
//        }
//        return dst;
//    }
    
//    bool _enabled = false;
//    uint16_t _rca = 0;
//    CardId _cardId;
//    CardData _cardData;
#undef Assert
#undef AssertArg
};

} // namespace SD

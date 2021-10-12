#pragma once
#include "ICE40.h"
#include "Assert.h"
#include "SleepMs.h"

class SDCard {
public:
    // Functions provided by client
    static void SetPowerEnabled(bool en);
    
    // Values provided by client
    static const uint8_t ClkDelaySlow;
    static const uint8_t ClkDelayFast;
    
    // BlockLen: block size of SD card
    static constexpr uint32_t BlockLen = 512;
    
    static constexpr uint32_t CeilToBlockLen(uint32_t len) {
        return ((len+BlockLen-1)/BlockLen)*BlockLen;
    }
    
    void init() {
        // Disable SDController clock
        ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Nop,         _SDInitMsg::ClkSpeed::Off,  ClkDelaySlow));
        SleepMs(1);
        
        // Enable slow SDController clock
        ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Nop,         _SDInitMsg::ClkSpeed::Slow, ClkDelaySlow));
        SleepMs(1);
        
        // Enter the init mode of the SDController state machine
        ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Reset,       _SDInitMsg::ClkSpeed::Slow, ClkDelaySlow));
        
        // Turn off SD card power and wait for it to reach 0V
        SetPowerEnabled(false);
        
        // Turn on SD card power and wait for it to reach 2.8V
        SetPowerEnabled(true);
        
        // Trigger the SD card low voltage signalling (LVS) init sequence
        ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Trigger,     _SDInitMsg::ClkSpeed::Slow, ClkDelaySlow));
        // Wait 6ms for the LVS init sequence to complete (LVS spec specifies 5ms, and ICE40 waits 5.5ms)
        SleepMs(6);
        
        // ====================
        // CMD0 | GO_IDLE_STATE
        //   State: X -> Idle
        //   Go to idle state
        // ====================
        {
            // SD "Initialization sequence": wait max(1ms, 74 cycles @ 400 kHz) == 1ms
            SleepMs(1);
            // Send CMD0
            ICE40::SDSendCmd(_CMD0, 0, _RespType::None);
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
            auto status = ICE40::SDSendCmd(_CMD8, (Voltage<<8)|(CheckPattern<<0));
            Assert(!status.respCRCErr());
            const uint8_t replyVoltage = status.respGetBits(19,16);
            Assert(replyVoltage == Voltage);
            const uint8_t replyCheckPattern = status.respGetBits(15,8);
            Assert(replyCheckPattern == CheckPattern);
        }
        
        // ====================
        // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
        //   State: Idle -> Ready
        //   Initialize
        // ====================
        for (;;) {
            // CMD55
            {
                auto status = ICE40::SDSendCmd(_CMD55, 0);
                Assert(!status.respCRCErr());
            }
            
            // CMD41
            {
                auto status = ICE40::SDSendCmd(_CMD41, 0x51008000);
                
                // Don't check CRC with .respCRCOK() (the CRC response to ACMD41 is all 1's)
                
                if (status.respGetBits(45,40) != 0x3F) {
                    for (volatile int i=0; i<10; i++);
                    continue;
                }
                
                // TODO: determine if the wrong CRC in the ACMD41 response is because `ClkDelaySlow` needs tuning
                if (status.respGetBits(7,1) != 0x7F) {
                    for (volatile int i=0; i<10; i++);
                    continue;
                }
                
                // Check if card is ready. If it's not, retry ACMD41.
                const bool ready = status.respGetBit(39);
                if (!ready) continue;
                // Check S18A; for LVS initialization, it's expected to be 0
                const bool S18A = status.respGetBit(32);
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
            ICE40::SDSendCmd(_CMD2, 0, _RespType::Len136);
            // Don't check the CRC because the R2 CRC isn't calculated in the typical manner,
            // so it'll be flagged as incorrect.
        }
        
        // ====================
        // CMD3 | SEND_RELATIVE_ADDR
        //   State: Identification -> Standby
        //   Publish a new relative address (RCA)
        // ====================
        {
            auto status = ICE40::SDSendCmd(_CMD3, 0);
            Assert(!status.respCRCErr());
            // Get the card's RCA from the response
            _rca = status.respGetBits(39,24);
        }
        
        // ====================
        // CMD7 | SELECT_CARD/DESELECT_CARD
        //   State: Standby -> Transfer
        //   Select card
        // ====================
        {
            auto status = ICE40::SDSendCmd(_CMD7, ((uint32_t)_rca)<<16);
            Assert(!status.respCRCErr());
        }
        
        // ====================
        // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
        //   State: Transfer -> Transfer
        //   Set bus width to 4 bits
        // ====================
        {
            // CMD55
            {
                auto status = ICE40::SDSendCmd(_CMD55, ((uint32_t)_rca)<<16);
                Assert(!status.respCRCErr());
            }
            
            // CMD6
            {
                auto status = ICE40::SDSendCmd(_CMD6, 0x00000002);
                Assert(!status.respCRCErr());
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
            auto status = ICE40::SDSendCmd(_CMD6, 0x80FFFFF3, _RespType::Len48, _DatInType::Len512x1);
            Assert(!status.respCRCErr());
            Assert(!status.datInCRCErr());
            // Verify that the access mode was successfully changed
            // TODO: properly handle this failing, see CMD6 docs
            Assert(status.datInCMD6AccessMode() == 0x03);
        }
        
        // SDClock=Off
        {
            ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Nop,    _SDInitMsg::ClkSpeed::Off,   ClkDelaySlow));
        }
        
        // SDClockDelay=FastDelay
        {
            ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Nop,    _SDInitMsg::ClkSpeed::Off,   ClkDelayFast));
        }
        
        // SDClock=FastClock
        {
            ICE40::Transfer(_SDInitMsg(_SDInitMsg::Action::Nop,    _SDInitMsg::ClkSpeed::Fast,   ClkDelayFast));
        }
        
        
    //    {
    //        // Update state
    //        _op = Op::SDRead;
    //        _opDataRem = 0xFFFFFE00; // divisible by 512
    //        
    //        // ====================
    //        // CMD18 | READ_MULTIPLE_BLOCK
    //        //   State: Transfer -> Send Data
    //        //   Read blocks of data (1 block == 512 bytes)
    //        // ====================
    //        {
    //            auto status = ICE40::SDSendCmd(_CMD18, 0, _RespType::Len48, _DatInType::Len4096xN);
    //            Assert(!status.respCRCErr());
    //        }
    //        
    //        // Send the Readout message, which causes us to enter the SD-readout mode until
    //        // we release the chip select
    //        _ICE_ST_SPI_CS_::Write(0);
    //        ICETransferNoCS(ReadoutMsg());
    //        
    //        // Advance state machine
    //        _sdRead_updateState();
    //    }
        
        
        
    //    bool on = true;
    //    for (volatile uint32_t iter=0;; iter++) {
    //        // ====================
    //        // ACMD23 | SET_WR_BLK_ERASE_COUNT
    //        //   State: Transfer -> Transfer
    //        //   Set the number of blocks to be
    //        //   pre-erased before writing
    //        // ====================
    //        {
    //            // CMD55
    //            {
    //                auto status = ICE40::SDSendCmd(_CMD55, ((uint32_t)_rca)<<16);
    //                Assert(!status.respCRCErr());
    //            }
    //            
    //            // CMD23
    //            {
    //                auto status = ICE40::SDSendCmd(_CMD23, 0x00000001);
    //                Assert(!status.respCRCErr());
    //            }
    //        }
    //        
    //        // ====================
    //        // CMD25 | WRITE_MULTIPLE_BLOCK
    //        //   State: Transfer -> Receive Data
    //        //   Write blocks of data (1 block == 512 bytes)
    //        // ====================
    //        {
    //            auto status = ICE40::SDSendCmd(_CMD25, 0);
    //            Assert(!status.respCRCErr());
    //        }
    //        
    //        // Clock out data on DAT lines
    //        {
    //            ICE40::Transfer(PixReadoutMsg(0));
    //        }
    //        
    //        // Wait until we're done clocking out data on DAT lines
    //        {
    //            // Waiting for writing to finish
    //            for (;;) {
    //                auto status = status();
    //                if (status.datOutDone()) {
    //                    if (status.datOutCRCErr()) {
    //                        _led3.write(true);
    //                        for (;;);
    //                    }
    //                    break;
    //                }
    //                // Busy
    //            }
    //        }
    //        
    //        // ====================
    //        // CMD12 | STOP_TRANSMISSION
    //        //   State: Receive Data -> Programming
    //        //   Finish writing
    //        // ====================
    //        {
    //            auto status = ICE40::SDSendCmd(_CMD12, 0);
    //            Assert(!status.respCRCErr());
    //            
    //            // Wait for SD card to indicate that it's ready (DAT0=1)
    //            for (;;) {
    //                if (status.dat0Idle()) break;
    //                status = status();
    //            }
    //        }
    //        
    //        _led0.write(on);
    //        on = !on;
    //    }
    }
    
    void readStart(uint32_t addr) {
        // ====================
        // CMD18 | READ_MULTIPLE_BLOCK
        //   State: Transfer -> Send Data
        //   Read blocks of data (1 block == 512 bytes)
        // ====================
        auto status = ICE40::SDSendCmd(_CMD18, addr, _RespType::Len48, _DatInType::Len4096xN);
        Assert(!status.respCRCErr());
    }
    
    void readStop() {
        _readWriteStop();
    }
    
    // `lenEst`: the estimated byte count that will be written; used to pre-erase SD blocks as a performance
    // optimization. More data can be written than `lenEst`, but performance may suffer if the actual length
    // is longer than the estimate.
    void writeStart(uint32_t addr, uint32_t lenEst=0) {
        // ====================
        // ACMD23 | SET_WR_BLK_ERASE_COUNT
        //   State: Transfer -> Transfer
        //   Set the number of blocks to be
        //   pre-erased before writing
        // ====================
        {
            // CMD55
            {
                auto status = ICE40::SDSendCmd(_CMD55, ((uint32_t)_rca)<<16);
                Assert(!status.respCRCErr());
            }
            
            // CMD23
            {
                // Round up to the nearest block size, with a minimum of 1 block
                const uint32_t blockCount = std::min(UINT32_C(1), (lenEst+BlockLen-1)/BlockLen);
                auto status = ICE40::SDSendCmd(_CMD23, blockCount);
                Assert(!status.respCRCErr());
            }
        }
        
        // ====================
        // CMD25 | WRITE_MULTIPLE_BLOCK
        //   State: Transfer -> Receive Data
        //   Write blocks of data
        // ====================
        {
            auto status = ICE40::SDSendCmd(_CMD25, addr);
            Assert(!status.respCRCErr());
        }
    }
    
    void writeStop() {
        _readWriteStop();
    }
    
    void writeImage(uint16_t idx) {
        constexpr uint32_t ImgSDBlockLen = CeilToBlockLen(MDC::ImgLen);
        const uint32_t addr = idx*ImgSDBlockLen;
        writeStart(addr, ImgSDBlockLen);
        
        // Clock out the image on the DAT lines
        ICE40::Transfer(ICE40::ImgReadoutMsg(0));
        
        // Wait for writing to finish
        for (;;) {
            auto status = ICE40::SDStatus();
            if (status.datOutDone()) {
                Assert(!status.datOutCRCErr());
                break;
            }
            // Busy
        }
        
        writeStop();
        
        // Wait for SD card to indicate that it's ready (DAT0=1)
        for (;;) {
            auto status = ICE40::SDStatus();
            if (status.dat0Idle()) break;
        }
    }
    
private:
    using _SDInitMsg        = ICE40::SDInitMsg;
    using _RespType         = ICE40::SDSendCmdMsg::RespType;
    using _DatInType        = ICE40::SDSendCmdMsg::DatInType;
    
    static constexpr uint8_t _CMD0  = 0;
    static constexpr uint8_t _CMD2  = 2;
    static constexpr uint8_t _CMD3  = 3;
    static constexpr uint8_t _CMD6  = 6;
    static constexpr uint8_t _CMD7  = 7;
    static constexpr uint8_t _CMD8  = 8;
    static constexpr uint8_t _CMD12 = 12;
    static constexpr uint8_t _CMD18 = 18;
    static constexpr uint8_t _CMD23 = 23;
    static constexpr uint8_t _CMD25 = 25;
    static constexpr uint8_t _CMD41 = 41;
    static constexpr uint8_t _CMD55 = 55;
    
    void _readWriteStop() {
        // ====================
        // CMD12 | STOP_TRANSMISSION
        //   State: Send Data -> Transfer
        //   Finish reading
        // ====================
        auto status = ICE40::SDSendCmd(_CMD12, 0);
        Assert(!status.respCRCErr());
    }
    
    uint16_t _rca = 0;
};

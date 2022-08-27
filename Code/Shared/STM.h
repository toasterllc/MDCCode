#pragma once
#include "Toastbox/Enum.h"
#include "Toastbox/USB.h"
#include "Util.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"

namespace STM {
    static constexpr uint32_t Version = 0;
    
    Enum(uint8_t, Endpoint, Endpoints,
        // Control endpoint
        Ctrl    = 0x00,
        // OUT endpoints (high bit 0)
        DataOut = 0x01,
        // IN endpoints (high bit 1)
        DataIn  = 0x81,
    );
    
    enum class Op : uint8_t {
        // Common command set
        None,
        EndpointsFlush,
        StatusGet,
        BootloaderInvoke,
        LEDSet,
        
        // STMLoader
        STMWrite,
        STMReset,
        
        // STMApp
        HostModeInit,
        HostModeEnter,
        
        ICERAMWrite,
        ICEFlashRead,
        ICEFlashWrite,
        
        MSPConnect,
        MSPDisconnect,
        MSPRead,
        MSPWrite,
        MSPDebug,
        
        SDCardInfo,
        SDRead,
        
        ImgInit,
        ImgExposureSet,
        ImgCapture,
    };
    
    struct [[gnu::packed]] Cmd {
        Op op;
        union {
            struct [[gnu::packed]] {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
            
            // # STMLoader
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } STMWrite;
            
            struct [[gnu::packed]] {
                uint32_t entryPointAddr;
            } STMReset;
            
            // # STMApp
            struct [[gnu::packed]] {
                uint32_t len;
            } ICERAMWrite;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } ICEFlashRead;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } ICEFlashWrite;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } MSPRead;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } MSPWrite;
            
            struct [[gnu::packed]] {
                uint32_t cmdsLen;
                uint32_t respLen;
            } MSPDebug;
            
            struct [[gnu::packed]] {
                SD::BlockIdx blockIdx;
            } SDRead;
            
            struct [[gnu::packed]] {
                uint8_t dstBlock;
                uint8_t skipCount;
            } ImgCapture;
            
            struct [[gnu::packed]] {
                uint16_t coarseIntTime;
                uint16_t fineIntTime;
                uint16_t analogGain;
            } ImgExposureSet;
        } arg;
    };
    static_assert(sizeof(Cmd)<=64, "Cmd: invalid size"); // Verify that Cmd will fit in a single EP0 packet
    
    struct [[gnu::packed]] Status {
        static constexpr uint32_t MagicNumber = 0xCAFEBABE;
        
        Enum(uint32_t, Mode, Modes,
            None,
            STMLoader,
            STMApp,
        );
        
        uint32_t magic;
        uint32_t version;
        Mode mode;
    };
    
    struct [[gnu::packed]] MSPDebugCmd {
        Enum(uint8_t, Op, Ops,
            TestSet,
            RstSet,
            TestPulse,
            SBWIO,
        );
        
        struct TestSetType {}; static constexpr auto TestSet = TestSetType();
        struct RstSetType {}; static constexpr auto RstSet = RstSetType();
        struct TestPulseType {}; static constexpr auto TestPulse = TestPulseType();
        struct SBWIOType {}; static constexpr auto SBWIO = SBWIOType();
        
        MSPDebugCmd(TestSetType, bool val) {
            opSet(Ops::TestSet);
            pinValSet(val);
        }
        
        MSPDebugCmd(RstSetType, bool val) {
            opSet(Ops::RstSet);
            pinValSet(val);
        }
        
        MSPDebugCmd(TestPulseType) {
            opSet(Ops::TestPulse);
        }
        
        MSPDebugCmd(SBWIOType, bool tms, bool tclk, bool tdi, bool tdoRead) {
            opSet(Ops::SBWIO);
            tmsSet(tms);
            tclkSet(tclk);
            tdiSet(tdi);
            tdoReadSet(tdoRead);
        }
        
        Op opGet() const            { return (data&(0x03<<0))>>0; }
        void opSet(Op x)            { data = (data&(~(0x03<<0)))|(x<<0); }
        
        bool pinValGet() const      { return (data&(0x01<<2))>>2; }
        void pinValSet(bool x)      { data = (data&(~(0x01<<2)))|(x<<2); }
        
        bool tmsGet() const         { return (data&(0x01<<2))>>2; }
        void tmsSet(bool x)         { data = (data&(~(0x01<<2)))|(x<<2); }
        
        bool tclkGet() const        { return (data&(0x01<<3))>>3; }
        void tclkSet(bool x)        { data = (data&(~(0x01<<3)))|(x<<3); }
        
        bool tdiGet() const         { return (data&(0x01<<4))>>4; }
        void tdiSet(bool x)         { data = (data&(~(0x01<<4)))|(x<<4); }
        
        bool tdoReadGet() const     { return (data&(0x01<<5))>>5; }
        void tdoReadSet(bool x)     { data = (data&(~(0x01<<5)))|(x<<5); }
        
        uint8_t data = 0;
    };
    
    struct [[gnu::packed]] SDCardInfo {
        SD::CardId cardId;
        SD::CardData cardData;
    };
    
    struct [[gnu::packed]] ImgCaptureStats {
        uint32_t len;
        uint32_t highlightCount;
        uint32_t shadowCount;
    };
    
    // Confirm that `Img::ImgPaddedLen` is a multiple of the USB max packet size.
    // This is necessary so that when multiple images are streamed, the
    // transfer continues indefinitely and isn't cut short by a short packet
    // (ie a packet < the MPS).
    static_assert((ImgSD::ImgPaddedLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk) == 0);
    
//    // ImgPaddedLen: Ceil the image size to the SD block size
//    // This is the amount of data that's sent from device -> host, for each image.
//    constexpr uint32_t ImgPaddedLen = Util::Ceil(
//        (uint32_t)Img::Len,
//        (uint32_t)SD::BlockLen
//    );
//    // Ceil the image size to the SD block size
//    constexpr uint32_t ImgCeilLen = Util::Ceil(
//        Util::Ceil(
//            (uint32_t)Img::Len,
//            (uint32_t)SD::BlockLen
//        ),
//        (uint32_t)USB::Endpoint::MaxPacketSizeBulk
//    );
}

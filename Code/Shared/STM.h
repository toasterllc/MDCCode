#pragma once
#include "Toastbox/Enum.h"
#include "Toastbox/USB.h"
#include "Util.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"
#include "MSP.h"

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
        ICERAMWrite,
        ICEFlashRead,
        ICEFlashWrite,
        
        MSPHostModeSet,
        MSPStateRead,
        MSPStateWrite,
        MSPTimeSet,
        
        MSPSBWConnect,
        MSPSBWDisconnect,
        MSPSBWRead,
        MSPSBWWrite,
        MSPSBWDebug,
        
        SDInit,
        SDRead,
        
        ImgInit,
        ImgExposureSet,
        ImgCapture,
        
        BatteryStatusGet,
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
                uint8_t en;
            } MSPHostModeSet;
            
            struct [[gnu::packed]] {
                uint32_t len;
            } MSPStateRead;
            
            struct [[gnu::packed]] {
                uint32_t len;
            } MSPStateWrite;
            
            struct [[gnu::packed]] {
                MSP::Time time;
            } MSPTimeSet;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } ICEFlashWrite;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } MSPSBWRead;
            
            struct [[gnu::packed]] {
                uint32_t addr;
                uint32_t len;
            } MSPSBWWrite;
            
            struct [[gnu::packed]] {
                uint32_t cmdsLen;
                uint32_t respLen;
            } MSPSBWDebug;
            
            struct [[gnu::packed]] {
                SD::Block block;
            } SDRead;
            
            struct [[gnu::packed]] {
                uint8_t dstRAMBlock;
                uint8_t skipCount;
                Img::Size size;
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
        
        uint32_t magic = 0;
        uint32_t version = 0;
        Mode mode = Modes::None;
    };
    
    struct [[gnu::packed]] MSPSBWDebugCmd {
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
        
        MSPSBWDebugCmd(TestSetType, bool val) {
            opSet(Ops::TestSet);
            pinValSet(val);
        }
        
        MSPSBWDebugCmd(RstSetType, bool val) {
            opSet(Ops::RstSet);
            pinValSet(val);
        }
        
        MSPSBWDebugCmd(TestPulseType) {
            opSet(Ops::TestPulse);
        }
        
        MSPSBWDebugCmd(SBWIOType, bool tms, bool tclk, bool tdi, bool tdoRead) {
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
        uint32_t len = 0;
        uint32_t highlightCount = 0;
        uint32_t shadowCount = 0;
    };
    
    // Confirm that `Img::ImagePaddedLen` is a multiple of the USB max packet size.
    // This is necessary so that when multiple images are streamed, the
    // transfer continues indefinitely and isn't cut short by a short packet
    // (ie a packet < the MPS).
    static_assert((ImgSD::Full::ImagePaddedLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk) == 0);
    static_assert((ImgSD::Thumb::ImagePaddedLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk) == 0);
    
//    // ImagePaddedLen: Ceil the image size to the SD block size
//    // This is the amount of data that's sent from device -> host, for each image.
//    constexpr uint32_t ImagePaddedLen = Util::Ceil(
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
    
    struct [[gnu::packed]] BatteryStatus {
        enum class ChargeStatus : uint8_t {
            Invalid,
            Shutdown,
            Underway,
            Complete,
        };
        
        ChargeStatus chargeStatus = ChargeStatus::Invalid;
        uint16_t voltage = 0;
    };
}

#pragma once
#include "Toastbox/Enum.h"
#include "Toastbox/USB.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"
#include "MSP.h"

namespace STM {

static constexpr uint32_t Version = 0;

struct Endpoint {
    // Control endpoint
    static constexpr uint8_t Ctrl    = 0x00;
    // OUT endpoints (high bit 0)
    static constexpr uint8_t DataOut = 0x01;
    // IN endpoints (high bit 1)
    static constexpr uint8_t DataIn  = 0x81;
};

enum class Op : uint8_t {
    // Common command set
    None,
    Reset,
    StatusGet,
    BatteryStatusGet,
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
    MSPTimeGet,
    MSPTimeSet,
    
    MSPSBWLock,
    MSPSBWUnlock,
    MSPSBWConnect,
    MSPSBWDisconnect,
    MSPSBWRead,
    MSPSBWWrite,
    MSPSBWErase,
    MSPSBWDebug,
    
    SDInit,
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
            uint8_t en;
        } MSPHostModeSet;
        
        struct [[gnu::packed]] {
            uint32_t len;
        } MSPStateRead;
        
        struct [[gnu::packed]] {
            uint32_t len;
        } MSPStateWrite;
        
        struct [[gnu::packed]] {
            Time::Instant time;
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
    
    enum class Mode : uint32_t {
        None,
        STMLoader,
        STMApp,
    };
    
    uint32_t magic = 0;
    uint32_t version = 0;
    Mode mode = Mode::None;
};

struct [[gnu::packed]] MSPSBWDebugCmd {
    enum class Op : uint8_t {
        TestSet,
        RstSet,
        TestPulse,
        SBWIO,
    };
    
    struct TestSetType {}; static constexpr auto TestSet = TestSetType();
    struct RstSetType {}; static constexpr auto RstSet = RstSetType();
    struct TestPulseType {}; static constexpr auto TestPulse = TestPulseType();
    struct SBWIOType {}; static constexpr auto SBWIO = SBWIOType();
    
    MSPSBWDebugCmd(TestSetType, bool val) {
        opSet(Op::TestSet);
        pinValSet(val);
    }
    
    MSPSBWDebugCmd(RstSetType, bool val) {
        opSet(Op::RstSet);
        pinValSet(val);
    }
    
    MSPSBWDebugCmd(TestPulseType) {
        opSet(Op::TestPulse);
    }
    
    MSPSBWDebugCmd(SBWIOType, bool tms, bool tclk, bool tdi, bool tdoRead) {
        opSet(Op::SBWIO);
        tmsSet(tms);
        tclkSet(tclk);
        tdiSet(tdi);
        tdoReadSet(tdoRead);
    }
    
    Op opGet() const            { return (Op)((data&(0x03<<0))>>0); }
    void opSet(Op x)            { data = (data&(~(0x03<<0)))|((uint8_t)x<<0); }
    
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

struct [[gnu::packed]] BatteryStatus {
    enum class ChargeStatus : uint8_t {
        Invalid,
        Shutdown,
        Underway,
        Complete,
    };
    
    ChargeStatus chargeStatus = ChargeStatus::Invalid;
    MSP::BatteryChargeLevel level = 0;
};

} // namespace STM

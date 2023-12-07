#pragma once
#include "Code/Lib/Toastbox/Enum.h"
#include "Code/Lib/Toastbox/USB.h"
#include "Code/Shared/MSP.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"

namespace STM {

using Version = uint16_t;
constexpr Version VersionInvalid = 0xFFFF;

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
    STMRAMWrite,
    STMReset,
    
    // STMApp
    STMFlashWriteInit,
    STMFlashWrite,
    
    HostModeSet,
    
    ICERAMWrite,
    ICEFlashRead,
    ICEFlashWrite,
    
    MSPStateRead,
    MSPStateWrite,
    MSPTimeGet,
    MSPTimeSet,
    MSPTimeAdjust,
    
    MSPLock,
    MSPUnlock,
    MSPSBWConnect,
    MSPSBWDisconnect,
    MSPSBWHalt,
    MSPSBWReset,
    MSPSBWRead,
    MSPSBWWrite,
    MSPSBWErase,
    MSPSBWDebugLog,
    MSPSBWDebug,
    
    SDInit,
    SDRead,
    SDErase,
    
    ImgInit,
    ImgExposureSet,
    ImgCapture,
};

struct [[gnu::packed]] Cmd {
    Op op;
    uint8_t _pad[3];
    
    union {
        struct [[gnu::packed]] {
            uint8_t idx;
            uint8_t on;
        } LEDSet;
        
        // # STMLoader
        struct [[gnu::packed]] {
            uint32_t addr;
            uint32_t len;
        } STMRAMWrite;
        
        struct [[gnu::packed]] {
            uint32_t entryPointAddr;
        } STMReset;
        
        // # STMApp
        struct [[gnu::packed]] {
            uint32_t addr;
            uint32_t len;
        } STMFlashWrite;
        
        struct [[gnu::packed]] {
            uint8_t en;
        } HostModeSet;
        
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
            uint32_t len;
        } MSPStateRead;
        
        struct [[gnu::packed]] {
            uint32_t len;
        } MSPStateWrite;
        
        struct [[gnu::packed]] {
            MSP::TimeState state;
        } MSPTimeSet;
        
        struct [[gnu::packed]] {
            MSP::TimeAdjustment adjustment;
        } MSPTimeAdjust;
        
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
            SD::Block first;
            SD::Block last;
        } SDErase;
        
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
        
        uint8_t _[60]; // Set union size
    } arg;
};
static_assert(sizeof(Cmd) == 64); // Verify that Cmd is exactly the size of a EP0 packet

struct [[gnu::packed]] Status {
    struct Header {
        uint32_t magic = 0;
        Version version = 0;
    };
    
    enum class Mode : uint32_t {
        None,
        STMLoader,
        STMApp,
    };
    
    Header header;
    MSP::Version mspVersion = 0;
    Mode mode = Mode::None;
};

constexpr Status::Header StatusHeader = {
    .magic   = 0xCAFEBABE,
    .version = 0,
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
    MSP::ChargeStatus chargeStatus = MSP::ChargeStatus::Invalid;
    MSP::BatteryLevelMv level = MSP::BatteryLevelMvInvalid;
};

} // namespace STM

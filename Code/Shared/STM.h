#pragma once
#include "Toastbox/Enum.h"
#include "Util.h"
#include "Img.h"
#include "Toastbox/USB.h"

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
        // # Common command set
        None,
        EndpointsFlush,
        StatusGet,
        BootloaderInvoke,
        LEDSet,
        
        // # STMLoader
        // STM32 Bootloader
        STMWrite,
        STMReset,
        // ICE40 Bootloader
        ICEWrite,
        // MSP430 Bootloader
        MSPConnect,
        MSPDisconnect,
        MSPRead,
        MSPWrite,
        MSPDebug,
        
        // # STMApp
        SDCardIdGet,
        SDRead,
        ImgCapture,
        ImgExposureSet,
    };
    
    struct Cmd {
        Op op;
        union {
            struct __attribute__((packed)) {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
            
            // # STMLoader
            struct __attribute__((packed)) {
                uint32_t addr;
                uint32_t len;
            } STMWrite;
            
            struct __attribute__((packed)) {
                uint32_t entryPointAddr;
            } STMReset;
            
            struct __attribute__((packed)) {
                uint32_t len;
            } ICEWrite;
            
            struct __attribute__((packed)) {
                uint32_t addr;
                uint32_t len;
            } MSPRead;
            
            struct __attribute__((packed)) {
                uint32_t addr;
                uint32_t len;
            } MSPWrite;
            
            struct __attribute__((packed)) {
                uint32_t cmdsLen;
                uint32_t respLen;
            } MSPDebug;
            
            // # STMApp
            struct __attribute__((packed)) {
                uint32_t addr;
            } SDRead;
            
            struct __attribute__((packed)) {
                uint8_t dstBlock;
                uint8_t skipCount;
            } ImgCapture;
            
            struct __attribute__((packed)) {
                uint16_t coarseIntTime;
                uint16_t fineIntTime;
                uint16_t analogGain;
            } ImgExposureSet;
        } arg;
        
    } __attribute__((packed));
    static_assert(sizeof(Cmd)<=64, "Cmd: invalid size"); // Verify that Cmd will fit in a single EP0 packet
    
    struct Status {
        static constexpr uint32_t MagicNumber = 0xCAFEBABE;
        
        Enum(uint32_t, Mode, Modes,
            None,
            STMLoader,
            STMApp,
        );
        
        uint32_t magic;
        uint32_t version;
        Mode mode;
    } __attribute__((packed));
    
    struct MSPDebugCmd {
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
    } __attribute__((packed));
    
    struct ImgCaptureStats {
        uint32_t len;
        uint32_t highlightCount;
        uint32_t shadowCount;
    } __attribute__((packed));
    
    // Confirm that `Img::PaddedLen` is a multiple of the USB max packet size.
    // This is necessary so that when multiple images are streamed, the
    // transfer continues indefinitely and isn't cut short by a short packet
    // (ie a packet < the MPS).
    static_assert((Img::PaddedLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk) == 0);
    
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

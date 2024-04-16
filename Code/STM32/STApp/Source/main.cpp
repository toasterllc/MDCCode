#include <cstdint>
#include "Code/Lib/Toastbox/Queue.h"
#include "Code/Lib/Toastbox/Math.h"
#include "Code/Shared/Assert.h"
#include "Code/Shared/ICE.h"
#include "Code/Shared/STM.h"
#include "Code/Shared/SDCard.h"
#include "Code/Shared/ImgSensor.h"
#include "Code/Shared/ImgSD.h"
#include "System.h"
#include "USB.h"
#include "QSPI.h"
#include "USBConfig.h"
using namespace STM;

static void _Reset();
static void _CmdHandle(const STM::Cmd& cmd);

struct _TaskUSBDataOut;
struct _TaskUSBDataIn;
struct _TaskReadout;

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
static void _BufQueueAssert(bool c) { Assert(c); }

struct _Buf {
    uint8_t data[63*1024];
    size_t len = 0;
};

using _BufQueue = Toastbox::Queue<_Buf, 2, false, _BufQueueAssert>;

#warning TODO: were not putting the _BufQueue code in .sram1 too are we?
[[gnu::section(".sram1")]]
static _BufQueue _Bufs;

using _ICE_CRST_                = GPIO::PortF::Pin<11, GPIO::Option::Output1>;
using _ICE_CDONE                = GPIO::PortB::Pin<1,  GPIO::Option::Input>;
using _ICE_STM_SPI_D_READY      = GPIO::PortA::Pin<3,  GPIO::Option::Input>;

namespace _GPIOConfigs {

struct QSPI {
    using ICE_STM_SPI_CS_   = GPIO::PortE::Pin<12, GPIO::Option::Output1, GPIO::Option::Speed3>;
    using ICE_STM_FLASH_EN  = GPIO::PortF::Pin<5,  GPIO::Option::Output0>;
    using ICE_STM_SPI_CLK   = GPIO::PortB::Pin<2,  GPIO::Option::Speed3, GPIO::Option::AltFn9>;
    using ICE_STM_SPI_D0    = GPIO::PortF::Pin<8,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D1    = GPIO::PortF::Pin<9,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D2    = GPIO::PortF::Pin<7,  GPIO::Option::Speed3, GPIO::Option::AltFn9>;
    using ICE_STM_SPI_D3    = GPIO::PortF::Pin<6,  GPIO::Option::Speed3, GPIO::Option::AltFn9>;
    using ICE_STM_SPI_D4    = GPIO::PortE::Pin<7,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D5    = GPIO::PortE::Pin<8,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D6    = GPIO::PortE::Pin<9,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D7    = GPIO::PortE::Pin<10, GPIO::Option::Speed3, GPIO::Option::AltFn10>;
};

struct Manual {
    using ICE_STM_SPI_CS_   = GPIO::PortE::Pin<12, GPIO::Option::Output1, GPIO::Option::Speed3>;
    using ICE_STM_FLASH_EN  = GPIO::PortF::Pin<5,  GPIO::Option::Output0>;
    using ICE_STM_SPI_CLK   = GPIO::PortB::Pin<2,  GPIO::Option::Output0>;
    using ICE_STM_SPI_D0    = GPIO::PortF::Pin<8,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D1    = GPIO::PortF::Pin<9,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D2    = GPIO::PortF::Pin<7,  GPIO::Option::Speed3, GPIO::Option::AltFn9>;
    using ICE_STM_SPI_D3    = GPIO::PortF::Pin<6,  GPIO::Option::Speed3, GPIO::Option::AltFn9>;
    using ICE_STM_SPI_D4    = GPIO::PortE::Pin<7,  GPIO::Option::Input>;
    using ICE_STM_SPI_D5    = GPIO::PortE::Pin<8,  GPIO::Option::Output0>;
    using ICE_STM_SPI_D6    = GPIO::PortE::Pin<9,  GPIO::Option::Speed3, GPIO::Option::AltFn10>;
    using ICE_STM_SPI_D7    = GPIO::PortE::Pin<10, GPIO::Option::Speed3, GPIO::Option::AltFn10>;
};

struct Floating {
    using ICE_STM_SPI_CS_   = GPIO::PortE::Pin<12, GPIO::Option::Input>;
    using ICE_STM_FLASH_EN  = GPIO::PortF::Pin<5,  GPIO::Option::Input>;
    using ICE_STM_SPI_CLK   = GPIO::PortB::Pin<2,  GPIO::Option::Input>;
    using ICE_STM_SPI_D0    = GPIO::PortF::Pin<8,  GPIO::Option::Input>;
    using ICE_STM_SPI_D1    = GPIO::PortF::Pin<9,  GPIO::Option::Input>;
    using ICE_STM_SPI_D2    = GPIO::PortF::Pin<7,  GPIO::Option::Input>;
    using ICE_STM_SPI_D3    = GPIO::PortF::Pin<6,  GPIO::Option::Input>;
    using ICE_STM_SPI_D4    = GPIO::PortE::Pin<7,  GPIO::Option::Input>;
    using ICE_STM_SPI_D5    = GPIO::PortE::Pin<8,  GPIO::Option::Input>;
    using ICE_STM_SPI_D6    = GPIO::PortE::Pin<9,  GPIO::Option::Input>;
    using ICE_STM_SPI_D7    = GPIO::PortE::Pin<10, GPIO::Option::Input>;
};

} // namespace _GPIOConfigs















using _System = System<
    STM::Status::Mode::STMApp,  // T_Mode
    true,                       // T_USBDMAEn
    _CmdHandle,                 // T_CmdHandle
    _Reset,                     // T_Reset
    
    // T_Pins
    std::tuple<
        _ICE_CRST_,
        _ICE_CDONE,
        _ICE_STM_SPI_D_READY,
        
        _GPIOConfigs::Floating::ICE_STM_SPI_CS_,
        _GPIOConfigs::Floating::ICE_STM_FLASH_EN,
        _GPIOConfigs::Floating::ICE_STM_SPI_CLK,
        _GPIOConfigs::Floating::ICE_STM_SPI_D0,
        _GPIOConfigs::Floating::ICE_STM_SPI_D1,
        _GPIOConfigs::Floating::ICE_STM_SPI_D2,
        _GPIOConfigs::Floating::ICE_STM_SPI_D3,
        _GPIOConfigs::Floating::ICE_STM_SPI_D4,
        _GPIOConfigs::Floating::ICE_STM_SPI_D5,
        _GPIOConfigs::Floating::ICE_STM_SPI_D6,
        _GPIOConfigs::Floating::ICE_STM_SPI_D7
    >,
    
    // T_Tasks
    std::tuple<
        _TaskUSBDataOut,
        _TaskUSBDataIn,
        _TaskReadout
    >
>;

using _Scheduler = _System::Scheduler;
using _USB = _System::USB;
using _MSPJTAG = _System::MSPJTAG;
using _QSPI = T_QSPI<_Scheduler>;

using _ICE = T_ICE<_Scheduler>;
using _ImgSensor = Img::Sensor<_Scheduler, _ICE>;

namespace _QSPIConfigs {

static _QSPI::Config ICEWrite = {
    .mode       = _QSPI::Mode::Single,
    .clkDivider = 5, // clkDivider: 5 -> QSPI clock = 21.3 MHz
    .align      = _QSPI::Align::Byte,
};

static _QSPI::Config ICEApp = {
    .mode       = _QSPI::Mode::Dual,
    .clkDivider = 1, // clkDivider: 1 -> QSPI clock = 64 MHz
//        .clkDivider = 31, // clkDivider: 31 -> QSPI clock = 4 MHz
//        .clkDivider = 255, // clkDivider: 255 -> QSPI clock = .5 MHz
    .align      = _QSPI::Align::Word,
};

} // namespace _QSPIConfigs

namespace _SPIConfigs {

struct Manual {
    using GPIOConfig = _GPIOConfigs::Manual;
    static constexpr _QSPI::Config* QSPIConfig = nullptr;
};

struct Floating {
    using GPIOConfig = _GPIOConfigs::Floating;
    static constexpr _QSPI::Config* QSPIConfig = nullptr;
};

struct ICEWrite {
    using GPIOConfig = _GPIOConfigs::QSPI;
    static constexpr _QSPI::Config* QSPIConfig = &_QSPIConfigs::ICEWrite;
};

struct ICEApp {
    using GPIOConfig = _GPIOConfigs::QSPI;
    static constexpr _QSPI::Config* QSPIConfig = &_QSPIConfigs::ICEApp;
};

} // namespace _SPIConfigs

using _SDCard = SD::Card<
    _Scheduler, // T_Scheduler
    _ICE,       // T_ICE
    1,          // T_ClkDelaySlow (odd values invert the clock)
    1           // T_ClkDelayFast (odd values invert the clock)
>;

class _SD {
public:
    static void Reset() {
        _SDCard::Reset();
    }
    
    static void Init() {
        _Reading = false;
        _RCA = _SDCard::Init(&_CardId, &_CardData);
    }
    
    static const SD::CardId& CardId() {
        return _CardId;
    }
    
    static const SD::CardData& CardData() {
        return _CardData;
    }
    
    static void ReadStart(SD::Block block) {
        if (_Reading) ReadStop(); // Stop current read if one is in progress
        
        _Reading = true;
        _SDCard::ReadStart(block);
    }
    
    static void ReadStop() {
        _Reading = false;
        _SDCard::ReadStop();
    }
    
    static void Erase(SD::Block blockFirst, SD::Block blockLast) {
        _SDCard::Erase(blockFirst, blockLast);
    }
    
private:
    static inline uint16_t _RCA = 0;
    
    alignas(void*) // Aligned to send via USB
    static inline SD::CardId _CardId;
    
    alignas(void*) // Aligned to send via USB
    static inline SD::CardData _CardData;
    
    static inline bool _Reading = false;
};

// MARK: - Utility Functions

static bool _VDDIMGSDSet(bool en) {
    const MSP::Cmd mspCmd = {
        .op = MSP::Cmd::Op::VDDIMGSDSet,
        .arg = {
            .VDDIMGSDSet = {
                .en = en,
            },
        },
    };
    
    const auto mspResp = _System::MSPSend(mspCmd);
    if (!mspResp || !mspResp->ok) return false;
    return true;
}

// MARK: - ICE40

namespace _QSPICmd {

static QSPI_CommandTypeDef ICEWrite(size_t len) {
    return QSPI_CommandTypeDef{
        .Instruction = 0,
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        
        .Address = 0,
        .AddressSize = QSPI_ADDRESS_8_BITS,
        .AddressMode = QSPI_ADDRESS_NONE,
        
        .AlternateBytes = 0,
        .AlternateBytesSize = QSPI_ALTERNATE_BYTES_8_BITS,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
        
        .DummyCycles = 0,
        
        .NbData = (uint32_t)len,
        .DataMode = QSPI_DATA_1_LINE,
        
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
}

static QSPI_CommandTypeDef ICEApp(const _ICE::Msg& msg, size_t respLen) {
    uint8_t b[8];
    static_assert(sizeof(msg) == sizeof(b));
    memcpy(b, &msg, sizeof(b));
    
    // When dual-flash quadspi is enabled, the supplied address is
    // divided by 2, so we left-shift `addr` in anticipation of that.
    // By doing so, we throw out the high bit of `msg`, however we
    // wrote the ICE40 Verilog to fake the first bit as 1, so verify
    // that the first bit is indeed 1.
    AssertArg(b[0] & 0x80);
    
    return QSPI_CommandTypeDef{
        // Use instruction stage to introduce 2 dummy cycles, to workaround an
        // apparent STM32 bug that always sends the first nibble as 0xF.
        .Instruction = 0x00,
        .InstructionMode = QSPI_INSTRUCTION_4_LINES,
        
        // When dual-flash quadspi is enabled, the supplied address is
        // divided by 2, so we left-shift `addr` in anticipation of that.
        .Address = (
            (uint32_t)b[0]<<24  |
            (uint32_t)b[1]<<16  |
            (uint32_t)b[2]<<8   |
            (uint32_t)b[3]<<0
        ) << 1,
//            .Address = 0,
        .AddressSize = QSPI_ADDRESS_32_BITS,
        .AddressMode = QSPI_ADDRESS_4_LINES,
        
        .AlternateBytes = (
            (uint32_t)b[4]<<24  |
            (uint32_t)b[5]<<16  |
            (uint32_t)b[6]<<8   |
            (uint32_t)b[7]<<0
        ),
//            .AlternateBytes = 0,
        .AlternateBytesSize = QSPI_ALTERNATE_BYTES_32_BITS,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_4_LINES,
        
        .DummyCycles = 4,
        
        .NbData = (uint32_t)respLen,
        .DataMode = (respLen ? QSPI_DATA_4_LINES : QSPI_DATA_NONE),
        
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
}

static QSPI_CommandTypeDef ICEAppReadOnly(size_t len) {
    return QSPI_CommandTypeDef{
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        .AddressMode = QSPI_ADDRESS_NONE,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
        .DummyCycles = 8,
        .NbData = (uint32_t)len,
        .DataMode = QSPI_DATA_4_LINES,
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
}

} // namespace _QSPICmd

template<typename T>
void _SPIConfigSet() {
_Pragma("GCC diagnostic push")
_Pragma("GCC diagnostic ignored \"-Waddress\"")
    if constexpr (T::QSPIConfig) {
        _QSPI::ConfigSet(*T::QSPIConfig);
    }
_Pragma("GCC diagnostic pop")
    
    T::GPIOConfig::ICE_STM_SPI_CS_::Init();
    T::GPIOConfig::ICE_STM_FLASH_EN::Init();
    T::GPIOConfig::ICE_STM_SPI_CLK::Init();
    T::GPIOConfig::ICE_STM_SPI_D0::Init();
    T::GPIOConfig::ICE_STM_SPI_D1::Init();
    T::GPIOConfig::ICE_STM_SPI_D2::Init();
    T::GPIOConfig::ICE_STM_SPI_D3::Init();
    T::GPIOConfig::ICE_STM_SPI_D4::Init();
    T::GPIOConfig::ICE_STM_SPI_D5::Init();
    T::GPIOConfig::ICE_STM_SPI_D6::Init();
    T::GPIOConfig::ICE_STM_SPI_D7::Init();
    
    // Reset chip-select
    T::GPIOConfig::ICE_STM_SPI_CS_::Write(1);
}

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
    if (resp) {
        _QSPI::Read(_QSPICmd::ICEApp(msg, sizeof(*resp)), resp);
    } else {
        _QSPI::Command(_QSPICmd::ICEApp(msg, 0));
    }
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
}

static void _ICEAppInit() {
    // Prepare for comms with ICEApp via QSPI
    _SPIConfigSet<_SPIConfigs::ICEApp>();
    
    bool ok = false;
    for (int i=0; i<100 && !ok; i++) {
        _Scheduler::Sleep(_Scheduler::Ms<1>);
        // Init ICE comms
        ok = _ICE::Init();
    }
    Assert(ok);
}

// MARK: - SD Card

//static bool _MSPSBWConnect(bool unlockPins) {
//    constexpr uint16_t PM5CTL0Addr  = 0x0130;
//    
//    const auto mspr = _MSPJTAG::connect();
//    if (mspr != _MSPJTAG::Status::OK) return false;
//    
//    if (unlockPins) {
//        // Clear LOCKLPM5 in the PM5CTL0 register
//        // This is necessary to be able to control the GPIOs
//        _MSPJTAG::write(PM5CTL0Addr, 0x0010);
//    }
//    
//    return true;
//}
//
//static bool _SDSetPowerEnabled(bool en) {
//    constexpr uint16_t BITB         = 1<<0xB;
//    constexpr uint16_t VDD_SD_EN    = BITB;
//    constexpr uint16_t PADIRAddr    = 0x0204;
//    constexpr uint16_t PAOUTAddr    = 0x0202;
//    
//    const bool br = _MSPSBWConnect(true);
//    if (!br) return false;
//    
//    const uint16_t PADIR = _MSPJTAG::read(PADIRAddr);
//    const uint16_t PAOUT = _MSPJTAG::read(PAOUTAddr);
//    _MSPJTAG::write(PADIRAddr, PADIR | VDD_SD_EN);
//    
//    if (en) {
//        _MSPJTAG::write(PAOUTAddr, PAOUT | VDD_SD_EN);
//    } else {
//        _MSPJTAG::write(PAOUTAddr, PAOUT & ~VDD_SD_EN);
//    }
//    
//    _MSPSBWDisconnect(false); // Don't allow MSP to run
//    
//    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
//    _Scheduler::Sleep(_Scheduler::Ms(2));
//    
//    return true;
//}

//static bool _ImgSetPowerEnabled(bool en) {
//    constexpr uint16_t BIT0             = 1<<0;
//    constexpr uint16_t BIT2             = 1<<2;
//    constexpr uint16_t VDD_1V8_IMG_EN   = BIT0;
//    constexpr uint16_t VDD_2V8_IMG_EN   = BIT2;
//    constexpr uint16_t PADIRAddr        = 0x0204;
//    constexpr uint16_t PAOUTAddr        = 0x0202;
//    
//    const bool br = _MSPSBWConnect(true);
//    if (!br) return false;
//    
//    const uint16_t PADIR = _MSPJTAG::read(PADIRAddr);
//    const uint16_t PAOUT = _MSPJTAG::read(PAOUTAddr);
//    _MSPJTAG::write(PADIRAddr, PADIR | (VDD_2V8_IMG_EN | VDD_1V8_IMG_EN));
//    
//    if (en) {
//        _MSPJTAG::write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN));
//        _Scheduler::Sleep(_Scheduler::Ms(1)); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V8)
//        _MSPJTAG::write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN|VDD_1V8_IMG_EN));
//    
//    } else {
//        // No delay between 2V8/1V8 needed for power down (per AR0330CS datasheet)
//        _MSPJTAG::write(PAOUTAddr, PAOUT & ~(VDD_2V8_IMG_EN|VDD_1V8_IMG_EN));
//    }
//    
//    _MSPSBWDisconnect(false); // Don't allow MSP to run
//    
//    #warning TODO: measure how long it takes for IMG rails to rise
//    // The TPS22919 takes 1ms for VDD_2V8_IMG VDD to reach 2.8V (empirically measured)
//    _Scheduler::Sleep(_Scheduler::Ms(2));
//    
//    return true;
//}

// MARK: - Tasks

struct _TaskUSBDataIn {
    static void Start() {
        // Make sure this task isn't already running
        Assert(!_Scheduler::Running<_TaskUSBDataIn>());
        _Scheduler::Start<_TaskUSBDataIn>(Run);
    }
    
    static void Run() {
        for (;;) {
            _Scheduler::Wait([] { return _Bufs.rok(); });
            
            // Send the data and wait until the transfer is complete
            auto& buf = _Bufs.rget();
            const bool br = _USB::Send(Endpoint::DataIn, buf.data, buf.len);
            if (!br) break;
            
            buf.len = 0;
            _Bufs.rpop();
        }
    }
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataIn")]]
    alignas(void*)
    static inline uint8_t Stack[256];
};

struct _TaskUSBDataOut {
    static void Start(size_t len) {
        // Make sure this task isn't already running
        Assert(!_Scheduler::Running<_TaskUSBDataOut>());
        _LenRem = len;
        _Scheduler::Start<_TaskUSBDataOut>(Run);
    }
    
    static void Run() {
        for (;;) {
            _Scheduler::Wait([] { return _Bufs.wok(); });
            _Buf& buf = _Bufs.wget();
            buf.len = 0;
            
            if (_LenRem) {
                // Prepare to receive either `len` bytes or the buffer capacity bytes,
                // whichever is smaller.
                const size_t cap = Toastbox::Ceil(_USB::MaxPacketSizeOut(), std::min(_LenRem, sizeof(buf.data)));
                // Ensure that after rounding up to the nearest packet size, we don't
                // exceed the buffer capacity. (This should always be safe as long as
                // the buffer capacity is a multiple of the max packet size.)
                Assert(cap <= sizeof(buf.data));
                const std::optional<size_t> recvLenOpt = _USB::Recv(Endpoint::DataOut, buf.data, cap);
                #warning TODO: handle errors somehow
                if (!recvLenOpt) break;
                
                // Never claim that we read more than the requested data, even if ceiling
                // to the max packet size caused us to read more than requested.
                const size_t recvLen = std::min(_LenRem, *recvLenOpt);
                buf.len = recvLen;
                _LenRem -= recvLen;
            }
            
            _Bufs.wpush();
            // We're done when we push an empty buffer (which signals EOF)
            if (!buf.len) break;
        }
    }
    
    static inline size_t _LenRem = 0;
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataOut")]]
    alignas(void*)
    static inline uint8_t Stack[256];
};

struct _TaskReadout {
    static void Start(std::optional<size_t> len) {
        // Make sure this task isn't already running
        Assert(!_Scheduler::Running<_TaskReadout>());
        _LenRem = len;
        _Scheduler::Start<_TaskReadout>(Run);
    }
    
    static void Run() {
        // Reset state
        _Bufs.reset();
        // Start the USB DataIn task
        _TaskUSBDataIn::Start();
        
        size_t initCount = 0;
        uint32_t initVal = 0;
        size_t bufCount = 0;
        // Read data over QSPI and write it to USB, indefinitely
        while (_LenRem.value_or(SIZE_MAX)) {
            // Wait until there's a buffer available
            _Scheduler::Wait([] { return _Bufs.wok(); });
            _Buf& buf = _Bufs.wget();
            buf.len = 0;
            
            if (initCount < 2) {
//                memset(buf.data, (int)((uint32_t)0xFFFFFFFF), sizeof(buf.data));
                memset(buf.data, (int)initVal, sizeof(buf.data));
                initCount++;
            }
            
            while (_LenRem.value_or(SIZE_MAX)) {
                const size_t lenRead = std::min(_LenRem.value_or(SIZE_MAX), _ICE::ReadoutMsg::ReadoutLen);
                const size_t lenBuf = sizeof(buf.data)-buf.len;
                // If the buffer can't fit `lenRead` more bytes, we're done with this buffer
                if (lenBuf < lenRead) break;
                buf.len += lenRead;
                if (_LenRem) *_LenRem -= lenRead;
            }
            
            // Push buffer if it has data
            if (buf.len) _Bufs.wpush();
            
            bufCount++;
            if (bufCount >= 1000) {
                initCount = 0;
                bufCount = 0;
                initVal = ~initVal;
            }
        }
        
        // Release chip-select to exit readout mode
        _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
    }
    
    static inline std::optional<size_t> _LenRem;
    
    // Task stack
    [[gnu::section(".stack._TaskReadout")]]
    alignas(void*)
    static inline uint8_t Stack[512];
};

// MARK: - Commands

static void _ICERAMWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICERAMWrite;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Enable manual control of SPI lines
    _SPIConfigSet<_SPIConfigs::Manual>();
    
    // Disable flash
    _GPIOConfigs::Manual::ICE_STM_FLASH_EN::Write(0);
    
    // Put ICE40 into configuration mode
    _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(1);
    
    // Assert chip select
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
    
    // Assert reset
    _ICE_CRST_::Write(0);
    _Scheduler::Sleep(_Scheduler::Ms<1>); // Sleep 1 ms (ideally, 200 ns)
    
    // Release reset
    _ICE_CRST_::Write(1);
    _Scheduler::Sleep(_Scheduler::Ms<2>); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Configure QSPI for writing the ICE40 configuration
    _SPIConfigSet<_SPIConfigs::ICEWrite>();
    
    // Send 8 clocks
    static const uint8_t ff = 0xff;
    _QSPI::Write(_QSPICmd::ICEWrite(sizeof(ff)), &ff);
    
    // Reset state
    _Bufs.reset();
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(arg.len);
    
    for (;;) {
        // Wait until we have data to consume
        _Scheduler::Wait([] { return _Bufs.rok(); });
        
        // Write the data over QSPI and wait for completion
        auto& buf = _Bufs.rget();
        if (!buf.len) break; // We're done when we receive an empty buffer
        
        _QSPI::Write(_QSPICmd::ICEWrite(buf.len), buf.data);
        _Bufs.rpop();
    }
    
    // Wait for CDONE to be asserted
    {
        bool ok = false;
        for (int i=0; i<10 && !ok; i++) {
            if (i) _Scheduler::Sleep(_Scheduler::Ms<1>); // Sleep 1 ms
            ok = _ICE_CDONE::Read();
        }
        
        if (!ok) {
            _System::USBSendStatus(false);
            return;
        }
    }
    
    // Finish
    {
        // Supply >=49 additional clocks (8*7=56 clocks), per the
        // "iCE40 Programming and Configuration" guide.
        // These clocks apparently reach the user application. Since this
        // appears unavoidable, prevent the clocks from affecting the user
        // application by writing 0xFF, which the user application must
        // consider as a NOP.
        constexpr uint8_t ClockCount = 7;
        static int i;
        for (i=0; i<ClockCount; i++) {
            _QSPI::Write(_QSPICmd::ICEWrite(sizeof(ff)), &ff);
        }
    }
    
    // Release chip-select now that we're done
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
    
    _System::USBSendStatus(true);
}

static void __ICEFlashIn(uint8_t* d, size_t len) {
    for (size_t i=0; i<len; i++) {
        uint8_t& b = d[i];
        for (int ii=0; ii<8; ii++) {
            _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(1);
            
            b <<= 1;
            b |= _GPIOConfigs::Manual::ICE_STM_SPI_D4::Read();
            
            _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(0);
        }
    }
}

static void __ICEFlashOut(const uint8_t* d, size_t len) {
    for (size_t i=0; i<len; i++) {
        uint8_t b = d[i];
        for (int ii=0; ii<8; ii++) {
            _GPIOConfigs::Manual::ICE_STM_SPI_D5::Write(b & 0x80);
            b <<= 1;
            
            _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(1);
            _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(0);
        }
    }
}

//static uint8_t _ICEFlashIn() {
//    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
//    uint8_t d = 0;
//    __ICEFlashIn(&d, 1);
//    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
//    return d;
//}

static void _ICEFlashOut(uint8_t out) {
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
    __ICEFlashOut(&out, 1);
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
}

static uint8_t _ICEFlashOutIn(uint8_t out) {
    uint8_t in = 0;
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
    __ICEFlashOut(&out, 1);
    __ICEFlashIn(&in, 1);
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
    return in;
}

static void _ICEFlashWait() {
    // Wait until erase is complete
    for (;;) {
        const uint8_t sr1 = _ICEFlashOutIn(0x05);
        const bool busy = (sr1 & 1);
        if (!busy) break;
    }
}

//static void __ICEFlashWriteWrite(uint8_t w, const uint8_t* d, size_t len) {
//    for (int i=0; i<8; i++) {
//        _ICE_STM_SPI_D4::Write(w & 0x80);
//        w <<= 1;
//        
//        _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(1);
//        _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(0);
//    }
//}
//
//static void _ICEFlashCmd(const uint8_t* instr, size_t instrLen, const uint8_t* data=nullptr, size_t dataLen=0) {
//    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
//    __ICEFlashCmd(instr, instrLen);
//    if (data) __ICEFlashCmd(data, dataLen);
//    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
//}
//
//static void _ICEFlashCmd(uint8_t w, const uint8_t* d=nullptr, size_t len=0) {
//    _ICEFlashCmd(&w, 1, d, len);
//}
//
//static uint8_t _ICEFlashCmd(uint8_t w) {
//    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
//    __ICEFlashCmd(&w, 1);
//    const uint8_t r = __ICEFlashWriteRead();
//    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
//    return r;
//}

static void _ICEFlashRead(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICEFlashRead;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Enable manual control of SPI lines
    _SPIConfigSet<_SPIConfigs::Manual>();
    
    // Hold ICE40 in reset while we read from flash
    _ICE_CRST_::Write(0);
    
    // Set default clock state before enabling flash
    _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(0);
    
    // De-assert chip select before enabling flash
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
    
    // Enable flash
    _GPIOConfigs::Manual::ICE_STM_FLASH_EN::Write(1);
    
    // Reset flash
    _ICEFlashOut(0x66);
    _ICEFlashOut(0x99);
    _Scheduler::Sleep(_Scheduler::Us<32>); // "the device will take approximately tRST=30us to reset"
    
    // Reset state
    _Bufs.reset();
    
    // Start the USB DataIn task
    _TaskUSBDataIn::Start();
    
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
    
    // Start flash read
    {
        const uint8_t instr[] = {
            0x03,
            (uint8_t)((arg.addr&0xFF0000)>>16),
            (uint8_t)((arg.addr&0x00FF00)>>8),
            (uint8_t)((arg.addr&0x0000FF)>>0),
        };
        
        __ICEFlashOut(instr, sizeof(instr));
    }
    
    uint32_t addr = arg.addr;
    uint32_t len = arg.len;
    while (len) {
        _Scheduler::Wait([] { return _Bufs.wok(); });
        _Buf& buf = _Bufs.wget();
        // Prepare to receive either `len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        buf.len = std::min((size_t)len, sizeof(buf.data));
        __ICEFlashIn(buf.data, buf.len);
        addr += buf.len;
        len -= buf.len;
        // Enqueue the buffer
        _Bufs.wpush();
    }
    
    // Wait for DataIn task to complete
    _Scheduler::Wait([] { return !_Bufs.rok(); });
    
    // Disable flash
    _GPIOConfigs::Manual::ICE_STM_FLASH_EN::Write(0);
    
    // Revert to default QSPI config
    _SPIConfigSet<_SPIConfigs::ICEApp>();
    
    // Take ICE40 out of reset
    _ICE_CRST_::Write(1);
    
    // Send status
    _System::USBSendStatus(true);
}

static void _ICEFlashWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICEFlashWrite;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Enable manual control of SPI lines
    _SPIConfigSet<_SPIConfigs::Manual>();
    
    // Hold ICE40 in reset while we write to flash
    _ICE_CRST_::Write(0);
    
    // Set default clock state before enabling flash
    _GPIOConfigs::Manual::ICE_STM_SPI_CLK::Write(0);
    
    // De-assert chip select before enabling flash
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
    
    // Enable flash
    _GPIOConfigs::Manual::ICE_STM_FLASH_EN::Write(1);
    
    // Reset flash
    _ICEFlashOut(0x66);
    _ICEFlashOut(0x99);
    _Scheduler::Sleep(_Scheduler::Us<32>); // "the device will take approximately tRST=30us to reset"
    
    // Write enable
    _ICEFlashOut(0x06);
    // Mass erase
    _ICEFlashOut(0xC7);
    // Wait until erase is complete
    _ICEFlashWait();
    
    // Reset state
    _Bufs.reset();
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(arg.len);
    
    constexpr size_t FlashPageSize = 256;
    uint32_t addr = 0;
    for (;;) {
        // Wait until we have data to consume, and QSPI is ready to write
        _Scheduler::Wait([] { return _Bufs.rok(); });
        
        // Write the data over SPI and wait for completion
        auto& buf = _Bufs.rget();
        if (buf.len) {
            // We only allow writing to addresses that are page-aligned.
            // If we receive some data over USB that isn't a multiple of the flash's page size,
            // then this check will fail. So data sent over USB must be a multiple of the flash
            // page size, excepting the final/remainder piece of data if the entire data isn't
            // a multiple of the flash's page size.
            if (addr & (FlashPageSize-1)) {
                _System::USBSendStatus(false);
                return;
            }
            
            size_t chunkOff = 0;
            for (;;) {
                const size_t chunkLen = std::min(FlashPageSize, buf.len-chunkOff);
                if (!chunkLen) break;
                
                // Write enable
                _ICEFlashOut(0x06);
                
                // Page program
                {
                    const uint8_t instr[] = {
                        0x02,
                        (uint8_t)((addr&0xFF0000)>>16),
                        (uint8_t)((addr&0x00FF00)>>8),
                        (uint8_t)((addr&0x0000FF)>>0),
                    };
                    
                    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(0);
                    __ICEFlashOut(instr, sizeof(instr));
                    __ICEFlashOut(buf.data+chunkOff, chunkLen);
                    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
                }
                
                // Wait until write is complete
                _ICEFlashWait();
                
                chunkOff += chunkLen;
                addr += chunkLen;
            }
        }
        
        _Bufs.rpop();
        if (!buf.len) break; // We're done when we receive an empty buffer
    }
    
    // Disable flash
    _GPIOConfigs::Manual::ICE_STM_FLASH_EN::Write(0);
    
    // Revert to default QSPI config
    _SPIConfigSet<_SPIConfigs::ICEApp>();
    
    // Take ICE40 out of reset
    _ICE_CRST_::Write(1);
    
    // Send status
    _System::USBSendStatus(true);
}

static bool __STMFlashWrite_ErasedSectors[4];

static void _STMFlashWriteInit(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    for (bool& x : __STMFlashWrite_ErasedSectors) {
        x = false;
    }
    
    _System::USBSendStatus(true);
}

static size_t __STMFlashWrite_WritableAddress(uint32_t addr) {
    // ITCM addresses: convert to AXIM address, which support writing (ITCM flash addresses are read-only)
    if (addr>=0x00200000 && addr<0x210000) {
        return (addr-0x00200000) + 0x08000000;
    
    // AXIM addresses: return as-is
    } else if (addr>=0x08000000 && addr<0x08010000) {
        return addr;
    
    // Anything else: invalid address
    } else {
        Assert(false);
    }
}

static uint8_t __STMFlashWrite_SectorForAddress(uint32_t addr) {
    if (addr < 0x08000000) {
        Assert(false);
    } else if (addr < 0x08004000) {
        return 0;
    } else if (addr < 0x08008000) {
        return 1;
    } else if (addr < 0x0800C000) {
        return 2;
    } else if (addr < 0x08010000) {
        return 3;
    } else {
        Assert(false);
    }
}

static bool __STMFlashWrite_EraseSectorIfNeeded(uint8_t sector) {
    if (__STMFlashWrite_ErasedSectors[sector]) {
        return true;
    }
    
    FLASH_EraseInitTypeDef info = {
        .TypeErase      = FLASH_TYPEERASE_SECTORS,
        .Sector         = sector,
        .NbSectors      = 1,
        .VoltageRange   = FLASH_VOLTAGE_RANGE_1, // 1.8 V
    };
    uint32_t junk = 0;
    
    HAL_StatusTypeDef hs = HAL_FLASHEx_Erase(&info, &junk);
    if (hs != HAL_OK) return false;
    
    __STMFlashWrite_ErasedSectors[sector] = true;
    return true;
}

static void _STMFlashWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.STMFlashWrite;
    
    // Require at least 1 byte to be written
    if (!arg.len) {
        // Reject command
        _System::USBAcceptCommand(false);
        return;
    }
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    // Clear any pending errors
    FLASH_WaitForLastOperation(0);
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(arg.len);
    
    HAL_FLASH_Unlock();
    
    uint32_t addr = __STMFlashWrite_WritableAddress(arg.addr);
    
    bool ok = true;
    
    // Erase affected sectors
    const uint32_t addrLast = __STMFlashWrite_WritableAddress(arg.addr + arg.len - 1);
    for (uint8_t sector=__STMFlashWrite_SectorForAddress(addr); sector<=__STMFlashWrite_SectorForAddress(addrLast); sector++) {
        bool erased = __STMFlashWrite_EraseSectorIfNeeded(sector);
        if (!erased) ok = false;
    }
    
    for (;;) {
        // Wait for a buffer containing more data to write
        _Scheduler::Wait([] { return _Bufs.rok(); });
        auto& buf = _Bufs.rget();
        if (!buf.len) break; // We're done when we receive an empty buffer
        
        // Program each byte individually
        for (size_t i=0; i<buf.len; i++, addr++) {
            HAL_StatusTypeDef hs = HAL_FLASH_Program(FLASH_TYPEPROGRAM_BYTE, addr, buf.data[i]);
            if (hs != HAL_OK) ok = false;
        }
        
        _Bufs.rpop();
    }
    
    HAL_FLASH_Lock();
    
    // Send status
    _System::USBSendStatus(ok);
}

static void _HostModeSet(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.HostModeSet;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // If we're exiting host mode, reset ICE40 since it may have been reprogrammed while in host mode
    if (!arg.en) {
        _SPIConfigSet<_SPIConfigs::Floating>();
        _ICE_CRST_::Write(0);
        _Scheduler::Sleep(_Scheduler::Ms<1>);
        _ICE_CRST_::Write(1);
        _Scheduler::Sleep(_Scheduler::Ms<30>);
    }
    
    const MSP::Cmd mspCmd = {
        .op = MSP::Cmd::Op::HostModeSet,
        .arg = { .HostModeSet = { .en = arg.en } },
    };
    
    const auto mspResp = _System::MSPSend(mspCmd);
    if (!mspResp || !mspResp->ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
}

static bool __MSPStateRead(size_t off, uint8_t* data, size_t len) {
    constexpr size_t ChunkSize = sizeof(MSP::Resp::arg.StateRead.data);
    while (len) {
        const size_t l = std::min(len, ChunkSize);
        const MSP::Cmd mspCmd = {
            .op = MSP::Cmd::Op::StateRead,
            .arg = { .StateRead = { .off = (uint16_t)off } },
        };
        const auto mspResp = _System::MSPSend(mspCmd);
        if (!mspResp || !mspResp->ok) return false;
        memcpy(data, mspResp->arg.StateRead.data, l);
        off += l;
        data += l;
        len -= l;
    }
    return true;
}

static bool __MSPStateWrite(size_t off, const uint8_t* data, size_t len) {
    constexpr size_t ChunkSize = sizeof(MSP::Cmd::arg.StateWrite.data);
    while (len) {
        const size_t l = std::min(len, ChunkSize);
        MSP::Cmd mspCmd = {
            .op = MSP::Cmd::Op::StateWrite,
            .arg = { .StateWrite = { .off = (uint16_t)off } },
        };
        memcpy(mspCmd.arg.StateWrite.data, data, l);
        const auto mspResp = _System::MSPSend(mspCmd);
        if (!mspResp || !mspResp->ok) return false;
        off += l;
        data += l;
        len -= l;
    }
    return true;
}

//static size_t __MSPStateRead(uint8_t* data, size_t cap) {
//    MSP::State::Header header;
//    if (cap < sizeof(header)) return 0;
//    
//    size_t off = 0;
//    bool ok = __MSPStateRead(off, (uint8_t*)&header, sizeof(header));
//    if (!ok) return 0;
//    
//    // Copy header into destination buffer
//    memcpy(data+off, (uint8_t*)&header, sizeof(header));
//    off += sizeof(header);
//    
//    // Validate that the caller has enough space to hold the header + payload
//    if (cap < sizeof(header) + header.length) return 0;
//    // Read payload directly into destination buffer
//    ok = __MSPStateRead(off, data+off, header.length);
//    if (!ok) return 0;
//    off += header.length;
//    return off;
//}

static void _MSPStateRead(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPStateRead;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    // Start the USB DataIn task
    _TaskUSBDataIn::Start();
    
    size_t off = 0;
    size_t len = arg.len;
    bool ok = true;
    while (len) {
        // Wait for an available buffer to write into
        _Scheduler::Wait([] { return _Bufs.wok(); });
        _Buf& buf = _Bufs.wget();
        buf.len = std::min(len, sizeof(buf.data));
        
        // Read state into the buffer
        ok &= __MSPStateRead(off, buf.data, buf.len);
        
        // Enqueue the buffer
        _Bufs.wpush();
        len -= buf.len;
        off += buf.len;
    }
    
    // Wait for DataIn task to complete
    _Scheduler::Wait([] { return !_Bufs.rok(); });
    // Send status
    _System::USBSendStatus(ok);
}

static void _MSPStateWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPStateWrite;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(arg.len);
    
    size_t off = 0;
    for (;;) {
        // Wait for a buffer containing more data to write
        _Scheduler::Wait([] { return _Bufs.rok(); });
        auto& buf = _Bufs.rget();
        if (!buf.len) break; // We're done when we receive an empty buffer
        
        // Write the data over Spy-bi-wire
        __MSPStateWrite(off, buf.data, buf.len);
        off += buf.len;
        _Bufs.rpop();
    }
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPTimeGet(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    const MSP::Cmd mspCmd = { .op = MSP::Cmd::Op::TimeGet };
    const auto mspResp = _System::MSPSend(mspCmd);
    if (!mspResp || !mspResp->ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
    
    // Send time
    alignas(void*) // Aligned to send via USB
    const MSP::TimeState state = mspResp->arg.TimeGet.state;
    _USB::Send(Endpoint::DataIn, &state, sizeof(state));
}

static void _MSPTimeInit(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPTimeInit;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    const MSP::Cmd mspCmd = {
        .op = MSP::Cmd::Op::TimeInit,
        .arg = { .TimeInit = { .state = arg.state } },
    };
    
    const auto mspResp = _System::MSPSend(mspCmd);
    if (!mspResp || !mspResp->ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPTimeAdjust(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPTimeAdjust;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    const MSP::Cmd mspCmd = {
        .op = MSP::Cmd::Op::TimeAdjust,
        .arg = { .TimeAdjust = { .adjustment = arg.adjustment } },
    };
    
    const auto mspResp = _System::MSPSend(mspCmd);
    if (!mspResp || !mspResp->ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
}

// _MSPLock: ensures mutual exclusion between MSP I2C comms (via System::_TaskMSPComms) and MSP Spy-bi-wire IO
static _System::MSPLock __MSPLock;

static void _MSPSBWReset() {
    _MSPJTAG::Disconnect();
    // Relinquish the lock if it was held (no-op otherwise)
    __MSPLock = {};
}

static void _MSPLock(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Acquire mutex to block MSP I2C comms until our SBW IO is done (and _MSPSBWDisconnect() is called)
    __MSPLock.lock();
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPUnlock(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    __MSPLock.unlock();
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWConnect(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    const auto mspr = _MSPJTAG::Connect();
    
    // Send status
    _System::USBSendStatus(mspr == _MSPJTAG::Status::OK);
}

static void _MSPSBWDisconnect(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    _MSPJTAG::Disconnect();
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWHalt(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    const auto mspr = _MSPJTAG::Halt();
    
    // Send status
    _System::USBSendStatus(mspr == _MSPJTAG::Status::OK);
}

static void _MSPSBWReset(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    _MSPJTAG::Reset();
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWRead(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPSBWRead;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    // Start the USB DataIn task
    _TaskUSBDataIn::Start();
    
    uint32_t addr = arg.addr;
    uint32_t len = arg.len;
    while (len) {
        _Scheduler::Wait([] { return _Bufs.wok(); });
        _Buf& buf = _Bufs.wget();
        // Prepare to receive either `len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        buf.len = std::min((size_t)len, sizeof(buf.data));
        _MSPJTAG::Read(addr, buf.data, buf.len);
        addr += buf.len;
        len -= buf.len;
        // Enqueue the buffer
        _Bufs.wpush();
    }
    
    // Wait for DataIn task to complete
    _Scheduler::Wait([] { return !_Bufs.rok(); });
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPSBWWrite;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(arg.len);
    
    uint32_t addr = arg.addr;
    for (;;) {
        _Scheduler::Wait([] { return _Bufs.rok(); });
        
        // Write the data over Spy-bi-wire
        auto& buf = _Bufs.rget();
        if (!buf.len) break; // We're done when we receive an empty buffer
        
        _MSPJTAG::Write(addr, buf.data, buf.len);
        addr += buf.len; // Update the MSP430 address to write to
        _Bufs.rpop();
    }
    
    _System::USBSendStatus(true);
}

static void _MSPSBWErase(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    const auto mspr = _MSPJTAG::Erase();
    
    _System::USBSendStatus(mspr == _MSPJTAG::Status::OK);
}

static void _MSPSBWDebugLog(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    // Start the USB DataIn task
    _TaskUSBDataIn::Start();
    
    for (;;) {
        _Scheduler::Wait([] { return _Bufs.wok(); });
        _Buf& buf = _Bufs.wget();
        buf.len = 0;
        
        for (int i=0; i<64; i++) {
            const auto jmb = _MSPJTAG::JMBRead();
            if (!jmb) {
                _Scheduler::Sleep(_Scheduler::Ms<1>);
                continue;
            }
            
            memcpy(buf.data+buf.len, &*jmb, sizeof(*jmb));
            buf.len += sizeof(*jmb);
        }
        
        // Enqueue the buffer if it has data
        if (buf.len) _Bufs.wpush();
    }
}

struct _MSPSBWDebugState {
    uint8_t bits = 0;
    uint8_t bitsLen = 0;
    size_t len = 0;
    bool ok = true;
};

static void _MSPSBWDebugPushReadBits(_MSPSBWDebugState& state, _Buf& buf) {
    if (state.len >= sizeof(buf.data)) {
        state.ok = false;
        return;
    }
    
    // Enqueue the new byte into `buf`
    buf.data[state.len] = state.bits;
    state.len++;
    // Reset our bits
    state.bits = 0;
    state.bitsLen = 0;
}

static void _MSPSBWDebugHandleSBWIO(const MSPSBWDebugCmd& cmd, _MSPSBWDebugState& state, _Buf& buf) {
    const bool tdo = _MSPJTAG::DebugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
    if (cmd.tdoReadGet()) {
        // Enqueue a new bit
        state.bits <<= 1;
        state.bits |= tdo;
        state.bitsLen++;
        
        // Enqueue the byte if it's filled
        if (state.bitsLen == 8) {
            _MSPSBWDebugPushReadBits(state, buf);
        }
    }
}

static void _MSPSBWDebugHandleCmd(const MSPSBWDebugCmd& cmd, _MSPSBWDebugState& state, _Buf& buf) {
    switch (cmd.opGet()) {
    case MSPSBWDebugCmd::Op::TestSet:       _MSPJTAG::DebugTestSet(cmd.pinValGet());    break;
    case MSPSBWDebugCmd::Op::RstSet:        _MSPJTAG::DebugRstSet(cmd.pinValGet());     break;
    case MSPSBWDebugCmd::Op::TestPulse:     _MSPJTAG::DebugTestPulse();                 break;
    case MSPSBWDebugCmd::Op::SBWIO:         _MSPSBWDebugHandleSBWIO(cmd, state, buf);	break;
    default:                                Assert(false);
    }
}

static void _MSPSBWDebug(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPSBWDebug;
    
    // Bail if more data was requested than the size of our buffer
    if (arg.respLen > sizeof(_Buf::data)) {
        // Reject command
        _System::USBAcceptCommand(false);
        return;
    }
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    _Buf& bufIn = _Bufs.wget();
    _Bufs.wpush();
    _Buf& bufOut = _Bufs.wget();
    
    _MSPSBWDebugState state;
    
    // Handle debug commands
    {
        size_t cmdsLenRem = arg.cmdsLen;
        while (cmdsLenRem) {
            // Receive debug commands into buf
            const std::optional<size_t> recvLenOpt = _USB::Recv(Endpoint::DataOut, bufIn.data, sizeof(bufIn.data));
            if (!recvLenOpt) return;
            
            const size_t cmdsLen = *recvLenOpt / sizeof(MSPSBWDebugCmd);
            
            // Handle each MSPSBWDebugCmd
            const MSPSBWDebugCmd* cmds = (MSPSBWDebugCmd*)bufIn.data;
            for (size_t i=0; i<cmdsLen && state.ok; i++) {
                _MSPSBWDebugHandleCmd(cmds[i], state, bufOut);
            }
            
            cmdsLenRem -= cmdsLen;
        }
    }
    
    // Reply with data generated from debug commands
    {
        // Push outstanding bits into the buffer
        // This is necessary for when the client reads a number of bits
        // that didn't fall on a byte boundary.
        if (state.bitsLen) _MSPSBWDebugPushReadBits(state, bufOut);
        
        if (arg.respLen) {
            // Send the data and wait for it to be received
            const bool br = _USB::Send(Endpoint::DataIn, bufOut.data, arg.respLen);
            if (!br) return;
        }
    }
    
    // Send status
    _System::USBSendStatus(state.ok);
}

void _SDInit(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Prepare for comms with ICEApp via QSPI
    _ICEAppInit();
    
    // Disable SD power
    bool ok = _VDDIMGSDSet(false);
    if (!ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Reset SD before turning power on
    // This is necessary to put the SD nets in a predefined state before applying power to SD
    _SD::Reset();
    
    // Enable SD power
    ok = _VDDIMGSDSet(true);
    if (!ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Init SD card now that its power has been cycled
    _SD::Init();
    
    // Send status
    _System::USBSendStatus(true);
    
    // Send SD card info
    alignas(void*) // Aligned to send via USB
    const SDCardInfo cardInfo = {
        .cardId = _SD::CardId(),
        .cardData = _SD::CardData(),
    };
    
    _USB::Send(Endpoint::DataIn, &cardInfo, sizeof(cardInfo));
}

static void _SDRead(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.SDRead;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset chip select in case a read was in progress
    _GPIOConfigs::Manual::ICE_STM_SPI_CS_::Write(1);
    
    _SD::ReadStart(arg.block);
    
    // Send status
    _System::USBSendStatus(true);
    
    // Start the Readout task
    _TaskReadout::Start(std::nullopt);
}

static void _SDErase(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.SDErase;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Perform the erase
    _SD::Erase(arg.first, arg.last);
    
    // Send status
    _System::USBSendStatus(true);
}

void _ImgInit(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Prepare for comms with ICEApp via QSPI
    _ICEAppInit();
    
    // Enable IMG power rails
    const bool ok = _VDDIMGSDSet(true);
    if (!ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    _ImgSensor::Init();
    _ImgSensor::SetStreamEnabled(true);
    
    // Send status
    _System::USBSendStatus(true);
}

void _ImgExposureSet(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.ImgExposureSet;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    _ImgSensor::SetCoarseIntTime(arg.coarseIntTime);
    _ImgSensor::SetFineIntTime(arg.fineIntTime);
    _ImgSensor::SetAnalogGain(arg.analogGain);
    
    // Send status
    _System::USBSendStatus(true);
}

void _ImgCapture(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.ImgCapture;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    const uint16_t imageWidth       = (arg.size==Img::Size::Full ? Img::Full::PixelWidth         : Img::Thumb::PixelWidth       );
    const uint16_t imageHeight      = (arg.size==Img::Size::Full ? Img::Full::PixelHeight        : Img::Thumb::PixelHeight      );
    const uint32_t imagePaddedLen   = (arg.size==Img::Size::Full ? ImgSD::Full::ImagePaddedLen   : ImgSD::Thumb::ImagePaddedLen   );
    const Img::Header header = {
        .magic          = Img::Header::MagicNumber,
        .version        = Img::Header::Version,
        .imageWidth     = imageWidth,
        .imageHeight    = imageHeight,
    };
    
    const _ICE::ImgCaptureStatusResp resp = _ICE::ImgCapture(header, arg.dstRAMBlock, arg.skipCount);
    
    alignas(void*) // Aligned to send via USB
    const ImgCaptureStats stats = {
        .len            = imagePaddedLen,
        .highlightCount = resp.highlightCount(),
        .shadowCount    = resp.shadowCount(),
    };
    
    // Send ImgCaptureStats
    const bool br = _USB::Send(Endpoint::DataIn, &stats, sizeof(stats));
    if (!br) return;
    
    // Arrange for the image to be read out
    _ICE::Transfer(_ICE::ImgReadoutMsg(arg.dstRAMBlock, arg.size));
    
    // Send status
    _System::USBSendStatus(true);
    
    // Start the Readout task
    _TaskReadout::Start(imagePaddedLen);
}

static void _TasksReset() {
    _Scheduler::Stop<_TaskUSBDataOut>();
    _Scheduler::Stop<_TaskUSBDataIn>();
    _Scheduler::Stop<_TaskReadout>();
}

static void _Reset() {
    _TasksReset();
    _MSPSBWReset();
    _SPIConfigSet<_SPIConfigs::ICEApp>();
}

static void _CmdHandle(const STM::Cmd& cmd) {
    _TasksReset();
    
    switch (cmd.op) {
    // Flashing
    case Op::STMFlashWriteInit:     _STMFlashWriteInit(cmd);            break;
    case Op::STMFlashWrite:         _STMFlashWrite(cmd);                break;
    // Host mode
    case Op::HostModeSet:           _HostModeSet(cmd);                  break;
    // ICE40 Bootloader
    case Op::ICERAMWrite:           _ICERAMWrite(cmd);                  break;
    case Op::ICEFlashRead:          _ICEFlashRead(cmd);                 break;
    case Op::ICEFlashWrite:         _ICEFlashWrite(cmd);                break;
    // MSP430
    case Op::MSPStateRead:          _MSPStateRead(cmd);                 break;
    case Op::MSPStateWrite:         _MSPStateWrite(cmd);                break;
    case Op::MSPTimeGet:            _MSPTimeGet(cmd);                   break;
    case Op::MSPTimeInit:           _MSPTimeInit(cmd);                  break;
    case Op::MSPTimeAdjust:         _MSPTimeAdjust(cmd);                break;
    // MSP430 SBW
    case Op::MSPLock:               _MSPLock(cmd);                      break;
    case Op::MSPUnlock:             _MSPUnlock(cmd);                    break;
    case Op::MSPSBWConnect:         _MSPSBWConnect(cmd);                break;
    case Op::MSPSBWDisconnect:      _MSPSBWDisconnect(cmd);             break;
    case Op::MSPSBWHalt:            _MSPSBWHalt(cmd);                   break;
    case Op::MSPSBWReset:           _MSPSBWReset(cmd);                  break;
    case Op::MSPSBWRead:            _MSPSBWRead(cmd);                   break;
    case Op::MSPSBWWrite:           _MSPSBWWrite(cmd);                  break;
    case Op::MSPSBWErase:           _MSPSBWErase(cmd);                  break;
    case Op::MSPSBWDebug:           _MSPSBWDebug(cmd);                  break;
    case Op::MSPSBWDebugLog:        _MSPSBWDebugLog(cmd);               break;
    // SD Card
    case Op::SDInit:                _SDInit(cmd);                       break;
    case Op::SDRead:                _SDRead(cmd);                       break;
    case Op::SDErase:               _SDErase(cmd);                      break;
    // Img
    case Op::ImgInit:               _ImgInit(cmd);                      break;
    case Op::ImgExposureSet:        _ImgExposureSet(cmd);               break;
    case Op::ImgCapture:            _ImgCapture(cmd);                   break;
    // Bad command
    default:                        _System::USBAcceptCommand(false);   break;
    }
}

// MARK: - ISRs

extern "C" [[gnu::section(".isr")]] void ISR_SysTick() {
    _Scheduler::Tick();
    HAL_IncTick();
}

extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS() {
    _USB::ISR();
}

extern "C" [[gnu::section(".isr")]] void ISR_QUADSPI() {
    _QSPI::ISR_QSPI();
}

extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream7() {
    _QSPI::ISR_DMA();
}

extern "C" [[gnu::section(".isr")]] void ISR_I2C1_EV() {
    _System::ISR_I2CEvent();
}

extern "C" [[gnu::section(".isr")]] void ISR_I2C1_ER() {
    _System::ISR_I2CError();
}

// MARK: - Abort

extern "C"
[[noreturn]]
void Abort(uintptr_t addr) {
    _System::Abort();
}

// MARK: - Main
int main() {
    _Scheduler::Run();
    return 0;
}


//#warning TODO: remove these debug symbols
//#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section
//constexpr auto& _Debug_Tasks              = _Scheduler::_Tasks;
//constexpr auto& _Debug_DidWork            = _Scheduler::_DidWork;
//constexpr auto& _Debug_CurrentTask        = _Scheduler::_CurrentTask;
//constexpr auto& _Debug_CurrentTime        = _Scheduler::_ISR.CurrentTime;
//constexpr auto& _Debug_Wake               = _Scheduler::_ISR.Wake;
//constexpr auto& _Debug_WakeTime           = _Scheduler::_ISR.WakeTime;

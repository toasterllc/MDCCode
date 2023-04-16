#define SchedulerARM32
#include "Toastbox/Scheduler.h"
#include "Toastbox/Queue.h"
#include "Toastbox/Math.h"
#include "Assert.h"
#include "System.h"
#include "ICE.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "SDCard.h"
#include "ImgSensor.h"
#include "ImgSD.h"
#include "USBConfig.h"
using namespace STM;

static void _Reset();
static void _CmdHandle(const STM::Cmd& cmd);

struct _TaskUSBDataOut;
struct _TaskUSBDataIn;
struct _TaskReadout;

using _System = System<
    STM::Status::Mode::STMApp,  // T_Mode
    true,                       // T_USBDMAEn
    _CmdHandle,                 // T_CmdHandle
    _Reset,                     // T_Reset
    
    // T_Tasks
    _TaskUSBDataOut,
    _TaskUSBDataIn,
    _TaskReadout
>;

using _Scheduler = _System::Scheduler;
using _USB = _System::USB;
using _MSPJTAG = _System::MSPJTAG;

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

using _QSPI = QSPIType<_Scheduler>;

using _ICE_CRST_          = GPIO::PortF::Pin<11, GPIO::Option::Output1>;
using _ICE_CDONE          = GPIO::PortB::Pin<1,  GPIO::Option::Input>;
using _ICE_ST_SPI_CS_     = GPIO::PortE::Pin<12, GPIO::Option::Output1, GPIO::Option::Speed3>;
using _ICE_ST_SPI_D_READY = GPIO::PortA::Pin<3,  GPIO::Option::Input>;
using _ICE_ST_FLASH_EN    = GPIO::PortF::Pin<5,  GPIO::Option::Output0>;

using _ICE_ST_SPI_CLK     = _QSPI::Pin::Clk::Opts<GPIO::Option::Output0>;
using _ICE_ST_SPI_D4      = _QSPI::Pin::D4::Opts<GPIO::Option::Input>;
using _ICE_ST_SPI_D5      = _QSPI::Pin::D5::Opts<GPIO::Option::Output0>;

[[noreturn]] static void _ICEError(uint16_t line);
using _ICE = ::ICE<_Scheduler, _ICEError>;

[[noreturn]] static void _ImgError(uint16_t line);
using _ImgSensor = Img::Sensor<
    _Scheduler, // T_Scheduler
    _ICE,       // T_ICE
    _ImgError   // T_Error
>;

[[noreturn]] static void _SDError(uint16_t line);
using _SDCard = SD::Card<
    _Scheduler, // T_Scheduler
    _ICE,       // T_ICE
    _SDError,   // T_Error
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
    
    static void ReadStart(uint32_t blockIdx) {
        if (_Reading) ReadStop(); // Stop current read if one is in progress
        
        _Reading = true;
        _SDCard::ReadStart(blockIdx);
    }
    
    static void ReadStop() {
        _Reading = false;
        _SDCard::ReadStop();
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

void _QSPIConfigSet(const _QSPI::Config* config) {
    // QSPI mode
    if (config) {
        _QSPI::ConfigSet(*config);
        
        _QSPI::Pin::Clk::Init<_ICE_ST_SPI_CLK>();
        _QSPI::Pin::D4::Init<_ICE_ST_SPI_D4>();
        _QSPI::Pin::D5::Init<_ICE_ST_SPI_D5>();
    
    // Manual mode
    } else {
        _ICE_ST_SPI_CLK::Init<_QSPI::Pin::Clk>();
        _ICE_ST_SPI_D4::Init<_QSPI::Pin::D4>();
        _ICE_ST_SPI_D5::Init<_QSPI::Pin::D5>();
    }
    
    // We manually control chip-select
    _ICE_ST_SPI_CS_::Write(1);
}

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    _ICE_ST_SPI_CS_::Write(0);
    if (resp) {
        _QSPI::Read(_QSPICmd::ICEApp(msg, sizeof(*resp)), resp);
    } else {
        _QSPI::Command(_QSPICmd::ICEApp(msg, 0));
    }
    _ICE_ST_SPI_CS_::Write(1);
}

static void _ICEAppInit() {
    // Prepare for comms with ICEApp via QSPI
    _QSPIConfigSet(&_QSPIConfigs::ICEApp);
    
    bool ok = false;
    for (int i=0; i<100 && !ok; i++) {
        _Scheduler::Sleep(_Scheduler::Ms(1));
        // Init ICE comms
        ok = _ICE::Init();
    }
    Assert(ok);
}

[[noreturn]]
static void _ICEError(uint16_t line) {
    _System::Abort();
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

[[noreturn]]
static void _SDError(uint16_t line) {
    _System::Abort();
}

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

[[noreturn]]
static void _ImgError(uint16_t line) {
    _System::Abort();
}

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
        
        // Send the Readout message, which causes us to enter the readout mode until
        // we release the chip select
        _ICE_ST_SPI_CS_::Write(0);
        _QSPI::Command(_QSPICmd::ICEApp(_ICE::ReadoutMsg(), 0));
        
        // Read data over QSPI and write it to USB, indefinitely
        while (_LenRem.value_or(SIZE_MAX)) {
            // Wait until there's a buffer available
            _Scheduler::Wait([] { return _Bufs.wok(); });
            _Buf& buf = _Bufs.wget();
            buf.len = 0;
            
            while (_LenRem.value_or(SIZE_MAX)) {
                const size_t lenRead = std::min(_LenRem.value_or(SIZE_MAX), _ICE::ReadoutMsg::ReadoutLen);
                const size_t lenBuf = sizeof(buf.data)-buf.len;
                // If the buffer can't fit `lenRead` more bytes, we're done with this buffer
                if (lenBuf < lenRead) break;
                
                // Wait until ICE40 signals that data is ready to be read
                #warning TODO: we should institute yield after some number of retries to avoid crashing the system if we never get data
                while (!_ICE_ST_SPI_D_READY::Read());
                
                _QSPI::Read(_QSPICmd::ICEAppReadOnly(lenRead), buf.data+buf.len);
                buf.len += lenRead;
                if (_LenRem) *_LenRem -= lenRead;
            }
            
            // Push buffer if it has data
            if (buf.len) _Bufs.wpush();
        }
        
        // Release chip-select to exit readout mode
        _ICE_ST_SPI_CS_::Write(1);
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
    _QSPIConfigSet(nullptr);
    
    // Disable flash
    _ICE_ST_FLASH_EN::Write(0);
    
    // Put ICE40 into configuration mode
    _ICE_ST_SPI_CLK::Write(1);
    
    // Assert chip select
    _ICE_ST_SPI_CS_::Write(0);
    
    // Assert reset
    _ICE_CRST_::Write(0);
    _Scheduler::Sleep(_Scheduler::Ms(1)); // Sleep 1 ms (ideally, 200 ns)
    
    // Release reset
    _ICE_CRST_::Write(1);
    _Scheduler::Sleep(_Scheduler::Ms(2)); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Configure QSPI for writing the ICE40 configuration
    _QSPIConfigSet(&_QSPIConfigs::ICEWrite);
    
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
            if (i) _Scheduler::Sleep(_Scheduler::Ms(1)); // Sleep 1 ms
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
    _ICE_ST_SPI_CS_::Write(1);
    
    _System::USBSendStatus(true);
}

static void __ICEFlashIn(uint8_t* d, size_t len) {
    for (size_t i=0; i<len; i++) {
        uint8_t& b = d[i];
        for (int ii=0; ii<8; ii++) {
            _ICE_ST_SPI_CLK::Write(1);
            
            b <<= 1;
            b |= _ICE_ST_SPI_D4::Read();
            
            _ICE_ST_SPI_CLK::Write(0);
        }
    }
}

static void __ICEFlashOut(const uint8_t* d, size_t len) {
    for (size_t i=0; i<len; i++) {
        uint8_t b = d[i];
        for (int ii=0; ii<8; ii++) {
            _ICE_ST_SPI_D5::Write(b & 0x80);
            b <<= 1;
            
            _ICE_ST_SPI_CLK::Write(1);
            _ICE_ST_SPI_CLK::Write(0);
        }
    }
}

//static uint8_t _ICEFlashIn() {
//    _ICE_ST_SPI_CS_::Write(0);
//    uint8_t d = 0;
//    __ICEFlashIn(&d, 1);
//    _ICE_ST_SPI_CS_::Write(1);
//    return d;
//}

static void _ICEFlashOut(uint8_t out) {
    _ICE_ST_SPI_CS_::Write(0);
    __ICEFlashOut(&out, 1);
    _ICE_ST_SPI_CS_::Write(1);
}

static uint8_t _ICEFlashOutIn(uint8_t out) {
    uint8_t in = 0;
    _ICE_ST_SPI_CS_::Write(0);
    __ICEFlashOut(&out, 1);
    __ICEFlashIn(&in, 1);
    _ICE_ST_SPI_CS_::Write(1);
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
//        _ICE_ST_SPI_D4::Write(w & 0x80);
//        w <<= 1;
//        
//        _ICE_ST_SPI_CLK::Write(1);
//        _ICE_ST_SPI_CLK::Write(0);
//    }
//}
//
//static void _ICEFlashCmd(const uint8_t* instr, size_t instrLen, const uint8_t* data=nullptr, size_t dataLen=0) {
//    _ICE_ST_SPI_CS_::Write(0);
//    __ICEFlashCmd(instr, instrLen);
//    if (data) __ICEFlashCmd(data, dataLen);
//    _ICE_ST_SPI_CS_::Write(1);
//}
//
//static void _ICEFlashCmd(uint8_t w, const uint8_t* d=nullptr, size_t len=0) {
//    _ICEFlashCmd(&w, 1, d, len);
//}
//
//static uint8_t _ICEFlashCmd(uint8_t w) {
//    _ICE_ST_SPI_CS_::Write(0);
//    __ICEFlashCmd(&w, 1);
//    const uint8_t r = __ICEFlashWriteRead();
//    _ICE_ST_SPI_CS_::Write(1);
//    return r;
//}

static void _ICEFlashRead(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICEFlashRead;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Enable manual control of SPI lines
    _QSPIConfigSet(nullptr);
    
    // Hold ICE40 in reset while we read from flash
    _ICE_CRST_::Write(0);
    
    // Set default clock state before enabling flash
    _ICE_ST_SPI_CLK::Write(0);
    
    // De-assert chip select before enabling flash
    _ICE_ST_SPI_CS_::Write(1);
    
    // Enable flash
    _ICE_ST_FLASH_EN::Write(1);
    
    // Reset flash
    _ICEFlashOut(0x66);
    _ICEFlashOut(0x99);
    _Scheduler::Sleep(_Scheduler::Us(32)); // "the device will take approximately tRST=30us to reset"
    
    // Reset state
    _Bufs.reset();
    
    // Start the USB DataIn task
    _TaskUSBDataIn::Start();
    
    _ICE_ST_SPI_CS_::Write(0);
    
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
    _ICE_ST_FLASH_EN::Write(0);
    
    // Revert to default QSPI config
    _QSPIConfigSet(&_QSPIConfigs::ICEApp);
    
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
    _QSPIConfigSet(nullptr);
    
    // Hold ICE40 in reset while we write to flash
    _ICE_CRST_::Write(0);
    
    // Set default clock state before enabling flash
    _ICE_ST_SPI_CLK::Write(0);
    
    // De-assert chip select before enabling flash
    _ICE_ST_SPI_CS_::Write(1);
    
    // Enable flash
    _ICE_ST_FLASH_EN::Write(1);
    
    // Reset flash
    _ICEFlashOut(0x66);
    _ICEFlashOut(0x99);
    _Scheduler::Sleep(_Scheduler::Us(32)); // "the device will take approximately tRST=30us to reset"
    
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
                    
                    _ICE_ST_SPI_CS_::Write(0);
                    __ICEFlashOut(instr, sizeof(instr));
                    __ICEFlashOut(buf.data+chunkOff, chunkLen);
                    _ICE_ST_SPI_CS_::Write(1);
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
    _ICE_ST_FLASH_EN::Write(0);
    
    // Revert to default QSPI config
    _QSPIConfigSet(&_QSPIConfigs::ICEApp);
    
    // Take ICE40 out of reset
    _ICE_CRST_::Write(1);
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPHostModeSet(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPHostModeSet;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
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
    const Time::Instant time = mspResp->arg.TimeGet.time;
    _USB::Send(Endpoint::DataIn, &time, sizeof(time));
}

static void _MSPTimeSet(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPTimeSet;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    const MSP::Cmd mspCmd = {
        .op = MSP::Cmd::Op::TimeSet,
        .arg = { .TimeSet = { .time = arg.time } },
    };
    
    const auto mspResp = _System::MSPSend(mspCmd);
    if (!mspResp || !mspResp->ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
}

// _MSPSBWLock: ensures mutual exclusion between MSP I2C comms (via System::_TaskMSPComms) and MSP Spy-bi-wire IO
static _System::MSPLock __MSPSBWLock;

static void _MSPSBWReset() {
    _MSPJTAG::Disconnect();
    // Relinquish the lock if it was held (no-op otherwise)
    __MSPSBWLock = {};
}

static void _MSPSBWLock(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Acquire mutex to block MSP I2C comms until our SBW IO is done (and _MSPSBWDisconnect() is called)
    __MSPSBWLock.lock();
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWUnlock(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    __MSPSBWLock.unlock();
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWConnect(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Acquire mutex to block MSP I2C comms until our SBW IO is done (and _MSPSBWDisconnect() is called)
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
    default:                                abort();
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
    _ICE_ST_SPI_CS_::Write(1);
    
    _SD::ReadStart(arg.block);
    
    // Send status
    _System::USBSendStatus(true);
    
    // Start the Readout task
    _TaskReadout::Start(std::nullopt);
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
    _QSPIConfigSet(&_QSPIConfigs::ICEApp);
}

static void _CmdHandle(const STM::Cmd& cmd) {
    _TasksReset();
    
    switch (cmd.op) {
    // ICE40 Bootloader
    case Op::ICERAMWrite:           _ICERAMWrite(cmd);                  break;
    case Op::ICEFlashRead:          _ICEFlashRead(cmd);                 break;
    case Op::ICEFlashWrite:         _ICEFlashWrite(cmd);                break;
    // MSP430
    case Op::MSPHostModeSet:        _MSPHostModeSet(cmd);               break;
    case Op::MSPStateRead:          _MSPStateRead(cmd);                 break;
    case Op::MSPStateWrite:         _MSPStateWrite(cmd);                break;
    case Op::MSPTimeGet:            _MSPTimeGet(cmd);                   break;
    case Op::MSPTimeSet:            _MSPTimeSet(cmd);                   break;
    // MSP430 SBW
    case Op::MSPSBWLock:            _MSPSBWLock(cmd);                   break;
    case Op::MSPSBWUnlock:          _MSPSBWUnlock(cmd);                 break;
    case Op::MSPSBWConnect:         _MSPSBWConnect(cmd);                break;
    case Op::MSPSBWDisconnect:      _MSPSBWDisconnect(cmd);             break;
    case Op::MSPSBWRead:            _MSPSBWRead(cmd);                   break;
    case Op::MSPSBWWrite:           _MSPSBWWrite(cmd);                  break;
    case Op::MSPSBWErase:           _MSPSBWErase(cmd);                  break;
    case Op::MSPSBWDebug:           _MSPSBWDebug(cmd);                  break;
    // SD Card
    case Op::SDInit:                _SDInit(cmd);                       break;
    case Op::SDRead:                _SDRead(cmd);                       break;
    // Img
    case Op::ImgInit:               _ImgInit(cmd);                      break;
    case Op::ImgExposureSet:        _ImgExposureSet(cmd);               break;
    case Op::ImgCapture:            _ImgCapture(cmd);                   break;
    // Bad command
    default:                        _System::USBAcceptCommand(false);   break;
    }
}

// MARK: - ISRs

extern "C" [[gnu::section(".isr")]] void ISR_NMI() {}
extern "C" [[gnu::section(".isr")]] void ISR_HardFault() { for (;;); }
extern "C" [[gnu::section(".isr")]] void ISR_MemManage() { for (;;); }
extern "C" [[gnu::section(".isr")]] void ISR_BusFault() { for (;;); }
extern "C" [[gnu::section(".isr")]] void ISR_UsageFault() { for (;;); }
extern "C" [[gnu::section(".isr")]] void ISR_SVC() {}
extern "C" [[gnu::section(".isr")]] void ISR_DebugMon() {}
extern "C" [[gnu::section(".isr")]] void ISR_PendSV() {}

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

extern "C" [[gnu::section(".isr")]] void ISR_EXTI15_10() {
    _System::ISR_ExtInt_15_10();
}

// MARK: - Abort

extern "C" [[noreturn]]
void abort() {
    _System::Abort();
}

// MARK: - Main

int main() {
    _System::Run<
        _ICE_CRST_,
        _ICE_CDONE,
        _ICE_ST_SPI_CS_,
        _ICE_ST_SPI_D_READY,
        _ICE_ST_FLASH_EN,
        
        _QSPI::Pin::Clk,
        _QSPI::Pin::D0,
        _QSPI::Pin::D1,
        _QSPI::Pin::D2,
        _QSPI::Pin::D3,
        _QSPI::Pin::D4,
        _QSPI::Pin::D5,
        _QSPI::Pin::D6,
        _QSPI::Pin::D7
    >();
    
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

#define TaskARM32
#include "Toastbox/Task.h"
#include "Toastbox/IntState.h"
#include "Assert.h"
#include "System.h"
#include "ICE.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "Battery.h"
#include "BufQueue.h"
#include "SDCard.h"
#include "ImgSensor.h"
#include "ImgSD.h"
#include "USBConfigDesc.h"
#include "MSP430JTAG.h"
using namespace STM;

// MARK: - Peripherals & Types

static const void* _USBConfigDesc(size_t& len);

using _USBType = USBType<
    true,                       // T_DMAEn
    _USBConfigDesc,             // T_ConfigDesc
    STM::Endpoints::DataOut,    // T_Endpoints
    STM::Endpoints::DataIn
>;

static const void* _USBConfigDesc(size_t& len) {
    return USBConfigDesc<_USBType>(len);
}

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
static void _BufQueueAssert(bool c) { Assert(c); }
using _BufQueue = BufQueue<uint8_t, 63*1024, 2, _BufQueueAssert>;

#warning TODO: were not putting the _BufQueue code in .sram1 too are we?
[[gnu::section(".sram1")]]
static _BufQueue _Bufs;

struct _TaskUSBDataOut;
struct _TaskUSBDataIn;
struct _TaskReadout;

static void _CmdHandle(const STM::Cmd& cmd);
using _System = System<
    _USBType,
    STM::Status::Modes::STMApp,
    _CmdHandle,
    // Additional Tasks
    _TaskUSBDataOut,
    _TaskUSBDataIn,
    _TaskReadout
>;

constexpr auto& _USB = _System::USB;
using _Scheduler = _System::Scheduler;

using _I2C = _System::I2C;

static QSPI _QSPI;
static Battery<_Scheduler> _Battery;

using _ICE_CRST_            = GPIO<GPIOPortF, 11>;
using _ICE_CDONE            = GPIO<GPIOPortB, 1>;
using _ICE_ST_SPI_CS_       = GPIO<GPIOPortE, 12>;
using _ICE_ST_SPI_D_READY   = GPIO<GPIOPortA, 3>;
using _ICE_ST_FLASH_EN      = GPIO<GPIOPortF, 5>;
using _ICE_ST_SPI_CLK       = QSPI::Clk;
using _ICE_ST_SPI_D4        = QSPI::D4;
using _ICE_ST_SPI_D5        = QSPI::D5;
using _MSP_TEST             = GPIO<GPIOPortG, 11>;
using _MSP_RST_             = GPIO<GPIOPortG, 12>;

[[noreturn]] static void _ICEError(uint16_t line);
using _ICE = ::ICE<_Scheduler, _ICEError>;

[[noreturn]] static void _ImgError(uint16_t line);
using _ImgSensor = Img::Sensor<
    _System::Scheduler,     // T_Scheduler
    _ICE,                   // T_ICE
    _ImgError               // T_Error
>;

[[noreturn]] static void _SDError(uint16_t line);
using _SDCard = SD::Card<
    _System::Scheduler, // T_Scheduler
    _ICE,               // T_ICE
    _SDError,           // T_Error
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    2                   // T_ClkDelayFast (odd values invert the clock)
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
    static inline SD::CardId _CardId;
    static inline SD::CardData _CardData;
    static inline bool _Reading = false;
};

// MARK: - Utility Functions

static bool _VDDIMGSDSet(bool en) {
    const MSP::Cmd cmd = {
        .op = MSP::Cmd::Op::VDDIMGSDSet,
        .arg = {
            .VDDIMGSDSet = {
                .en = en,
            },
        },
    };
    
    MSP::Resp resp;
    const bool ok = _I2C::Send(cmd, resp);
    if (!ok || !resp.ok) return false;
    
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

static QSPI::Config ICEWrite = {
    .mode       = QSPI::Mode::Single,
    .clkDivider = 5, // clkDivider: 5 -> QSPI clock = 21.3 MHz
    .align      = QSPI::Align::Byte,
};

static QSPI::Config ICEApp = {
    .mode       = QSPI::Mode::Dual,
    .clkDivider = 1, // clkDivider: 1 -> QSPI clock = 64 MHz
//        .clkDivider = 31, // clkDivider: 31 -> QSPI clock = 4 MHz
//        .clkDivider = 255, // clkDivider: 255 -> QSPI clock = .5 MHz
    .align      = QSPI::Align::Word,
};

} // namespace _QSPIConfigs

void _QSPISetConfig(const QSPI::Config& config) {
    _QSPI.setConfig(config);
    
    // We manually control chip-select
    _ICE_ST_SPI_CS_::Write(1);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, 0);
}

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    _ICE_ST_SPI_CS_::Write(0);
    if (resp) {
        _QSPI.read(_QSPICmd::ICEApp(msg, sizeof(*resp)), resp);
    } else {
        _QSPI.command(_QSPICmd::ICEApp(msg, 0));
    }
    _Scheduler::Wait([] { return _QSPI.ready(); });
    _ICE_ST_SPI_CS_::Write(1);
}

static void _ICEAppInit() {
    // Prepare for comms with ICEApp via QSPI
    _QSPISetConfig(_QSPIConfigs::ICEApp);
    // Confirm comms are working
    _ICE::Init();
}

[[noreturn]]
static void _ICEError(uint16_t line) {
    _System::Abort();
}

// MARK: - MSP430
static MSP430JTAG<_MSP_TEST, _MSP_RST_, _System::CPUFreqMHz> _MSP;

// MARK: - SD Card

//static bool _MSPSBWConnect(bool unlockPins) {
//    constexpr uint16_t PM5CTL0Addr  = 0x0130;
//    
//    const auto mspr = _MSP.connect();
//    if (mspr != _MSP.Status::OK) return false;
//    
//    if (unlockPins) {
//        // Clear LOCKLPM5 in the PM5CTL0 register
//        // This is necessary to be able to control the GPIOs
//        _MSP.write(PM5CTL0Addr, 0x0010);
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
//    const uint16_t PADIR = _MSP.read(PADIRAddr);
//    const uint16_t PAOUT = _MSP.read(PAOUTAddr);
//    _MSP.write(PADIRAddr, PADIR | VDD_SD_EN);
//    
//    if (en) {
//        _MSP.write(PAOUTAddr, PAOUT | VDD_SD_EN);
//    } else {
//        _MSP.write(PAOUTAddr, PAOUT & ~VDD_SD_EN);
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
//    const uint16_t PADIR = _MSP.read(PADIRAddr);
//    const uint16_t PAOUT = _MSP.read(PAOUTAddr);
//    _MSP.write(PADIRAddr, PADIR | (VDD_2V8_IMG_EN | VDD_1V8_IMG_EN));
//    
//    if (en) {
//        _MSP.write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN));
//        _Scheduler::Sleep(_Scheduler::Ms(1)); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V8)
//        _MSP.write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN|VDD_1V8_IMG_EN));
//    
//    } else {
//        // No delay between 2V8/1V8 needed for power down (per AR0330CS datasheet)
//        _MSP.write(PAOUTAddr, PAOUT & ~(VDD_2V8_IMG_EN|VDD_1V8_IMG_EN));
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

// _TaskUSBDataOut: reads `len` bytes from the DataOut endpoint and writes them to _Bufs
struct _TaskUSBDataOut {
    static void Start(size_t l) {
        // Make sure this task isn't busy
        Assert(!_Scheduler::Running<_TaskUSBDataOut>());
        
        static size_t len = 0;
        len = l;
        _Scheduler::Start<_TaskUSBDataOut>([] {
            for (;;) {
                _Scheduler::Wait([] { return _Bufs.wok(); });
                
                auto& buf = _Bufs.wget();
                if (!len) {
                    // Signal EOF when there's no more data to receive
                    buf.len = 0;
                    _Bufs.wpush();
                    break;
                }
                
                // Prepare to receive either `len` bytes or the buffer capacity bytes,
                // whichever is smaller.
                const size_t cap = _USB.CeilToMaxPacketSize(_USB.MaxPacketSizeOut(), std::min(len, sizeof(buf.data)));
                // Ensure that after rounding up to the nearest packet size, we don't
                // exceed the buffer capacity. (This should always be safe as long as
                // the buffer capacity is a multiple of the max packet size.)
                Assert(cap <= sizeof(buf.data));
                _USB.recv(Endpoints::DataOut, buf.data, cap);
                _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
                
                // Never claim that we read more than the requested data, even if ceiling
                // to the max packet size caused us to read more than requested.
                const size_t recvLen = std::min(len, _USB.recvLen(Endpoints::DataOut));
                len -= recvLen;
                buf.len = recvLen;
                _Bufs.wpush();
            }
        });
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataOut")]]
    static inline uint8_t Stack[256];
};

// _TaskUSBDataIn: writes buffers from _Bufs to the DataIn endpoint, and pops them from _Bufs
struct _TaskUSBDataIn {
    static void Start() {
        _Scheduler::Start<_TaskUSBDataIn>([] {
            for (;;) {
                _Scheduler::Wait([] { return _Bufs.rok(); });
                
                // Send the data and wait until the transfer is complete
                auto& buf = _Bufs.rget();
                _USB.send(Endpoints::DataIn, buf.data, buf.len);
                _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
                
                buf.len = 0;
                _Bufs.rpop();
            }
        });
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataIn")]]
    static inline uint8_t Stack[256];
};

// _TaskReadout:
struct _TaskReadout {
    static void Start(std::optional<size_t> len) {
        static std::optional<size_t> remLen;
        remLen = len;
        
        _Scheduler::Start<_TaskReadout>([] {
            // Reset state
            _Bufs.reset();
            // Start the USB DataIn task
            _TaskUSBDataIn::Start();
            
            // Send the Readout message, which causes us to enter the readout mode until
            // we release the chip select
            _ICE_ST_SPI_CS_::Write(0);
            _QSPI.command(_QSPICmd::ICEApp(_ICE::ReadoutMsg(), 0));
            
            // Read data over QSPI and write it to USB, indefinitely
            for (;;) {
                // Wait until: there's an available buffer, QSPI is ready, and ICE40 says data is available
                _Scheduler::Wait([] { return _Bufs.wok() && _QSPI.ready(); });
                
                const size_t len = std::min(remLen.value_or(SIZE_MAX), _ICE::ReadoutMsg::ReadoutLen);
                auto& buf = _Bufs.wget();
                
                // If there's no more data to read, bail
                if (!len) {
                    // Before bailing, push the final buffer if it holds data
                    if (buf.len) _Bufs.wpush();
                    break;
                }
                
                // If we can't read any more data into the producer buffer,
                // push it so the data will be sent over USB
                if (sizeof(buf.data)-buf.len < len) {
                    _Bufs.wpush();
                    continue;
                }
                
                // Wait until ICE40 signals that data is ready to be read
                #warning TODO: we should institute yield after some number of retries to avoid crashing the system if we never get data
                while (!_ICE_ST_SPI_D_READY::Read());
                
                _QSPI.read(_QSPICmd::ICEAppReadOnly(len), buf.data+buf.len);
                buf.len += len;
                
                if (remLen) *remLen -= len;
            }
        });
    }
    
    static void DidStop() {
        // De-assert the SPI chip select when the _TaskReadout is stopped.
        // This is necessary because the _TaskReadout asserts the SPI chip select,
        // but never deasserts it because _TaskReadout continues indefinitely.
        _ICE_ST_SPI_CS_::Write(1);
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .DidStop = DidStop,
    };
    
    // Task stack
    [[gnu::section(".stack._TaskReadout")]]
    static inline uint8_t Stack[512];
};

// MARK: - Commands

static void _HostModeSet(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.HostModeSet;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    const MSP::Cmd cmd = {
        .op = MSP::Cmd::Op::HostModeSet,
        .arg = { .HostModeSet = { .en = arg.en } },
    };
    MSP::Resp resp;
    
    const bool ok = _I2C::Send(cmd, resp);
    if (!ok || !resp.ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
}

static void _ICERAMWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICERAMWrite;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Configure ICE40 control GPIOs
    _ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_FLASH_EN::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Disable flash
    _ICE_ST_FLASH_EN::Write(0);
    
    // Put ICE40 into configuration mode
    _ICE_ST_SPI_CLK::Write(1);
    
    _ICE_ST_SPI_CS_::Write(0);
    _ICE_CRST_::Write(0);
    _Scheduler::Sleep(_Scheduler::Ms(1)); // Sleep 1 ms (ideally, 200 ns)
    
    _ICE_CRST_::Write(1);
    _Scheduler::Sleep(_Scheduler::Ms(2)); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Configure QSPI for writing the ICE40 configuration
    _QSPISetConfig(_QSPIConfigs::ICEWrite);
    
    // Send 8 clocks and wait for them to complete
    static const uint8_t ff = 0xff;
    _QSPI.write(_QSPICmd::ICEWrite(sizeof(ff)), &ff);
    _Scheduler::Wait([] { return _QSPI.ready(); });
    
    // Reset state
    _Bufs.reset();
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(arg.len);
    
    for (;;) {
        // Wait until we have data to consume, and QSPI is ready to write
        _Scheduler::Wait([] { return _Bufs.rok() && _QSPI.ready(); });
        
        // Write the data over QSPI and wait for completion
        auto& buf = _Bufs.rget();
        if (buf.len) {
            _QSPI.write(_QSPICmd::ICEWrite(buf.len), buf.data);
            _Scheduler::Wait([] { return _QSPI.ready(); });
        }
        _Bufs.rpop();
        if (!buf.len) break; // We're done when we receive an empty buffer
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
            _QSPI.write(_QSPICmd::ICEWrite(sizeof(ff)), &ff);
            _Scheduler::Wait([] { return _QSPI.ready(); });
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
    
    // Configure ICE40 control GPIOs
    _ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_FLASH_EN::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D4::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D5::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
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
        
        auto& buf = _Bufs.wget();
        // Prepare to receive either `len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        const size_t chunkLen = std::min((size_t)len, sizeof(buf.data));
        __ICEFlashIn(buf.data, chunkLen);
        addr += chunkLen;
        len -= chunkLen;
        // Enqueue the buffer
        buf.len = chunkLen;
        _Bufs.wpush();
    }
    
    // Wait for DataIn task to complete
    _Scheduler::Wait([] { return !_Bufs.rok(); });
    
    // Disable flash
    _ICE_ST_FLASH_EN::Write(0);
    
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_FLASH_EN::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D4::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D5::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Take ICE40 out of reset
    _ICE_CRST_::Write(1);
    
    // Send status
    _System::USBSendStatus(true);
}

static void _ICEFlashWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICEFlashWrite;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Configure ICE40 control GPIOs
    _ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_FLASH_EN::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D4::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D5::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
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
    
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_FLASH_EN::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D4::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_D5::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Take ICE40 out of reset
    _ICE_CRST_::Write(1);
    
    // Send status
    _System::USBSendStatus(true);
}

static bool __MSPStateRead(size_t off, uint8_t* data, size_t len) {
    constexpr size_t ChunkSize = sizeof(MSP::Resp::arg.StateRead.data);
    AssertArg((off % ChunkSize) == 0);
    
    const size_t chunkOff = off / ChunkSize;
    const size_t chunkCount = (len+ChunkSize-1) / ChunkSize;
    for (uint8_t chunk=0; chunk<chunkCount; chunk++) {
        const MSP::Cmd cmd = {
            .op = MSP::Cmd::Op::StateRead,
            .arg = { .StateRead = { .chunk = chunkOff+chunk } },
        };
        
        MSP::Resp resp;
        const bool ok = _I2C::Send(cmd, resp);
        if (!ok) return false;
        
        const size_t l = std::min(len, ChunkSize);
        memcpy(data+off, resp.arg.StateRead.data, l);
        off += l;
        len -= l;
    }
    
    return true;
}


//static bool __MSPStateReadChunk(uint8_t* data, size_t dataCap, size_t off) {
//    constexpr size_t ChunkSize = sizeof(MSP::Resp::arg.StateRead.data);
//    AssertArg((off % ChunkSize) == 0);
//    
//    for (;;) {
//        const MSP::Cmd cmd = {
//            .op = MSP::Cmd::Op::StateRead,
//            .arg = { .StateRead = { .chunk = off/ChunkSize } },
//        };
//        
//        MSP::Resp resp;
//        const bool ok = _I2C::Send(cmd, resp);
//        if (!ok) return false;
//    }
//    
//    return true;
//}


static size_t __MSPStateRead(uint8_t* data, size_t cap) {
    MSP::State::Header header;
    if (cap < sizeof(header)) return 0;
    
    size_t off = 0;
    bool ok = __MSPStateRead(off, &header, sizeof(header));
    if (!ok) return 0;
    
    // Copy header into destination buffer
    memcpy(data+off, &header, sizeof(header));
    off += sizeof(header);
    
    // Validate the header
    if (header.magic != MSP::State::MagicNumber) return 0;
    // Validate that the caller has enough space to hold the header + payload
    if (cap < sizeof(header) + header.size) return 0;
    // Read payload directly into destination buffer
    ok = __MSPStateRead(off, data+off, header.size);
    if (!ok) return 0;
    off += header.size;
    return off;
}

static void _MSPStateRead(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    
    auto& buf = _Bufs.wget();
    size_t len = __MSPStateRead(buf.data, sizeof(buf.data));
    if (!len) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
    
    // Send MSPStateInfo
    {
        alignas(4) const MSPStateInfo stateInfo = {
            .len = len,
        };
        
        _USB.send(Endpoints::DataIn, &stateInfo, sizeof(stateInfo));
        _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    }
    
    // Send state itself
    {
        _USB.send(Endpoints::DataIn, buf.data, len);
        _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    }
}

static void _MSPStateWrite(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    
    
    
    
    
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPTimeSet(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPTimeSet;
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    const MSP::Cmd cmd = {
        .op = MSP::Cmd::Op::TimeSet,
        .arg = { .TimeSet = { .time = arg.time } },
    };
    
    MSP::Resp resp;
    const bool ok = _I2C::Send(cmd, resp);
    if (!ok || !resp.ok) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPSBWConnect(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    const auto mspr = _MSP.connect();
    
    // Send status
    _System::USBSendStatus(mspr == _MSP.Status::OK);
}

static void _MSPSBWDisconnect(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    _MSP.disconnect();
    
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
        
        auto& buf = _Bufs.wget();
        // Prepare to receive either `len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        const size_t chunkLen = std::min((size_t)len, sizeof(buf.data));
        _MSP.read(addr, buf.data, chunkLen);
        addr += chunkLen;
        len -= chunkLen;
        // Enqueue the buffer
        buf.len = chunkLen;
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
        if (buf.len) {
            _MSP.write(addr, buf.data, buf.len);
            addr += buf.len; // Update the MSP430 address to write to
        }
        _Bufs.rpop();
        if (!buf.len) break; // We're done when we receive an empty buffer
    }
    
    _System::USBSendStatus(true);
}

struct _MSPSBWDebugState {
    uint8_t bits = 0;
    uint8_t bitsLen = 0;
    size_t len = 0;
    bool ok = true;
};

static void _MSPSBWDebugPushReadBits(_MSPSBWDebugState& state, _BufQueue::Buf& buf) {
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

static void _MSPSBWDebugHandleSBWIO(const MSPSBWDebugCmd& cmd, _MSPSBWDebugState& state, _BufQueue::Buf& buf) {
    const bool tdo = _MSP.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
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

static void _MSPSBWDebugHandleCmd(const MSPSBWDebugCmd& cmd, _MSPSBWDebugState& state, _BufQueue::Buf& buf) {
    switch (cmd.opGet()) {
    case MSPSBWDebugCmd::Ops::TestSet:     _MSP.debugTestSet(cmd.pinValGet());     break;
    case MSPSBWDebugCmd::Ops::RstSet:      _MSP.debugRstSet(cmd.pinValGet()); 	    break;
    case MSPSBWDebugCmd::Ops::TestPulse:   _MSP.debugTestPulse(); 				    break;
    case MSPSBWDebugCmd::Ops::SBWIO:       _MSPSBWDebugHandleSBWIO(cmd, state, buf);	break;
    default:                            abort();
    }
}

static void _MSPSBWDebug(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPSBWDebug;
    
    // Bail if more data was requested than the size of our buffer
    if (arg.respLen > sizeof(_BufQueue::Buf::data)) {
        // Reject command
        _System::USBAcceptCommand(false);
        return;
    }
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Reset state
    _Bufs.reset();
    auto& bufIn = _Bufs.wget();
    _Bufs.wpush();
    auto& bufOut = _Bufs.wget();
    
    _MSPSBWDebugState state;
    
    // Handle debug commands
    {
        size_t cmdsLenRem = arg.cmdsLen;
        while (cmdsLenRem) {
            // Receive debug commands into buf
            _USB.recv(Endpoints::DataOut, bufIn.data, sizeof(bufIn.data));
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
            
            // Handle each MSPSBWDebugCmd
            const MSPSBWDebugCmd* cmds = (MSPSBWDebugCmd*)bufIn.data;
            const size_t cmdsLen = _USB.recvLen(Endpoints::DataOut) / sizeof(MSPSBWDebugCmd);
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
            _USB.send(Endpoints::DataIn, bufOut.data, arg.respLen);
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
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
    alignas(4) const SDCardInfo cardInfo = {
        .cardId = _SD::CardId(),
        .cardData = _SD::CardData(),
    };
    
    _USB.send(Endpoints::DataIn, &cardInfo, sizeof(cardInfo));
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
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
    
    // stats: aligned to send via USB
    alignas(4) const ImgCaptureStats stats = {
        .len            = imagePaddedLen,
        .highlightCount = resp.highlightCount(),
        .shadowCount    = resp.shadowCount(),
    };
    
    // Send ImgCaptureStats
    _USB.send(Endpoints::DataIn, &stats, sizeof(stats));
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Arrange for the image to be read out
    _ICE::Transfer(_ICE::ImgReadoutMsg(arg.dstRAMBlock, arg.size));
    
    // Send status
    _System::USBSendStatus(true);
    
    // Start the Readout task
    _TaskReadout::Start(imagePaddedLen);
}

void _BatteryStatusGet(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Send battery status
    alignas(4) const BatteryStatus status = _Battery.status();
    _USB.send(Endpoints::DataIn, &status, sizeof(status));
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
}

static void _CmdHandle(const STM::Cmd& cmd) {
    switch (cmd.op) {
    // Host Mode
    case Op::HostModeSet:           _HostModeSet(cmd);                  break;
    // ICE40 Bootloader
    case Op::ICERAMWrite:           _ICERAMWrite(cmd);                  break;
    case Op::ICEFlashRead:          _ICEFlashRead(cmd);                 break;
    case Op::ICEFlashWrite:         _ICEFlashWrite(cmd);                break;
    // MSP430 State Read/Write
    case Op::MSPStateRead:          _MSPStateRead(cmd);                 break;
    case Op::MSPStateWrite:         _MSPStateWrite(cmd);                break;
    case Op::MSPTimeSet:            _MSPTimeSet(cmd);                   break;
    // MSP430 SBW
    case Op::MSPSBWConnect:         _MSPSBWConnect(cmd);                break;
    case Op::MSPSBWDisconnect:      _MSPSBWDisconnect(cmd);             break;
    case Op::MSPSBWRead:            _MSPSBWRead(cmd);                   break;
    case Op::MSPSBWWrite:           _MSPSBWWrite(cmd);                  break;
    case Op::MSPSBWDebug:           _MSPSBWDebug(cmd);                  break;
    // SD Card
    case Op::SDInit:                _SDInit(cmd);                       break;
    case Op::SDRead:                _SDRead(cmd);                       break;
    // Img
    case Op::ImgInit:               _ImgInit(cmd);                      break;
    case Op::ImgExposureSet:        _ImgExposureSet(cmd);               break;
    case Op::ImgCapture:            _ImgCapture(cmd);                   break;
    // Battery
    case Op::BatteryStatusGet:      _BatteryStatusGet(cmd);             break;
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
    _USB.isr();
}

extern "C" [[gnu::section(".isr")]] void ISR_QUADSPI() {
    _QSPI.isrQSPI();
}

extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream7() {
    _QSPI.isrDMA();
}

extern "C" [[gnu::section(".isr")]] void ISR_I2C1_EV() {
    _I2C::ISR_Event();
}

extern "C" [[gnu::section(".isr")]] void ISR_I2C1_ER() {
    _I2C::ISR_Error();
}

// MARK: - Abort

extern "C" [[noreturn]]
void abort() {
    _System::Abort();
}

// MARK: - Main

int main() {
    _System::Init();
    
    // Enable GPIO clocks
    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();
    __HAL_RCC_GPIOE_CLK_ENABLE();
    __HAL_RCC_GPIOF_CLK_ENABLE();
    __HAL_RCC_GPIOG_CLK_ENABLE();
    
    // Init Battery
    {
        _Battery.init();
    }
    
    // Init MSP
    {
        _MSP.init();
    }
    
    _Scheduler::Run();
    return 0;
}


#warning TODO: remove these debug symbols
#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section
constexpr auto& _Debug_Tasks              = _Scheduler::_Tasks;
constexpr auto& _Debug_DidWork            = _Scheduler::_DidWork;
constexpr auto& _Debug_CurrentTask        = _Scheduler::_CurrentTask;
constexpr auto& _Debug_CurrentTime        = _Scheduler::_ISR.CurrentTime;
constexpr auto& _Debug_Wake               = _Scheduler::_ISR.Wake;
constexpr auto& _Debug_WakeTime           = _Scheduler::_ISR.WakeTime;

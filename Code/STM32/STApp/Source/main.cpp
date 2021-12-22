#define TaskARM32
#include "Toastbox/Task.h"
#include "Toastbox/IntState.h"
#include "Assert.h"
#include "System.h"
#include "MSP430.h"
#include "ICE.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "SDCard.h"
#include "ImgSensor.h"
using namespace STM;

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
using _BufQueue = BufQueue<uint8_t,63*1024,2>;

using _USBType = USB;

using _QSPIType = QSPI<
    QSPIMode::Dual,               // T_Mode
    1,                            // T_ClkDivider (1 -> QSPI clock = 64 MHz)
    QSPIAlign::Word,              // T_Align
    QSPIChipSelect::Uncontrolled  // T_ChipSelect
>;

#warning TODO: we're not putting the _BufQueue code in .sram1 too are we?
[[gnu::section(".sram1")]]
static _BufQueue _Bufs;

// MARK: - Peripherals & Types

struct _TaskUSBDataIn;
struct _TaskReadout;

static void _CmdHandle(const STM::Cmd& cmd);
using _System = System<
    _USBType,
    _QSPIType,
    _CmdHandle,
    // Additional Tasks
    _TaskUSBDataIn,
    _TaskReadout
>;

constexpr auto& _MSP = _System::MSP;
using _ICE = _System::ICE;
constexpr auto& _USB = _System::USB;
constexpr auto& _QSPI = _System::QSPI;
using _Scheduler = _System::Scheduler;

static QSPI_CommandTypeDef _ICEQSPICmd(const _ICE::Msg& msg, size_t respLen);

static void _ImgSetPowerEnabled(bool en);
using _ImgSensor = Img::Sensor<
    _System::Scheduler,     // T_Scheduler
    _System::ICE,           // T_ICE
    _ImgSetPowerEnabled     // T_SetPowerEnabled
>;

static void _SDSetPowerEnabled(bool en);
static SD::Card<
    _System::Scheduler, // T_Scheduler
    _System::ICE,       // T_ICE
    _SDSetPowerEnabled, // T_SetPowerEnabled
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    0                   // T_ClkDelayFast (odd values invert the clock)
> _SDCard;

// MARK: - ICE40

static QSPI_CommandTypeDef _ICEQSPICmd(const _ICE::Msg& msg, size_t respLen) {
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

static QSPI_CommandTypeDef _ICEQSPICmdReadOnly(size_t len) {
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

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    _System::ICE_ST_SPI_CS_::Write(0);
    if (resp) {
        _QSPI.read(_ICEQSPICmd(msg, sizeof(*resp)), resp, sizeof(*resp));
    } else {
        _QSPI.command(_ICEQSPICmd(msg, 0));
    }
    _QSPI.wait();
    _System::ICE_ST_SPI_CS_::Write(1);
}

// MARK: - MSP430

static void _MSPInit() {
    constexpr uint16_t PM5CTL0  = 0x0130;
    constexpr uint16_t PAOUT    = 0x0202;
    
    auto s = _MSP.connect();
    Assert(s == _MSP.Status::OK);
    
    // Clear LOCKLPM5 in the PM5CTL0 register
    // This is necessary to be able to control the GPIOs
    _MSP.write(PM5CTL0, 0x0010);
    
    // Clear PAOUT so everything is driven to 0 by default
    _MSP.write(PAOUT, 0x0000);
}

static void _SDSetPowerEnabled(bool en) {
    constexpr uint16_t BITB         = 1<<0xB;
    constexpr uint16_t VDD_SD_EN    = BITB;
    constexpr uint16_t PADIRAddr    = 0x0204;
    constexpr uint16_t PAOUTAddr    = 0x0202;
    
    const uint16_t PADIR = _MSP.read(PADIRAddr);
    const uint16_t PAOUT = _MSP.read(PAOUTAddr);
    _MSP.write(PADIRAddr, PADIR | VDD_SD_EN);
    
    if (en) {
        _MSP.write(PAOUTAddr, PAOUT | VDD_SD_EN);
    } else {
        _MSP.write(PAOUTAddr, PAOUT & ~VDD_SD_EN);
    }
    
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _Scheduler::SleepMs<2>();
}

static void _ImgSetPowerEnabled(bool en) {
    constexpr uint16_t BIT0             = 1<<0;
    constexpr uint16_t BIT2             = 1<<2;
    constexpr uint16_t VDD_1V9_IMG_EN   = BIT0;
    constexpr uint16_t VDD_2V8_IMG_EN   = BIT2;
    constexpr uint16_t PADIRAddr        = 0x0204;
    constexpr uint16_t PAOUTAddr        = 0x0202;
    
    const uint16_t PADIR = _MSP.read(PADIRAddr);
    const uint16_t PAOUT = _MSP.read(PAOUTAddr);
    _MSP.write(PADIRAddr, PADIR | (VDD_2V8_IMG_EN | VDD_1V9_IMG_EN));
    
    if (en) {
        _MSP.write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN));
        _Scheduler::SleepMs<1>(); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        _MSP.write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN|VDD_1V9_IMG_EN));
    
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        _MSP.write(PAOUTAddr, PAOUT & ~(VDD_2V8_IMG_EN|VDD_1V9_IMG_EN));
    }
    
    #warning TODO: measure how long it takes for IMG rails to rise
    // The TPS22919 takes 1ms for VDD_2V8_IMG VDD to reach 2.8V (empirically measured)
    _Scheduler::SleepMs<2>();
}

// MARK: - Tasks

// _TaskUSBDataIn: writes buffers from _Bufs to the DataIn endpoint, and pops them from _Bufs
struct _TaskUSBDataIn {
    static void Start() {
        _Scheduler::Start<_TaskUSBDataIn>([] {
            for (;;) {
                _Scheduler::Wait([] { return !_Bufs.empty(); });
                
                // Send the data and wait until the transfer is complete
                auto& buf = _Bufs.front();
                _USB.send(Endpoints::DataIn, buf.data, buf.len);
                _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
                
                buf.len = 0;
                _Bufs.pop();
            }
        });
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
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
            _System::ICE_ST_SPI_CS_::Write(0);
            _QSPI.command(_ICEQSPICmd(_ICE::ReadoutMsg(), 0));
            
            // Read data over QSPI and write it to USB, indefinitely
            for (;;) {
                // Wait until: there's an available buffer, QSPI is ready, and ICE40 says data is available
                _Scheduler::Wait([] { return !_Bufs.full() && _QSPI.ready(); });
                
                const size_t len = std::min(remLen.value_or(SIZE_MAX), _ICE::ReadoutMsg::ReadoutLen);
                auto& buf = _Bufs.back();
                
                // If there's no more data to read, bail
                if (!len) {
                    // Before bailing, push the final buffer if it holds data
                    if (buf.len) _Bufs.push();
                    break;
                }
                
                // If we can't read any more data into the producer buffer,
                // push it so the data will be sent over USB
                if (sizeof(buf.data)-buf.len < len) {
                    _Bufs.push();
                    continue;
                }
                
                // Wait until ICE40 signals that data is ready to be read
                #warning TODO: we should institute yield after some number of retries to avoid crashing the system if we never get data
                while (!_System::ICE_ST_SPI_D_READY::Read());
                
                _QSPI.read(_ICEQSPICmdReadOnly(len), buf.data+buf.len, len);
                buf.len += len;
                
                if (remLen) *remLen -= len;
            }
        });
    }
    
    static void DidStop() {
        // De-assert the SPI chip select when the _TaskReadout is stopped.
        // This is necessary because the _TaskReadout asserts the SPI chip select,
        // but never deasserts it because _TaskReadout continues indefinitely.
        #warning TODO: we don't want to do this in the STLoader case, where do we put it?
        _System::ICE_ST_SPI_CS_::Write(1);
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._TaskReadout")]]
    static inline uint8_t Stack[256];
};

// MARK: - Commands

static void _SDRead(const STM::Cmd& cmd) {
    static bool init = false;
    static bool reading = false;
    const auto& arg = cmd.arg.SDRead;
    
    // Initialize the SD card if we haven't done so
    if (!init) {
        _SDCard.enable();
        init = true;
    }
    
    // Stop reading from the SD card if a read is in progress
    if (reading) {
        _System::ICE_ST_SPI_CS_::Write(1);
        _SDCard.readStop();
        reading = false;
    }
    
    // Verify that the address is a multiple of the SD block length
    if (arg.addr % SD::BlockLen) {
        _System::USBSendStatus(false);
        return;
    }
    
    // Send status
    _System::USBSendStatus(true);
    
    // Update state
    reading = true;
    _SDCard.readStart(arg.addr);
    
    // Start the Readout task
    _TaskReadout::Start(std::nullopt);
}

void _ImgInit() {
    static bool init = false;
    if (init) return;
    _ImgSensor::Enable();
    _ImgSensor::SetStreamEnabled(true);
    init = true;
}

void _ImgSetExposure(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.ImgSetExposure;
    _ImgInit();
    _ImgSensor::SetCoarseIntTime(arg.coarseIntTime);
    _ImgSensor::SetFineIntTime(arg.fineIntTime);
    _ImgSensor::SetAnalogGain(arg.analogGain);
    // Send status
    _System::USBSendStatus(true);
}

void _ImgCapture(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.ImgCapture;
    
    _ImgInit();
    
    const Img::Header header = {
        .version        = Img::HeaderVersion,
        .imageWidth     = Img::PixelWidth,
        .imageHeight    = Img::PixelHeight,
    };
    
    const _ICE::ImgCaptureStatusResp resp = _ICE::ImgCapture(header, arg.dstBlock, arg.skipCount);
    
    // stats: aligned to send via USB
    alignas(4) const ImgCaptureStats stats = {
        .len            = resp.wordCount()*sizeof(Img::Word),
        .highlightCount = resp.highlightCount(),
        .shadowCount    = resp.shadowCount(),
    };
    
    // Send status
    _System::USBSendStatus(true);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Send ImgCaptureStats
    _USB.send(Endpoints::DataIn, &stats, sizeof(stats));
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Arrange for the image to be read out
    _ICE::Transfer(_ICE::ImgReadoutMsg(arg.dstBlock));
    
    // Start the Readout task
    _TaskReadout::Start(stats.len);
}

static void _CmdHandle(const STM::Cmd& cmd) {
    switch (cmd.op) {
    case Op::SDRead:            _SDRead(cmd);                   break;
    case Op::ImgCapture:        _ImgCapture(cmd);               break;
    case Op::ImgSetExposure:    _ImgSetExposure(cmd);           break;
    // Bad command
    default:                    _System::USBSendStatus(false);  break;
    }
}

// MARK: - ISRs

extern "C" __attribute__((section(".isr"))) void ISR_NMI() {}
extern "C" __attribute__((section(".isr"))) void ISR_HardFault() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_MemManage() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_BusFault() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_UsageFault() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_SVC() {}
extern "C" __attribute__((section(".isr"))) void ISR_DebugMon() {}
extern "C" __attribute__((section(".isr"))) void ISR_PendSV() {}

extern "C" __attribute__((section(".isr"))) void ISR_SysTick() {
    _Scheduler::Tick();
    HAL_IncTick();
}

extern "C" __attribute__((section(".isr"))) void ISR_OTG_HS() {
    _USB.isr();
}

extern "C" __attribute__((section(".isr"))) void ISR_QUADSPI() {
    _QSPI.isrQSPI();
}

extern "C" __attribute__((section(".isr"))) void ISR_DMA2_Stream7() {
    _QSPI.isrDMA();
}

// MARK: - Abort

extern "C" [[noreturn]]
void abort() {
    _System::Abort();
}

// MARK: - Main

int main() {
    _System::Init();
    
    _USB.init();
    _QSPI.init();
    
    _System::ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, 0);
    _System::ICE_ST_SPI_CS_::Write(1);
    
    _ICE::Init();
    _MSPInit();
    
    _Scheduler::Run();
    return 0;
}

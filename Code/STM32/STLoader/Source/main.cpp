#include <string.h>
#include <algorithm>
#define TaskARM32
#include "Toastbox/Task.h"
#include "Assert.h"
#include "Toastbox/IntState.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "System.h"
#include "USBConfigDesc.h"

using namespace STM;

// MARK: - Peripherals & Types
static const void* _USBConfigDesc(size_t& len);

using _USBType = USBType<
    false,                      // T_DMAEn: disabled because we want USB to be able to write to
                                // ITCM RAM (because we write to that region as a part of
                                // bootloading), but DMA masters can't access it.
    _USBConfigDesc,             // T_ConfigDesc
    STM::Endpoints::DataOut,    // T_Endpoints
    STM::Endpoints::DataIn
>;

static const void* _USBConfigDesc(size_t& len) {
    return USBConfigDesc<_USBType>(len);
}

using _QSPIType = QSPIType<
    QSPIMode::Single,           // T_Mode
    5,                          // T_ClkDivider (5 -> QSPI clock = 21.3 MHz)
    QSPIAlign::Byte,            // T_Align
    QSPIChipSelect::Controlled  // T_ChipSelect
>;

struct _TaskUSBDataOut;
struct _TaskUSBDataIn;

static void _CmdHandle(const STM::Cmd& cmd);
using _System = System<
    _USBType,
    _QSPIType,
    STM::Status::Modes::STMLoader,
    _CmdHandle,
    // Additional Tasks
    _TaskUSBDataOut,
    _TaskUSBDataIn
>;

constexpr auto& _MSP = _System::MSP;
using _ICE = _System::ICE;
constexpr auto& _USB = _System::USB;
constexpr auto& _QSPI = _System::QSPI;
using _Scheduler = _System::Scheduler;

using _BufQueue = BufQueue<uint8_t,1024,2>;
static _BufQueue _Bufs;

// The Startup class needs to exist in the `uninit` section,
// so that its _appEntryPointAddr member doesn't get clobbered
// on startup.
using _VoidFn = void(*)();
static volatile _VoidFn _AppEntryPoint [[noreturn, gnu::section(".uninit")]] = 0;

// _TaskUSBDataOut: reads `len` bytes from the DataOut endpoint and writes them to _Bufs
struct _TaskUSBDataOut {
    static void Start(size_t len);
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataOut")]]
    static inline uint8_t Stack[256];
};

// _TaskUSBDataIn: writes buffers from _Bufs to the DataIn endpoint, and pops them from _Bufs
struct _TaskUSBDataIn {
    static void Start();
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataIn")]]
    static inline uint8_t Stack[256];
};

// MARK: - Common Commands

static size_t _USBCeilToMaxPacketSize(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%_USB.MaxPacketSizeIn();
    len += (rem>0 ? _USB.MaxPacketSizeIn()-rem : 0);
    return len;
}

// MARK: - Tasks

void _TaskUSBDataOut::Start(size_t l) {
    // Make sure this task isn't busy
    Assert(!_Scheduler::Running<_TaskUSBDataOut>());
    
    static size_t len = 0;
    len = l;
    _Scheduler::Start<_TaskUSBDataOut>([] {
        while (len) {
            _Scheduler::Wait([] { return !_Bufs.full(); });
            
            auto& buf = _Bufs.back();
            // Prepare to receive either `len` bytes or the
            // buffer capacity bytes, whichever is smaller.
            const size_t cap = _USBCeilToMaxPacketSize(std::min(len, sizeof(buf.data)));
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
            _Bufs.push();
        }
    });
}

void _TaskUSBDataIn::Start() {
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

// MARK: - Commands

static size_t _STMRegionCapacity(void* addr) {
    // Verify that `addr` is in one of the allowed RAM regions
    extern uint8_t _sitcm_ram[], _eitcm_ram[];
    extern uint8_t _sdtcm_ram[], _edtcm_ram[];
    extern uint8_t _ssram1[], _esram1[];
    size_t cap = 0;
    if (addr>=_sitcm_ram && addr<_eitcm_ram) {
        cap = (uintptr_t)_eitcm_ram-(uintptr_t)addr;
    } else if (addr>=_sdtcm_ram && addr<_edtcm_ram) {
        cap = (uintptr_t)_edtcm_ram-(uintptr_t)addr;
    } else if (addr>=_ssram1 && addr<_esram1) {
        cap = (uintptr_t)_esram1-(uintptr_t)addr;
    }
    return cap;
}

static void _STMWrite(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.STMWrite;
    
    // Bail if the region capacity is too small to hold the
    // incoming data length (ceiled to the packet length)
    const size_t len = _USBCeilToMaxPacketSize(arg.len);
    if (len > _STMRegionCapacity((void*)arg.addr)) {
        // Send preliminary status: error
        _System::USBSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _System::USBSendStatus(true);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Receive USB data
    _USB.recv(Endpoints::DataOut, (void*)arg.addr, len);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
    
    // Send final status
    _System::USBSendStatus(true);
}

static void _STMReset(const STM::Cmd& cmd) {
    _AppEntryPoint = (_VoidFn)cmd.arg.STMReset.entryPointAddr;
    
    // Send status
    _System::USBSendStatus(true);
    // Wait for host to receive status before resetting
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

static void _ICEQSPIWrite(const void* data, size_t len) {
    const QSPI_CommandTypeDef cmd = {
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
    
    _QSPI.write(cmd, data, len);
}

static void _ICEWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.ICEWrite;
    
    // Configure ICE40 control GPIOs
    _System::ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _System::ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _System::ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _System::ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Put ICE40 into configuration mode
    _System::ICE_ST_SPI_CLK::Write(1);
    
    _System::ICE_ST_SPI_CS_::Write(0);
    _System::ICE_CRST_::Write(0);
    _Scheduler::SleepMs<1>(); // Sleep 1 ms (ideally, 200 ns)
    
    _System::ICE_CRST_::Write(1);
    _Scheduler::SleepMs<2>(); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Release chip-select before we give control of _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_ to QSPI
    _System::ICE_ST_SPI_CS_::Write(1);
    
    // Have QSPI take over _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_
    _QSPI.config();
    
    // Send 8 clocks and wait for them to complete
    static const uint8_t ff = 0xff;
    _ICEQSPIWrite(&ff, 1);
    _Scheduler::Wait([] { return _QSPI.ready(); });
    
    // Reset state
    _Bufs.reset();
    
    size_t len = arg.len;
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(len);
    
    while (len) {
        // Wait until we have data to consume, and QSPI is ready to write
        _Scheduler::Wait([] { return !_Bufs.empty() && _QSPI.ready(); });
        
        // Write the data over QSPI and wait for completion
        _ICEQSPIWrite(_Bufs.front().data, _Bufs.front().len);
        _Scheduler::Wait([] { return _QSPI.ready(); });
        
        // Update the remaining data and pop the buffer so it can be used again
        len -= _Bufs.front().len;
        _Bufs.pop();
    }
    
    // Wait for CDONE to be asserted
    {
        bool ok = false;
        for (int i=0; i<10 && !ok; i++) {
            if (i) _Scheduler::SleepMs<1>(); // Sleep 1 ms
            ok = _System::ICE_CDONE::Read();
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
        // application in two ways:
        //   1. write 0xFF, which the user application must consider as a NOP;
        //   2. write a byte at a time, causing chip-select to be de-asserted
        //      between bytes, which must cause the user application to reset
        //      itself.
        constexpr uint8_t ClockCount = 7;
        static int i;
        for (i=0; i<ClockCount; i++) {
            _ICEQSPIWrite(&ff, sizeof(ff));
            _Scheduler::Wait([] { return _QSPI.ready(); });
        }
    }
    
    _System::USBSendStatus(true);
}

static void _MSPConnect(const STM::Cmd& cmd) {
    const auto r = _MSP.connect();
    // Send status
    _System::USBSendStatus(r == _MSP.Status::OK);
}

static void _MSPDisconnect(const STM::Cmd& cmd) {
    _MSP.disconnect();
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPRead(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPRead;
    
    // Reset state
    _Bufs.reset();
    
    // Start the USB DataIn task
    _TaskUSBDataIn::Start();
    
    uint32_t addr = arg.addr;
    uint32_t len = arg.len;
    while (len) {
        _Scheduler::Wait([] { return !_Bufs.full(); });
        
        auto& buf = _Bufs.back();
        // Prepare to receive either `len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        const size_t chunkLen = std::min((size_t)len, sizeof(buf.data));
        _MSP.read(addr, buf.data, chunkLen);
        addr += chunkLen;
        len -= chunkLen;
        // Enqueue the buffer
        buf.len = chunkLen;
        _Bufs.push();
    }
    
    // Wait for DataIn task to complete
    _Scheduler::Wait([] { return _Bufs.empty(); });
    // Send status
    _System::USBSendStatus(true);
}

static void _MSPWrite(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPWrite;
    
    // Reset state
    _Bufs.reset();
    _MSP.crcReset();
    
    uint32_t addr = arg.addr;
    uint32_t len = arg.len;
    
    // Trigger the USB DataOut task with the amount of data
    _TaskUSBDataOut::Start(len);
    
    while (len) {
        _Scheduler::Wait([] { return !_Bufs.empty(); });
        
        // Write the data over Spy-bi-wire
        auto& buf = _Bufs.front();
        _MSP.write(addr, buf.data, buf.len);
        // Update the MSP430 address to write to
        addr += buf.len;
        len -= buf.len;
        // Pop the buffer, which we just finished sending over Spy-bi-wire
        _Bufs.pop();
    }
    
    // Verify the CRC of all the data we wrote
    const auto r = _MSP.crcVerify();
    // Send status
    _System::USBSendStatus(r == _MSP.Status::OK);
}

struct _MSPDebugState {
    uint8_t bits = 0;
    uint8_t bitsLen = 0;
    size_t len = 0;
    bool ok = true;
};

static void _MSPDebugPushReadBits(_MSPDebugState& state, _BufQueue::Buf& buf) {
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

static void _MSPDebugHandleSBWIO(const MSPDebugCmd& cmd, _MSPDebugState& state, _BufQueue::Buf& buf) {
    const bool tdo = _MSP.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
    if (cmd.tdoReadGet()) {
        // Enqueue a new bit
        state.bits <<= 1;
        state.bits |= tdo;
        state.bitsLen++;
        
        // Enqueue the byte if it's filled
        if (state.bitsLen == 8) {
            _MSPDebugPushReadBits(state, buf);
        }
    }
}

static void _MSPDebugHandleCmd(const MSPDebugCmd& cmd, _MSPDebugState& state, _BufQueue::Buf& buf) {
    switch (cmd.opGet()) {
    case MSPDebugCmd::Ops::TestSet:     _MSP.debugTestSet(cmd.pinValGet());     break;
    case MSPDebugCmd::Ops::RstSet:      _MSP.debugRstSet(cmd.pinValGet()); 	    break;
    case MSPDebugCmd::Ops::TestPulse:   _MSP.debugTestPulse(); 				    break;
    case MSPDebugCmd::Ops::SBWIO:       _MSPDebugHandleSBWIO(cmd, state, buf);	break;
    default:                            abort();
    }
}

static void _MSPDebug(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPDebug;
    
    // Reset state
    _Bufs.reset();
    auto& bufIn = _Bufs.back();
    _Bufs.push();
    auto& bufOut = _Bufs.back();
    
    // Bail if more data was requested than the size of our buffer
    if (arg.respLen > sizeof(bufOut.data)) {
        // Send preliminary status: error
        _System::USBSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _System::USBSendStatus(true);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    _MSPDebugState state;
    
    // Handle debug commands
    {
        size_t cmdsLenRem = arg.cmdsLen;
        while (cmdsLenRem) {
            // Receive debug commands into buf
            _USB.recv(Endpoints::DataOut, bufIn.data, sizeof(bufIn.data));
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
            
            // Handle each MSPDebugCmd
            const MSPDebugCmd* cmds = (MSPDebugCmd*)bufIn.data;
            const size_t cmdsLen = _USB.recvLen(Endpoints::DataOut) / sizeof(MSPDebugCmd);
            for (size_t i=0; i<cmdsLen && state.ok; i++) {
                _MSPDebugHandleCmd(cmds[i], state, bufOut);
            }
            
            cmdsLenRem -= cmdsLen;
        }
    }
    
    // Reply with data generated from debug commands
    {
        // Push outstanding bits into the buffer
        // This is necessary for when the client reads a number of bits
        // that didn't fall on a byte boundary.
        if (state.bitsLen) _MSPDebugPushReadBits(state, bufOut);
        
        if (arg.respLen) {
            // Send the data and wait for it to be received
            _USB.send(Endpoints::DataIn, bufOut.data, arg.respLen);
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
        }
    }
    
    // Send status
    _System::USBSendStatus(state.ok);
}

static void _CmdHandle(const STM::Cmd& cmd) {
    switch (cmd.op) {
    // STM32 Bootloader
    case Op::STMWrite:              _STMWrite(cmd);                 break;
    case Op::STMReset:              _STMReset(cmd);                 break;
    // ICE40 Bootloader
    case Op::ICEWrite:              _ICEWrite(cmd);                 break;
    // MSP430 Bootloader
    case Op::MSPConnect:            _MSPConnect(cmd);               break;
    case Op::MSPDisconnect:         _MSPDisconnect(cmd);            break;
    // MSP430 Debug
    case Op::MSPRead:               _MSPRead(cmd);                  break;
    case Op::MSPWrite:              _MSPWrite(cmd);                 break;
    case Op::MSPDebug:              _MSPDebug(cmd);                 break;
    // Bad command
    default:                        _System::USBSendStatus(false);  break;
    }
}

// MARK: - ISRs

extern "C" [[gnu::section(".isr")]] void ISR_NMI()          {}
extern "C" [[gnu::section(".isr")]] void ISR_HardFault()    { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_MemManage()    { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_BusFault()     { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_UsageFault()   { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_SVC()          {}
extern "C" [[gnu::section(".isr")]] void ISR_DebugMon()     {}
extern "C" [[gnu::section(".isr")]] void ISR_PendSV()       {}

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

// MARK: - Main

static void _JumpToAppIfNeeded() {
    // Stash and reset `_AppEntryPoint` so that we only attempt to start the app once
    // after each software reset.
	const _VoidFn appEntryPoint = _AppEntryPoint;
    _AppEntryPoint = nullptr;
    
    // Cache RCC_CSR since we're about to clear it
    auto csr = READ_REG(RCC->CSR);
    // Clear RCC_CSR by setting the RMVF bit
    SET_BIT(RCC->CSR, RCC_CSR_RMVF);
    // Check if we reset due to a software reset (SFTRSTF), and
    // we have the app's vector table.
    if (READ_BIT(csr, RCC_CSR_SFTRSTF) && appEntryPoint) {
        // Start the application
        appEntryPoint();
        for (;;); // Loop forever if the app returns
    }
}

// MARK: - Abort

extern "C" [[noreturn]]
void abort() {
    _System::Abort();
}

int main() {
    _JumpToAppIfNeeded();
    
    _System::Init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    _USB.init();
    _QSPI.init();
    
    _Scheduler::Run();
    return 0;
}




#warning debug symbols
#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section
#include "stm32f7xx.h"
constexpr auto& _Tasks              = _Scheduler::_Tasks;
constexpr auto& _DidWork            = _Scheduler::_DidWork;
constexpr auto& _CurrentTask        = _Scheduler::_CurrentTask;
constexpr auto& _CurrentTime        = _Scheduler::_CurrentTime;
constexpr auto& _Wake               = _Scheduler::_Wake;
constexpr auto& _WakeTime           = _Scheduler::_WakeTime;
constexpr auto& _MainStackGuard     = _Scheduler::_MainStackGuard;
const auto& _SCB                    = *SCB;

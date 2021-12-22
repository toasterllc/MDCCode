#include <string.h>
#include <algorithm>
#define TaskARM32
#include "Toastbox/Task.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Toastbox/IntState.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "SystemBase.h"

using namespace STM;

// MARK: - Peripherals & Types
static USB _USB;

// QSPI clock divider=5 => run QSPI clock at 21.3 MHz
// QSPI alignment=byte, so we can transfer single bytes at a time
static QSPI<
    QSPIMode::Single,           // T_Mode
    5,                          // T_ClkDivider
    QSPIAlign::Byte,            // T_Align
    QSPIChipSelect::Controlled  // T_ChipSelect
> _QSPI;

constexpr auto& _MSP = SystemBase::MSP;

using _ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
using _ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
using _ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;

alignas(4) uint8_t _Buf0[1024]; // Aligned to send via USB
alignas(4) uint8_t _Buf1[1024]; // Aligned to send via USB
BufQueue<2> _Bufs(_Buf0, _Buf1);

// The Startup class needs to exist in the `uninit` section,
// so that its _appEntryPointAddr member doesn't get clobbered
// on startup.
using _VoidFn = void(*)();
static volatile _VoidFn _AppEntryPoint [[noreturn, gnu::section(".uninit")]] = 0;

static constexpr uint32_t _UsPerTick  = 1000;

class _TaskCmdRecv;
class _TaskCmdHandle;
class _TaskUSBDataOut;
class _TaskUSBDataIn;

#define _Subtasks       \
    _TaskCmdHandle,     \
    _TaskUSBDataOut,    \
    _TaskUSBDataIn

using _Scheduler = Toastbox::Scheduler<
    _UsPerTick, // T_UsPerTick
    #warning TODO: remove stack guards for production
    _StackMain, // T_MainStack
    4,          // T_StackGuardCount
    // Tasks
    _TaskCmdRecv,
    _Subtasks
>;

// _TaskUSBDataOut: reads `len` bytes from the DataOut endpoint and writes them to _Bufs
struct _TaskUSBDataOut {
    static void Start(size_t len);
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataOut")]]
    static inline uint8_t Stack[256];
};

// _TaskUSBDataIn: writes buffers from _Bufs to the DataIn endpoint, and pops them from _Bufs
struct _TaskUSBDataIn {
    static void Start();
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataIn")]]
    static inline uint8_t Stack[256];
};

// _TaskCmdHandle: handle _Cmd
struct _TaskCmdHandle {
    static void Handle(const STM::Cmd& c);
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._TaskCmdHandle")]]
    static inline uint8_t Stack[512];
};

// _TaskCmdRecv: receive commands over USB initiate handling them
struct _TaskCmdRecv {
    static void Run();
    
    // Task options
    using Options = Toastbox::TaskOptions<
        Toastbox::TaskOption::AutoStart<Run> // Task should start running
    >;
    
    // Task stack
    [[gnu::section(".stack._TaskCmdRecv")]]
    static inline uint8_t Stack[512];
};

// MARK: - Command Handlers

static size_t _USBCeilToMaxPacketSize(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%USB::MaxPacketSizeIn();
    len += (rem>0 ? USB::MaxPacketSizeIn()-rem : 0);
    return len;
}

static void _USBSendStatus(bool s) {
    alignas(4) static bool status = false; // Aligned to send via USB
    status = s;
    _USB.send(Endpoints::DataIn, &status, sizeof(status));
}

static void _StatusGet(const STM::Cmd& cmd) {
    // Send status
    _USBSendStatus(true);
    // Wait for host to receive status
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Send status struct
    alignas(4) static const STM::Status status = { // Aligned to send via USB
        .magic      = STM::Status::MagicNumber,
        .version    = STM::Version,
        .mode       = STM::Status::Modes::STMLoader,
    };
    
    _USB.send(Endpoints::DataIn, &status, sizeof(status));
}

static void _BootloaderInvoke(const STM::Cmd& cmd) {
    // Send status
    _USBSendStatus(true);
    // Wait for host to receive status before resetting
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

static void _LEDSet(const STM::Cmd& cmd) {
    switch (cmd.arg.LEDSet.idx) {
    case 0: _USBSendStatus(false); return;
    case 1: SystemBase::LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: SystemBase::LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: SystemBase::LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    // Send status
    _USBSendStatus(true);
}

static void _EndpointsFlush(const STM::Cmd& cmd) {
    // Reset endpoints
    _USB.endpointReset(Endpoints::DataOut);
    _USB.endpointReset(Endpoints::DataIn);
    // Wait until both endpoints are ready
    _Scheduler::Wait([] {
        return _USB.endpointReady(Endpoints::DataOut) &&
               _USB.endpointReady(Endpoints::DataIn);
    });
    // Send status
    _USBSendStatus(true);
}

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
    } else {
        // TODO: implement proper error handling on writing out of the allowed regions
        abort();
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
        _USBSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _USBSendStatus(true);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Receive USB data
    _USB.recv(Endpoints::DataOut, (void*)arg.addr, len);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
    
    // Send final status
    _USBSendStatus(true);
}

static void _STMReset(const STM::Cmd& cmd) {
    _AppEntryPoint = (_VoidFn)cmd.arg.STMReset.entryPointAddr;
    
    // Send status
    _USBSendStatus(true);
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
    _ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Put ICE40 into configuration mode
    _ICE_ST_SPI_CLK::Write(1);
    
    _ICE_ST_SPI_CS_::Write(0);
    _ICE_CRST_::Write(0);
    _Scheduler::SleepMs<1>(); // Sleep 1 ms (ideally, 200 ns)
    
    _ICE_CRST_::Write(1);
    _Scheduler::SleepMs<2>(); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Release chip-select before we give control of _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_ to QSPI
    _ICE_ST_SPI_CS_::Write(1);
    
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
            ok = _ICE_CDONE::Read();
        }
        
        if (!ok) {
            _USBSendStatus(false);
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
    
    _USBSendStatus(true);
}

static void _MSPConnect(const STM::Cmd& cmd) {
    const auto r = _MSP.connect();
    // Send status
    _USBSendStatus(r == _MSP.Status::OK);
}

static void _MSPDisconnect(const STM::Cmd& cmd) {
    _MSP.disconnect();
    // Send status
    _USBSendStatus(true);
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
        const size_t chunkLen = std::min((size_t)len, buf.cap);
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
    _USBSendStatus(true);
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
    _USBSendStatus(r == _MSP.Status::OK);
}

struct _MSPDebugState {
    uint8_t bits = 0;
    uint8_t bitsLen = 0;
    size_t len = 0;
    bool ok = true;
};

static void _MSPDebugPushReadBits(_MSPDebugState& state) {
    if (state.len >= sizeof(_Buf1)) {
        state.ok = false;
        return;
    }
    
    // Enqueue the new byte into `_Buf1`
    _Buf1[state.len] = state.bits;
    state.len++;
    // Reset our bits
    state.bits = 0;
    state.bitsLen = 0;
}

static void _MSPDebugHandleSBWIO(const MSPDebugCmd& cmd, _MSPDebugState& state) {
    const bool tdo = _MSP.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
    if (cmd.tdoReadGet()) {
        // Enqueue a new bit
        state.bits <<= 1;
        state.bits |= tdo;
        state.bitsLen++;
        
        // Enqueue the byte if it's filled
        if (state.bitsLen == 8) {
            _MSPDebugPushReadBits(state);
        }
    }
}

static void _MSPDebugHandleCmd(const MSPDebugCmd& cmd, _MSPDebugState& state) {
    switch (cmd.opGet()) {
    case MSPDebugCmd::Ops::TestSet:     _MSP.debugTestSet(cmd.pinValGet()); break;
    case MSPDebugCmd::Ops::RstSet:      _MSP.debugRstSet(cmd.pinValGet()); 	break;
    case MSPDebugCmd::Ops::TestPulse:   _MSP.debugTestPulse(); 				break;
    case MSPDebugCmd::Ops::SBWIO:       _MSPDebugHandleSBWIO(cmd, state);	break;
    default:                            abort();
    }
}

static void _MSPDebug(const STM::Cmd& cmd) {
    auto& arg = cmd.arg.MSPDebug;
    
    // Bail if more data was requested than the size of our buffer
    if (arg.respLen > sizeof(_Buf1)) {
        // Send preliminary status: error
        _USBSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _USBSendStatus(true);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    _MSPDebugState state;
    
    // Handle debug commands
    {
        size_t cmdsLenRem = arg.cmdsLen;
        while (cmdsLenRem) {
            // Receive debug commands into _Buf0
            _USB.recv(Endpoints::DataOut, _Buf0, sizeof(_Buf0));
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
            
            // Handle each MSPDebugCmd
            const MSPDebugCmd* cmds = (MSPDebugCmd*)_Buf0;
            const size_t cmdsLen = _USB.recvLen(Endpoints::DataOut) / sizeof(MSPDebugCmd);
            for (size_t i=0; i<cmdsLen && state.ok; i++) {
                _MSPDebugHandleCmd(cmds[i], state);
            }
            
            cmdsLenRem -= cmdsLen;
        }
    }
    
    // Reply with data generated from debug commands
    {
        // Push outstanding bits into the buffer
        // This is necessary for when the client reads a number of bits
        // that didn't fall on a byte boundary.
        if (state.bitsLen) _MSPDebugPushReadBits(state);
        
        if (arg.respLen) {
            // Send the data and wait for it to be received
            _USB.send(Endpoints::DataIn, _Buf1, arg.respLen);
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
        }
    }
    
    // Send status
    _USBSendStatus(state.ok);
}

// MARK: - Tasks

template <typename... T_Tasks>
static void _TasksReset() {
    (_Scheduler::Stop<T_Tasks>(), ...);
}

void _TaskCmdRecv::Run() {
    for (;;) {
        // Wait for USB to be re-connected (`Connecting` state) so we can call _USB.connect(),
        // or for a new command to arrive so we can handle it.
        _Scheduler::Wait([&] { return _USB.state()==USB::State::Connecting || _USB.cmdRecv(); });
        
        #warning TODO: do we still need to disable interrupts?
        // Disable interrupts so we can inspect+modify _usb atomically
        Toastbox::IntState ints(false);
        
        // Reset all tasks
        // This needs to happen before we call `_USB.connect()` so that any tasks that
        // were running in the previous USB session are stopped before we enable
        // USB again by calling _USB.connect().
        _TasksReset<_Subtasks>();
        
        switch (_USB.state()) {
        case USB::State::Connecting:
            _USB.connect();
            continue;
        case USB::State::Connected:
            if (!_USB.cmdRecv()) continue;
            break;
        default:
            continue;
        }
        
        auto usbCmd = *_USB.cmdRecv();
        
        // Re-enable interrupts while we handle the command
        ints.restore();
        
        // Reject command if the length isn't valid
        STM::Cmd cmd;
        if (usbCmd.len != sizeof(cmd)) {
            _USB.cmdAccept(false);
            continue;
        }
        
        memcpy(&cmd, usbCmd.data, usbCmd.len);
        
        // Only accept command if it's a flush command (in which case the endpoints
        // don't need to be ready), or it's not a flush command, but both endpoints
        // are ready. Otherwise, reject the command.
        if (!(cmd.op==Op::EndpointsFlush || (_USB.endpointReady(Endpoints::DataOut) && _USB.endpointReady(Endpoints::DataIn)))) {
            _USB.cmdAccept(false);
            continue;
        }
        
        _USB.cmdAccept(true);
        _TaskCmdHandle::Handle(cmd);
    }
}

void _TaskCmdHandle::Handle(const STM::Cmd& c) {
    static STM::Cmd cmd = {};
    cmd = c;
    
    _Scheduler::Start<_TaskCmdHandle>([] {
        switch (cmd.op) {
        // Common Commands
        case Op::EndpointsFlush:        _EndpointsFlush(cmd);           break;
        case Op::StatusGet:             _StatusGet(cmd);                break;
        case Op::BootloaderInvoke:      _BootloaderInvoke(cmd);         break;
        case Op::LEDSet:                _LEDSet(cmd);                   break;
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
        default:                        _USBSendStatus(false);          break;
        }
    });
}

void _TaskUSBDataOut::Start(size_t l) {
    // Make sure this task isn't busy
    Assert(!_Scheduler::Running<_TaskUSBDataOut>());
    
    static size_t len = 0;
    len = l;
    _Scheduler::Start<_TaskUSBDataOut>([] {
        while (len) {
            _Scheduler::Wait([] { return !_Bufs.full(); });
            
            // Prepare to receive either `len` bytes or the
            // buffer capacity bytes, whichever is smaller.
            const size_t cap = _USBCeilToMaxPacketSize(std::min(len, _Bufs.back().cap));
            // Ensure that after rounding up to the nearest packet size, we don't
            // exceed the buffer capacity. (This should always be safe as long as
            // the buffer capacity is a multiple of the max packet size.)
            Assert(cap <= _Bufs.back().cap);
            _USB.recv(Endpoints::DataOut, _Bufs.back().data, cap);
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
            
            // Never claim that we read more than the requested data, even if ceiling
            // to the max packet size caused us to read more than requested.
            const size_t recvLen = std::min(len, _USB.recvLen(Endpoints::DataOut));
            len -= recvLen;
            _Bufs.back().len = recvLen;
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

// MARK: - IntState

bool Toastbox::IntState::InterruptsEnabled() {
    return !__get_PRIMASK();
}

void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __enable_irq();
    else __disable_irq();
}

void Toastbox::IntState::WaitForInterrupt() {
    Toastbox::IntState ints(true);
    __WFI();
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

int main() {
    _JumpToAppIfNeeded();
    
    SystemBase::Init();
    
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

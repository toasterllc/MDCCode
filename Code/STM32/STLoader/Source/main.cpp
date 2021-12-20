#include <string.h>
#include <algorithm>

#define TaskARM32
#include "Toastbox/Task.h"

#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"
#include "Toastbox/IntState.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "SystemBase.h"

using namespace STM;





// Peripherals
USB _USB;

// QSPI clock divider=5 => run QSPI clock at 21.3 MHz
// QSPI alignment=byte, so we can transfer single bytes at a time
QSPI _QSPI(QSPI::Mode::Single, 5, QSPI::Align::Byte, QSPI::ChipSelect::Controlled);

using _ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
using _ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
using _ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;

STM::Cmd _Cmd = {};

alignas(4) uint8_t _Buf0[1024]; // Aligned to send via USB
alignas(4) uint8_t _Buf1[1024]; // Aligned to send via USB
BufQueue<2> _Bufs(_Buf0, _Buf1);

struct {
    size_t len = 0;
    alignas(4) bool status = false; // Aligned to send via USB
} _USBDataIn;

struct {
    struct {
        uint8_t bits = 0;
        uint8_t bitsLen = 0;
        size_t len = 0;
    } read;
} _MSPDebug;

static constexpr uint32_t _UsPerTick  = 1000;

class _CmdTask;
class _USBDataOutTask;
class _AsyncTask;

#define _Subtasks       \
    _USBDataOutTask,    \
    _AsyncTask

using _Scheduler = Toastbox::Scheduler<
    // Microseconds per tick
    _UsPerTick,
    // Tasks
    _CmdTask,
    _Subtasks
>;

#warning debug symbols
#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section

constexpr auto& _DidWork            = _Scheduler::_DidWork;
constexpr auto& _CurrentTask        = _Scheduler::_CurrentTask;
constexpr auto& _SP                 = _Scheduler::_SP;
constexpr auto& _CurrentTime        = _Scheduler::_CurrentTime;
constexpr auto& _Wake               = _Scheduler::_Wake;
constexpr auto& _WakeTime           = _Scheduler::_WakeTime;

//Toastbox::Task _usb_cmdTask             = Toastbox::Task([&] {  _usb_cmdTaskFn();           });
//Toastbox::Task _usb_dataOutTask         = Toastbox::Task([&] {  _usb_dataOutTaskFn();       });
//Toastbox::Task _usb_dataInTask          = Toastbox::Task([&] {  _usb_dataInTaskFn();        });
//Toastbox::Task _endpointsFlush_task     = Toastbox::Task([&] {  _endpointsFlush_taskFn();   });
//Toastbox::Task _statusGet_task          = Toastbox::Task([&] {  _statusGet_taskFn();        });
//Toastbox::Task _bootloaderInvoke_task   = Toastbox::Task([&] {  _bootloaderInvoke_taskFn(); });
//Toastbox::Task _stm_writeTask           = Toastbox::Task([&] {  _stm_writeTaskFn();         });
//Toastbox::Task _stm_resetTask           = Toastbox::Task([&] {  _stm_resetTaskFn();         });
//Toastbox::Task _ice_writeTask           = Toastbox::Task([&] {  _ice_writeTaskFn();         });
//Toastbox::Task _msp_readTask            = Toastbox::Task([&] {  _msp_readTaskFn();          });
//Toastbox::Task _msp_writeTask           = Toastbox::Task([&] {  _msp_writeTaskFn();         });
//Toastbox::Task _msp_debugTask           = Toastbox::Task([&] {  _msp_debugTaskFn();         });
//
//std::reference_wrapper<Toastbox::Task> _tasks[12] = {
//    _usb_cmdTask,
//    _usb_dataOutTask,
//    _usb_dataInTask,
//    _endpointsFlush_task,
//    _statusGet_task,
//    _bootloaderInvoke_task,
//    _stm_writeTask,
//    _stm_resetTask,
//    _ice_writeTask,
//    _msp_readTask,
//    _msp_writeTask,
//    _msp_debugTask,
//};



























template <typename... T_Tasks>
static void _ResetTasks() {
    (_Scheduler::Stop<T_Tasks>(), ...);
}


//void _ResetTasks() {
//    #warning how can we iterate over every task?
//    _Scheduler::Stop<_USBDataOutTask>();
//    _Scheduler::Stop<_AsyncTask>();
////    _Scheduler::Stop<>();
//}

static size_t _ceilToMaxPacketSize(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%USB::MaxPacketSizeIn();
    len += (rem>0 ? USB::MaxPacketSizeIn()-rem : 0);
    return len;
}

// _usb_dataOutTask: reads `_usbDataOut.len` bytes from the DataOut endpoint and writes it to _Bufs
struct _USBDataOutTask {
    static void Recv(size_t len) {
        // Make sure this task isn't busy
        Assert(!_Scheduler::Running<_USBDataOutTask>());
        
        _Len = len;
        _Scheduler::Start<_USBDataOutTask>([] {
            while (_Len) {
                _Scheduler::Wait([] { return !_Bufs.full(); });
                
                // Prepare to receive either `_Len` bytes or the
                // buffer capacity bytes, whichever is smaller.
                const size_t cap = _ceilToMaxPacketSize(std::min(_Len, _Bufs.back().cap));
                // Ensure that after rounding up to the nearest packet size, we don't
                // exceed the buffer capacity. (This should always be safe as long as
                // the buffer capacity is a multiple of the max packet size.)
                Assert(cap <= _Bufs.back().cap);
                _USB.recv(Endpoints::DataOut, _Bufs.back().data, cap);
                _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
                
                // Never claim that we read more than the requested data, even if ceiling
                // to the max packet size caused us to read more than requested.
                const size_t recvLen = std::min(_Len, _USB.recvLen(Endpoints::DataOut));
                _Len -= recvLen;
                _Bufs.back().len = recvLen;
                _Bufs.push();
            }
        });
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._USBDataOutTask")]]
    static inline uint8_t Stack[128];
    
private:
    static inline size_t _Len = 0;
};

static void _usb_dataInSendStatus(bool s) {
    alignas(4) static bool status = false; // Aligned to send via USB
    status = s;
    _USB.send(Endpoints::DataIn, &status, sizeof(status));
}




//// _usb_dataInTask: writes buffers from _Bufs to the DataIn endpoint, and pops them from _Bufs
//void _usb_dataInTaskFn() {
//    TaskBegin();
//    
//    for (;;) {
//        TaskWait(!_Bufs.empty());
//        
//        // Send the data and wait until the transfer is complete
//        _USB.send(Endpoints::DataIn, _Bufs.front().data, _Bufs.front().len);
//        TaskWait(_USB.endpointReady(Endpoints::DataIn));
//        
//        _Bufs.front().len = 0;
//        _Bufs.pop();
//    }
//}
//
//void _usb_dataInSendStatus(bool status) {
//    _usbDataIn.status = status;
//    _USB.send(Endpoints::DataIn, &_usbDataIn.status, sizeof(_usbDataIn.status));
//}
//
//void _endpointsFlush_taskFn() {
//    TaskBegin();
//    // Reset endpoints
//    _USB.endpointReset(Endpoints::DataOut);
//    _USB.endpointReset(Endpoints::DataIn);
//    TaskWait(_USB.endpointReady(Endpoints::DataOut) && _USB.endpointReady(Endpoints::DataIn));
//    // Send status
//    _usb_dataInSendStatus(true);
//}
//
//void _statusGet_taskFn() {
//    TaskBegin();
//    // Send status
//    _usb_dataInSendStatus(true);
//    // Wait for host to receive status
//    TaskWait(_USB.endpointReady(Endpoints::DataIn));
//    
//    // Send status struct
//    alignas(4) static const STM::Status status = { // Aligned to send via USB
//        .magic      = STM::Status::MagicNumber,
//        .version    = STM::Version,
//        .mode       = STM::Status::Modes::STMLoader,
//    };
//    
//    _USB.send(Endpoints::DataIn, &status, sizeof(status));
//}
//
//void _bootloaderInvoke_taskFn() {
//    TaskBegin();
//    // Send status
//    _usb_dataInSendStatus(true);
//    // Wait for host to receive status before resetting
//    TaskWait(_USB.endpointReady(Endpoints::DataIn));
//    
//    // Perform software reset
//    HAL_NVIC_SystemReset();
//    // Unreachable
//    abort();
//}

//static size_t _stm_regionCapacity(void* addr) {
//    // Verify that `addr` is in one of the allowed RAM regions
//    extern uint8_t _sitcm_ram[], _eitcm_ram[];
//    extern uint8_t _sdtcm_ram[], _edtcm_ram[];
//    extern uint8_t _ssram1[], _esram1[];
//    size_t cap = 0;
//    if (addr>=_sitcm_ram && addr<_eitcm_ram) {
//        cap = (uintptr_t)_eitcm_ram-(uintptr_t)addr;
//    } else if (addr>=_sdtcm_ram && addr<_edtcm_ram) {
//        cap = (uintptr_t)_edtcm_ram-(uintptr_t)addr;
//    } else if (addr>=_ssram1 && addr<_esram1) {
//        cap = (uintptr_t)_esram1-(uintptr_t)addr;
//    } else {
//        // TODO: implement proper error handling on writing out of the allowed regions
//        abort();
//    }
//    return cap;
//}
//
//void _stm_writeTaskFn() {
//    const auto& arg = _Cmd.arg.STMWrite;
//    
//    TaskBegin();
//    
//    // Bail if the region capacity is too small to hold the
//    // incoming data length (ceiled to the packet length)
//    static size_t len;
//    len = _ceilToMaxPacketSize(arg.len);
//    if (len > _stm_regionCapacity((void*)arg.addr)) {
//        // Send preliminary status: error
//        _usb_dataInSendStatus(false);
//        return;
//    }
//    
//    // Send preliminary status: OK
//    _usb_dataInSendStatus(true);
//    TaskWait(_USB.endpointReady(Endpoints::DataIn));
//    
//    // Receive USB data
//    _USB.recv(Endpoints::DataOut, (void*)arg.addr, len);
//    TaskWait(_USB.endpointReady(Endpoints::DataOut));
//    
//    // Send final status
//    _usb_dataInSendStatus(true);
//}
//
//void _stm_resetTaskFn() {
//    TaskBegin();
//    Start.setAppEntryPointAddr(_Cmd.arg.STMReset.entryPointAddr);
//    
//    // Send status
//    _usb_dataInSendStatus(true);
//    // Wait for host to receive status before resetting
//    TaskWait(_USB.endpointReady(Endpoints::DataIn));
//    
//    // Perform software reset
//    HAL_NVIC_SystemReset();
//    // Unreachable
//    abort();
//}
//
//static void _ice_qspiWrite(QSPI& qspi, const void* data, size_t len) {
//    QSPI_CommandTypeDef cmd = {
//        .Instruction = 0,
//        .InstructionMode = QSPI_INSTRUCTION_NONE,
//        
//        .Address = 0,
//        .AddressSize = QSPI_ADDRESS_8_BITS,
//        .AddressMode = QSPI_ADDRESS_NONE,
//        
//        .AlternateBytes = 0,
//        .AlternateBytesSize = QSPI_ALTERNATE_BYTES_8_BITS,
//        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
//        
//        .DummyCycles = 0,
//        
//        .NbData = (uint32_t)len,
//        .DataMode = QSPI_DATA_1_LINE,
//        
//        .DdrMode = QSPI_DDR_MODE_DISABLE,
//        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
//        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
//    };
//    
//    qspi.write(cmd, data, len);
//}
//
//void _ice_writeTaskFn() {
//    auto& arg = _Cmd.arg.ICEWrite;
//    TaskBegin();
//    
//    // Configure ICE40 control GPIOs
//    _ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    _ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    _ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    
//    // Put ICE40 into configuration mode
//    _ICE_ST_SPI_CLK::Write(1);
//    
//    _ICE_ST_SPI_CS_::Write(0);
//    _ICE_CRST_::Write(0);
//    HAL_Delay(1); // Sleep 1 ms (ideally, 200 ns)
//    
//    _ICE_CRST_::Write(1);
//    HAL_Delay(2); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
//    
//    // Release chip-select before we give control of _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_ to QSPI
//    _ICE_ST_SPI_CS_::Write(1);
//    
//    // Have QSPI take over _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_
//    _qspi.config();
//    
//    // Send 8 clocks and wait for them to complete
//    static const uint8_t ff = 0xff;
//    _ice_qspiWrite(_qspi, &ff, 1);
//    TaskWait(_qspi.ready());
//    
//    // Reset state
//    _Bufs.reset();
//    // Trigger the USB DataOut task with the amount of data
//    _usb_dataOutTask.start();
//    _usbDataOut.len = arg.len;
//    
//    while (arg.len) {
//        // Wait until we have data to consume, and QSPI is ready to write
//        TaskWait(!_Bufs.empty() && _qspi.ready());
//        
//        // Write the data over QSPI and wait for completion
//        _ice_qspiWrite(_qspi, _Bufs.front().data, _Bufs.front().len);
//        TaskWait(_qspi.ready());
//        
//        // Update the remaining data and pop the buffer so it can be used again
//        arg.len -= _Bufs.front().len;
//        _Bufs.pop();
//    }
//    
//    // Wait for CDONE to be asserted
//    {
//        bool ok = false;
//        for (int i=0; i<10 && !ok; i++) {
//            if (i) HAL_Delay(1); // Sleep 1 ms
//            ok = _ICE_CDONE::Read();
//        }
//        
//        if (!ok) {
//            _usb_dataInSendStatus(false);
//            return;
//        }
//    }
//    
//    // Finish
//    {
//        // Supply >=49 additional clocks (8*7=56 clocks), per the
//        // "iCE40 Programming and Configuration" guide.
//        // These clocks apparently reach the user application. Since this
//        // appears unavoidable, prevent the clocks from affecting the user
//        // application in two ways:
//        //   1. write 0xFF, which the user application must consider as a NOP;
//        //   2. write a byte at a time, causing chip-select to be de-asserted
//        //      between bytes, which must cause the user application to reset
//        //      itself.
//        constexpr uint8_t ClockCount = 7;
//        static int i;
//        for (i=0; i<ClockCount; i++) {
//            static const uint8_t ff = 0xff;
//            _ice_qspiWrite(_qspi, &ff, sizeof(ff));
//            TaskWait(_qspi.ready());
//        }
//    }
//    
//    _usb_dataInSendStatus(true);
//}
//
//void _msp_connect() {
//    const auto r = _MSP.connect();
//    // Send status
//    _usb_dataInSendStatus(r == _MSP.Status::OK);
//}
//
//void _msp_disconnect() {
//    _MSP.disconnect();
//    // Send status
//    _usb_dataInSendStatus(true);
//}
//
//void _msp_readTaskFn() {
//    auto& arg = _Cmd.arg.MSPRead;
//    TaskBegin();
//    
//    // Reset state
//    _Bufs.reset();
//    
//    // Start the USB DataIn task
//    _usb_dataInTask.start();
//    
//    while (arg.len) {
//        TaskWait(!_Bufs.full());
//        
//        auto& buf = _Bufs.back();
//        // Prepare to receive either `arg.len` bytes or the
//        // buffer capacity bytes, whichever is smaller.
//        const size_t chunkLen = std::min((size_t)arg.len, buf.cap);
//        _MSP.read(arg.addr, buf.data, chunkLen);
//        arg.addr += chunkLen;
//        arg.len -= chunkLen;
//        // Enqueue the buffer
//        buf.len = chunkLen;
//        _Bufs.push();
//    }
//    
//    // Wait for DataIn task to complete
//    TaskWait(_Bufs.empty());
//    // Send status
//    _usb_dataInSendStatus(true);
//}
//
//void _msp_writeTaskFn() {
//    auto& arg = _Cmd.arg.MSPWrite;
//    TaskBegin();
//    
//    // Reset state
//    _Bufs.reset();
//    _MSP.crcReset();
//    
//    // Trigger the USB DataOut task with the amount of data
//    _usb_dataOutTask.start();
//    _usbDataOut.len = arg.len;
//    
//    while (arg.len) {
//        TaskWait(!_Bufs.empty());
//        
//        // Write the data over Spy-bi-wire
//        auto& buf = _Bufs.front();
//        _MSP.write(arg.addr, buf.data, buf.len);
//        // Update the MSP430 address to write to
//        arg.addr += buf.len;
//        arg.len -= buf.len;
//        // Pop the buffer, which we just finished sending over Spy-bi-wire
//        _Bufs.pop();
//    }
//    
//    // Verify the CRC of all the data we wrote
//    const auto r = _MSP.crcVerify();
//    // Send status
//    _usb_dataInSendStatus(r == _MSP.Status::OK);
//}
//
//void _msp_debugTaskFn() {
//    auto& arg = _Cmd.arg.MSPDebug;
//    TaskBegin();
//    
//    // Bail if more data was requested than the size of our buffer
//    if (arg.respLen > sizeof(_buf1)) {
//        // Send preliminary status: error
//        _usb_dataInSendStatus(false);
//        return;
//    }
//    
//    // Send preliminary status: OK
//    _usb_dataInSendStatus(true);
//    TaskWait(_USB.endpointReady(Endpoints::DataIn));
//    
//    static bool ok;
//    ok = true;
//    
//    // Handle debug commands
//    {
//        while (arg.cmdsLen) {
//            // Receive debug commands into _buf0
//            _USB.recv(Endpoints::DataOut, _buf0, sizeof(_buf0));
//            TaskWait(_USB.endpointReady(Endpoints::DataOut));
//            
//            // Handle each MSPDebugCmd
//            const MSPDebugCmd* cmds = (MSPDebugCmd*)_buf0;
//            const size_t cmdsLen = _USB.recvLen(Endpoints::DataOut) / sizeof(MSPDebugCmd);
//            for (size_t i=0; i<cmdsLen && ok; i++) {
//                ok &= _msp_debugHandleCmd(cmds[i]);
//            }
//            
//            arg.cmdsLen -= cmdsLen;
//        }
//    }
//    
//    // Reply with data generated from debug commands
//    {
//        // Push outstanding bits into the buffer
//        // This is necessary for when the client reads a number of bits
//        // that didn't fall on a byte boundary.
//        if (_mspDebug.read.bitsLen) ok &= _msp_debugPushReadBits();
//        _mspDebug.read = {};
//        
//        if (arg.respLen) {
//            // Send the data and wait for it to be received
//            _USB.send(Endpoints::DataIn, _buf1, arg.respLen);
//            TaskWait(_USB.endpointReady(Endpoints::DataIn));
//        }
//    }
//    
//    // Send status
//    _usb_dataInSendStatus(ok);
//}
//
//bool _msp_debugPushReadBits() {
//    if (_mspDebug.read.len >= sizeof(_buf1)) return false;
//    // Enqueue the new byte into `_buf1`
//    _buf1[_mspDebug.read.len] = _mspDebug.read.bits;
//    _mspDebug.read.len++;
//    // Reset our bits
//    _mspDebug.read.bits = 0;
//    _mspDebug.read.bitsLen = 0;
//    return true;
//}
//
//bool _msp_debugHandleSBWIO(const MSPDebugCmd& cmd) {
//    const bool tdo = _MSP.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
//    if (cmd.tdoReadGet()) {
//        // Enqueue a new bit
//        _mspDebug.read.bits <<= 1;
//        _mspDebug.read.bits |= tdo;
//        _mspDebug.read.bitsLen++;
//        
//        // Enqueue the byte if it's filled
//        if (_mspDebug.read.bitsLen == 8) {
//            return _msp_debugPushReadBits();
//        }
//    }
//    return true;
//}
//
//bool _msp_debugHandleCmd(const MSPDebugCmd& cmd) {
//    switch (cmd.opGet()) {
//    case MSPDebugCmd::Ops::TestSet:     _MSP.debugTestSet(cmd.pinValGet()); return true;
//    case MSPDebugCmd::Ops::RstSet:      _MSP.debugRstSet(cmd.pinValGet());  return true;
//    case MSPDebugCmd::Ops::TestPulse:   _MSP.debugTestPulse();              return true;
//    case MSPDebugCmd::Ops::SBWIO:       return _msp_debugHandleSBWIO(cmd);
//    default:                            abort();
//    }
//}

static void _ledSet() {
    switch (_Cmd.arg.LEDSet.idx) {
    case 0: _usb_dataInSendStatus(false); return;
    case 1: SystemBase::LED1::Write(_Cmd.arg.LEDSet.on); break;
    case 2: SystemBase::LED2::Write(_Cmd.arg.LEDSet.on); break;
    case 3: SystemBase::LED3::Write(_Cmd.arg.LEDSet.on); break;
    }
    
    // Send status
    _usb_dataInSendStatus(true);
}

struct _AsyncTask {
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._AsyncTask")]]
    static inline uint8_t Stack[128];
};

static void _endpointsFlush() {
    _Scheduler::Start<_AsyncTask>([] {
        // Reset endpoints
        _USB.endpointReset(Endpoints::DataOut);
        _USB.endpointReset(Endpoints::DataIn);
        // Wait until both endpoints are ready
        _Scheduler::Wait([&] {
            return _USB.endpointReady(Endpoints::DataOut) &&
                   _USB.endpointReady(Endpoints::DataIn);
        });
        // Send status
        _usb_dataInSendStatus(true);
    });
}

struct _CmdTask {
    static void Run() {
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
            _ResetTasks<_Subtasks>();
            
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
            if (usbCmd.len != sizeof(_Cmd)) {
                _USB.cmdAccept(false);
                continue;
            }
            
            memcpy(&_Cmd, usbCmd.data, usbCmd.len);
            
            // Specially handle the EndpointsFlush command -- it's the only command that doesn't
            // require the endpoints to be ready.
            if (_Cmd.op == Op::EndpointsFlush) {
                _USB.cmdAccept(true);
                _endpointsFlush();
                continue;
            }
            
            // Reject command if the endpoints aren't ready
            if (!_USB.endpointReady(Endpoints::DataOut) || !_USB.endpointReady(Endpoints::DataIn)) {
                _USB.cmdAccept(false);
                continue;
            }
            
            _USB.cmdAccept(true);
            
            switch (_Cmd.op) {
            // Common Commands
//            case Op::StatusGet:         _statusGet_task.start();        break;
//            case Op::BootloaderInvoke:  _bootloaderInvoke_task.start(); break;
            case Op::LEDSet:            _ledSet();                      break;
//            // STM32 Bootloader
//            case Op::STMWrite:          _stm_writeTask.start();         break;
//            case Op::STMReset:          _stm_resetTask.start();         break;
//            // ICE40 Bootloader
//            case Op::ICEWrite:          _ice_writeTask.start();         break;
//            // MSP430 Bootloader
//            case Op::MSPConnect:        _msp_connect();                 break;
//            case Op::MSPDisconnect:     _msp_disconnect();              break;
//            // MSP430 Debug
//            case Op::MSPRead:           _msp_readTask.start();          break;
//            case Op::MSPWrite:          _msp_writeTask.start();         break;
//            case Op::MSPDebug:          _msp_debugTask.start();         break;
            // Bad command
            default:                    _usb_dataInSendStatus(false);   break;
            }
        }
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<
        Toastbox::TaskOption::AutoStart<Run> // Task should start running
    >;
    
    // Task stack
    [[gnu::section(".stack._CmdTask")]]
    static inline uint8_t Stack[128];
};










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


// MARK: - Main

int main() {
    SystemBase::Init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    _USB.init();
    _QSPI.init();
    
    abort();
    _Scheduler::Run();
    
    return 0;
}

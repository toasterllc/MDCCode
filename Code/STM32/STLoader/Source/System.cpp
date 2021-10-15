#include "System.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>
#include <algorithm>

using namespace STM;

#pragma mark - System

System::System() :
// QSPI clock divider=5 => run QSPI clock at 21.3 MHz
// QSPI alignment=byte, so we can transfer single bytes at a time
_qspi(QSPI::Mode::Single, 5, QSPI::Align::Byte, QSPI::ChipSelect::Controlled),
_bufs(_buf0, _buf1)
{}

void System::init() {
    _super::init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    _usb.init();
    _qspi.init();
    
    _resetTasks();
}

void System::run() {
    Task::Run(_tasks);
}

void System::_resetTasks() {
    for (Task& t : _tasks) {
        if (&t == &_usb_cmdTask) continue; // Never pause the USB command task
        t.pause();
    }
}

#pragma mark - USB

void System::_usb_cmdTaskFn() {
    TaskBegin();
    for (;;) {
        auto usbCmd = *TaskWait(_usb.cmdRecv());
        
        // Reject command if the length isn't valid
        if (usbCmd.len != sizeof(_cmd)) {
            _usb.cmdAccept(false);
            continue;
        }
        
        memcpy(&_cmd, usbCmd.data, usbCmd.len);
        
        // Stop all tasks
        _resetTasks();
        
        // Specially handle the EndpointsFlush command -- it's the only command that doesn't
        // require the endpoints to be ready.
        if (_cmd.op == Op::EndpointsFlush) {
            _usb.cmdAccept(true);
            _endpointsFlush_task.start();
            continue;
        }
        
        // Reject command if the endpoints aren't ready
        if (!_usb.ready(Endpoints::DataOut) || !_usb.ready(Endpoints::DataIn)) {
            _usb.cmdAccept(false);
            continue;
        }
        
        _usb.cmdAccept(true);
        
        switch (_cmd.op) {
        // Set LED
        case Op::BootloaderInvoke:  _bootloaderInvoke_task.start(); break;
        case Op::LEDSet:            _ledSet();                      break;
        // STM32 Bootloader
        case Op::STMWrite:          _stm_writeTask.start();         break;
        case Op::STMReset:          _stm_resetTask.start();         break;
        // ICE40 Bootloader
        case Op::ICEWrite:          _ice_writeTask.start();         break;
        // MSP430 Bootloader
        case Op::MSPConnect:        _msp_connect();                 break;
        case Op::MSPDisconnect:     _msp_disconnect();              break;
        // MSP430 Debug
        case Op::MSPRead:           _msp_readTask.start();          break;
        case Op::MSPWrite:          _msp_writeTask.start();         break;
        case Op::MSPDebug:          _msp_debugTask.start();         break;
        // Bad command
        default:                    _usb_dataInSendStatus(false);   break;
        }
    }
}

static size_t _ceilToMaxPacketSize(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%USB::MaxPacketSizeIn();
    len += (rem>0 ? USB::MaxPacketSizeIn()-rem : 0);
    return len;
}

// _usb_dataOutTask: reads `_usbDataOut.len` bytes from the DataOut endpoint and writes it to _bufs
void System::_usb_dataOutTaskFn() {
    auto& s = _usbDataOut;
    
    TaskBegin();
    
    while (s.len) {
        TaskWait(!_bufs.full());
        
        // Prepare to receive either `s.len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        static size_t cap;
        cap = _ceilToMaxPacketSize(std::min(s.len, _bufs.back().cap));
        // Ensure that after rounding up to the nearest packet size, we don't
        // exceed the buffer capacity. (This should always be safe as long as
        // the buffer capacity is a multiple of the max packet size.)
        Assert(cap <= _bufs.back().cap);
        _usb.recv(Endpoints::DataOut, _bufs.back().data, cap);
        TaskWait(_usb.ready(Endpoints::DataOut));
        
        // Never claim that we read more than the requested data, even if ceiling
        // to the max packet size caused us to read more than requested.
        const size_t recvLen = std::min(s.len, _usb.recvLen(Endpoints::DataOut));
        s.len -= recvLen;
        _bufs.back().len = recvLen;
        _bufs.push();
    }
}

// _usb_dataInTask: writes buffers from _bufs to the DataIn endpoint, and pops them from _bufs
void System::_usb_dataInTaskFn() {
    TaskBegin();
    
    for (;;) {
        TaskWait(!_bufs.empty());
        
        // Send the data and wait until the transfer is complete
        _usb.send(Endpoints::DataIn, _bufs.front().data, _bufs.front().len);
        TaskWait(_usb.ready(Endpoints::DataIn));
        
        _bufs.front().len = 0;
        _bufs.pop();
    }
}

void System::_usb_dataInSendStatus(bool status) {
    _usbDataIn.status = status;
    _usb.send(Endpoints::DataIn, &_usbDataIn.status, sizeof(_usbDataIn.status));
}

#pragma mark - Common Commands

void System::_endpointsFlush_taskFn() {
    TaskBegin();
    // Reset endpoints
    _usb.reset(Endpoints::DataOut);
    _usb.reset(Endpoints::DataIn);
    TaskWait(_usb.ready(Endpoints::DataOut) && _usb.ready(Endpoints::DataIn));
    // Send status
    _usb_dataInSendStatus(true);
}

void System::_bootloaderInvoke_taskFn() {
    TaskBegin();
    // Send status
    _usb_dataInSendStatus(true);
    // Wait for host to receive status before resetting
    TaskWait(_usb.ready(Endpoints::DataIn));
    
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

void System::_ledSet() {
    switch (_cmd.arg.LEDSet.idx) {
    case 0: _usb_dataInSendStatus(false); return;
    case 1: _LED1::Write(_cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(_cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(_cmd.arg.LEDSet.on); break;
    }
    
    // Send status
    _usb_dataInSendStatus(true);
}

#pragma mark - STM32 Bootloader

static size_t _stm_regionCapacity(void* addr) {
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

void System::_stm_writeTaskFn() {
    const auto& arg = _cmd.arg.STMWrite;
    
    TaskBegin();
    
    // Bail if the region capacity is too small to hold the
    // incoming data length (ceiled to the packet length)
    static size_t len;
    len = _ceilToMaxPacketSize(arg.len);
    if (len > _stm_regionCapacity((void*)arg.addr)) {
        // Send preliminary status: error
        _usb_dataInSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _usb_dataInSendStatus(true);
    TaskWait(_usb.ready(Endpoints::DataIn));
    
    // Receive USB data
    _usb.recv(Endpoints::DataOut, (void*)arg.addr, len);
    TaskWait(_usb.ready(Endpoints::DataOut));
    
    // Send final status
    _usb_dataInSendStatus(true);
}

void System::_stm_resetTaskFn() {
    TaskBegin();
    Start.setAppEntryPointAddr(_cmd.arg.STMReset.entryPointAddr);
    
    // Send status
    _usb_dataInSendStatus(true);
    // Wait for host to receive status before resetting
    TaskWait(_usb.ready(Endpoints::DataIn));
    
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

#pragma mark - ICE40 Bootloader
static void _ice_qspiWrite(QSPI& qspi, const void* data, size_t len) {
    QSPI_CommandTypeDef cmd = {
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
    
    qspi.write(cmd, data, len);
}

void System::_ice_writeTaskFn() {
    auto& arg = _cmd.arg.ICEWrite;
    TaskBegin();
    
    // Configure ICE40 control GPIOs
    _ICE_CRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_CDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CLK::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Put ICE40 into configuration mode
    _ICE_ST_SPI_CLK::Write(1);
    
    _ICE_ST_SPI_CS_::Write(0);
    _ICE_CRST_::Write(0);
    HAL_Delay(1); // Sleep 1 ms (ideally, 200 ns)
    
    _ICE_CRST_::Write(1);
    HAL_Delay(2); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Release chip-select before we give control of _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_ to QSPI
    _ICE_ST_SPI_CS_::Write(1);
    
    // Have QSPI take over _ICE_ST_SPI_CLK/_ICE_ST_SPI_CS_
    _qspi.config();
    
    // Send 8 clocks and wait for them to complete
    static const uint8_t ff = 0xff;
    _ice_qspiWrite(_qspi, &ff, 1);
    TaskWait(_qspi.ready());
    
    // Reset state
    _bufs.reset();
    // Trigger the USB DataOut task with the amount of data
    _usb_dataOutTask.start();
    _usbDataOut.len = arg.len;
    
    while (arg.len) {
        // Wait until we have data to consume, and QSPI is ready to write
        TaskWait(!_bufs.empty() && _qspi.ready());
        
        // Write the data over QSPI and wait for completion
        _ice_qspiWrite(_qspi, _bufs.front().data, _bufs.front().len);
        TaskWait(_qspi.ready());
        
        // Update the remaining data and pop the buffer so it can be used again
        arg.len -= _bufs.front().len;
        _bufs.pop();
    }
    
    // Wait for CDONE to be asserted
    {
        bool ok = false;
        for (int i=0; i<10 && !ok; i++) {
            if (i) HAL_Delay(1); // Sleep 1 ms
            ok = _ICE_CDONE::Read();
        }
        
        if (!ok) {
            _usb_dataInSendStatus(false);
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
            static const uint8_t ff = 0xff;
            _ice_qspiWrite(_qspi, &ff, sizeof(ff));
            TaskWait(_qspi.ready());
        }
    }
    
    _usb_dataInSendStatus(true);
}

#pragma mark - MSP430 Bootloader
void System::_msp_connect() {
    const auto r = _msp.connect();
    // Send status
    _usb_dataInSendStatus(r == _msp.Status::OK);
}

void System::_msp_disconnect() {
    _msp.disconnect();
    // Send status
    _usb_dataInSendStatus(true);
}

void System::_msp_readTaskFn() {
    auto& arg = _cmd.arg.MSPRead;
    TaskBegin();
    
    // Reset state
    _bufs.reset();
    
    // Start the USB DataIn task
    _usb_dataInTask.start();
    
    while (arg.len) {
        TaskWait(!_bufs.full());
        
        auto& buf = _bufs.back();
        // Prepare to receive either `arg.len` bytes or the
        // buffer capacity bytes, whichever is smaller.
        const size_t chunkLen = std::min((size_t)arg.len, buf.cap);
        _msp.read(arg.addr, buf.data, chunkLen);
        arg.addr += chunkLen;
        arg.len -= chunkLen;
        // Enqueue the buffer
        buf.len = chunkLen;
        _bufs.push();
    }
    
    // Wait for DataIn task to complete
    TaskWait(_bufs.empty());
    // Send status
    _usb_dataInSendStatus(true);
}

void System::_msp_writeTaskFn() {
    auto& arg = _cmd.arg.MSPWrite;
    TaskBegin();
    
    // Reset state
    _bufs.reset();
    _msp.crcReset();
    
    // Trigger the USB DataOut task with the amount of data
    _usb_dataOutTask.start();
    _usbDataOut.len = arg.len;
    
    while (arg.len) {
        TaskWait(!_bufs.empty());
        
        // Write the data over Spy-bi-wire
        auto& buf = _bufs.front();
        _msp.write(arg.addr, buf.data, buf.len);
        // Update the MSP430 address to write to
        arg.addr += buf.len;
        arg.len -= buf.len;
        // Pop the buffer, which we just finished sending over Spy-bi-wire
        _bufs.pop();
    }
    
    // Verify the CRC of all the data we wrote
    const auto r = _msp.crcVerify();
    // Send status
    _usb_dataInSendStatus(r == _msp.Status::OK);
}

void System::_msp_debugTaskFn() {
    auto& arg = _cmd.arg.MSPDebug;
    TaskBegin();
    
    // Bail if more data was requested than the size of our buffer
    if (arg.respLen > sizeof(_buf1)) {
        // Send preliminary status: error
        _usb_dataInSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _usb_dataInSendStatus(true);
    TaskWait(_usb.ready(Endpoints::DataIn));
    
    static bool ok;
    ok = true;
    
    // Handle debug commands
    {
        while (arg.cmdsLen) {
            // Receive debug commands into _buf0
            _usb.recv(Endpoints::DataOut, _buf0, sizeof(_buf0));
            TaskWait(_usb.ready(Endpoints::DataOut));
            
            // Handle each MSPDebugCmd
            const MSPDebugCmd* cmds = (MSPDebugCmd*)_buf0;
            const size_t cmdsLen = _usb.recvLen(Endpoints::DataOut) / sizeof(MSPDebugCmd);
            for (size_t i=0; i<cmdsLen && ok; i++) {
                ok &= _msp_debugHandleCmd(cmds[i]);
            }
            
            arg.cmdsLen -= cmdsLen;
        }
    }
    
    // Reply with data generated from debug commands
    {
        // Push outstanding bits into the buffer
        // This is necessary for when the client reads a number of bits
        // that didn't fall on a byte boundary.
        if (_mspDebug.read.bitsLen) ok &= _msp_debugPushReadBits();
        _mspDebug.read = {};
        
        if (arg.respLen) {
            // Send the data and wait for it to be received
            _usb.send(Endpoints::DataIn, _buf1, arg.respLen);
            TaskWait(_usb.ready(Endpoints::DataIn));
        }
    }
    
    // Send status
    _usb_dataInSendStatus(ok);
}

bool System::_msp_debugPushReadBits() {
    if (_mspDebug.read.len >= sizeof(_buf1)) return false;
    // Enqueue the new byte into `_buf1`
    _buf1[_mspDebug.read.len] = _mspDebug.read.bits;
    _mspDebug.read.len++;
    // Reset our bits
    _mspDebug.read.bits = 0;
    _mspDebug.read.bitsLen = 0;
    return true;
}

bool System::_msp_debugHandleSBWIO(const MSPDebugCmd& cmd) {
    const bool tdo = _msp.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
    if (cmd.tdoReadGet()) {
        // Enqueue a new bit
        _mspDebug.read.bits <<= 1;
        _mspDebug.read.bits |= tdo;
        _mspDebug.read.bitsLen++;
        
        // Enqueue the byte if it's filled
        if (_mspDebug.read.bitsLen == 8) {
            return _msp_debugPushReadBits();
        }
    }
    return true;
}

bool System::_msp_debugHandleCmd(const MSPDebugCmd& cmd) {
    switch (cmd.opGet()) {
    case MSPDebugCmd::Ops::TestSet:     _msp.debugTestSet(cmd.pinValGet()); return true;
    case MSPDebugCmd::Ops::RstSet:      _msp.debugRstSet(cmd.pinValGet());  return true;
    case MSPDebugCmd::Ops::TestPulse:   _msp.debugTestPulse();              return true;
    case MSPDebugCmd::Ops::SBWIO:       return _msp_debugHandleSBWIO(cmd);
    default:                            abort();
    }
}

System Sys;

bool IRQState::SetInterruptsEnabled(bool en) {
    const bool prevEn = !__get_PRIMASK();
    if (en) __enable_irq();
    else __disable_irq();
    return prevEn;
}

void IRQState::WaitForInterrupt() {
    __WFI();
}

int main() {
    Sys.init();
    Sys.run();
    return 0;
}

[[noreturn]] void abort() {
    Sys.abort();
}

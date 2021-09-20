#include "System.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>
#include <algorithm>

using namespace STLoader;

#pragma mark - System
System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
}

[[noreturn]] void abort() {
    Sys.abort();
}

System::System() :
// QSPI clock divider=5 => run QSPI clock at 21.3 MHz
// QSPI alignment=byte, so we can transfer single bytes at a time
_qspi(QSPI::Mode::Single, 5, QSPI::Align::Byte, QSPI::ChipSelect::Controlled),
_bufs(_buf0, _buf1) {
}

void System::init() {
    _super::init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    _usb.init();
    _qspi.init();
}

void System::_handleEvent() {
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.cmdRecvChannel.readSelect()) {
    	_usb_cmdHandle(*x);
    
    } else if (auto x = _usb.recvDoneChannel(Endpoints::DataOut).readSelect()) {
        _usb_recvDone(*x);
    
    } else if (auto x = _usb.sendReadyChannel(Endpoints::DataIn).readSelect()) {
    	_usb_sendReady(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _ice_qspiHandleEvent(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
}

void System::_reset(const Cmd& cmd) {
    _op = Op::None;
    _usb.reset(Endpoints::DataOut);
    _usb.reset(Endpoints::DataIn);
    _finishCmd(true);
}

#pragma mark - USB

void System::_usb_task() {
    TaskBegin();
    for (;;) {
        auto ev = TaskRead(_usb.cmdRecvChannel);
        Cmd cmd;
        
        // Validate command length
        if (ev.len != sizeof(cmd)) {
            _usb_finishCmd(false);
            continue;
        }
        
        memcpy(&cmd, ev.data, ev.len);
        
        switch (cmd.op) {
        case Op::Reset:                 _reset(cmd);                break;
        // STM32 Bootloader
        case Op::STMWrite:
        case Op::STMReset:
            _stm.task.reset();
            _stm.chan.reset();
            _stm.chan.write(cmd);
            break;
        // ICE40 Bootloader
        case Op::ICEWrite:              _ice_write(cmd);            break;
        // MSP430 Bootloader
        case Op::MSPConnect:            _msp_connect(cmd);          break;
        case Op::MSPDisconnect:         _msp_disconnect(cmd);       break;
        // MSP430 Debug
        case Op::MSPRead:               _mspRead(cmd);              break;
        case Op::MSPWrite:              _mspWrite(cmd);             break;
        case Op::MSPDebug:              _mspDebug(cmd);             break;
        // Set LED
        case Op::LEDSet:                _ledSet(cmd);               break;
        // Bad command
        default:            			_finishCmd(false);  		break;
        }
    }
    TaskEnd();
}

void System::_usb_cmdHandle(const USB::CmdRecvEvent& ev) {
    Cmd cmd;

    // Validate command length
    if (ev.len != sizeof(cmd)) {
        _finishCmd(false);
        return;
    }
    
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    case Op::Reset:
        _reset(cmd);
        break;
    // STM32 Bootloader
    case Op::STMWrite:
    case Op::STMReset:
        _stm.task.reset();
        _stm.chan.reset();
        _stm.chan.write(cmd);
        break;
    // ICE40 Bootloader
    case Op::ICEWrite:
        _ice.task.reset();
        _ice.chan.reset();
        _ice.chan.write(cmd);
        break;
    // MSP430 Bootloader
    case Op::MSPConnect:            _msp_connect(cmd);          break;
    case Op::MSPDisconnect:         _msp_disconnect(cmd);       break;
    // MSP430 Debug
    case Op::MSPRead:               _mspRead(cmd);              break;
    case Op::MSPWrite:              _mspWrite(cmd);             break;
    case Op::MSPDebug:              _mspDebug(cmd);             break;
    // Set LED
    case Op::LEDSet:                _ledSet(cmd);               break;
    // Bad command
    default:            			_finishCmd(false);  		break;
    }
}

void System::_usb_recvDone(const USB::RecvDoneEvent& ev) {
    Assert(ev.len <= _opDataRem);
    
    _opDataRem -= ev.len;
    
    switch (_op) {
    case Op::STMWrite:   _stm_usbRecvDone(ev);      break;
    case Op::ICEWrite:  _ice_usbRecvDone(ev);       break;
    case Op::MSPWrite:  _mspWrite_usbRecvDone(ev);  break;
    default:            abort();                    break;
    }
}

void System::_usb_sendReady(const USB::SendReadyEvent& ev) {
    Assert(!_bufs.empty());
    
    // Reset the buffer length so it's back in its default state
    _bufs.front().len = 0;
    // Pop the buffer, which we just finished sending over USB
    _bufs.pop();
    
    switch (_op) {
    case Op::MSPRead:   _mspRead_usbSendReady(ev);  break;
    default:            abort();                    break;
    }
}

static size_t _ceilToPacketLength(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%USB::MaxPacketSizeIn();
    len += (rem>0 ? USB::MaxPacketSizeIn()-rem : 0);
    return len;
}

void System::_usb_recvToBuf() {
    Assert(!_bufs.full());
    Assert(_opDataRem);
    auto& buf = _bufs.back();
    
    // Prepare to receive either `_opDataRem` bytes or the
    // buffer capacity bytes, whichever is smaller.
    const size_t len = _ceilToPacketLength(std::min(_opDataRem, buf.cap));
    // Ensure that after rounding up to the nearest packet size, we don't
    // exceed the buffer capacity. (This should always be safe as long as
    // the buffer capacity is a multiple of the max packet size.)
    Assert(len <= buf.cap);
    
    _usb.recv(Endpoints::DataOut, buf.data, len);
}

void System::_usb_sendFromBuf() {
    Assert(!_bufs.empty());
    const auto& buf = _bufs.front();
    _usb.send(Endpoints::DataIn, buf.data, buf.len);
}

void System::_usb_finishCmd(bool status) {
    // Send our response
    _usb.cmdSendStatus(status);
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

void System::_stm_task() {
    TaskBegin();
    for (;;) {
        // Wait for a command
        const Cmd cmd = TaskRead(_stm.chan);
        
        switch (cmd.op) {
        case Op::STMWrite: {
            void*const addr = (void*)cmd.arg.STMWrite.addr;
            const size_t len = cmd.arg.STMWrite.len;
            const size_t ceilLen = _ceilToPacketLength(len);
            const size_t regionCap = _stm_regionCapacity(addr);
            // Confirm that the region's capacity is large enough to hold the incoming
            // data length (ceiled to the packet length)
            Assert(regionCap >= ceilLen); // TODO: error handling
            
            _finishCmd(true);
            
            // Reset the data channel (which sends a 2xZLP+sentinel sequence)
            _usb.reset(Endpoints::DataOut);
            // Wait until we're done resetting the DataOut endpoint
            TaskWait(_usb.recvReady(Endpoints::DataOut));
            
            // Arrange to receive USB data
            _usb.recv(Endpoints::DataOut, addr, ceilLen);
            
            break;
        }
        
        case Op::STMReset: {
            Start.setAppEntryPointAddr(cmd.arg.STMReset.entryPointAddr);
            // Perform software reset
            HAL_NVIC_SystemReset();
            // Unreachable
            abort();
            break;
        }}
    }
    TaskEnd();
}

#pragma mark - ICE40 Bootloader
static void _qspiWrite(QSPI& qspi, const void* data, size_t len) {
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

void System::_ice_task() {
    TaskBegin();
    for (;;) {
        // Wait for a command
        const Cmd cmd = TaskRead(_ice.chan);
        
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
        _qspiWrite(_qspi, &ff, 1);
        _qspi.eventChannel.read();
        
        // Update state
        _op = Op::ICEWrite;
        _opDataRem = cmd.arg.ICEWrite.len;
        
        for (;;) {
            bool didWork;
            
            do {
                // Start a QSPI transaction when:
                //   - we have data to write, and
                //   - we haven't arranged to send QSPI data yet
                if (!_bufs.empty() && _qspi.ready()) {
                    _ice_writeFromBuf();
                    didWork = true;
                }
                
                // Prepare to receive more USB data if:
                //   - we expect more data, and
                //   - there's space in the queue, and
                //   - we haven't arranged to receive USB data yet
                if (_opDataRem && !_bufs.full() && _usb.recvReady(Endpoints::DataOut)) {
                    _usb_recvToBuf();
                    didWork = true;
                }
                
                // We're done when:
                //   - there's no more data coming over USB, and
                //   - there's no more data to write over QSPI
                if (!_opDataRem && _bufs.empty()) {
                    _ice_writeFinish();
                    didWork = true;
                }
            } while (didWork);
        }
        
        // Prepare to receive USB data
        _usb_recvToBuf();
    }
    TaskEnd();
}

void System::_ice_writeFinish() {
    Assert(_bufs.empty());
    
    bool ok = false;
    for (int i=0; i<10; i++) {
        ok = _ICE_CDONE::Read();
        if (ok) break;
        HAL_Delay(1); // Sleep 1 ms
    }
    
    if (ok) {
        // Supply >=49 additional clocks (8*7=56 clocks), per the
        // "iCE40 Programming and Configuration" guide.
        // These clocks apparently reach the user application. Since this
        // appears unavoidable, prevent the clocks from affecting the user
        // application in two ways:
        //   1. write 0xFF, which the user application must consider as a NOP;
        //   2. write a byte at a time, causing chip-select to be de-asserted
        //      between bytes, which must cause the user application to reset
        //      itself.
        const uint8_t clockCount = 7;
        for (int i=0; i<clockCount; i++) {
            static const uint8_t ff = 0xff;
            _qspiWrite(_qspi, &ff, 1);
            _qspi.eventChannel.read(); // Wait for write to complete
        }
        
        _finishCmd(true);
    
    } else {
        // If CDONE isn't high after 10ms, consider it a failure
        _finishCmd(false);
    }
}

void System::_ice_updateState() {

}

void System::_ice_usbRecvDone(const USB::RecvDoneEvent& ev) {
    Assert(ev.len);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _ice_updateState();
}

void System::_ice_qspiHandleEvent(const QSPI::Event& ev) {
    Assert(_op == Op::ICEWrite);
    Assert(!_bufs.empty());
    
    // Pop the buffer, which we just finished sending over QSPI
    _bufs.pop();
    _ice_updateState();
}

void System::_ice_writeFromBuf() {
    Assert(!_bufs.empty());
    const auto& buf = _bufs.front();
    _qspiWrite(_qspi, buf.data, buf.len);
}

#pragma mark - MSP430 Bootloader
void System::_msp_connect(const Cmd& cmd) {
    const auto r = _msp.connect();
    _finishCmd(r == _msp.Status::OK);
}

void System::_msp_disconnect(const Cmd& cmd) {
    _msp.disconnect();
    _finishCmd(true);
}

void System::_mspRead(const STLoader::Cmd& cmd) {
    // Update state
    _op = Op::MSPRead;
    _opDataRem = cmd.arg.MSPRead.len;
    _mspAddr = cmd.arg.MSPRead.addr;
    
    _mspRead_updateState();
    
    _finishCmd(true);
}

void System::_mspRead_finish() {
    #warning how do we communicate status to host?
}

void System::_mspRead_updateState() {
    // Send data when:
    //   - we have data to write
    //   - we haven't arranged to send USB data yet
    // Do this before reading from MSP430, so we can send USB data
    // in the background while reading from MSP430.
    if (!_bufs.empty() && _usb.sendReady(Endpoints::DataIn)) {
        _usb_sendFromBuf();
    }
    
    // Fill our buffers with data read from MSP430 when:
    //   - there's more data to be read, and
    //   - there's space in the queue
    while (_opDataRem && !_bufs.full()) {
        _mspRead_readToBuf();
    }
    
    // Send data when:
    //   - we have data to write
    //   - we haven't arranged to send USB data yet
    // Do this again after reading from MSP, since we may not have had any
    // buffers available to send before we read from MSP.
    if (!_bufs.empty() && _usb.sendReady(Endpoints::DataIn)) {
        _usb_sendFromBuf();
    }
    
    // We're done when:
    //   - there's no more data to be read, and
    //   - there's no more data to send over USB
    if (!_opDataRem && _bufs.empty()) {
        _mspRead_finish();
    }
}

void System::_mspRead_readToBuf() {
    Assert(!_bufs.full());
    Assert(_opDataRem);
    auto& buf = _bufs.back();
    
    // Prepare to receive either `_opDataRem` bytes or the
    // buffer capacity bytes, whichever is smaller.
    const size_t len = std::min(_opDataRem, buf.cap);
    _msp.read(_mspAddr, buf.data, len);
    _opDataRem -= len;
    _mspAddr += len;
    
    // Enqueue the buffer
    buf.len = len;
    _bufs.push();
}

void System::_mspRead_usbSendReady(const USB::SendReadyEvent& ev) {
    _mspRead_updateState();
}

void System::_mspWrite(const Cmd& cmd) {
    // Update state
    _op = Op::MSPWrite;
    _opDataRem = cmd.arg.MSPWrite.len;
    _msp.crcReset();
    _mspAddr = cmd.arg.MSPWrite.addr;
    
    // Prepare to receive USB data
    _usb_recvToBuf();
    
    _finishCmd(true);
}

void System::_mspWrite_finish() {
    // Verify the CRC of all the data we wrote
    const auto r = _msp.crcVerify();
    #warning how do we communicate status to host?
}

void System::_mspWrite_usbRecvDone(const USB::RecvDoneEvent& ev) {
    Assert(ev.len);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _mspWrite_updateState();
}

void System::_mspWrite_updateState() {
    // Prepare to receive more USB data if:
    //   - we expect more data, and
    //   - there's space in the queue, and
    //   - we haven't arranged to receive USB data yet
    //
    // *** We want to do this before executing `_msp.write`, so that we can
    // *** be receiving USB data while we're sending data via Spy-bi-wire.
    if (_opDataRem && !_bufs.full() && _usb.recvReady(Endpoints::DataOut)) {
        _usb_recvToBuf();
    }
    
    // Send data if we have data to write
    if (!_bufs.empty()) {
        _mspWrite_writeFromBuf();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (!_opDataRem && _bufs.empty()) {
        _mspWrite_finish();
    }
}

void System::_mspWrite_writeFromBuf() {
    // Write the data over Spy-bi-wire
    const void* data = _bufs.front().data;
    const size_t len = _bufs.front().len;
    _msp.write(_mspAddr, data, len);
    // Update the MSP430 address to write to
    _mspAddr += len;
    // Pop the buffer, which we just finished sending over Spy-bi-wire
    _bufs.pop();
}

void System::_mspDebug(const Cmd& cmd) {
    _finishCmd(true);
    
    const auto& arg = cmd.arg.MSPDebug;
    _mspDebug_handleWrite(arg.writeLen);
    _mspDebug_handleRead(arg.readLen);
}

void System::_mspDebug_pushReadBits() {
    Assert(_mspDebugRead.len < sizeof(_buf1));
    // Enqueue the new byte into `_buf1`
    _buf1[_mspDebugRead.len] = _mspDebugRead.bits;
    _mspDebugRead.len++;
    // Reset our bits
    _mspDebugRead.bits = 0;
    _mspDebugRead.bitsLen = 0;
}

void System::_mspDebug_handleSBWIO(const MSPDebugCmd& cmd) {
    bool tdo = _msp.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
    if (cmd.tdoReadGet()) {
        // Enqueue a new bit
        _mspDebugRead.bits <<= 1;
        _mspDebugRead.bits |= tdo;
        _mspDebugRead.bitsLen++;
        
        // Enqueue the byte if it's filled
        if (_mspDebugRead.bitsLen == 8) {
            _mspDebug_pushReadBits();
        }
    }
}

void System::_mspDebug_handleCmd(const MSPDebugCmd& cmd) {
    switch (cmd.opGet()) {
    case MSPDebugCmd::Ops::TestSet:     _msp.debugTestSet(cmd.pinValGet()); break;
    case MSPDebugCmd::Ops::RstSet:      _msp.debugRstSet(cmd.pinValGet());  break;
    case MSPDebugCmd::Ops::TestPulse:   _msp.debugTestPulse();              break;
    case MSPDebugCmd::Ops::SBWIO:       _mspDebug_handleSBWIO(cmd);         break;
    default:                            abort();                            break;
    }
}

void System::_mspDebug_handleWrite(size_t len) {
    // We're using _buf0/_buf1 directly, so make sure _bufs isn't in use
    Assert(_bufs.empty());
    // Accept MSPDebugCmds over the DataOut endpoint until we've handled `len` commands
    size_t remLen = len;
    while (remLen) {
        _usb.recv(Endpoints::DataOut, _buf0, sizeof(_buf0));
        
        const auto ev = _usb.recvDoneChannel(Endpoints::DataOut).read();
        Assert(ev.len <= remLen);
        remLen -= ev.len;
        
        // Handle each MSPDebugCmd
        const MSPDebugCmd* cmds = (MSPDebugCmd*)_buf0;
        for (size_t i=0; i<ev.len; i++) {
            _mspDebug_handleCmd(cmds[i]);
        }
    }
}

void System::_mspDebug_handleRead(size_t len) {
    Assert(len <= sizeof(_buf1));
    // Push outstanding bits into the buffer
    // This is necessary for when the client reads a number of bits
    // that didn't fall on a byte boundary.
    if (_mspDebugRead.bitsLen) _mspDebug_pushReadBits();
    if (len) {
        // Send the data and wait for it to be received
        _usb.send(Endpoints::DataIn, _buf1, len);
        _usb.sendReadyChannel(Endpoints::DataIn).read();
    }
    _mspDebugRead = {};
}

#pragma mark - Other Commands

void System::_ledSet(const Cmd& cmd) {
    switch (cmd.arg.LEDSet.idx) {
//    case 0: _LED0::Write(cmd.arg.LEDSet.on); break;
    case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    _finishCmd(true);
}

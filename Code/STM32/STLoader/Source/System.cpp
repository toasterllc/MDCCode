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
_qspi(QSPI::Mode::Single, 5, QSPI::Align::Byte),
_bufs(_buf0, _buf1) {
}

void System::init() {
    _super::init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    _usb.init();
    _qspi.init();
}

void System::_handleEvent() {
//    _msp.connect();
//    for (;;);
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.eventChannel.readSelect()) {
        _usbHandleEvent(*x);
    
    } else if (auto x = _usb.cmdRecvChannel.readSelect()) {
        _usbHandleCmd(*x);
    
    } else if (auto x = _usb.dataRecvChannel.readSelect()) {
        _usbHandleDataRecv(*x);
    
    } else if (auto x = _usb.dataSendChannel.readSelect()) {
        _usbHandleDataSend(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _iceHandleQSPIEvent(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
}

void System::_finishCmd(Status status) {
    Assert(!_bufs.full());
    Assert(!_usbDataBusy);
    
    // Update our state
    _op = Op::None;
    
    // Send our response
    auto& buf = _bufs.back();
    memcpy(buf.data, &status, sizeof(status));
    buf.len = sizeof(status);
    _bufs.push();
    _usbSendFromBuf();
}

#pragma mark - USB
void System::_usbCmdRecv() {
    // Prepare to receive another command
    _usb.cmdRecv();
}

void System::_usbHandleEvent(const USB::Event& ev) {
    using Type = USB::Event::Type;
    switch (ev.type) {
    case Type::StateChanged: {
        // Handle USB connection
        if (_usb.state() == USB::State::Connected) {
            // Prepare to receive bootloader commands
            _usbCmdRecv();
        }
        break;
    }
    
    default: {
        // Invalid event type
        abort();
    }}
}

void System::_usbHandleCmd(const USB::CmdRecv& ev) {
    Assert(_op == Op::None);
    
    Cmd cmd;
    Assert(ev.len == sizeof(cmd));
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    // STM32 Bootloader
    case Op::STWrite:               _stWrite(cmd);              break;
    case Op::STReset:               _stReset(cmd);              break;
    // ICE40 Bootloader
    case Op::ICEWrite:              _iceWrite(cmd);             break;
    // MSP430 Bootloader
    case Op::MSPConnect:            _mspConnect(cmd);           break;
    case Op::MSPDisconnect:         _mspDisconnect(cmd);        break;
    case Op::MSPRead:               _mspRead(cmd);              break;
    case Op::MSPWrite:              _mspWrite(cmd);             break;
    case Op::MSPDebug:              _mspDebug(cmd);             break;
    // MSP430 Debug
    // Set LED
    case Op::LEDSet:                _ledSet(cmd);               break;
    // Bad command
    default:                        abort();                    break;
    }
}

void System::_usbHandleDataRecv(const USB::DataRecv& ev) {
    Assert(_usbDataBusy);
    Assert(ev.len <= _opDataRem);
    
    _opDataRem -= ev.len;
    _usbDataBusy = false;
    
    switch (_op) {
    case Op::STWrite:   _stHandleUSBDataRecv(ev);       break;
    case Op::ICEWrite:  _iceHandleUSBDataRecv(ev);      break;
    case Op::MSPWrite:  _mspWriteHandleUSBDataRecv(ev); break;
    default:            abort();                        break;
    }
}

void System::_usbHandleDataSend(const USB::DataSend& ev) {
    Assert(_usbDataBusy);
    Assert(!_bufs.empty());
    
    // Reset the buffer length so it's back in its default state
    _bufs.front().len = 0;
    // Pop the buffer, which we just finished sending over USB
    _bufs.pop();
    _usbDataBusy = false;
    
    switch (_op) {
    case Op::MSPRead:   _mspReadHandleUSBDataSend(ev);  break;
    // The host received the status response;
    // arrange to receive another command
    case Op::None:      _usbCmdRecv();                  break;
    default:            abort();                        break;
    }
}

static size_t _ceilToPacketLength(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%USB::MaxPacketSize::Data;
    len += (rem>0 ? USB::MaxPacketSize::Data-rem : 0);
    return len;
}

void System::_usbRecvToBuf() {
    Assert(!_bufs.full());
    Assert(_opDataRem);
    Assert(!_usbDataBusy);
    auto& buf = _bufs.back();
    
    // Prepare to receive either `_opDataRem` bytes or the
    // buffer capacity bytes, whichever is smaller.
    const size_t len = _ceilToPacketLength(std::min(_opDataRem, buf.cap));
    // Ensure that after rounding up to the nearest packet size, we don't
    // exceed the buffer capacity. (This should always be safe as long as
    // the buffer capacity is a multiple of the max packet size.)
    Assert(len <= buf.cap);
    
    _usb.dataRecv(buf.data, len);
    _usbDataBusy = true;
}

void System::_usbSendFromBuf() {
    Assert(!_bufs.empty());
    Assert(!_usbDataBusy);
    
    const auto& buf = _bufs.front();
    _usb.dataSend(buf.data, buf.len);
    _usbDataBusy = true;
}

static size_t _stRegionCapacity(void* addr) {
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

#pragma mark - STM32 Bootloader
void System::_stWrite(const Cmd& cmd) {
    void*const addr = (void*)cmd.arg.STWrite.addr;
    const size_t len = cmd.arg.STWrite.len;
    const size_t ceilLen = _ceilToPacketLength(len);
    const size_t regionCap = _stRegionCapacity(addr);
    // Confirm that the region's capacity is large enough to hold the incoming
    // data length (ceiled to the packet length)
    Assert(regionCap >= ceilLen); // TODO: error handling
    
    // Update state
    _op = cmd.op;
    _opDataRem = len;
    
    // Arrange to receive USB data
    _usb.dataRecv(addr, ceilLen);
    _usbDataBusy = true;
}

void System::_stReset(const Cmd& cmd) {
    Start.setAppEntryPointAddr(cmd.arg.STReset.entryPointAddr);
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

void System::_stHandleUSBDataRecv(const USB::DataRecv& ev) {
    Assert(ev.len);
    _finishCmd(Status::OK);
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

void System::_iceWrite(const Cmd& cmd) {
    // Configure ICE40 control GPIOs
    _ICECRST_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICECDONE::Config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICESPIClk::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _ICESPICS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Put ICE40 into configuration mode
    _ICESPIClk::Write(1);
    
    _ICESPICS_::Write(0);
    _ICECRST_::Write(0);
    HAL_Delay(1); // Sleep 1 ms (ideally, 200 ns)
    
    _ICECRST_::Write(1);
    HAL_Delay(2); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
    
    // Release chip-select before we give control of _ICESPIClk/_ICESPICS_ to QSPI
    _ICESPICS_::Write(1);
    
    // Have QSPI take over _ICESPIClk/_ICESPICS_
    _qspi.config();
    
    // Send 8 clocks and wait for them to complete
    static const uint8_t ff = 0xff;
    _qspiWrite(_qspi, &ff, 1);
    _qspi.eventChannel.read();
    
    // Update state
    _op = cmd.op;
    _opDataRem = cmd.arg.ICEWrite.len;
    
    // Prepare to receive USB data
    _usbRecvToBuf();
}

void System::_iceWriteFinish() {
    Assert(_bufs.empty());
    
    bool ok = false;
    for (int i=0; i<10; i++) {
        ok = _ICECDONE::Read();
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
        
        _finishCmd(Status::OK);
    
    } else {
        // If CDONE isn't high after 10ms, consider it a failure
        _finishCmd(Status::Error);
    }
}

void System::_iceUpdateState() {
    // Start a QSPI transaction when:
    //   - we have data to write, and
    //   - we haven't arranged to send QSPI data yet
    if (!_bufs.empty() && !_qspiBusy) {
        _qspiWriteFromBuf();
    }
    
    // Prepare to receive more USB data if:
    //   - we expect more data, and
    //   - there's space in the queue, and
    //   - we haven't arranged to receive USB data yet
    if (_opDataRem && !_bufs.full() && !_usbDataBusy) {
        _usbRecvToBuf();
    }
    
    // We're done when:
    //   - there's no more data coming over USB, and
    //   - there's no more data to write over QSPI
    if (!_opDataRem && _bufs.empty()) {
        _iceWriteFinish();
    }
}

void System::_iceHandleUSBDataRecv(const USB::DataRecv& ev) {
    Assert(ev.len);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _iceUpdateState();
}

void System::_iceHandleQSPIEvent(const QSPI::Signal& ev) {
    Assert(_op == Op::ICEWrite);
    Assert(!_bufs.empty());
    Assert(_qspiBusy);
    
    // Pop the buffer, which we just finished sending over QSPI
    _bufs.pop();
    _qspiBusy = false;
    
    _iceUpdateState();
}

void System::_qspiWriteFromBuf() {
    Assert(!_bufs.empty());
    const auto& buf = _bufs.front();
    _qspiWrite(_qspi, buf.data, buf.len);
    _qspiBusy = true;
}

#pragma mark - MSP430 Bootloader
void System::_mspConnect(const Cmd& cmd) {
    const auto r = _msp.connect();
    _finishCmd(r==_msp.Status::OK ? Status::OK : Status::Error);
}

void System::_mspDisconnect(const Cmd& cmd) {
    _msp.disconnect();
    _finishCmd(Status::OK);
}

void System::_mspRead(const STLoader::Cmd& cmd) {
    // Update state
    _op = cmd.op;
    _opDataRem = cmd.arg.MSPRead.len;
    _mspAddr = cmd.arg.MSPRead.addr;
    
    _mspReadUpdateState();
}

void System::_mspReadFinish() {
    _finishCmd(Status::OK);
}

void System::_mspReadUpdateState() {
    // Send data when:
    //   - we have data to write
    //   - we haven't arranged to send USB data yet
    // Do this before reading from MSP430, so we can send USB data
    // in the background while reading from MSP430.
    if (!_bufs.empty() && !_usbDataBusy) {
        _usbSendFromBuf();
    }
    
    // Fill our buffers with data read from MSP430 when:
    //   - there's more data to be read, and
    //   - there's space in the queue
    while (_opDataRem && !_bufs.full()) {
        _mspReadToBuf();
    }
    
    // Send data when:
    //   - we have data to write
    //   - we haven't arranged to send USB data yet
    // Do this again after reading from MSP, since we may not have had any
    // buffers available to send before we read from MSP.
    if (!_bufs.empty() && !_usbDataBusy) {
        _usbSendFromBuf();
    }
    
    // We're done when:
    //   - there's no more data to be read, and
    //   - there's no more data to send over USB
    if (!_opDataRem && _bufs.empty()) {
        _mspReadFinish();
    }
}

void System::_mspReadToBuf() {
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

void System::_mspReadHandleUSBDataSend(const USB::DataSend& ev) {
    _mspReadUpdateState();
}

void System::_mspWrite(const Cmd& cmd) {
    // Update state
    _op = cmd.op;
    _opDataRem = cmd.arg.MSPWrite.len;
    _msp.crcReset();
    _mspAddr = cmd.arg.MSPWrite.addr;
    
    // Prepare to receive USB data
    _usbRecvToBuf();
}

void System::_mspWriteFinish() {
    // Verify the CRC of all the data we wrote
    const auto r = _msp.crcVerify();
    _finishCmd(r==_msp.Status::OK ? Status::OK : Status::Error);
}

void System::_mspWriteHandleUSBDataRecv(const USB::DataRecv& ev) {
    Assert(ev.len);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _mspWriteUpdateState();
}

void System::_mspWriteUpdateState() {
    // Prepare to receive more USB data if:
    //   - we expect more data, and
    //   - there's space in the queue, and
    //   - we haven't arranged to receive USB data yet
    //
    // *** We want to do this before executing `_msp.write`, so that we can
    // *** be receiving USB data while we're sending data via Spy-bi-wire.
    if (_opDataRem && !_bufs.full() && !_usbDataBusy) {
        _usbRecvToBuf();
    }
    
    // Send data if we have data to write
    if (!_bufs.empty()) {
        _mspWriteFromBuf();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (!_opDataRem && _bufs.empty()) {
        _mspWriteFinish();
    }
}

void System::_mspWriteFromBuf() {
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
    const auto& arg = cmd.arg.MSPDebug;
    _mspDebugHandleWrite(arg.writeLen);
    _mspDebugHandleRead(arg.readLen);
    _finishCmd(Status::OK);
}

void System::_mspDebugPushReadBits() {
    Assert(_mspDebugRead.len < sizeof(_buf1));
    // Enqueue the new byte into `_buf1`
    _buf1[_mspDebugRead.len] = _mspDebugRead.bits;
    _mspDebugRead.len++;
    // Reset our bits
    _mspDebugRead.bits = 0;
    _mspDebugRead.bitsLen = 0;
}

void System::_mspDebugHandleSBWIO(const MSPDebugCmd& cmd) {
    bool tdo = _msp.debugSBWIO(cmd.tmsGet(), cmd.tclkGet(), cmd.tdiGet());
    if (cmd.tdoReadGet()) {
        // Enqueue a new bit
        _mspDebugRead.bits <<= 1;
        _mspDebugRead.bits |= tdo;
        _mspDebugRead.bitsLen++;
        
        // Enqueue the byte if it's filled
        if (_mspDebugRead.bitsLen == 8) {
            _mspDebugPushReadBits();
        }
    }
}

void System::_mspDebugHandleCmd(const MSPDebugCmd& cmd) {
    switch (cmd.opGet()) {
    case MSPDebugCmd::Ops::TestSet:     _msp.debugTestSet(cmd.pinValGet()); break;
    case MSPDebugCmd::Ops::RstSet:      _msp.debugRstSet(cmd.pinValGet());  break;
    case MSPDebugCmd::Ops::TestPulse:   _msp.debugTestPulse();              break;
    case MSPDebugCmd::Ops::SBWIO:       _mspDebugHandleSBWIO(cmd);          break;
    default:                            abort();                            break;
    }
}

void System::_mspDebugHandleWrite(size_t len) {
    // We're using _buf0/_buf1 directly, so make sure _bufs isn't in use
    Assert(_bufs.empty());
    // Accept MSPDebugCmds over the DataOut endpoint until we've handled `len` commands
    size_t remLen = len;
    while (remLen) {
        _usb.dataRecv(_buf0, sizeof(_buf0));
        
        const auto ev = _usb.dataRecvChannel.read();
        Assert(ev.len <= remLen);
        remLen -= ev.len;
        
        // Handle each MSPDebugCmd
        const MSPDebugCmd* cmds = (MSPDebugCmd*)_buf0;
        for (size_t i=0; i<ev.len; i++) {
            _mspDebugHandleCmd(cmds[i]);
        }
    }
}

void System::_mspDebugHandleRead(size_t len) {
    Assert(len <= sizeof(_buf1));
    // Push outstanding bits into the buffer
    // This is necessary for when the client reads a number of bits
    // that didn't fall on a byte boundary.
    if (_mspDebugRead.bitsLen) _mspDebugPushReadBits();
    if (len) {
        // Send the data and wait for it to be received
        _usb.dataSend(_buf1, len);
        _usb.dataSendChannel.read();
    }
    _mspDebugRead = {};
}

#pragma mark - Other Commands

void System::_ledSet(const Cmd& cmd) {
    switch (cmd.arg.LEDSet.idx) {
    case 0: _LED0::Write(cmd.arg.LEDSet.on); break;
    case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    _finishCmd(Status::OK);
}

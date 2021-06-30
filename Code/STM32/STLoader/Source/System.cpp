#include "System.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>

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
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.eventChannel.readSelect()) {
        _usbHandleEvent(*x);
    
    } else if (auto x = _usb.cmdChannel.readSelect()) {
        _usbHandleCmd(*x);
    
    } else if (auto x = _usb.dataChannel.readSelect()) {
        _usbHandleData(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _iceHandleQSPIEvent(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
}

void System::_usbHandleEvent(const USB::Event& ev) {
    using Type = USB::Event::Type;
    switch (ev.type) {
    case Type::StateChanged: {
        // Handle USB connection
        if (_usb.state() == USB::State::Connected) {
            // Prepare to receive bootloader commands
            _usb.cmdRecv();
        }
        break;
    }
    
    default: {
        // Invalid event type
        abort();
    }}
}

void System::_usbHandleCmd(const USB::Cmd& ev) {
    Cmd cmd;
    Assert(ev.len == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    // STM32
    case Op::STWrite:   _stWrite(cmd);      break;
    case Op::STFinish:  _stFinish(cmd);     break;
    
    // ICE40
    case Op::ICEWrite:  _iceWrite(cmd);     break;
    
    // MSP430
    case Op::MSPStart:  _mspStart(cmd);     break;
    case Op::MSPWrite:  _mspWrite(cmd);     break;
    case Op::MSPFinish: _mspFinish(cmd);    break;
    
    // Get status
    case Op::StatusGet: {
        _usb.statusSend(&_status, sizeof(_status));
        break;
    }
    
    // Set LED
    case Op::LEDSet: {
        switch (cmd.arg.LEDSet.idx) {
        case 0: _LED0::Write(cmd.arg.LEDSet.on); break;
        case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
        case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
        case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
        }
        
        break;
    }
    
    // Bad command
    default: {
        break;
    }}
    
    // Prepare to receive another command
    _usb.cmdRecv(); // TODO: handle errors
}

void System::_usbHandleData(const USB::Data& ev) {
    Assert(_status == Status::Busy);
    
    switch (_op) {
    case Op::STWrite:
        _stHandleUSBData(ev);
        break;
    
    case Op::ICEWrite:
        _iceHandleUSBData(ev);
        break;
    
    case Op::MSPWrite:
        _mspHandleUSBData(ev);
        break;
    
    default:
        // Invalid _op
        abort();
        break;
    }
}

void System::_usbDataRecv() {
    Assert(!_bufs.full());
    auto& buf = _bufs.back();
    _usb.dataRecv(buf.data, buf.cap); // TODO: handle errors
}

#pragma mark - STM32 Bootloader
void System::_stWrite(const Cmd& cmd) {
    Assert(cmd.op == Op::STWrite);
    Assert(_status != Status::Busy);
    
    // Update our status
    _usbDataOp = cmd.op;
    _status = Status::Busy;
    
    void*const addr = (void*)cmd.arg.STWrite.addr;
    // Verify that `addr` is in one of the allowed RAM regions
    extern uint8_t _sitcm_ram[], _eitcm_ram[];
    extern uint8_t _sdtcm_ram[], _edtcm_ram[];
    extern uint8_t _ssram1[], _esram1[];
    size_t len = 0;
    if (addr>=_sitcm_ram && addr<_eitcm_ram) {
        len = (uintptr_t)_eitcm_ram-(uintptr_t)addr;
    } else if (addr>=_sdtcm_ram && addr<_edtcm_ram) {
        len = (uintptr_t)_edtcm_ram-(uintptr_t)addr;
    } else if (addr>=_ssram1 && addr<_esram1) {
        len = (uintptr_t)_esram1-(uintptr_t)addr;
    } else {
        // TODO: implement proper error handling on writing out of the allowed regions
        abort();
    }
    
    // Round `len` down to the nearest max packet size.
    // (We can only restrict the receipt of USB data
    // at multiples of the max packet size.)
    len -= len%USB::MaxPacketSize::Data;
    Assert(len); // TODO: error handling
    _usb.dataRecv(addr, len);
}

void System::_stWriteFinish() {
    Assert(_status == Status::Busy);
    // Update our status
    _status = Status::OK;
}

void System::_stFinish(const Cmd& cmd) {
    Assert(cmd.op == Op::STFinish);
    Assert(_status == Status::Busy);
    
    Start.setAppEntryPointAddr(cmd.arg.STFinish.entryPointAddr);
    // Perform software reset
    HAL_NVIC_SystemReset();
    break;
}

void System::_stHandleUSBData(const USB::Data& ev) {
    Assert(_status == Status::Busy);
    _stWriteFinish();
}

#pragma mark - ICE40 Bootloader
void System::_iceWrite(const Cmd& cmd) {
    Assert(cmd.op == Op::ICEWrite);
    Assert(_status != Status::Busy);
    
    // Update our status
    _usbDataOp = cmd.op;
    _status = Status::Busy;
    _usbDataEnd = false;
    
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
    
    // Send 8 clocks
    static const uint8_t ff = 0xff;
    _qspiWrite(&ff, 1);
    
    // Wait for write to complete
    _qspi.eventChannel.read();
    
    // Prepare to receive ICE40 bootloader data
    _usbDataRecv();
}

void System::_iceWriteFinish() {
    Assert(_status == Status::Busy);
    Assert(_bufs.empty());
    
    bool ok = false;
    for (int i=0; i<10; i++) {
        ok = _ICECDONE::Read();
        if (ok) break;
        HAL_Delay(1); // Sleep 1 ms
    }
    
    if (!ok) {
        // If CDONE isn't high after 10ms, consider it a failure
        _status = Status::Error;
        return;
    }
    
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
        _qspiWrite(&ff, 1);
        // Wait for write to complete
        _qspi.eventChannel.read();
    }
    
    _status = Status::OK;
}

void System::_iceUpdateState() {
    // Start a QSPI transaction if we have data to write and QSPI is idle
    if (!_bufs.empty() && !_qspi.underway()) {
        _qspiWriteBuf();
    }
    
    // Prepare to receive more USB data if:
    //   - we expect more data, and
    //   - there's space in the queue, and
    //   - we haven't arranged to receive USB data yet
    if (!_usbDataEnd && !_bufs.full() && !_usb.dataRecvUnderway()) {
        _usbDataRecv();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (_usbDataEnd && _bufs.empty()) {
        _iceWriteFinish();
    }
}

void System::_iceHandleUSBData(const USB::Data& ev) {
    Assert(_status == Status::Busy);
    Assert(!_bufs.full());
    
    if (ev.len) {
        // Enqueue the buffer
        _bufs.back().len = ev.len;
        _bufs.push();
    } else {
        _usbDataEnd = true;
    }
    
    _iceUpdateState();
}

void System::_iceHandleQSPIEvent(const QSPI::Signal& ev) {
    Assert(_status == Status::Busy);
    Assert(!_bufs.empty());
    
    // Pop the buffer, which we just finished sending
    _bufs.pop();
    
    _iceUpdateState();
}

void System::_qspiWriteBuf() {
    Assert(!_bufs.empty());
    const auto& buf = _bufs.front();
    _qspiWrite(buf.data, buf.len);
}

void System::_qspiWrite(const void* data, size_t len) {
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
    
    _qspi.write(cmd, data, len);
}

#pragma mark - MSP430 Bootloader
void System::_mspStart(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPStart);
    Assert(_status != Status::Busy);
    
    auto s = _msp.connect();
    if (s != _msp.Status::OK) {
        _status = Status::Error;
        return;
    }
    
    _status = Status::OK;
}

void System::_mspWrite(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPWrite);
    Assert(_status != Status::Busy);
    
    // Update our status
    _usbDataOp = cmd.op;
    _status = Status::Busy;
    
    // Prepare to receive MSP430 bootloader data
    _usbDataRecv();
}

void System::_mspWriteFinish() {
    _status = Status::OK;
}

void System::_mspHandleUSBData(const USB::Data& ev) {
    Assert(ev.len);
    Assert(!_bufs.full());
    Assert(_status == Status::Busy);
    
    const bool wasEmpty = _bufs.empty();
    
    // Enqueue the buffer
    {
        _bufs.back().len = ev.len;
        _bufs.push();
    }
    
    // Start a SPI transaction when `_bufs.empty()` transitions from 1->0
    if (wasEmpty) {
        _qspiWriteBuf();
    }
    
    // Prepare to receive more data if there's space in the queue
    if (!_bufs.full()) {
        _usbDataRecv();
    }
}

void System::_mspFinish(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPFinish);
    Assert(_status != Status::Busy);
    
    _msp.disconnect();
    _status = Status::OK;
}

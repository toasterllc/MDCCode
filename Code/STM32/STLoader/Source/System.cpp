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
    // STM32: Write data
    case Op::STWrite: {
        _stStart(cmd);
        break;
    }
    
    // STM32: Reset
    //   Stash the entry point address for access after we reset,
    //   Perform a software reset
    case Op::STReset: {
        Start.setAppEntryPointAddr(cmd.arg.STReset.entryPointAddr);
        // Perform software reset
        HAL_NVIC_SystemReset();
        break;
    }
    
    // ICE40: Write data
    case Op::ICEWrite: {
        _iceStart(cmd);
        break;
    }
    
    // MSP430: Write data
    case Op::MSPWrite: {
        _mspStart(cmd);
        break;
    }
    
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
        if (!ev.len) {
            // End of data
            _stFinish();
        }
        break;
    
    case Op::ICEWrite:
        if (ev.len) {
            _iceHandleData(ev);
        } else {
            _iceFinish();
        }
        break;
    
    case Op::MSPWrite:
        if (ev.len) {
            _mspHandleData(ev);
        } else {
            _mspFinish();
        }
        break;
    
    default:
        // Invalid _op
        abort();
        break;
    }
}

#pragma mark - STM32 Bootloader
void System::_stStart(const Cmd& cmd) {
    Assert(cmd.op == Op::STWrite);
    Assert(_status==Status::Idle || _status==Status::Error);
    
    // Update our status
    _op = cmd.op;
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

void System::_stFinish() {
    Assert(_status == Status::Busy);
    // Update our status
    _status = Status::Idle;
}

#pragma mark - ICE40 Bootloader
void System::_iceStart(const Cmd& cmd) {
    Assert(cmd.op == Op::ICEWrite);
    Assert(_status==Status::Idle || _status==Status::Error);
    
    // Update our status
    _op = cmd.op;
    _status = Status::Busy;
    _iceEndOfData = false;
    
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
    _iceDataRecv();
}

void System::_iceHandleData(const USB::Data& ev) {
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
        _iceDataRecv();
    }
}

void System::_iceFinish() {
    Assert(_status == Status::Busy);
    
    _iceEndOfData = true;
    
    // Short-circuit if there are still buffers being written
    if (!_bufs.empty()) {
        return;
    }
    
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
            _qspiWrite(&ff, 1);
            // Wait for write to complete
            _qspi.eventChannel.read();
        }
        
        _status = Status::Idle;
    
    } else {
        // If CDONE isn't high after 10ms, consider it a failure
        _status = Status::Error;
    }
}

void System::_iceHandleQSPIEvent(const QSPI::Signal& ev) {
    Assert(_status == Status::Busy);
    Assert(!_bufs.empty());
    const bool wasFull = _bufs.full();
    
    // Pop the buffer, which we just finished sending
    _bufs.pop();
    
    // Prepare to receive more data if we're expecting more, and we were previously full
    if (!_iceEndOfData && wasFull) {
        _iceDataRecv();
    }
    
    // Start another SPI transaction if there's more data to write
    if (!_bufs.empty()) {
        _qspiWriteBuf();
    
    // Otherwise, if we've been notified that there's no more data coming over USB, we're done
    } else if (_iceEndOfData) {
        _iceFinish();
    }
}

void System::_iceDataRecv() {
    Assert(!_bufs.full());
    auto& buf = _bufs.back();
    _usb.dataRecv(buf.data, buf.cap); // TODO: handle errors
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
    Assert(cmd.op == Op::MSPWrite);
    Assert(_status==Status::Idle || _status==Status::Error);
    
    // Update our status
    _op = cmd.op;
    _status = Status::Busy;
}

void System::_mspHandleData(const USB::Data& ev) {
    Assert(ev.len);
    Assert(!_bufs.full());
    Assert(_status == Status::Busy);
}

void System::_mspFinish() {
    _status = Status::Idle;
}

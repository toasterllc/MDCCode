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
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.eventChannel.readSelect()) {
        _usbHandleEvent(*x);
    
    } else if (auto x = _usb.cmdRecvChannel.readSelect()) {
        _usbHandleCmd(*x);
    
    } else if (auto x = _usb.dataRecvChannel.readSelect()) {
        _usbHandleDataRecv(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _iceHandleQSPIEvent(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
}

void System::_updateStatus(Status status, bool send) {
    _status = status;
    // Send our response
    if (send) {
        _usb.dataSend(&_status, sizeof(_status));
    }
}

#pragma mark - USB
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
    // TODO: if this works, remove all the redundant checks from the functions called below
    Assert(_status != Status::Busy);
    
    Cmd cmd;
    Assert(ev.len == sizeof(cmd));
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    // STM32 Bootloader
    case Op::STWrite:               _stWrite(cmd);              break;
    case Op::STFinish:              _stFinish(cmd);             break;
    // ICE40 Bootloader
    case Op::ICEWrite:              _iceWrite(cmd);             break;
    // MSP430 Bootloader
    case Op::MSPConnect:            _mspConnect(cmd);           break;
    case Op::MSPRead:               _mspRead(cmd);           break;
    case Op::MSPWrite:              _mspWrite(cmd);          break;
    case Op::MSPDisconnect:         _mspDisconnect(cmd);        break;
    // MSP430 Debug
    // Set LED
    case Op::LEDSet:                _ledSet(cmd);               break;
    // Bad command
    default:                        abort();                    break;
    }
    
    // Prepare to receive another command
    _usb.cmdRecv();
}

void System::_usbHandleDataRecv(const USB::Data& ev) {
    Assert(_status == Status::Busy);
    Assert(ev.len <= _usbDataRem);
    _usbDataRem -= ev.len;
    
    switch (_usbDataOp) {
    case Op::STWrite:   _stHandleUSBDataRecv(ev);       break;
    case Op::ICEWrite:  _iceHandleUSBDataRecv(ev);      break;
    case Op::MSPWrite:  _mspWriteHandleUSBDataRecv(ev); break;
    default:            abort();                    break;
    }
}

static size_t _ceilToPacketLength(size_t len) {
    // Round `len` up to the nearest packet size, since the USB hardware limits
    // the data received based on packets instead of bytes
    const size_t rem = len%USB::MaxPacketSize::Data;
    len += (rem>0 ? USB::MaxPacketSize::Data-rem : 0);
    return len;
}

void System::_usbDataRecv() {
    Assert(!_bufs.full());
    Assert(_usbDataRem);
    auto& buf = _bufs.back();
    
    // Prepare to receive either `_usbDataRem` bytes or the
    // buffer capacity bytes, whichever is smaller.
    const size_t len = _ceilToPacketLength(std::min(_usbDataRem, buf.cap));
    // Ensure that after rounding up to the nearest packet size, we don't
    // exceed the buffer capacity. (This should always be safe as long as
    // the buffer capacity is a multiple of the max packet size.)
    Assert(len <= buf.cap);
    
    _usb.dataRecv(buf.data, len); // TODO: handle errors
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
    Assert(cmd.op == Op::STWrite);
    Assert(_status != Status::Busy);
    
    void*const addr = (void*)cmd.arg.STWrite.addr;
    const size_t len = cmd.arg.STWrite.len;
    const size_t ceilLen = _ceilToPacketLength(len);
    const size_t regionCap = _stRegionCapacity(addr);
    // Confirm that the region's capacity is large enough to hold the incoming
    // data length (ceiled to the packet length)
    Assert(regionCap >= ceilLen); // TODO: error handling
    
    // Update state
    _usbDataOp = cmd.op;
    _usbDataRem = len;
    _updateStatus(Status::Busy);
    
    // Prepare to receive USB data
    _usb.dataRecv(addr, ceilLen);
}

void System::_stFinish(const Cmd& cmd) {
    Assert(cmd.op == Op::STFinish);
    
    Start.setAppEntryPointAddr(cmd.arg.STFinish.entryPointAddr);
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

void System::_stWriteFinish() {
    Assert(_status == Status::Busy);
    _updateStatus(Status::OK, true);
}

void System::_stHandleUSBDataRecv(const USB::Data& ev) {
    Assert(ev.len);
    Assert(_status == Status::Busy);
    _stWriteFinish();
}

#pragma mark - ICE40 Bootloader
void System::_iceWrite(const Cmd& cmd) {
    Assert(cmd.op == Op::ICEWrite);
    Assert(_status != Status::Busy);
    
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
    
    // Update state
    _usbDataOp = cmd.op;
    _usbDataRem = cmd.arg.ICEWrite.len;
    _updateStatus(Status::Busy);
    
    // Prepare to receive USB data
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
        
        _updateStatus(Status::OK, true);
    
    } else {
        // If CDONE isn't high after 10ms, consider it a failure
        _updateStatus(Status::Error, true);
    }
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
    if (_usbDataRem && !_bufs.full() && !_usb.dataRecvUnderway()) {
        _usbDataRecv();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (!_usbDataRem && _bufs.empty()) {
        _iceWriteFinish();
    }
}

void System::_iceHandleUSBDataRecv(const USB::Data& ev) {
    Assert(ev.len);
    Assert(_status == Status::Busy);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _iceUpdateState();
}

void System::_iceHandleQSPIEvent(const QSPI::Signal& ev) {
    Assert(_status == Status::Busy);
    Assert(!_bufs.empty());
    
    // Pop the buffer, which we just finished sending over QSPI
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
void System::_mspConnect(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPStart);
    Assert(_status != Status::Busy);
    
    const auto r = _msp.connect();
    _updateStatus((r==_msp.Status::OK ? Status::OK : Status::Error), true);
}

void System::_mspRead(const STLoader::Cmd& cmd) {
    Assert(cmd.op == Op::MSPRead);
    Assert(_status != Status::Busy);
    
    // Update state
    _usbDataOp = cmd.op;
    _usbDataRem = cmd.arg.MSPRead.len;
    _mspAddr = cmd.arg.MSPRead.addr;
    _updateStatus(Status::Busy);
    
    // Prepare to receive USB data
    _usbDataRecv();
}

void System::_mspWrite(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPWrite);
    Assert(_status != Status::Busy);
    
    // Update state
    _usbDataOp = cmd.op;
    _usbDataRem = cmd.arg.MSPWrite.len;
    _msp.crcReset();
    _mspAddr = cmd.arg.MSPWrite.addr;
    _updateStatus(Status::Busy);
    
    // Prepare to receive USB data
    _usbDataRecv();
}

void System::_mspDisconnect(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPFinish);
    Assert(_status != Status::Busy);
    
    _msp.disconnect();
    _updateStatus(Status::OK, true);
}

void System::_mspWriteFinish() {
    // Verify the CRC of all the data we wrote
    const auto r = _msp.crcVerify();
    _updateStatus((r==_msp.Status::OK ? Status::OK : Status::Error), true);
}

void System::_mspWriteHandleUSBDataRecv(const USB::Data& ev) {
    Assert(ev.len);
    Assert(_status == Status::Busy);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _mspWriteUpdateState();
}

void System::_mspReadUpdateState() {
    // Prepare to read more data from MSP430:
    //   - we expect more data, and
    //   - there's space in the queue, and
    //   - we haven't arranged to receive USB data yet
    //
    // *** We want to do this before executing `_msp.write`, so that we can
    // *** be receiving USB data while we're sending data via Spy-bi-wire.
    if (_usbDataRem && !_bufs.full()) {
        _usbDataRecv();
    }
    
    // Send data if we have data to write
    if (!_bufs.empty()) {
        _mspWriteBuf();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (!_usbDataRem && _bufs.empty()) {
        _mspWriteFinish();
    }
}

void System::_mspReadBuf() {
    
    Assert(!_bufs.full());
    Assert(_usbDataRem);
    auto& buf = _bufs.back();
    
    // Prepare to receive either `_usbDataRem` bytes or the
    // buffer capacity bytes, whichever is smaller.
    const size_t len = std::min(_usbDataRem, buf.cap);
    // Verify that the data length is a multiple of sizeof(uint16_t),
    // which _msp.write() requires
    Assert(!(len % sizeof(uint16_t))); // TODO: error handling
    
    _msp.read(_mspAddr, buf.data(), len/sizeof(uint16_t));
    _mspAddr += len;
    
    const uint32_t addr = cmd.arg.MSPDebugReadMem.addr;
    const size_t len = cmd.arg.MSPDebugReadMem.len; // uint16_t word count
    void* dst = _usb.dataSendBuf();
    // Verify that the requested amount of data will fit in `_usb.dataSendBuf()`
    Assert(len*sizeof(uint16_t) <= _usb.dataSendBufCap());
    _msp.read(_mspAddr, dst, len);
    _usb.dataSend(dst, len*sizeof(uint16_t));
    _updateStatus(Status::OK, true);
    
    
    _usb.dataRecv(buf.data, len); // TODO: handle errors
    
    
    
    
    // Verify that the data length is a multiple of sizeof(uint16_t),
    // which _msp.write() requires
    Assert(!(_bufs.front().len % sizeof(uint16_t))); // TODO: error handling
    // Write the data over Spy-bi-wire
    const uint16_t* data = (uint16_t*)_bufs.front().data;
    const size_t len = _bufs.front().len;
    const size_t wordCount = len/sizeof(uint16_t);
    _msp.write(_mspAddr, data, wordCount);
    // Update the MSP430 address to write to
    _mspAddr += len;
    // Pop the buffer, which we just finished sending over Spy-bi-wire
    _bufs.pop();
}


void System::_mspWriteUpdateState() {
    // Prepare to receive more USB data if:
    //   - we expect more data, and
    //   - there's space in the queue, and
    //   - we haven't arranged to receive USB data yet
    //
    // *** We want to do this before executing `_msp.write`, so that we can
    // *** be receiving USB data while we're sending data via Spy-bi-wire.
    if (_usbDataRem && !_bufs.full() && !_usb.dataRecvUnderway()) {
        _usbDataRecv();
    }
    
    // Send data if we have data to write
    if (!_bufs.empty()) {
        _mspWriteBuf();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (!_usbDataRem && _bufs.empty()) {
        _mspWriteFinish();
    }
}

void System::_mspWriteBuf() {
    // Verify that the data length is a multiple of sizeof(uint16_t),
    // which _msp.write() requires
    Assert(!(_bufs.front().len % sizeof(uint16_t))); // TODO: error handling
    // Write the data over Spy-bi-wire
    const uint16_t* data = (uint16_t*)_bufs.front().data;
    const size_t len = _bufs.front().len;
    const size_t wordCount = len/sizeof(uint16_t);
    _msp.write(_mspAddr, data, wordCount);
    // Update the MSP430 address to write to
    _mspAddr += len;
    // Pop the buffer, which we just finished sending over Spy-bi-wire
    _bufs.pop();
}

//#pragma mark - MSP430 Debug
//void System::_mspDebugConnect(const STLoader::Cmd& cmd) {
//    Assert(cmd.op == Op::MSPDebugConnect);
//    Assert(_status != Status::Busy);
//    
//    const auto r = _msp.connect();
//    _updateStatus((r==_msp.Status::OK ? Status::OK : Status::Error), true);
//}
//
//void System::_mspDebugDisconnect(const STLoader::Cmd& cmd) {
//    Assert(cmd.op == Op::MSPDebugDisconnect);
//    Assert(_status != Status::Busy);
//    
//    _msp.disconnect();
//    _updateStatus(Status::OK, true);
//}
//
//void System::_mspDebugReadMem(const STLoader::Cmd& cmd) {
//    Assert(cmd.op == Op::MSPDebugReadMem);
//    Assert(_status != Status::Busy);
//    
//    const uint32_t addr = cmd.arg.MSPDebugReadMem.addr;
//    const size_t len = cmd.arg.MSPDebugReadMem.len; // uint16_t word count
//    void* dst = _usb.dataSendBuf();
//    // Verify that the requested amount of data will fit in `_usb.dataSendBuf()`
//    Assert(len*sizeof(uint16_t) <= _usb.dataSendBufCap());
//    _msp.read(addr, dst, len);
//    _usb.dataSend(dst, len*sizeof(uint16_t));
//    _updateStatus(Status::OK, true);
//}
//
//void System::_mspDebugWriteMem(const STLoader::Cmd& cmd) {
//    
//}

#pragma mark - Other Commands

void System::_ledSet(const Cmd& cmd) {
    Assert(cmd.op == Op::LEDSet);
    Assert(_status != Status::Busy);
    
    switch (cmd.arg.LEDSet.idx) {
    case 0: _LED0::Write(cmd.arg.LEDSet.on); break;
    case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    _updateStatus(Status::OK, true);
}

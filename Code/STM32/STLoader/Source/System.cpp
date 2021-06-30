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







//void System::init() {
//    _super::init();
//    _usb.init();
//    _qspi.init();
//    
//    for (;;) {
//        auto s = _msp.connect();
//        if (s != _msp.Status::OK) {
//            if (s == _msp.Status::JTAGDisabled) {
//                s = _msp.erase();
//                continue;
//            } else {
//                abort();
//            }
//        }
//        
//        constexpr uint16_t PM5CTL0  = 0x0130;
//        constexpr uint16_t PAOUT    = 0x0202;
//        constexpr uint16_t PADIR    = 0x0204;
//        constexpr uint16_t PAREN    = 0x0206;
//        constexpr uint16_t PASEL0   = 0x020A;
//        constexpr uint16_t PASEL1   = 0x020C;
//        
////        // Clear LOCKLPM5 in the PM5CTL0 register
////        _msp.write(PM5CTL0, 0x0010);
//        
//        
//        
////        {
////            uint16_t val = 0;
////            
////            val = 1<<2;
////            _msp.framWrite(PADIR, &val, 1);
////            
////            val = 0xFFFF;
////            _msp.framWrite(PAOUT, &val, 1);
////            
////            val = _msp.read(PADIR);
////            val = _msp.read(PAOUT);
////            
////            // PAOUT = 0x7FFF
////            for (;;);
////        }
//        
//        
//        
//        {
//            uint16_t val = 0;
//            
//            val = 0xFFFF;
//            _msp.framWrite(PAOUT, &val, 1);
//            
//            val = _msp.read(PAOUT);
//            
//            val = 1<<2;
//            _msp.framWrite(PADIR, &val, 1);
//            
//            val = _msp.read(PAOUT);
//            val = _msp.read(PADIR);
//            
//            // PAOUT = 0x0000
//            for (;;);
//        }
//        
//        abort();
//        
//        _msp.disconnect();
//        HAL_Delay(500);
//    }
//}







//template <typename MSP>
//void _testFRAMWrite(MSP msp) {
//    constexpr uint32_t AddrStart = 0xE300;
//    constexpr uint32_t AddrEnd = 0xFF80;
//    constexpr uint32_t Len = (AddrEnd-AddrStart)/2; // Number of 16-bit words
//    
//    msp.crcReset();
//    msp.framWrite(AddrStart, (uint16_t*)(0x00200000), Len);
//    
//    auto s = msp.crcVerify(AddrStart, Len);
//    if (s != MSP::Status::OK) {
//        abort();
//    }
//}
//
//template <typename MSP>
//void _testRAMWrite(MSP msp) {
//    constexpr uint32_t AddrStart = 0x2000;
//    constexpr uint32_t AddrEnd = 0x2800;
//    constexpr uint32_t Len = (AddrEnd-AddrStart)/2; // Number of 16-bit words
//    
//    msp.crcReset();
//    msp.write(AddrStart, (uint16_t*)(0x00200000), Len);
//    
//    auto s = msp.crcVerify(AddrStart, Len);
//    if (s != MSP::Status::OK) {
//        abort();
//    }
//}
//
//// Test MSP430 RAM/FRAM writing
//void System::init() {
//    _super::init();
//    _usb.init();
//    _qspi.init();
//    
//    for (;; HAL_Delay(500)) {
//        auto s = _msp.connect();
//        if (s != _msp.Status::OK) {
//            if (s == _msp.Status::JTAGDisabled) {
//                s = _msp.erase();
//                continue;
//            } else {
//                abort();
//            }
//        }
//        
//        _testRAMWrite(_msp);
//        _testRAMWrite(_msp);
//        
//        _testRAMWrite(_msp);
//        _testFRAMWrite(_msp);
//        
//        _testFRAMWrite(_msp);
//        _testRAMWrite(_msp);
//        
//        _testFRAMWrite(_msp);
//        _testFRAMWrite(_msp);
//        
//        _msp.disconnect();
//    }
//}
//

//// Test MSP430 FRAM writing
//void System::init() {
//    _super::init();
//    _usb.init();
//    _qspi.init();
//    
//    for (;; HAL_Delay(500)) {
//        auto s = _msp.connect();
//        if (s != _msp.Status::OK) {
//            if (s == _msp.Status::JTAGDisabled) {
//                s = _msp.erase();
//                continue;
//            } else {
//                abort();
//            }
//        }
//        
//        constexpr uint32_t AddrStart = 0xE300;
//        constexpr uint32_t AddrEnd = 0xFF80;
//        constexpr uint32_t Len = (AddrEnd-AddrStart)/2; // Number of 16-bit words
//        
//        _msp.crcReset();
//        _msp.framWrite(AddrStart, (uint16_t*)(0x20010000), Len);
//        
//        s = _msp.crcVerify(AddrStart, Len);
//        if (s != _msp.Status::OK) {
//            abort();
//        }
//        
//        _msp.disconnect();
//    }
//}
//
//
//
//// Test MSP430 RAM writing
//void System::init() {
//    _super::init();
//    _usb.init();
//    _qspi.init();
//    
//    for (;; HAL_Delay(500)) {
//        auto s = _msp.connect();
//        if (s != _msp.Status::OK) {
//            if (s == _msp.Status::JTAGDisabled) {
//                s = _msp.erase();
//                continue;
//            } else {
//                abort();
//            }
//        }
//        
//        constexpr uint32_t AddrStart = 0x2000;
//        constexpr uint32_t AddrEnd = 0x2800;
//        constexpr uint32_t Len = (AddrEnd-AddrStart)/2; // Number of 16-bit words
//        
//        _msp.crcReset();
//        _msp.write(AddrStart, (uint16_t*)(0x20010000), Len);
//        
////        uint16_t* stmAddr = (uint16_t*)0x20010000;
////        uint32_t mspAddr = AddrStart;
////
////        const uint16_t expected = *stmAddr;
////        uint16_t got1 = 0;
////        _msp.read(mspAddr, &got1, 1);
////
////        uint16_t got2 = 0;
////        got2 = _msp.read(mspAddr);
////
////        _msp.crcReset();
////        _msp.framWrite(AddrStart, (uint16_t*)(0x20010000), 1);
////        
////        for (uint32_t i=0; i<Len; i++) {
////            const uint16_t expected = *stmAddr;
////            uint16_t got1 = 0;
////            _msp.read(mspAddr, &got1, 1);
////            
////            uint16_t got2 = 0;
////            got2 = _msp.read(mspAddr);
////            
////            if (expected != got1) {
////                abort();
////            }
////            
////            if (expected != got2) {
////                abort();
////            }
////            
////            stmAddr++;
////            mspAddr+=2;
////        }
//        
//        s = _msp.crcVerify(AddrStart, Len);
//        if (s != _msp.Status::OK) {
//            abort();
//        }
//        
//        _msp.disconnect();
//    }
//}









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
    Assert(ev.len == sizeof(cmd));
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
    case Op::StatusGet: _statusGet(cmd);   break;
    // Set LED
    case Op::LEDSet:    _ledSet(cmd);       break;
    // Bad command
    default:            abort();            break;
    }
    
    // Prepare to receive another command
    _usb.cmdRecv();
}

void System::_usbHandleData(const USB::Data& ev) {
    Assert(_status == Status::Busy);
    Assert(ev.len <= _usbDataRem);
    _usbDataRem -= ev.len;
    
    switch (_usbDataOp) {
    case Op::STWrite:   _stHandleUSBData(ev);   break;
    case Op::ICEWrite:  _iceHandleUSBData(ev);  break;
    case Op::MSPWrite:  _mspHandleUSBData(ev);  break;
    default:            abort();                break;
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

static size_t _regionCapacity(void* addr) {
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
    const size_t regionCap = _regionCapacity(addr);
    // Confirm that the region's capacity is large enough to hold the incoming
    // data length (ceiled to the packet length)
    Assert(regionCap >= ceilLen); // TODO: error handling
    
    // Update our status
    _usbDataOp = cmd.op;
    _usbDataRem = len;
    _status = Status::Busy;
    
    // Prepare to receive USB data
    _usb.dataRecv(addr, ceilLen);
}

void System::_stFinish(const Cmd& cmd) {
    Assert(cmd.op == Op::STFinish);
    
    Start.setAppEntryPointAddr(cmd.arg.STFinish.entryPointAddr);
    // Perform software reset
    HAL_NVIC_SystemReset();
    
    // Unreachable
    // Update our status
    _status = Status::OK;
}

void System::_stWriteFinish() {
    Assert(_status == Status::Busy);
    // Update our status
    _status = Status::OK;
}

void System::_stHandleUSBData(const USB::Data& ev) {
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
    
    // Update our status
    _usbDataOp = cmd.op;
    _usbDataRem = cmd.arg.ICEWrite.len;
    _status = Status::Busy;
    
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
    if (_usbDataRem && !_bufs.full() && !_usb.dataRecvUnderway()) {
        _usbDataRecv();
    }
    
    // If there's no more data coming over USB, and there's no more
    // data to write, then we're done
    if (!_usbDataRem && _bufs.empty()) {
        _iceWriteFinish();
    }
}

void System::_iceHandleUSBData(const USB::Data& ev) {
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
    _usbDataRem = cmd.arg.MSPWrite.len;
    _msp.crcReset();
    _mspAddr = cmd.arg.MSPWrite.addr;
    _status = Status::Busy;
    
    // Prepare to receive USB data
    _usbDataRecv();
}

void System::_mspFinish(const Cmd& cmd) {
    Assert(cmd.op == Op::MSPFinish);
    Assert(_status != Status::Busy);
    
    _msp.disconnect();
    _status = Status::OK;
}

void System::_mspWriteFinish() {
    // Verify the CRC of all the data we wrote
    auto r = _msp.crcVerify();
    if (r != _msp.Status::OK) {
        _status = Status::Error;
        return;
    }
    
    _status = Status::OK;
}

void System::_mspHandleUSBData(const USB::Data& ev) {
    Assert(ev.len);
    Assert(_status == Status::Busy);
    Assert(!_bufs.full());
    
    // Enqueue the buffer
    _bufs.back().len = ev.len;
    _bufs.push();
    
    _mspUpdateState();
}

void System::_mspUpdateState() {
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

#pragma mark - Other Commands

void System::_statusGet(const Cmd& cmd) {
    Assert(cmd.op == Op::StatusGet);
    _usb.statusSend(&_status, sizeof(_status));
}

void System::_ledSet(const Cmd& cmd) {
    Assert(cmd.op == Op::LEDSet);
    Assert(_status != Status::Busy);
    
    switch (cmd.arg.LEDSet.idx) {
    case 0: _LED0::Write(cmd.arg.LEDSet.on); break;
    case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    _status = Status::OK;
}

#include "System.h"
#include "Assert.h"
#include "Abort.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>

using namespace STLoader;

System::System() :
// QSPI clock divider=5 => run QSPI clock at 21.3 MHz
// QSPI alignment=byte, so we can transfer single bytes at a time
_qspi(QSPI::Mode::Single, 5, QSPI::Align::Byte),
_iceCRST_(GPIOI, GPIO_PIN_6),
_iceCDONE(GPIOI, GPIO_PIN_7),
_iceSPIClk(GPIOB, GPIO_PIN_2),
_iceSPICS_(GPIOB, GPIO_PIN_6),
_iceBufs(_iceBuf0, _iceBuf1) {
}

void System::init() {
    _super::init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    _usb.init();
    _qspi.init();
    
    // Configure ice40 control GPIOs
    _iceCRST_.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _iceCDONE.config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
}

void System::_handleEvent() {
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.eventChannel.readSelect()) {
        _usbHandleEvent(*x);
    
    } else if (auto x = _usb.stCmdChannel.readSelect()) {
        _stHandleCmd(*x);
    
    } else if (auto x = _usb.stDataChannel.readSelect()) {
        _stHandleData(*x);
    
    } else if (auto x = _usb.iceCmdChannel.readSelect()) {
        _iceHandleCmd(*x);
    
    } else if (auto x = _usb.iceDataChannel.readSelect()) {
        _iceHandleData(*x);
    
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
            // Prepare to receive STM32 bootloader commands
            _usb.stCmdRecv();
            // Prepare to receive ICE40 bootloader commands
            _usb.iceCmdRecv();
        }
        break;
    }
    
    default: {
        // Invalid event type
        Abort();
    }}
}

void System::_stHandleCmd(const USB::Cmd& ev) {
    STCmd cmd;
    Assert(ev.len == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.len);
    switch (cmd.op) {
    // Get status
    case STCmd::Op::GetStatus: {
        _usb.stStatusSend(&_stStatus, sizeof(_stStatus));
        break;
    }
    
    // Write data
    //   Prepare the DATA_OUT endpoint for writing at the given address+length
    case STCmd::Op::WriteData: {
        _stStatus = STStatus::Writing;
        void*const addr = (void*)cmd.arg.writeData.addr;
        // Verify that `addr` is in one of the allowed RAM regions
        extern uint8_t _sitcm_ram[], _eitcm_ram[];
        extern uint8_t _sdtcm[], _edtcm[];
        extern uint8_t _ssram1[], _esram1[];
        size_t len = 0;
        if (addr>=_sitcm_ram && addr<_eitcm_ram) {
            len = (uintptr_t)_eitcm_ram-(uintptr_t)addr;
        } else if (addr>=_sdtcm && addr<_edtcm) {
            len = (uintptr_t)_edtcm-(uintptr_t)addr;
        } else if (addr>=_ssram1 && addr<_esram1) {
            len = (uintptr_t)_esram1-(uintptr_t)addr;
        } else {
            // TODO: implement proper error handling on writing out of the allowed regions
            Abort();
        }
        
        // Round `len` down to the nearest max packet size.
        // (We can only restrict the receipt of USB data
        // at multiples of the max packet size.)
        len -= len%USB::MaxPacketSize::Data;
        Assert(len); // TODO: error handling
        _usb.stDataRecv(addr, len);
        break;
    }
    
    // Reset
    //   Stash the entry point address for access after we reset,
    //   Perform a software reset
    case STCmd::Op::Reset: {
        Start.setAppEntryPointAddr(cmd.arg.reset.entryPointAddr);
        // Perform software reset
        HAL_NVIC_SystemReset();
        break;
    }
    
    // Set LED
    case STCmd::Op::LEDSet: {
        switch (cmd.arg.ledSet.idx) {
        case 0: _led0.write(cmd.arg.ledSet.on); break;
        case 1: _led1.write(cmd.arg.ledSet.on); break;
        case 2: _led2.write(cmd.arg.ledSet.on); break;
        case 3: _led3.write(cmd.arg.ledSet.on); break;
        }
        
        break;
    }
    
    // Bad command
    default: {
        break;
    }}
    
    // Prepare to receive another command
    _usb.stCmdRecv(); // TODO: handle errors
}

void System::_stHandleData(const USB::Data& ev) {
    // We're done writing
    _stStatus = STStatus::Idle;
}

void System::_iceHandleCmd(const USB::Cmd& ev) {
    ICECmd cmd;
    Assert(ev.len == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.len);
    switch (cmd.op) {
    // Get status
    case ICECmd::Op::GetStatus: {
        _usb.iceStatusSend(&_iceStatus, sizeof(_iceStatus));
        break;
    }
    
    // Start configuring
    case ICECmd::Op::Start: {
        Assert( _iceStatus==ICEStatus::Idle ||
                _iceStatus==ICEStatus::Done ||
                _iceStatus==ICEStatus::Error);
        Assert(cmd.arg.start.len);
        
        _iceSPIClk.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _iceSPICS_.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        
        // Put ICE40 into configuration mode
        _iceSPIClk.write(1);
        
        _iceSPICS_.write(0);
        _iceCRST_.write(0);
        HAL_Delay(1); // Sleep 1 ms (ideally, 200 ns)
        
        _iceCRST_.write(1);
        HAL_Delay(2); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
        
        // Release chip-select before we give control of _iceSPIClk/_iceSPICS_ to QSPI
        _iceSPICS_.write(1);
        
        // Have QSPI take over _iceSPIClk/_iceSPICS_
        _qspi.config();
        
        // Send 8 clocks
        static const uint8_t ff = 0xff;
        _qspiWrite(&ff, 1);
        
        // Wait for write to complete
        _qspi.eventChannel.read();
        
        // Update our state
        _iceRemLen = cmd.arg.start.len;
        _iceStatus = ICEStatus::Configuring;
        
        // Prepare to receive ICE40 bootloader data
        _iceDataRecv();
        break;
    }
    
    // Finish configuring
    case ICECmd::Op::Finish: {
        bool done = false;
        for (int i=0; i<10; i++) {
            done = _iceCDONE.read();
            if (done) break;
            HAL_Delay(1); // Sleep 1 ms
        }
        
        if (done) {
            _iceStatus = ICEStatus::Done;
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
        
        } else {
            // If CDONE isn't high after 10ms, consider it a failure
            _iceStatus = ICEStatus::Error;
        }
        
        break;
    }
    
    // Bad command
    default: {
        break;
    }}
    
    // Prepare to receive another command
    _usb.iceCmdRecv(); // TODO: handle errors
}

void System::_iceHandleData(const USB::Data& ev) {
    Assert(_iceBufs.writable());
    Assert(_iceStatus == ICEStatus::Configuring);
    Assert(ev.len <= _iceRemLen);
    
    const bool wasReadable = _iceBufs.readable();
    
    // Enqueue the buffer
    {
        _iceBufs.writeBuf().len = ev.len;
        _iceBufs.writeEnqueue();
        
        // Update the number of remaining bytes to receive from the host
        _iceRemLen -= ev.len;
    }
    
    // Start a SPI transaction when we go from 0->1
    if (!wasReadable) {
        _qspiWriteBuf();
    }
    
    // Prepare to receive more data if we're expecting more,
    // and we have a buffer to store the data in
    if (_iceRemLen && _iceBufs.writable()) {
        _iceDataRecv();
    }
}

void System::_iceHandleQSPIEvent(const QSPI::Signal& ev) {
    Assert(_iceBufs.readable());
    const bool wasWritable = _iceBufs.writable();
    
    // Dequeue the buffer
    _iceBufs.readDequeue();
    
    // Start another SPI transaction if there's more data to write
    if (_iceBufs.readable()) {
        _qspiWriteBuf();
    }
    
    if (_iceRemLen) {
        // Prepare to receive more data if we're expecting more,
        // and we were previously un-writable
        if (!wasWritable) {
            _iceDataRecv();
        }
    } else if (!_iceBufs.readable()) {
        // We're done
        _iceStatus = ICEStatus::Idle;
    }

}

void System::_iceDataRecv() {
    Assert(_iceBufs.writable());
    auto& buf = _iceBufs.writeBuf();
    _usb.iceDataRecv(buf.data, buf.cap); // TODO: handle errors
}

void System::_qspiWriteBuf() {
    Assert(_iceBufs.readable());
    const auto& buf = _iceBufs.readBuf();
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

System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
}

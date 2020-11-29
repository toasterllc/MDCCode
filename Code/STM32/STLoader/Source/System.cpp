#include "System.h"
#include "Assert.h"
#include "Abort.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>

using namespace STLoader;

System::System() :
_iceCRST_(GPIOI, GPIO_PIN_6),
_iceCDONE(GPIOI, GPIO_PIN_7),
_iceSPIClk(GPIOB, GPIO_PIN_2),
_iceSPICS_(GPIOB, GPIO_PIN_6) {
}

void System::init() {
    _super::init();
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    // Configure ice40 control GPIOs
    _iceCRST_.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _iceCDONE.config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
}

void System::_handleEvent() {
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = usb.eventChannel.readSelect()) {
        _usbHandleEvent(*x);
    
    } else if (auto x = usb.stCmdChannel.readSelect()) {
        _stHandleCmd(*x);
    
    } else if (auto x = usb.stDataChannel.readSelect()) {
        _stHandleData(*x);
    
    } else if (auto x = usb.iceCmdChannel.readSelect()) {
        _iceHandleCmd(*x);
    
    } else if (auto x = usb.iceDataChannel.readSelect()) {
        _iceHandleData(*x);
    
    } else if (auto x = qspi.eventChannel.readSelect()) {
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
        if (usb.state() == USB::State::Connected) {
            // Prepare to receive STM32 bootloader commands
            usb.stRecvCmd();
            // Prepare to receive ICE40 bootloader commands
            usb.iceRecvCmd();
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
        usb.stSendStatus(&_stStatus, sizeof(_stStatus));
        break;
    }
    
    // Write data
    //   Prepare the DATA_OUT endpoint for writing at the given address+length
    case STCmd::Op::WriteData: {
        _stStatus = STStatus::Writing;
        void*const addr = (void*)cmd.arg.writeData.addr;
        // Verify that `addr` is in the allowed RAM range
        extern uint8_t _sapp_ram[];
        extern uint8_t _eapp_ram[];
        Assert(addr >= _sapp_ram); // TODO: error handling
        Assert(addr < _eapp_ram); // TODO: error handling
        size_t len = (uintptr_t)_eapp_ram-(uintptr_t)addr;
        // Round `len` down to the nearest max packet size.
        // (We can only restrict the receipt of USB data
        // at multiples of the max packet size.)
        len -= len%USB::MaxPacketSize::Data;
        Assert(len); // TODO: error handling
        usb.stRecvData(addr, len);
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
        case 0: led0.write(cmd.arg.ledSet.on); break;
        case 1: led1.write(cmd.arg.ledSet.on); break;
        case 2: led2.write(cmd.arg.ledSet.on); break;
        case 3: led3.write(cmd.arg.ledSet.on); break;
        }
        
        break;
    }
    
    // Bad command
    default: {
        break;
    }}
    
    // Prepare to receive another command
    usb.stRecvCmd(); // TODO: handle errors
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
        usb.iceSendStatus(&_iceStatus, sizeof(_iceStatus));
        break;
    }
    
    // Start configuring
    case ICECmd::Op::Start: {
        Assert(_iceStatus == ICEStatus::Idle);
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
        qspi.config();
        
        // Send 8 clocks
        qspi.write(_iceBuf, 1);
        
        // Wait for write to complete
        QSPI::Event qev = qspi.eventChannel.read();
        Assert(qev.type == QSPI::Event::Type::WriteDone);
        
        // Update our state
        _iceRemLen = cmd.arg.start.len;
        _iceStatus = ICEStatus::Configuring;
        
        // Prepare to receive ICE40 bootloader data
        _iceRecvData();
        break;
    }
    
    // Finish configuring
    case ICECmd::Op::Finish: {
        Assert(_iceStatus == ICEStatus::Idle);
        // Send >100 clocks (13*8 = 104 clocks)
        qspi.write(_iceBuf, 13);
        // Wait for write to complete
        QSPI::Event qev = qspi.eventChannel.read();
        Assert(qev.type == QSPI::Event::Type::WriteDone);
        break;
    }
    
    // Read CDONE pin
    case ICECmd::Op::ReadCDONE: {
        _iceCDONEState = (_iceCDONE.read() ? ICECDONE::OK : ICECDONE::Error);
        usb.iceSendStatus(&_iceCDONEState, sizeof(_iceCDONEState));
        break;
    }
    
    // Bad command
    default: {
        break;
    }}
    
    // Prepare to receive another command
    usb.iceRecvCmd(); // TODO: handle errors
}

void System::_iceHandleData(const USB::Data& ev) {
    Assert(!_iceBufFull);
    Assert(_iceStatus == ICEStatus::Configuring);
    Assert(ev.len <= _iceRemLen);
    
    const bool wasEmpty = _iceBufEmpty();
    
    // Enqueue the buffer
    {
        ICEBuf& buf = _iceBuf[_iceBufWPtr];
        _iceBufWPtr++;
        if (_iceBufWPtr == _ICEBufCount) _iceBufWPtr = 0;
        if (_iceBufWPtr == _iceBufRPtr) _iceBufFull = true;
        
        buf.len = ev.len;
        
        // Update the number of remaining bytes to receive from the host
        _iceRemLen -= ev.len;
    }
    
    // Start a SPI transaction when we go from 0->1
    if (wasEmpty) {
        _qspiWriteBuf();
    }
    
    // Prepare to receive more data if we're expecting more,
    // and we have a buffer to store the data in
    if (_iceRemLen && !_iceBufFull) {
        _iceRecvData();
    }
}

void System::_iceHandleQSPIEvent(const QSPI::Event& ev) {
    Assert(!_iceBufEmpty());
    switch (ev.type) {
    // Write done
    case QSPI::Event::Type::WriteDone: {
        const bool wasFull = _iceBufFull;
        
        // Dequeue the buffer
        {
            _iceBufRPtr++;
            if (_iceBufRPtr == _ICEBufCount) _iceBufRPtr = 0;
            _iceBufFull = false;
        }
        
        // Start another SPI transaction if there's more data to write
        if (!_iceBufEmpty()) {
            _qspiWriteBuf();
        }
        
        if (_iceRemLen) {
            // Prepare to receive more data if we're expecting more,
            // and we were previously full
            if (wasFull) {
                _iceRecvData();
            }
        } else if (_iceBufEmpty()) {
            // We're done
            _iceStatus = ICEStatus::Idle;
        }
        break;
    }
    
    default: {
        Abort();
    }}
}

bool System::_iceBufEmpty() {
    return _iceBufWPtr==_iceBufRPtr && !_iceBufFull;
}

void System::_iceRecvData() {
    Assert(!_iceBufFull);
    ICEBuf& buf = _iceBuf[_iceBufWPtr];
    usb.iceRecvData(buf.data, sizeof(buf.data)); // TODO: handle errors
}

void System::_qspiWriteBuf() {
    Assert(!_iceBufEmpty());
    const ICEBuf& buf = _iceBuf[_iceBufRPtr];
    _qspiWrite(buf.data, buf.len);
}

void System::_qspiWrite(void* data, size_t len) {
    static const QSPI_CommandTypeDef QSPICmd = {
        .Instruction = 0,
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        
        .Address = 0,
        .AddressSize = QSPI_ADDRESS_32_BITS,
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
    
    qspi.write(QSPICmd, data, len);
}

System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
}

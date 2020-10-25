#include "System.h"
#include "assert.h"
#include "abort.h"
#include "usbd_core.h"
#include "SystemClock.h"
#include "Startup.h"

using namespace STLoader;

System Sys;

System::System() :
_iceCRST_(GPIOC, GPIO_PIN_3),
_iceCDONE(GPIOC, GPIO_PIN_2),
_iceSPIClk(GPIOB, GPIO_PIN_2),
_iceSPICS_(GPIOB, GPIO_PIN_6),

_led0(GPIOE, GPIO_PIN_12),
_led1(GPIOE, GPIO_PIN_15),
_led2(GPIOB, GPIO_PIN_10),
_led3(GPIOB, GPIO_PIN_11) {
    
}

void System::init() {
    // Reset peripherals, initialize flash interface, initialize Systick
    HAL_Init();
    
    // Configure the system clock
    SystemClock::Init();
    
    __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE
    __HAL_RCC_GPIOB_CLK_ENABLE(); // QSPI, LEDs
    __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
    __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
    
    // Configure ice40 control GPIOs
    _iceCRST_.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _iceCDONE.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Configure our LEDs
    _led0.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _led1.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _led2.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _led3.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Initialize QSPI
    qspi.init();
    
    // Initialize USB
    usb.init();
}

void System::handleEvent() {
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
            // Prepare to receive ICE40 bootloader data
            usb.iceRecvData(_iceBuf, sizeof(_iceBuf)); // TODO: handle errors
        }
        break;
    }
    
    default: {
        // Invalid event tpye
        abort();
    }}
}

void System::_stHandleCmd(const USB::Cmd& ev) {
    STCmd cmd;
    assert(ev.dataLen == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.dataLen);
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
        extern uint8_t _sram_app[];
        extern uint8_t _eram_app[];
        assert(addr >= _sram_app); // TODO: error handling
        assert(addr < _eram_app); // TODO: error handling
        const size_t len = (uintptr_t)_eram_app-(uintptr_t)addr;
        usb.stRecvData((void*)cmd.arg.writeData.addr, len);
        break;
    }
    
    // Reset
    //   Stash the entry point address for access after we reset,
    //   Perform a software reset
    case STCmd::Op::Reset: {
        Startup::SetAppEntryPointAddr(cmd.arg.reset.entryPointAddr);
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
    usb.stRecvCmd(); // TODO: handle errors
}

void System::_stHandleData(const USB::Data& ev) {
    // We're done writing
    _stStatus = STStatus::Idle;
}

void System::_iceHandleCmd(const USB::Cmd& ev) {
    ICECmd cmd;
    assert(ev.dataLen == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.dataLen);
    switch (cmd.op) {
    // Get status
    case ICECmd::Op::GetStatus: {
        usb.iceSendStatus(&_iceStatus, sizeof(_iceStatus));
        break;
    }
    
    // Start configuring
    case ICECmd::Op::Start: {
//        _iceSPIClk.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//        _iceSPICS_.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//        
//        // Put ICE40 into configuration mode
//        _iceSPIClk.write(1);
//        
//        _iceSPICS_.write(0);
//        _iceCRST_.write(0);
//        HAL_Delay(1); // Sleep 1 ms (ideally, 200 ns)
//        
//        _iceCRST_.write(1);
//        HAL_Delay(2); // Sleep 2 ms (ideally, 1.2 ms for 8K devices)
//        
//        // Release chip-select before we give control of _iceSPIClk/_iceSPICS_ to QSPI
//        _iceSPICS_.write(1);
        
        // Have QSPI take over _iceSPIClk/_iceSPICS_
        qspi.config();
        
        // Send 8 clocks
        qspi.write(_iceBuf, 1);
        
        // Wait for write to complete
        QSPI::Event qev = qspi.eventChannel.read();
        assert(qev.type == QSPI::Event::Type::WriteDone);
        
        _iceStatus = ICEStatus::Configuring;
        break;
    }
    
    // Finish configuring
    case ICECmd::Op::Finish: {
        // Send >100 clocks (13*8 = 104 clocks)
        qspi.write(_iceBuf, 13);
        // Wait for write to complete
        QSPI::Event qev = qspi.eventChannel.read();
        assert(qev.type == QSPI::Event::Type::WriteDone);
        
        _iceStatus = ICEStatus::Idle;
        break;
    }
    
    // Read CDONE pin
    case ICECmd::Op::ReadCDONE: {
        ICECDONE cdone = (_iceCDONE.read() ? ICECDONE::OK : ICECDONE::Error);
        usb.iceSendStatus(&cdone, sizeof(cdone));
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
    assert(_iceStatus == ICEStatus::Configuring);
    qspi.write(_iceBuf, ev.dataLen);
}

void System::_iceHandleQSPIEvent(const QSPI::Event& ev) {
    switch (ev.type) {
    // Write done
    case QSPI::Event::Type::WriteDone: {
        // Prepare to receive more data
        usb.iceRecvData(_iceBuf, sizeof(_iceBuf)); // TODO: handle errors
        break;
    }}
}

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys.handleEvent();
    }
}

#include <stdbool.h>
#include <algorithm>
#include "assert.h"
#include "usbd_core.h"
#include "GPIO.h"
#include "USB.h"
#include "QSPI.h"
#include "STLoaderTypes.h"
#include "SystemClock.h"
#include "Startup.h"

class System {
public:
    System() :
    _iceCRST_(GPIOC, GPIO_PIN_3),
    _iceCDONE(GPIOC, GPIO_PIN_2),
    _led0(GPIOE, GPIO_PIN_12),
    _led1(GPIOE, GPIO_PIN_15),
    _led2(GPIOB, GPIO_PIN_10),
    _led3(GPIOB, GPIO_PIN_11) {
        
    }
    
    void init() {
        // Reset peripherals, initialize flash interface, initialize Systick
        HAL_Init();
        
        // Configure the system clock
        SystemClock::Init();
        
        __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE
        __HAL_RCC_GPIOB_CLK_ENABLE(); // QSPI, LEDs
        __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
        __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
        
        // Configure ice40 control GPIOs
        _iceCRST_.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _iceCDONE.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        
        // Configure our LEDs
        _led0.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _led1.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _led2.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _led3.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        
        // Initialize peripherals
        _qspi.init();
        _usb.init();
    }
    
    void handleEvent() {
        // Wait for an event to occur on one of our channels
        ChannelSelect::Start();
        if (auto x = _usb.stCmdChannel.readSelect()) {
            _handleSTCmd(*x);
        
        } else if (auto x = _usb.stDataChannel.readSelect()) {
            _handleSTData(*x);
        
        } else if (auto x = _usb.iceCmdChannel.readSelect()) {
            _handleICECmd(*x);
        
        } else if (auto x = _usb.iceDataChannel.readSelect()) {
            _handleICEData(*x);
        
        } else {
            // No events, go to sleep
            ChannelSelect::Wait();
        }
    }
    
private:
    void _handleSTCmd(const USB::CmdEvent& ev) {
        STLoader::STCmd cmd;
        assert(ev.dataLen == sizeof(cmd)); // TODO: handle errors
        memcpy(&cmd, ev.data, ev.dataLen);
        switch (cmd.op) {
        // Get status
        case STLoader::STCmd::Op::GetStatus: {
            _usb.stSendStatus(&_stStatus, sizeof(_stStatus));
            break;
        }
        
        // Write data
        //   Prepare the DATA_OUT endpoint for writing at the given address+length
        case STLoader::STCmd::Op::WriteData: {
            _stStatus = STLoader::STStatus::Writing;
            void*const addr = (void*)cmd.arg.writeData.addr;
            // Verify that `addr` is in the allowed RAM range
            extern uint8_t _sram_app[];
            extern uint8_t _eram_app[];
            assert(addr >= _sram_app); // TODO: error handling
            assert(addr < _eram_app); // TODO: error handling
            const size_t len = (uintptr_t)_eram_app-(uintptr_t)addr;
            _usb.stRecvData((void*)cmd.arg.writeData.addr, len);
            break;
        }
        
        // Reset
        //   Stash the entry point address for access after we reset,
        //   Perform a software reset
        case STLoader::STCmd::Op::Reset: {
            Startup::SetAppEntryPointAddr(cmd.arg.reset.entryPointAddr);
            // Perform software reset
            HAL_NVIC_SystemReset();
            break;
        }
        
        // Set LED
        case STLoader::STCmd::Op::LEDSet: {
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
        _usb.stRecvCmd(); // TODO: handle errors
    }
    
    void _handleSTData(const USB::DataEvent& ev) {
        // We're done writing
        _stStatus = STLoader::STStatus::Idle;
    }
    
    void _handleICECmd(const USB::CmdEvent& ev) {
    }
    
    void _handleICEData(const USB::DataEvent& ev) {
    }
    
    QSPI _qspi;
    USB _usb;
    STLoader::STStatus _stStatus = STLoader::STStatus::Idle;
    STLoader::ICEStatus _iceStatus = STLoader::ICEStatus::Idle;
    
    GPIO _iceCRST_;
    GPIO _iceCDONE;
    
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
};

static System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys.handleEvent();
    }
}

#include "SystemBase.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "Toastbox/TaskOld.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    [[noreturn]] void run();
    
private:
    void _resetTasks();
    
    // USB
    void _usb_cmdTaskFn();
    
    void _usb_dataOutTaskFn();
    
    void _usb_dataInTaskFn();
    void _usb_dataInSendStatus(bool status);
    
    // Common Commands
    void _endpointsFlush_taskFn();
    void _statusGet_taskFn();
    void _bootloaderInvoke_taskFn();
    void _ledSet();
    
    // STM32 Bootloader
    void _stm_writeTaskFn();
    void _stm_resetTaskFn();
    
    // ICE40 Bootloader
    void _ice_writeTaskFn();
    
    // MSP430 Bootloader
    void _msp_connect();
    void _msp_disconnect();
    void _msp_readTaskFn();
    void _msp_writeTaskFn();
    void _msp_debugTaskFn();
    bool _msp_debugPushReadBits();
    bool _msp_debugHandleSBWIO(const STM::MSPDebugCmd& cmd);
    bool _msp_debugHandleCmd(const STM::MSPDebugCmd& cmd);
    
    // Peripherals
    USB _usb;
    QSPI _qspi;
    using _ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    STM::Cmd _cmd = {};
    
    alignas(4) uint8_t _buf0[1024]; // Aligned to send via USB
    alignas(4) uint8_t _buf1[1024]; // Aligned to send via USB
    BufQueue<2> _bufs;
    
    struct {
        size_t len = 0;
    } _usbDataOut;
    
    struct {
        size_t len = 0;
        alignas(4) bool status = false; // Aligned to send via USB
    } _usbDataIn;
    
    struct {
        struct {
            uint8_t bits = 0;
            uint8_t bitsLen = 0;
            size_t len = 0;
        } read;
    } _mspDebug;
    
    Toastbox::Task _usb_cmdTask             = Toastbox::Task([&] {  _usb_cmdTaskFn();           });
    Toastbox::Task _usb_dataOutTask         = Toastbox::Task([&] {  _usb_dataOutTaskFn();       });
    Toastbox::Task _usb_dataInTask          = Toastbox::Task([&] {  _usb_dataInTaskFn();        });
    Toastbox::Task _endpointsFlush_task     = Toastbox::Task([&] {  _endpointsFlush_taskFn();   });
    Toastbox::Task _statusGet_task          = Toastbox::Task([&] {  _statusGet_taskFn();        });
    Toastbox::Task _bootloaderInvoke_task   = Toastbox::Task([&] {  _bootloaderInvoke_taskFn(); });
    Toastbox::Task _stm_writeTask           = Toastbox::Task([&] {  _stm_writeTaskFn();         });
    Toastbox::Task _stm_resetTask           = Toastbox::Task([&] {  _stm_resetTaskFn();         });
    Toastbox::Task _ice_writeTask           = Toastbox::Task([&] {  _ice_writeTaskFn();         });
    Toastbox::Task _msp_readTask            = Toastbox::Task([&] {  _msp_readTaskFn();          });
    Toastbox::Task _msp_writeTask           = Toastbox::Task([&] {  _msp_writeTaskFn();         });
    Toastbox::Task _msp_debugTask           = Toastbox::Task([&] {  _msp_debugTaskFn();         });
    
    std::reference_wrapper<Toastbox::Task> _tasks[12] = {
        _usb_cmdTask,
        _usb_dataOutTask,
        _usb_dataInTask,
        _endpointsFlush_task,
        _statusGet_task,
        _bootloaderInvoke_task,
        _stm_writeTask,
        _stm_resetTask,
        _ice_writeTask,
        _msp_readTask,
        _msp_writeTask,
        _msp_debugTask,
    };
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

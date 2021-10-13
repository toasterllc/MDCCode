#include "SystemBase.h"
#include "ST.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    [[noreturn]] void run();
    
private:
    void _resetTasks();
    
    // USB
    void _usbCmd_taskFn();
    
    void _usbDataOut_taskFn();
    
    void _usbDataIn_taskFn();
    void _usbDataIn_sendStatus(bool status);
    
    // Common Commands
    void _resetEndpoints_taskFn();
    void _invokeBootloader();
    void _ledSet();
    
    // STM32 Bootloader
    void _stm_taskFn();
    void _stm_reset();
    
    // ICE40 Bootloader
    void _ice_taskFn();
    
    // MSP430 Bootloader
    void _msp_connect();
    void _msp_disconnect();
    
    void _mspRead_taskFn();
    
    void _mspWrite_taskFn();
    
    void _mspDebug_taskFn();
    bool _mspDebug_pushReadBits();
    bool _mspDebug_handleSBWIO(const ST::MSPDebugCmd& cmd);
    bool _mspDebug_handleCmd(const ST::MSPDebugCmd& cmd);
    
    USB _usb;
    QSPI _qspi;
    using _ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    ST::Cmd _cmd = {};
    
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
    
    Task _usbCmd_task           = Task([&] {  _usbCmd_taskFn();           });
    Task _usbDataOut_task       = Task([&] {  _usbDataOut_taskFn();       });
    Task _usbDataIn_task        = Task([&] {  _usbDataIn_taskFn();        });
    Task _resetEndpoints_task   = Task([&] {  _resetEndpoints_taskFn();   });
    Task _stm_task              = Task([&] {  _stm_taskFn();              });
    Task _ice_task              = Task([&] {  _ice_taskFn();              });
    Task _mspRead_task          = Task([&] {  _mspRead_taskFn();          });
    Task _mspWrite_task         = Task([&] {  _mspWrite_taskFn();         });
    Task _mspDebug_task         = Task([&] {  _mspDebug_taskFn();         });
    
    std::reference_wrapper<Task> _tasks[9] = {
        _usbCmd_task,
        _usbDataOut_task,
        _usbDataIn_task,
        _resetEndpoints_task,
        _stm_task,
        _ice_task,
        _mspRead_task,
        _mspWrite_task,
        _mspDebug_task,
    };
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

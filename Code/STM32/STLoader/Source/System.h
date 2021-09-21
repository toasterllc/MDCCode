#include "SystemBase.h"
#include "STLoaderTypes.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    [[noreturn]] void run();
    
private:
    void _pauseTasks();
    
    // USB
    void _usbCmd_task();
    void _usbCmd_reset();
    void _usbCmd_finish(bool status);
    
    void _usbDataOut_task();
    
    void _usbDataIn_task();
    void _usbDataIn_sendStatus(bool status);
    
    // STM32 Bootloader
    void _stm_task();
    void _stm_reset();
    
    // ICE40 Bootloader
    void _ice_task();
    void _ice_write();
    bool _ice_writeFinish();
    
    // MSP430 Bootloader
    void _msp_connect();
    void _msp_disconnect();
    
    void _mspRead_task();
    
    void _mspWrite_task();
    
    void _mspDebug_task();
    bool _mspDebug_pushReadBits();
    bool _mspDebug_handleSBWIO(const STLoader::MSPDebugCmd& cmd);
    bool _mspDebug_handleCmd(const STLoader::MSPDebugCmd& cmd);
    
    // Other commands
    void _ledSet();
    
    USB _usb;
    QSPI _qspi;
    using _ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    STLoader::Cmd _cmd = {};
    
    alignas(4) uint8_t _buf0[1024]; // Aligned to send via USB
    alignas(4) uint8_t _buf1[1024]; // Aligned to send via USB
    BufQueue<2> _bufs;
    
    struct {
        Task task;
    } _usbCmd;
    
    struct {
        Task task;
        size_t len = 0;
    } _usbDataOut;
    
    struct {
        Task task;
        size_t len = 0;
        alignas(4) bool status = false; // Aligned to send via USB
    } _usbDataIn;
    
    struct {
        Task task;
    } _stm;
    
    struct {
        Task task;
    } _ice;
    
    struct {
        Task task;
    } _mspRead;
    
    struct {
        Task task;
    } _mspWrite;
    
    struct {
        Task task;
        struct {
            uint8_t bits = 0;
            uint8_t bitsLen = 0;
            size_t len = 0;
        } read;
    } _mspDebug;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

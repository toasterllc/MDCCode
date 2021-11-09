#include "SystemBase.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "USB.h"
#include "STM.h"
#include "SDCard.h"
#include "Toastbox/Task.h"
#include "ImgSensor.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    [[noreturn]] void run();
    
private:
    void _resetTasks();
    
    void _usb_cmdTaskFn();
    void _usb_dataInTaskFn();
    void _usb_dataInSendStatus(bool status);
    
    void _endpointsFlush_taskFn();
    void _statusGet_taskFn();
    void _bootloaderInvoke_taskFn();
    void _ledSet();
    
    void _readout_taskFn();
    
    void _msp_init();
    
    void _sd_readTaskFn();
    
    void _img_init();
    void _img_setExposure();
    void _img_captureTaskFn();
    
    // Peripherals
    USB _usb;
    QSPI _qspi;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using _ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    SD::Card _sd;
    
    BufQueue<2> _bufs;
    STM::Cmd _cmd = {};
    
    struct {
        size_t len = 0;
        alignas(4) bool status = false; // Aligned to send via USB
    } _usbDataIn;
    
    struct {
        std::optional<size_t> len;
    } _readout;
    
    struct {
        bool init = false;
    } _img;
    
    // Tasks
    Toastbox::Task _usb_cmdTask           = Toastbox::Task([&] {    _usb_cmdTaskFn();           });
    Toastbox::Task _usb_dataInTask        = Toastbox::Task([&] {    _usb_dataInTaskFn();        });
    Toastbox::Task _endpointsFlush_task   = Toastbox::Task([&] {    _endpointsFlush_taskFn();   });
    Toastbox::Task _statusGet_task        = Toastbox::Task([&] {    _statusGet_taskFn();        });
    Toastbox::Task _bootloaderInvoke_task = Toastbox::Task([&] {    _bootloaderInvoke_taskFn(); });
    Toastbox::Task _readout_task          = Toastbox::Task([&] {    _readout_taskFn();          });
    Toastbox::Task _sd_readTask           = Toastbox::Task([&] {    _sd_readTaskFn();           });
    Toastbox::Task _img_captureTask       = Toastbox::Task([&] {    _img_captureTaskFn();       });
    
    std::reference_wrapper<Toastbox::Task> _tasks[8] = {
        _usb_cmdTask,
        _usb_dataInTask,
        _endpointsFlush_task,
        _statusGet_task,
        _bootloaderInvoke_task,
        _readout_task,
        _sd_readTask,
        _img_captureTask,
    };
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    friend class ICE;
    friend class Img::Sensor;
    friend class SD::Card;
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

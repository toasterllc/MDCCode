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
    Task _usb_cmdTask           = Task([&] { _usb_cmdTaskFn();              });
    Task _usb_dataInTask        = Task([&] { _usb_dataInTaskFn();           });
    Task _endpointsFlush_task   = Task([&] { _endpointsFlush_taskFn();      });
    Task _bootloaderInvoke_task = Task([&] { _bootloaderInvoke_taskFn();    });
    Task _readout_task          = Task([&] { _readout_taskFn();             });
    Task _sd_readTask           = Task([&] { _sd_readTaskFn();              });
    Task _img_captureTask       = Task([&] { _img_captureTaskFn();          });
    
    std::reference_wrapper<Task> _tasks[7] = {
        _usb_cmdTask,
        _usb_dataInTask,
        _endpointsFlush_task,
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

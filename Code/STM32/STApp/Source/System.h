#include "SystemBase.h"
#include "QSPI.h"
#include "ICE40.h"
#include "BufQueue.h"
#include "USB.h"
#include "STAppTypes.h"
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
    
    void _usbCmd_taskFn();
    void _usbDataIn_taskFn();
    
    void _resetEndpoints_taskFn();
    
    void _readout_taskFn();
    
    void _bootloader();
    
    void _msp_init();
    
    void _sd_readTask();
    
    void _img_init();
    void _img_setExposure();
    void _img_reset();
    void _img_captureTask();
    
    void _ledSet();
    
    // Peripherals
    USB _usb;
    QSPI _qspi;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using _ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    SD::Card _sd;
    
    BufQueue<2> _bufs;
    STApp::Cmd _cmd = {};
    std::optional<size_t> _readoutLen;
    bool _imgInit = false;
    
    // Tasks
    Task _usbCmd_task           = Task([&] { _usbCmd_taskFn();          });
    Task _usbDataIn_task        = Task([&] { _usbDataIn_taskFn();       });
    Task _resetEndpoints_task   = Task([&] { _resetEndpoints_taskFn();  });
    Task _readout_task          = Task([&] { _readout_taskFn();         });
    Task _sdRead_task           = Task([&] { _sd_readTask();            });
    Task _imgCapture_task       = Task([&] { _img_captureTask();        });
    
    std::reference_wrapper<Task> _tasks[6] = {
        _usbCmd_task,
        _usbDataIn_task,
        _resetEndpoints_task,
        _readout_task,
        _sdRead_task,
        _imgCapture_task,
    };
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    friend class ICE40;
    friend class Img::Sensor;
    friend class SD::Card;
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

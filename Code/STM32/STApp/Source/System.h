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
    
    void _usbCmd_task();
    void _usbDataIn_task();
    
    void _resetEndpoints_task();
    
    void _readout_task();
    
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
    Task _usbCmdTask            = Task([&] { _usbCmd_task();            });
    Task _usbDataInTask         = Task([&] { _usbDataIn_task();         });
    Task _resetEndpointsTask    = Task([&] { _resetEndpoints_task();    });
    Task _readoutTask           = Task([&] { _readout_task();           });
    Task _sdReadTask            = Task([&] { _sd_readTask();            });
    Task _imgCaptureTask        = Task([&] { _img_captureTask();        });
    
    std::reference_wrapper<Task> _tasks[6] = {
        _usbCmdTask,
        _usbDataInTask,
        _resetEndpointsTask,
        _readoutTask,
        _sdReadTask,
        _imgCaptureTask,
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

#include "SystemBase.h"
#include "QSPI.h"
#include "ICE40.h"
#include "BufQueue.h"
#include "USB.h"
#include "STAppTypes.h"
#include "SDCard.h"
#include "Toastbox/Task.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    [[noreturn]] void run();
    
private:
    void _resetTasks();
    
    void _usbCmd_task();
    void _usbDataIn_task();
    
    void _reset_task();
    
    void _readout_task();
    
    void _bootloader();
    
    void _msp_init();
    
    void _sd_readTask();
    
    void _img_setPowerEnabled(bool en);
    void _img_reset();
    void _img_i2cTask();
    void _img_captureTask();
    
    void _ledSet();
    
    // Peripherals
    USB _usb;
    QSPI _qspi;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using _ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    ICE40 _ice;
    SDCard _sd;
    
    BufQueue<2> _bufs;
    STApp::Cmd _cmd = {};
    std::optional<size_t> _readoutLen;
    
    // Tasks
    Task _usbCmdTask     = Task([&] { _usbCmd_task();       });
    Task _usbDataInTask  = Task([&] { _usbDataIn_task();    });
    Task _resetTask      = Task([&] { _reset_task();        });
    Task _readoutTask    = Task([&] { _readout_task();      });
    Task _sdReadTask     = Task([&] { _sd_readTask();       });
    Task _imgI2CTask     = Task([&] { _img_i2cTask();       });
    Task _imgCaptureTask = Task([&] { _img_captureTask();   });
    
    std::reference_wrapper<Task> _tasks[7] = {
        _usbCmdTask,
        _usbDataInTask,
        _resetTask,
        _readoutTask,
        _sdReadTask,
        _imgI2CTask,
        _imgCaptureTask,
    };
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    friend class ICE40;
    friend class SDCard;
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

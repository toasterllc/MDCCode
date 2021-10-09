#include "SystemBase.h"
#include "QSPI.h"
#include "ICE40Types.h"
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
    
    void _ice_init();
    void _ice_transferNoCS(const ICE40::Msg& msg);
    void _ice_transfer(const ICE40::Msg& msg);
    void _ice_transfer(const ICE40::Msg& msg, ICE40::Resp& resp);
    void _ice_qspiRead(void* buf, size_t len);
    void _ice_readout(void* buf, size_t len);
    
    void _msp_init();
    
    void _sd_readTask();
    
    void _img_setPowerEnabled(bool en);
    void _img_init();
    ICE40::ImgI2CStatusResp _imgI2CStatus();
    ICE40::ImgCaptureStatusResp _imgCaptureStatus();
    ICE40::ImgI2CStatusResp _imgI2C(bool write, uint16_t addr, uint16_t val);
    ICE40::ImgI2CStatusResp _imgI2CRead(uint16_t addr);
    ICE40::ImgI2CStatusResp _imgI2CWrite(uint16_t addr, uint16_t val);
    void _img_i2cTask();
    void _img_captureTask();
    
    void _ledSet();
    
    // Peripherals
    USB _usb;
    QSPI _qspi;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using _ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    const uint8_t SDClkDelaySlow = 7;
    const uint8_t SDClkDelayFast = 0;
    using SDCard = SDCard<SDClkDelaySlow, SDClkDelayFast>;
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
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;

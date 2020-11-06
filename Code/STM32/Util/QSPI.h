#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Channel.h"

extern "C" void ISR_QUADSPI();
extern "C" void ISR_DMA2_Stream7();

class QSPI {
public:
    QSPI();
    void init();
    void config(); // Reconfigures GPIOs, in case they're reused for some other purpose
    void read(void* data, size_t len);
    void write(const void* data, size_t len);
    
    struct Event {
        enum class Type : uint8_t {
            ReadDone,
            WriteDone,
        };
        
        Type type;
    };
    
    Channel<Event, 1> eventChannel;
    
private:
    void _isrQSPI();
    void _isrDMA();
    void _handleCmdDone();
    void _handleReadDone();
    void _handleWriteDone();
    
    QSPI_HandleTypeDef _device;
    DMA_HandleTypeDef _dma;
    GPIO _clk;
    GPIO _cs;
    GPIO _do;
    GPIO _di;
    
    void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device);
    void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
};

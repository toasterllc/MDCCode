#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Channel.h"

extern "C" void ISR_QUADSPI();

class QSPI {
public:
    QSPI();
    void init();
    void config();
    void write(void* data, size_t len);
    
    struct Event {
        enum class Type : uint8_t {
            WriteDone,
        };
        
        Type type;
    };
    
    Channel<Event, 1> eventChannel;
    
private:
    void _isr();
    void _handleWriteDone();
    
    QSPI_HandleTypeDef _device;
    GPIO _clk;
    GPIO _cs;
    GPIO _do;
    GPIO _di;
    
    void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void ISR_QUADSPI();
};

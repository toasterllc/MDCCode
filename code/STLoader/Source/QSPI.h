#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"

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
    
private:
    void _handleWriteDone();
    
    QSPI_HandleTypeDef _qspi;
    GPIO _clk;
    GPIO _cs;
    GPIO _do;
    GPIO _di;
    
    void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* qspi);
    friend void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* qspi);
};

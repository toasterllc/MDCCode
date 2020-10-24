#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"

void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* qspi);

class QSPI {
public:
    QSPI();
    void init();
    void config();
    void write(void* data, size_t len);
    
private:
    void _handleWriteComplete();
    
    QSPI_HandleTypeDef _qspi;
    GPIO _clk;
    GPIO _cs;
    GPIO _do;
    GPIO _di;
    
    friend void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* qspi);
};

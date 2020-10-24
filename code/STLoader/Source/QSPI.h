#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"

class QSPI {
public:
    QSPI();
    void init();
    void config();
//    void configForBitbang();
    
private:
    QSPI_HandleTypeDef _qspi;
    GPIO _clk;
    GPIO _cs;
    GPIO _do;
    GPIO _di;
};

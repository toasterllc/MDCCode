#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"

class QSPI {
public:
    QSPI();
    void init();
    void config();
//    void configForBitbang();
    
    GPIO& clk();
    GPIO& cs();
    
private:
    QSPI_HandleTypeDef _qspi;
    GPIO _clk;
    GPIO _cs;
    GPIO _so;
    GPIO _si;
};

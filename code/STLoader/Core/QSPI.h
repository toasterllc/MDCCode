#pragma once
#include "stm32f7xx.h"

class QSPI {
public:
    void init();
    
private:
    QSPI_HandleTypeDef _qspi;
};

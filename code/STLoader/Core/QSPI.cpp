#include "QSPI.h"
#include "assert.h"

void QSPI::init() {
    _qspi.Instance = QUADSPI;
    _qspi.Init.ClockPrescaler = 5; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1) = 128/(7+1) = 21.3 MHz
    _qspi.Init.FifoThreshold = 1;
    _qspi.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
    _qspi.Init.FlashSize = 1;
    _qspi.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
    _qspi.Init.ClockMode = QSPI_CLOCK_MODE_0;
    _qspi.Init.FlashID = QSPI_FLASH_ID_1;
    _qspi.Init.DualFlash = QSPI_DUALFLASH_DISABLE;
    
    HAL_StatusTypeDef sr = HAL_QSPI_Init(&_qspi);
    assert(sr == HAL_OK);
}

#include "QSPI.h"
#include "assert.h"

QSPI::QSPI() :
_clk(GPIOB, GPIO_PIN_2),
_cs(GPIOB, GPIO_PIN_6),
_do(GPIOC, GPIO_PIN_9),
_di(GPIOC, GPIO_PIN_10) {
    
}

void QSPI::init() {
    __HAL_RCC_QSPI_CLK_ENABLE();
    
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

void QSPI::config() {
    _clk.init(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _cs.init(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
    _do.init(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _di.init(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
}

//void QSPI::configForBitbang() {
//    _clk.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    _cs.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    _do.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//    _di.init(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
//}

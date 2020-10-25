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
    _qspi.Ctx = this;
    
    HAL_StatusTypeDef sr = HAL_QSPI_Init(&_qspi);
    assert(sr == HAL_OK);
}

void QSPI::config() {
    _clk.config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _cs.config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
    _do.config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _di.config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
}

void QSPI::write(void* data, size_t len) {
    QSPI_CommandTypeDef cmd = {
        .Instruction = 0,
        .Address = 0,
        .AlternateBytes = 0,
        .AddressSize = QSPI_ADDRESS_8_BITS,
        .AlternateBytesSize = QSPI_ALTERNATE_BYTES_8_BITS,
        .DummyCycles = 0,
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        .AddressMode = QSPI_ADDRESS_NONE,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
        .DataMode = QSPI_DATA_1_LINE,
        .NbData = (uint32_t)len,
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
    HAL_QSPI_Command_IT(&_qspi, &cmd);
}

void QSPI::_isr() {
    ISR_HAL_QSPI(&_qspi);
}

void QSPI::_handleWriteDone() {
    eventChannel.writeTry(Event{
        .type = Event::Type::WriteDone,
    });
}

// TODO: make sure this is being used by commenting out, and making sure we get a linker error
void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* qspi) {
    ((QSPI*)qspi->Ctx)->_handleWriteDone();
}

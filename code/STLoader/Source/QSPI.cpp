#include "QSPI.h"
#include "abort.h"
#include "assert.h"

QSPI::QSPI() :
_clk(GPIOB, GPIO_PIN_2),
_cs(GPIOB, GPIO_PIN_6),
_do(GPIOC, GPIO_PIN_9),
_di(GPIOC, GPIO_PIN_10) {
    
}

void QSPI::init() {
    __HAL_RCC_QSPI_CLK_ENABLE();
    __HAL_RCC_QSPI_FORCE_RESET();
    __HAL_RCC_QSPI_RELEASE_RESET();
    
    HAL_NVIC_SetPriority(QUADSPI_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(QUADSPI_IRQn);
    
    _device.Instance = QUADSPI;
    _device.Init.ClockPrescaler = 5; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1) = 128/(7+1) = 21.3 MHz
    _device.Init.FifoThreshold = 1;
    _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
    _device.Init.FlashSize = 31; // Flash size is 31+1 address bits => 2^(31+1) bytes
    _device.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
    _device.Init.ClockMode = QSPI_CLOCK_MODE_3; // Clock is high while chip-select is released
    _device.Init.FlashID = QSPI_FLASH_ID_1;
    _device.Init.DualFlash = QSPI_DUALFLASH_DISABLE;
    _device.Ctx = this;
    
    HAL_StatusTypeDef sr = HAL_QSPI_Init(&_device);
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
        .AddressSize = QSPI_ADDRESS_32_BITS,
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
    HAL_StatusTypeDef hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
    assert(hs == HAL_OK);
    
    hs = HAL_QSPI_Transmit_IT(&_device, (uint8_t*)data);
    assert(hs == HAL_OK);
}

void QSPI::_isr() {
    ISR_HAL_QSPI(&_device);
}

void QSPI::_handleWriteDone() {
    eventChannel.writeTry(Event{
        .type = Event::Type::WriteDone,
    });
}

void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device) {
    ((QSPI*)device->Ctx)->_handleWriteDone();
}

void HAL_QSPI_ErrorCallback(QSPI_HandleTypeDef* device) {
    abort();
}

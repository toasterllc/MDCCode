#include "QSPI.h"
#include "Abort.h"
#include "Assert.h"

QSPI::QSPI(Mode mode) :
_mode(mode),
_clk(GPIOB, GPIO_PIN_2),
_cs(GPIOB, GPIO_PIN_6),
_d{
    GPIO(GPIOC, GPIO_PIN_9),    // SPI D0
    GPIO(GPIOC, GPIO_PIN_10),   // SPI D1
    GPIO(GPIOF, GPIO_PIN_7),    // SPI D2
    GPIO(GPIOF, GPIO_PIN_6),    // SPI D3
    GPIO(GPIOH, GPIO_PIN_2),    // SPI D4
    GPIO(GPIOH, GPIO_PIN_3),    // SPI D5
    GPIO(GPIOG, GPIO_PIN_9),    // SPI D6
    GPIO(GPIOG, GPIO_PIN_14)    // SPI D7
} {}

void QSPI::init() {
    // DMA clock/IRQ
    __HAL_RCC_DMA2_CLK_ENABLE();
    HAL_NVIC_SetPriority(DMA2_Stream7_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(DMA2_Stream7_IRQn);
    
    // QSPI clock/IRQ
    __HAL_RCC_QSPI_CLK_ENABLE();
    __HAL_RCC_QSPI_FORCE_RESET();
    __HAL_RCC_QSPI_RELEASE_RESET();
    HAL_NVIC_SetPriority(QUADSPI_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(QUADSPI_IRQn);
    
    // Init QUADSPI
    _device.Instance = QUADSPI;
    // TODO: make ClockPrescaler configurable -- STLoader needs it to be <=25MHz, but STApp wants it to be as fast as ctrl_clk can go
    _device.Init.ClockPrescaler = 5; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1) = 128/(5+1) = 21.3 MHz
    _device.Init.FifoThreshold = 1;
    _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
    _device.Init.FlashSize = 31; // Flash size is 31+1 address bits => 2^(31+1) bytes
    _device.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
    _device.Init.ClockMode = QSPI_CLOCK_MODE_0; // Clock idles low
//    _device.Init.ClockMode = QSPI_CLOCK_MODE_3; // Clock idles high
    _device.Init.FlashID = QSPI_FLASH_ID_1;
    _device.Init.DualFlash = (_mode==Mode::Single ? QSPI_DUALFLASH_DISABLE : QSPI_DUALFLASH_ENABLE);
    _device.Ctx = this;
    
    HAL_StatusTypeDef hs = HAL_QSPI_Init(&_device);
    Assert(hs == HAL_OK);
    
    // Init DMA
    _dma.Instance = DMA2_Stream7;
    _dma.Init.Channel = DMA_CHANNEL_3;
    _dma.Init.Direction = DMA_MEMORY_TO_PERIPH;
    _dma.Init.PeriphInc = DMA_PINC_DISABLE;
    _dma.Init.MemInc = DMA_MINC_ENABLE;
    _dma.Init.PeriphDataAlignment = DMA_PDATAALIGN_BYTE;
    _dma.Init.MemDataAlignment = DMA_MDATAALIGN_BYTE;
    _dma.Init.Mode = DMA_NORMAL;
    _dma.Init.Priority = DMA_PRIORITY_VERY_HIGH;
    _dma.Init.FIFOMode = DMA_FIFOMODE_DISABLE;
    
    hs = HAL_DMA_Init(&_dma);
    Assert(hs == HAL_OK);
    
    __HAL_LINKDMA(&_device, hdma, _dma);
    
    config();
}

void QSPI::config() {
    _clk.config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _cs.config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
    _d[0].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[1].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[2].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[3].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[4].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[5].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[6].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _d[7].config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
}

void QSPI::command(const QSPI_CommandTypeDef& cmd) {
    AssertArg(cmd.DataMode == QSPI_DATA_NONE);
    AssertArg(!cmd.NbData);
    
    HAL_StatusTypeDef hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
    Assert(hs == HAL_OK);
}

void QSPI::read(const QSPI_CommandTypeDef& cmd, void* data, size_t len) {
    AssertArg(cmd.DataMode != QSPI_DATA_NONE);
    AssertArg(cmd.NbData == len);
    AssertArg(data);
    AssertArg(len);
    
    HAL_StatusTypeDef hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
    Assert(hs == HAL_OK);
    
    hs = HAL_QSPI_Receive_DMA(&_device, (uint8_t*)data);
    Assert(hs == HAL_OK);
}

void QSPI::write(const QSPI_CommandTypeDef& cmd, const void* data, size_t len) {
    AssertArg(cmd.DataMode != QSPI_DATA_NONE);
    AssertArg(cmd.NbData == len);
    AssertArg(data);
    AssertArg(len);
    
    HAL_StatusTypeDef hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
    Assert(hs == HAL_OK);
    
    hs = HAL_QSPI_Transmit_DMA(&_device, (uint8_t*)data);
    Assert(hs == HAL_OK);
}

void QSPI::_isrQSPI() {
    ISR_HAL_QSPI(&_device);
}

void QSPI::_isrDMA() {
    ISR_HAL_DMA(&_dma);
}

void QSPI::_handleCommandDone() {
    eventChannel.writeTry(Event{
        .type = Event::Type::CommandDone,
    });
}

void QSPI::_handleReadDone() {
    eventChannel.writeTry(Event{
        .type = Event::Type::ReadDone,
    });
}

void QSPI::_handleWriteDone() {
    eventChannel.writeTry(Event{
        .type = Event::Type::WriteDone,
    });
}

void HAL_QSPI_CmdCpltCallback(QSPI_HandleTypeDef* device) {
    ((QSPI*)device->Ctx)->_handleCommandDone();
}

void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device) {
    ((QSPI*)device->Ctx)->_handleReadDone();
}

void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device) {
    ((QSPI*)device->Ctx)->_handleWriteDone();
}

void HAL_QSPI_ErrorCallback(QSPI_HandleTypeDef* device) {
    Abort();
}

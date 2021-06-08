#include "QSPI.h"
#include "Assert.h"

QSPI::QSPI(Mode mode, uint8_t clkDivider, Align align) :
_mode(mode),
_clkDivider(clkDivider),
_align(align)
{}

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
    _device.Init.ClockPrescaler = _clkDivider; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1)
    _device.Init.FifoThreshold = 4;
    _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
//    _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_HALFCYCLE;
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
    _dma.Init.PeriphDataAlignment = (_align==Align::Byte ? DMA_PDATAALIGN_BYTE : DMA_PDATAALIGN_WORD);
    _dma.Init.MemDataAlignment = (_align==Align::Byte ? DMA_MDATAALIGN_BYTE : DMA_MDATAALIGN_WORD);
    _dma.Init.Mode = DMA_NORMAL;
    _dma.Init.Priority = DMA_PRIORITY_VERY_HIGH;
    _dma.Init.FIFOMode = DMA_FIFOMODE_ENABLE;
    _dma.Init.FIFOThreshold = DMA_FIFO_THRESHOLD_HALFFULL;
    _dma.Init.MemBurst = DMA_MBURST_SINGLE;
    _dma.Init.PeriphBurst = DMA_PBURST_SINGLE;
    
    hs = HAL_DMA_Init(&_dma);
    Assert(hs == HAL_OK);
    
    __HAL_LINKDMA(&_device, hdma, _dma);
    
    config();
}

void QSPI::config() {
    _Clk::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _CS::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
    _D0::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D1::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D2::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D3::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D4::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D5::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D6::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
    _D7::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
}

void QSPI::reset() {
    // Disable interrupts so that resetting is atomic
    IRQState irq;
    irq.disable();
    
    // Abort whatever is underway (if anything)
    HAL_QSPI_Abort(&_device);
    
    // Reset channels to clear pending events
    eventChannel.reset();
}

void QSPI::command(const QSPI_CommandTypeDef& cmd) {
    AssertArg(cmd.DataMode == QSPI_DATA_NONE);
    AssertArg(!cmd.NbData);
    
    // Dummy cycles don't appear to work correctly when no data is transferred.
    // (For some reason, only DummyCycles=0 and DummyCycles=2 work correctly,
    // while other values never trigger the "Transfer complete" (TCF) flag,
    // so we hang forever.)
    //
    // To work around this, if dummy cycles are used, perform a minimum-length
    // read instead. This will cause more cycles than the caller may expect,
    // so this strategy will only work if these extra cycles have no adverse
    // effect.
    
    if (cmd.DummyCycles) {
        const size_t readLen = (_align==Align::Byte ? 1 : 4);
        QSPI_CommandTypeDef readCmd = cmd;
        readCmd.NbData = readLen;
        readCmd.DataMode = QSPI_DATA_4_LINES;
        
        static uint32_t buf = 0;
        read(readCmd, &buf, readLen);
        return;
    }
    
    // Use HAL_QSPI_Command_IT() in this case, instead of HAL_QSPI_Command(),
    // because we're not transferring any data, so the HAL_QSPI_Command()
    // synchronously performs the SPI transaction, instead asynchronously
    // like we want.
    HAL_StatusTypeDef hs = HAL_QSPI_Command_IT(&_device, &cmd);
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
    eventChannel.writeTry(Signal{});
}

void QSPI::_handleReadDone() {
    eventChannel.writeTry(Signal{});
}

void QSPI::_handleWriteDone() {
    eventChannel.writeTry(Signal{});
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
    abort();
}

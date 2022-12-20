#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Toastbox/IntState.h"

class QSPI {
public:
    enum class Mode {
        Single,
        Dual,
    };

    enum class Align {
        Byte,
        Word, // Best performance for large transfers
    };
    
    struct Config {
        Mode mode = Mode::Single;
        uint8_t clkDivider = 0;
        Align align = Align::Byte;
    };
    
    using Clk = GPIO<GPIOPortB, GPIO_PIN_2>; // AF9
    using D0 = GPIO<GPIOPortF, GPIO_PIN_8>;  // AF10
    using D1 = GPIO<GPIOPortF, GPIO_PIN_9>;  // AF10
    using D2 = GPIO<GPIOPortF, GPIO_PIN_7>;  // AF9
    using D3 = GPIO<GPIOPortF, GPIO_PIN_6>;  // AF9
    using D4 = GPIO<GPIOPortE, GPIO_PIN_7>;  // AF10
    using D5 = GPIO<GPIOPortE, GPIO_PIN_8>;  // AF10
    using D6 = GPIO<GPIOPortE, GPIO_PIN_9>;  // AF10
    using D7 = GPIO<GPIOPortE, GPIO_PIN_10>; // AF10
    
    QSPI() {}
    
    const Config* getConfig() const { return _config; }
    
    void setConfig(const Config& config) {
        if (_config) {
            HAL_StatusTypeDef hs = HAL_DMA_DeInit(&_dma);
            Assert(hs == HAL_OK);
            
            hs = HAL_QSPI_DeInit(&_device);
            Assert(hs == HAL_OK);
        }
        
        _config = &config;
        
        constexpr uint32_t InterruptPriority = 1; // Should be >0 so that SysTick can still preempt
        
        // Enable GPIO clocks
        __HAL_RCC_GPIOB_CLK_ENABLE();
        __HAL_RCC_GPIOF_CLK_ENABLE();
        __HAL_RCC_GPIOE_CLK_ENABLE();
        
        // DMA clock/IRQ
        __HAL_RCC_DMA2_CLK_ENABLE();
        HAL_NVIC_SetPriority(DMA2_Stream7_IRQn, InterruptPriority, 0);
        HAL_NVIC_EnableIRQ(DMA2_Stream7_IRQn);
        
        // QSPI clock/IRQ
        __HAL_RCC_QSPI_CLK_ENABLE();
        __HAL_RCC_QSPI_FORCE_RESET();
        __HAL_RCC_QSPI_RELEASE_RESET();
        HAL_NVIC_SetPriority(QUADSPI_IRQn, InterruptPriority, 0);
        HAL_NVIC_EnableIRQ(QUADSPI_IRQn);
        
        // Init QUADSPI
        _device.Instance = QUADSPI;
        _device.Init.ClockPrescaler = _config->clkDivider; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1)
        _device.Init.FifoThreshold = 4;
        _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
//        _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_HALFCYCLE;
        _device.Init.FlashSize = 31; // Flash size is 31+1 address bits => 2^(31+1) bytes
        _device.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
        _device.Init.ClockMode = QSPI_CLOCK_MODE_0; // Clock idles low
//        _device.Init.ClockMode = QSPI_CLOCK_MODE_3; // Clock idles high
        // In single mode, we want QSPI to use D4/D5 (flash 2), not D0/D1 (flash 1)
        _device.Init.FlashID = (_config->mode==Mode::Single ? QSPI_FLASH_ID_2 : QSPI_FLASH_ID_1);
        _device.Init.DualFlash = (_config->mode==Mode::Single ? QSPI_DUALFLASH_DISABLE : QSPI_DUALFLASH_ENABLE);
        _device.Ctx = this;
        
        HAL_StatusTypeDef hs = HAL_QSPI_Init(&_device);
        Assert(hs == HAL_OK);
        
        // Init DMA
        _dma.Instance = DMA2_Stream7;
        _dma.Init.Channel = DMA_CHANNEL_3;
        _dma.Init.Direction = DMA_MEMORY_TO_PERIPH;
        _dma.Init.PeriphInc = DMA_PINC_DISABLE;
        _dma.Init.MemInc = DMA_MINC_ENABLE;
        _dma.Init.PeriphDataAlignment = (_config->align==Align::Byte ? DMA_PDATAALIGN_BYTE : DMA_PDATAALIGN_WORD);
        _dma.Init.MemDataAlignment = (_config->align==Align::Byte ? DMA_MDATAALIGN_BYTE : DMA_MDATAALIGN_WORD);
        _dma.Init.Mode = DMA_NORMAL;
        _dma.Init.Priority = DMA_PRIORITY_VERY_HIGH;
        _dma.Init.FIFOMode = DMA_FIFOMODE_ENABLE;
        _dma.Init.FIFOThreshold = DMA_FIFO_THRESHOLD_HALFFULL;
        _dma.Init.MemBurst = DMA_MBURST_SINGLE;
        _dma.Init.PeriphBurst = DMA_PBURST_SINGLE;
        
        hs = HAL_DMA_Init(&_dma);
        Assert(hs == HAL_OK);
        
        __HAL_LINKDMA(&_device, hdma, _dma);
        
        // Init callbacks
        _device.CmdCpltCallback = [] (QSPI_HandleTypeDef* me) {
            ((QSPI*)me->Ctx)->_handleCommandDone();
        };
        
        _device.RxCpltCallback = [] (QSPI_HandleTypeDef* me) {
            ((QSPI*)me->Ctx)->_handleReadDone();
        };
        
        _device.TxCpltCallback = [] (QSPI_HandleTypeDef* me) {
            ((QSPI*)me->Ctx)->_handleWriteDone();
        };
        
        _device.ErrorCallback = [] (QSPI_HandleTypeDef* me) {
            abort();
        };
        
        configPins();
    }
    
    // configPins(): reconfigures GPIOs, in case they're reused for some other purpose
    void configPins() {
        Clk::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
        
        D0::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
        D1::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
        D2::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
        D3::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF9_QUADSPI);
        D4::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
        D5::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
        D6::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
        D7::Config(GPIO_MODE_AF_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF10_QUADSPI);
    }
    
    // reset(): aborts whatever is in progress and resets state
    void reset() {
        AssertArg(_config);
        
        // Disable interrupts so that resetting is atomic
        Toastbox::IntState ints(false);
        
        // Abort whatever is underway (if anything)
        HAL_QSPI_Abort(&_device);
        
        // Reset state
        _busy = false;
    }
    
    bool ready() const {
        return !_busy;
    }
    
    void command(const QSPI_CommandTypeDef& cmd) {
        AssertArg(_config);
        AssertArg(cmd.DataMode == QSPI_DATA_NONE);
        AssertArg(!cmd.NbData);
        
        // Dummy cycles don't appear to work correctly when no data is transferred.
        // (For some reason, only DummyCycles=0 and DummyCycles=2 work correctly,
        // while other values never trigger the "Transfer complete" (TCF) flag,
        // so we hang forever.)
        // 
        //   * Mode=Single
        //       DummyCycles=2       read 1 byte  / 4 lines = 2 cycle
        //       DummyCycles=4       read 2 bytes / 4 lines = 4 cycles
        //       DummyCycles=6       read 3 bytes / 4 lines = 6 cycles
        //       DummyCycles=8       read 4 bytes / 4 lines = 8 cycles
        //       ...
        //       Len = DummyCycles/2 (only even DummyCycles allowed)
        //
        //   * Mode=Dual
        //       DummyCycles=1       read 1 byte / 8 lines = 1 cycle
        //       DummyCycles=2       read 2 bytes / 8 lines = 2 cycles
        //       DummyCycles=3       read 3 bytes / 8 lines = 3 cycles
        //       DummyCycles=4       read 4 bytes / 8 lines = 4 cycles
        //       ...
        //       Len = DummyCycles
        if (cmd.DummyCycles) {
            static uint8_t buf[32]; // Dummy cycles (DCYC) register is 5 bits == up to 31 cycles
            size_t readLen = 0;
            
            if (_config->mode == Mode::Single) {
                // In single mode, we can only fake even values for the number of dummy cycles.
                // This is because we can only read whole bytes, and each byte requires 2 cycles
                // when using 4 lines (QSPI_DATA_4_LINES).
                AssertArg(!(cmd.DummyCycles % 2));
                readLen = cmd.DummyCycles/2;
            } else {
                readLen = cmd.DummyCycles;
            }
            
            QSPI_CommandTypeDef readCmd = cmd;
            readCmd.NbData = readLen;
            readCmd.DataMode = QSPI_DATA_4_LINES;
            readCmd.DummyCycles = 0;
            read(readCmd, buf);
        
        } else {
            Assert(ready());
            
            // Update _busy before the interrupt can occur, otherwise `_busy = true`
            // could occur after the transaction is complete, cloberring the `_busy = false`
            // assignment in the completion interrupt handler.
            _busy = true;
            
            // Use HAL_QSPI_Command_IT() in this case, instead of HAL_QSPI_Command(),
            // because we're not transferring any data, so the HAL_QSPI_Command()
            // synchronously performs the SPI transaction, instead asynchronously
            // like we want.
            HAL_StatusTypeDef hs = HAL_QSPI_Command_IT(&_device, &cmd);
            Assert(hs == HAL_OK);
        }
    }
    
    void read(const QSPI_CommandTypeDef& cmd, void* data) {
        const size_t len = cmd.NbData;
        AssertArg(_config);
        AssertArg(cmd.DataMode != QSPI_DATA_NONE);
        AssertArg(data);
        AssertArg(len);
        // Validate `len` alignment
        if (_config->align == Align::Word) {
            AssertArg(!(len % sizeof(uint32_t)));
        }
        Assert(ready());
        
        // Update _busy before the interrupt can occur, otherwise `_busy = true`
        // could occur after the transaction is complete, cloberring the `_busy = false`
        // assignment in the completion interrupt handler.
        _busy = true;
        
        HAL_StatusTypeDef hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
        Assert(hs == HAL_OK);
        
        hs = HAL_QSPI_Receive_DMA(&_device, (uint8_t*)data);
        Assert(hs == HAL_OK);
    }
    
    void write(const QSPI_CommandTypeDef& cmd, const void* data) {
        const size_t len = cmd.NbData;
        AssertArg(_config);
        AssertArg(cmd.DataMode != QSPI_DATA_NONE);
        AssertArg(data);
        AssertArg(len);
        // Validate `len` alignment
        if (_config->align == Align::Word) {
            AssertArg(!(len % sizeof(uint32_t)));
        }
        Assert(ready());
        
        // Update _busy before the interrupt can occur, otherwise `_busy = true`
        // could occur after the transaction is complete, cloberring the `_busy = false`
        // assignment in the completion interrupt handler.
        _busy = true;
        
        HAL_StatusTypeDef hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
        Assert(hs == HAL_OK);
        
        hs = HAL_QSPI_Transmit_DMA(&_device, (uint8_t*)data);
        Assert(hs == HAL_OK);
    }
    
    void isrQSPI() {
        ISR_HAL_QSPI(&_device);
    }
    
    void isrDMA() {
        ISR_HAL_DMA(&_dma);
    }
    
private:
    const Config* _config = nullptr;
    QSPI_HandleTypeDef _device;
    DMA_HandleTypeDef _dma;
    bool _busy = false;
    
    void _handleCommandDone() {
        _busy = false;
    }
    
    void _handleReadDone() {
        _busy = false;
    }
    
    void _handleWriteDone() {
        _busy = false;
    }
};

#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Toastbox/IntState.h"

template <
typename T_Scheduler
>
class QSPIType {
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
    
    using Clk = GPIO<GPIOPortB, 2>;  // AF9
    using D0  = GPIO<GPIOPortF, 8>;  // AF10
    using D1  = GPIO<GPIOPortF, 9>;  // AF10
    using D2  = GPIO<GPIOPortF, 7>;  // AF9
    using D3  = GPIO<GPIOPortF, 6>;  // AF9
    using D4  = GPIO<GPIOPortE, 7>;  // AF10
    using D5  = GPIO<GPIOPortE, 8>;  // AF10
    using D6  = GPIO<GPIOPortE, 9>;  // AF10
    using D7  = GPIO<GPIOPortE, 10>; // AF10
    
    static void ConfigSet(const Config& config) {
        if (_Config) {
            // Abort whatever is underway (if anything)
            HAL_QSPI_Abort(&_Device);
            
            HAL_StatusTypeDef hs = HAL_DMA_DeInit(&_DMA);
            Assert(hs == HAL_OK);
            
            hs = HAL_QSPI_DeInit(&_Device);
            Assert(hs == HAL_OK);
            
            // Reset state
            _Busy = false;
        }
        
        _Config = &config;
        
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
        // In single mode, we want QSPI to use D4/D5 (flash 2), not D0/D1 (flash 1)
        _Device.Init.ClockPrescaler = _Config->clkDivider; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1)
        _Device.Init.FlashID = (_Config->mode==Mode::Single ? QSPI_FLASH_ID_2 : QSPI_FLASH_ID_1);
        _Device.Init.DualFlash = (_Config->mode==Mode::Single ? QSPI_DUALFLASH_DISABLE : QSPI_DUALFLASH_ENABLE);
        
        HAL_StatusTypeDef hs = HAL_QSPI_Init(&_Device);
        Assert(hs == HAL_OK);
        
        // Init DMA
        _DMA.Init.PeriphDataAlignment = (_Config->align==Align::Byte ? DMA_PDATAALIGN_BYTE : DMA_PDATAALIGN_WORD),
        _DMA.Init.MemDataAlignment = (_Config->align==Align::Byte ? DMA_MDATAALIGN_BYTE : DMA_MDATAALIGN_WORD),
        
        hs = HAL_DMA_Init(&_DMA);
        Assert(hs == HAL_OK);
        
        __HAL_LINKDMA(&_Device, hdma, _DMA);
        
        // Configure GPIOs
        {
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
    }
    
    static void Command(const QSPI_CommandTypeDef& cmd) {
        AssertArg(_Config);
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
            alignas(4) static uint8_t buf[32]; // Dummy cycles (DCYC) register is 5 bits == up to 31 cycles
            size_t readLen = 0;
            
            if (_Config->mode == Mode::Single) {
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
            Read(readCmd, buf);
        
        } else {
            Assert(!_Busy);
            
            // Update _Busy before the interrupt can occur, otherwise `_Busy = true`
            // could occur after the transaction is complete, cloberring the `_Busy = false`
            // assignment in the completion interrupt handler.
            _Busy = true;
            
            // Use HAL_QSPI_Command_IT() in this case, instead of HAL_QSPI_Command(),
            // because we're not transferring any data, so the HAL_QSPI_Command()
            // synchronously performs the SPI transaction, instead asynchronously
            // like we want.
            HAL_StatusTypeDef hs = HAL_QSPI_Command_IT(&_Device, &cmd);
            Assert(hs == HAL_OK);
        }
        
        // Wait until we're done
        T_Scheduler::Wait([&] { return !_Busy; });
    }
    
    static void Read(const QSPI_CommandTypeDef& cmd, void* data) {
        const size_t len = cmd.NbData;
        AssertArg(_Config);
        AssertArg(cmd.DataMode != QSPI_DATA_NONE);
        AssertArg(data);
        AssertArg(len);
        // Validate pointer/length alignment
        if (_Config->align == Align::Word) {
            AssertArg(!((uintptr_t)data % sizeof(uint32_t)));
            AssertArg(!(len % sizeof(uint32_t)));
        }
        Assert(!_Busy);
        
        // Update _Busy before the interrupt can occur, otherwise `_Busy = true`
        // could occur after the transaction is complete, cloberring the `_Busy = false`
        // assignment in the completion interrupt handler.
        _Busy = true;
        
        HAL_StatusTypeDef hs = HAL_QSPI_Command(&_Device, &cmd, HAL_MAX_DELAY);
        Assert(hs == HAL_OK);
        
        hs = HAL_QSPI_Receive_DMA(&_Device, (uint8_t*)data);
        Assert(hs == HAL_OK);
        
        // Wait until we're done
        T_Scheduler::Wait([&] { return !_Busy; });
    }
    
    static void Write(const QSPI_CommandTypeDef& cmd, const void* data) {
        const size_t len = cmd.NbData;
        AssertArg(_Config);
        AssertArg(cmd.DataMode != QSPI_DATA_NONE);
        AssertArg(data);
        AssertArg(len);
        // Validate pointer/length alignment
        if (_Config->align == Align::Word) {
            AssertArg(!((uintptr_t)data % sizeof(uint32_t)));
            AssertArg(!(len % sizeof(uint32_t)));
        }
        Assert(!_Busy);
        
        // Update _Busy before the interrupt can occur, otherwise `_Busy = true`
        // could occur after the transaction is complete, cloberring the `_Busy = false`
        // assignment in the completion interrupt handler.
        _Busy = true;
        
        HAL_StatusTypeDef hs = HAL_QSPI_Command(&_Device, &cmd, HAL_MAX_DELAY);
        Assert(hs == HAL_OK);
        
        hs = HAL_QSPI_Transmit_DMA(&_Device, (uint8_t*)data);
        Assert(hs == HAL_OK);
        
        // Wait until we're done
        T_Scheduler::Wait([&] { return !_Busy; });
    }
    
    static void ISR_QSPI() {
        ISR_HAL_QSPI(&_Device);
    }
    
    static void ISR_DMA() {
        ISR_HAL_DMA(&_DMA);
    }
    
private:
    static void _CallbackCommandDone(QSPI_HandleTypeDef* me) {
        _Busy = false;
    }
    
    static void _CallbackReadDone(QSPI_HandleTypeDef* me) {
        _Busy = false;
    }
    
    static void _CallbackWriteDone(QSPI_HandleTypeDef* me) {
        _Busy = false;
    }
    
    static void _CallbackError(QSPI_HandleTypeDef* me) {
        abort();
    }
    
    static inline const Config* _Config = nullptr;
    static inline QSPI_HandleTypeDef _Device = {
        .Instance = QUADSPI,
        .Init = {
            .FifoThreshold = 4,
            .SampleShifting = QSPI_SAMPLE_SHIFTING_NONE,
//            .SampleShifting = QSPI_SAMPLE_SHIFTING_HALFCYCLE,
            .FlashSize = 31, // Flash size is 31+1 address bits => 2^(31+1) bytes
            .ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE,
            .ClockMode = QSPI_CLOCK_MODE_0, // Clock idles low
//            .ClockMode = QSPI_CLOCK_MODE_3, // Clock idles high
        },
        .ErrorCallback   = _CallbackError,
        .CmdCpltCallback = _CallbackCommandDone,
        .RxCpltCallback  = _CallbackReadDone,
        .TxCpltCallback  = _CallbackWriteDone,
    };
    
    static inline DMA_HandleTypeDef _DMA = {
        .Instance = DMA2_Stream7,
        .Init = {
            .Channel = DMA_CHANNEL_3,
            .Direction = DMA_MEMORY_TO_PERIPH,
            .PeriphInc = DMA_PINC_DISABLE,
            .MemInc = DMA_MINC_ENABLE,
            .Mode = DMA_NORMAL,
            .Priority = DMA_PRIORITY_VERY_HIGH,
            .FIFOMode = DMA_FIFOMODE_ENABLE,
            .FIFOThreshold = DMA_FIFO_THRESHOLD_HALFFULL,
            .MemBurst = DMA_MBURST_SINGLE,
            .PeriphBurst = DMA_PBURST_SINGLE,
        },
    };
    
    static inline bool _Busy = false;
};

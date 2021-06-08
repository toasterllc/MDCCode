#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Channel.h"

extern "C" void ISR_QUADSPI();
extern "C" void ISR_DMA2_Stream7();

class QSPI {
public:
    enum class Mode {
        Single,
        Dual
    };
    
    enum class Align {
        Byte,
        Word // Best performance for large transfers
    };
    
    QSPI(Mode mode, uint8_t clkDivider, Align align);
    void init();
    void config(); // Reconfigures GPIOs, in case they're reused for some other purpose
    
    void reset(); // Aborts whatever is in progress, and resets all channels
    void command(const QSPI_CommandTypeDef& cmd);
    void read(const QSPI_CommandTypeDef& cmd, void* data, size_t len);
    void write(const QSPI_CommandTypeDef& cmd, const void* data, size_t len);
    
    struct Signal {};
    Channel<Signal, 1> eventChannel;
    
private:
    void _isrQSPI();
    void _isrDMA();
    void _handleCommandDone();
    void _handleReadDone();
    void _handleWriteDone();
    
    Mode _mode = Mode::Single;
    uint8_t _clkDivider = 0;
    Align _align = Align::Byte;
    
    QSPI_HandleTypeDef _device;
    DMA_HandleTypeDef _dma;
    
    GPIO<GPIOPortB, GPIO_PIN_2>  _clk;
    GPIO<GPIOPortB, GPIO_PIN_6>  _cs;
    GPIO<GPIOPortC, GPIO_PIN_9>  _d0;
    GPIO<GPIOPortC, GPIO_PIN_10> _d1;
    GPIO<GPIOPortF, GPIO_PIN_7>  _d2;
    GPIO<GPIOPortF, GPIO_PIN_6>  _d3;
    GPIO<GPIOPortH, GPIO_PIN_2>  _d4;
    GPIO<GPIOPortH, GPIO_PIN_3>  _d5;
    GPIO<GPIOPortG, GPIO_PIN_9>  _d6;
    GPIO<GPIOPortG, GPIO_PIN_14> _d7;
    
    void HAL_QSPI_CmdCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_CmdCpltCallback(QSPI_HandleTypeDef* device);
    void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device);
    void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
};

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
    GPIO _clk;
    GPIO _cs;
    GPIO _d[8];
    
    void HAL_QSPI_CmdCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_CmdCpltCallback(QSPI_HandleTypeDef* device);
    void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_RxCpltCallback(QSPI_HandleTypeDef* device);
    void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void HAL_QSPI_TxCpltCallback(QSPI_HandleTypeDef* device);
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
};

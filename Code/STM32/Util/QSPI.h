#pragma once
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Channel.h"

extern "C" void ISR_QUADSPI();
extern "C" void ISR_DMA2_Stream7();

class QSPI {
public:
    QSPI();
    void init();
    void config(); // Reconfigures GPIOs, in case they're reused for some other purpose
    void command(const QSPI_CommandTypeDef& cmd);
    void read(const QSPI_CommandTypeDef& cmd, void* data, size_t len);
    void write(const QSPI_CommandTypeDef& cmd, const void* data, size_t len);
    
    struct Event {
        enum class Type : uint8_t {
            CommandDone,
            ReadDone,
            WriteDone,
        };
        
        Type type;
    };
    
    // TODO: if both _handleCommandDone and _handleReadDone/_handleWriteDone are called per transaction, this channel needs to have 2 slots to avoid dropping events
    Channel<Event, 1> eventChannel;
    
private:
    void _isrQSPI();
    void _isrDMA();
    void _handleCommandDone();
    void _handleReadDone();
    void _handleWriteDone();
    
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

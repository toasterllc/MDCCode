#include "System.h"
#include "Assert.h"
#include "Abort.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>

using namespace STLoader;

System::System() :
ice40(qspi),
_led0(GPIOE, GPIO_PIN_12),
_led1(GPIOE, GPIO_PIN_15),
_led2(GPIOB, GPIO_PIN_10),
_led3(GPIOB, GPIO_PIN_11) {
}

void System::init() {
    // Reset peripherals, initialize flash interface, initialize Systick
    HAL_Init();
    
    // Configure the system clock
    SystemClock::Init();
    
    __HAL_RCC_GPIOB_CLK_ENABLE(); // QSPI, LEDs
    __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
    __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
    __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    // Configure our LEDs
    _led0.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _led1.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _led2.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    _led3.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    
    // Initialize USB
    usb.init();
    
    // Initialize QSPI
    qspi.init();
    qspi.config();
}

ICE40::SDGetStatusResp System::_getSDStatus() {
    ice40.write(SDGetStatusMsg());
    return ice40.read<SDGetStatusResp>();
}

ICE40::SDGetStatusResp System::_sendSDCmd(uint8_t sdCmd, uint32_t sdArg,
    SDSendCmdMsg::RespType respType, SDSendCmdMsg::DatInType datInType) {
    ice40.write(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
    
    // Wait for command to be sent
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) HAL_Delay(1);
        auto status = _getSDStatus();
        // Continue if the command hasn't been sent yet
        if (!status.sdCmdSent()) continue;
        // Continue if we expect a response but it hasn't been received yet
        if (respType!=SDRespType::None && !status.sdRespRecv()) continue;
        // Continue if we expect DatIn but it hasn't been received yet
        if (datInType!=SDDatInType::None && !status.sdDatInRecv()) continue;
        return status;
    }
}

void System::_handleEvent() {
    uint16_t rca = 0;
    
    char str[] = "halla";
    ice40.write(EchoMsg(str));
    auto status = ice40.read<ICE40::EchoResp>();
    Assert(!strcmp((char*)status.payload, str));
    
    const uint8_t SDClkSlowDelay = 15;
    const uint8_t SDClkFastDelay = 2;
    
    
    
    volatile uint32_t start = HAL_GetTick();
    {
        // Disable SD clock
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::None, SDClkSlowDelay));
        }
        
        // Enable SD slow clock
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::Slow, SDClkSlowDelay));
        }
        
        // ====================
        // CMD0 | GO_IDLE_STATE
        //   State: X -> Idle
        //   Go to idle state
        // ====================
        {
            _sendSDCmd(0, 0, SDRespType::None);
            // There's no response to CMD0
        }
        
        // ====================
        // CMD8 | SEND_IF_COND
        //   State: Idle -> Idle
        //   Send interface condition
        // ====================
        {
            auto status = _sendSDCmd(8, 0x000001AA);
            Assert(!status.sdRespCRCErr());
            Assert(status.getBits(15,8) == 0xAA); // Verify the response pattern is what we sent
        }
    }
    volatile uint32_t Phase1Duration = HAL_GetTick()-start;
    
    
    
    
    start = HAL_GetTick();
    {
        // ====================
        // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
        //   State: Idle -> Ready
        //   Initialize
        // ====================
        {
            for (;;) {
                // CMD55
                {
                    auto status = _sendSDCmd(55, 0);
                    Assert(!status.sdRespCRCErr());
                }
                
                // CMD41
                {
                    auto status = _sendSDCmd(41, 0x51008000);
                    // Don't check CRC with .sdRespCRCOK() (the CRC response to ACMD41 is all 1's)
                    // TODO: should we be checking these reserved fields in the response? what if a future spec version changes the response values?
                    Assert(status.getBits(45,40) == 0x3F); // Command should be 6'b111111
                    Assert(status.getBits(7,1) == 0x7F); // CRC should be 7'b1111111
                    // Check if card is ready. If it's not, retry ACMD41.
                    if (!status.getBits(39, 39)) {
                        // -> Card busy (response: 0x%012jx)\n\n", (uintmax_t)status.sdResp());
                        continue;
                    }
                    Assert(status.getBits(32, 32)); // Verify that card can switch to 1.8V
                    
                    break;
                }
            }
        }
    }
    volatile uint32_t Phase2Duration = HAL_GetTick()-start;
    
    
    
    start = HAL_GetTick();
    {
        // ====================
        // CMD11 | VOLTAGE_SWITCH
        //   State: Ready -> Ready
        //   Switch to 1.8V signaling voltage
        // ====================
        {
            auto status = _sendSDCmd(11, 0);
            Assert(!status.sdRespCRCErr());
        }
        
        // Disable SD clock for 5ms (SD clock source = none)
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::None, SDClkSlowDelay));
            HAL_Delay(5);
        }
        
        // Re-enable the SD clock
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::Slow, SDClkSlowDelay));
        }
        
        // Wait for SD card to indicate that it's ready (DAT0=1)
        {
            for (;;) {
                auto status = _getSDStatus();
                if (status.sdDat0Idle()) break;
                // Busy
            }
            // Ready
        }
    }
    volatile uint32_t Phase3Duration = HAL_GetTick()-start;
    
    
    
    
    start = HAL_GetTick();
    {
        // ====================
        // CMD2 | ALL_SEND_CID
        //   State: Ready -> Identification
        //   Get card identification number (CID)
        // ====================
        {
            // The response to CMD2 is 136 bits, instead of the usual 48 bits
            _sendSDCmd(2, 0, SDRespType::Long136);
            // Don't check the CRC because the CRC isn't calculated in the typical manner,
            // so it'll be flagged as incorrect
        }
        
        // ====================
        // CMD3 | SEND_RELATIVE_ADDR
        //   State: Identification -> Standby
        //   Publish a new relative address (RCA)
        // ====================
        {
            auto status = _sendSDCmd(3, 0);
            Assert(!status.sdRespCRCErr());
            // Get the card's RCA from the response
            rca = status.getBits(39, 24);
        }
    }
    volatile uint32_t Phase4Duration = HAL_GetTick()-start;
    
    
    
    start = HAL_GetTick();
    {
        // ====================
        // CMD7 | SELECT_CARD/DESELECT_CARD
        //   State: Standby -> Transfer
        //   Select card
        // ====================
        {
            auto status = _sendSDCmd(7, ((uint32_t)rca)<<16);
            Assert(!status.sdRespCRCErr());
        }
        
        // ====================
        // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
        //   State: Transfer -> Transfer
        //   Set bus width to 4 bits
        // ====================
        {
            // CMD55
            {
                auto status = _sendSDCmd(55, ((uint32_t)rca)<<16);
                Assert(!status.sdRespCRCErr());
            }
            
            // CMD6
            {
                auto status = _sendSDCmd(6, 0x00000002);
                Assert(!status.sdRespCRCErr());
            }
        }
    }
    volatile uint32_t Phase5Duration = HAL_GetTick()-start;
    
    
    
    start = HAL_GetTick();
    {
        // ====================
        // CMD6 | SWITCH_FUNC
        //   State: Transfer -> Data
        //   Switch to SDR104
        // ====================
        {
            // TODO: we need to check that the 'Access Mode' was successfully changed
            //       by looking at the function group 1 of the DAT response
            // Mode = 1 (switch function)  = 0x80
            // Group 6 (Reserved)          = 0xF (no change)
            // Group 5 (Reserved)          = 0xF (no change)
            // Group 4 (Current Limit)     = 0xF (no change)
            // Group 3 (Driver Strength)   = 0xF (no change; 0x0=TypeB[1x], 0x1=TypeA[1.5x], 0x2=TypeC[.75x], 0x3=TypeD[.5x])
            // Group 2 (Command System)    = 0xF (no change)
            // Group 1 (Access Mode)       = 0x3 (SDR104)
            auto status = _sendSDCmd(6, 0x80FFFFF3, SDRespType::Normal48, SDDatInType::Block512);
            Assert(!status.sdRespCRCErr());
            Assert(!status.sdDatInCRCErr());
        }
        
        // Disable SD clock
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::None, SDClkSlowDelay));
        }
        
        // Switch to the fast delay
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::None, SDClkFastDelay));
        }
        
        // Enable SD fast clock
        {
            ice40.write(SDSetClkMsg(SDSetClkMsg::ClkSrc::Fast, SDClkFastDelay));
        }
    }
    volatile uint32_t Phase6Duration = HAL_GetTick()-start;
    
    bool on = true;
    for (volatile uint32_t iter=0;; iter++) {
        // ====================
        // ACMD23 | SET_WR_BLK_ERASE_COUNT
        //   State: Transfer -> Transfer
        //   Set the number of blocks to be
        //   pre-erased before writing
        // ====================
        {
            // CMD55
            {
                auto status = _sendSDCmd(55, ((uint32_t)rca)<<16);
                Assert(!status.sdRespCRCErr());
            }
            
            // CMD23
            {
                auto status = _sendSDCmd(23, 0x00000001);
                Assert(!status.sdRespCRCErr());
            }
        }
        
        // ====================
        // CMD25 | WRITE_MULTIPLE_BLOCK
        //   State: Transfer -> Receive Data
        //   Write blocks of data
        // ====================
        {
            auto status = _sendSDCmd(25, 0);
            Assert(!status.sdRespCRCErr());
        }
        
        // Clock out data on DAT lines
        {
            ice40.write(SDDatOutMsg());
        }
        
        // Wait some pre-determined amount of time that guarantees that the
        // datOut state machine has started.
        // This is necessary so that when we observe sdDatOutIdle=1, it
        // means we're done writing, rather than that we haven't started yet.
        // TODO: determine the upper bound here using the write module's frequency and the number of cycles required for BankFifo to trigger its `rok` wire
        HAL_Delay(1);
        
        // Wait until we're done clocking out data on DAT lines
        {
            // Waiting for writing to finish
            for (;;) {
                auto status = _getSDStatus();
                if (status.sdDatOutIdle()) {
                    if (status.sdDatOutCRCErr()) {
                        _led3.write(true);
                        for (;;);
                    }
                    break;
                }
                // Busy
            }
        }
        
        // ====================
        // CMD12 | STOP_TRANSMISSION
        //   State: Receive Data -> Programming
        //   Finish writing
        // ====================
        {
            auto status = _sendSDCmd(12, 0);
            Assert(!status.sdRespCRCErr());
            
            // Wait for SD card to indicate that it's ready (DAT0=1)
            for (;;) {
                if (status.sdDat0Idle()) break;
                status = _getSDStatus();
            }
        }
        
        _led0.write(on);
        on = !on;
    }
    
//    volatile uint32_t duration = HAL_GetTick()-tickstart;
    for (;;);
}

void System::_usbHandleEvent(const USB::Event& ev) {
    using Type = USB::Event::Type;
    switch (ev.type) {
    case Type::StateChanged: {
        // Handle USB connection
        if (usb.state() == USB::State::Connected) {
            // Handle USB connected
        }
        break;
    }
    
    default: {
        // Invalid event type
        Abort();
    }}
}

System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
}

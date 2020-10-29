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
    
    // Initialize QSPI
    qspi.init();
    
    // Initialize USB
    usb.init();
}

void System::_sendSDCmd(uint8_t sdCmd, uint32_t sdArg) {
    using SDSendCmdMsg = ICE40::SDSendCmdMsg;
    using SDGetStatusMsg = ICE40::SDGetStatusMsg;
    using SDGetStatusResp = ICE40::SDGetStatusResp;
    ice40.write(SDSendCmdMsg(sdCmd, sdArg));
    
    // Wait for command to be sent
    for (;;) {
        ice40.write(SDGetStatusMsg());
        auto resp = ice40.read<SDGetStatusResp>();
        if (resp.sdCommandSent()) break;
    }
}

ICE40::SDGetStatusResp System::_getSDStatus() {
    using SDGetStatusMsg = ICE40::SDGetStatusMsg;
    using SDGetStatusResp = ICE40::SDGetStatusResp;
    ice40.write(SDGetStatusMsg());
    return ice40.read<SDGetStatusResp>();
}

ICE40::SDGetStatusResp System::_getSDResp() {
    for (;;) {
        auto status = _getSDStatus();
        if (status.sdRespRecv()) return status;
    }
}

void System::_handleEvent() {
    qspi.config();
    
    using SDSetClkSrcMsg = ICE40::SDSetClkSrcMsg;
    using SDDatOutMsg = ICE40::SDDatOutMsg;
    
    // Enable SD slow clock
    {
        ice40.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::Slow));
    }
    
    // Issue SD CMD0
    {
        _sendSDCmd(0, 0);
    }
    
    // Issue SD CMD8
    {
        _sendSDCmd(8, 0x000001AA);
        auto resp = _getSDResp();
        Assert(!resp.sdRespCRCErr());
        Assert(resp.getBits(15,8) == 0xAA); // Verify the response pattern is what we sent
    }
    
    // Issue SD ACMD41
    {
        for (;;) {
            // CMD55
            {
                _sendSDCmd(55, 0x00000000);
                auto resp = _getSDResp();
                Assert(!resp.sdRespCRCErr());
            }
            
            // CMD41
            {
                _sendSDCmd(41, 0x51008000);
                auto resp = _getSDResp();
                // Don't check CRC with .sdRespCRCOK() (the CRC response to ACMD41 is all 1's)
                Assert(resp.getBits(45,40) == 0x3F); // Command should be 6'b111111
                Assert(resp.getBits(7,1) == 0x7F); // CRC should be 7'b1111111
                // Check if card is ready. If it's not, retry ACMD41.
                if (!resp.getBits(39, 39)) {
                    // -> Card busy (response: 0x%012jx)\n\n", (uintmax_t)resp.sdResp());
                    continue;
                }
                Assert(resp.getBits(32, 32)); // Verify that card can switch to 1.8V
                
                break;
            }
        }
    }
    
    // Issue SD CMD11
    {
        _sendSDCmd(11, 0x00000000);
        auto resp = _getSDResp();
        Assert(!resp.sdRespCRCErr());
    }
    
    // Disable SD clock for 5ms (SD clock source = none)
    {
        ice40.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::None));
        HAL_Delay(5);
    }
    
    // Re-enable the SD clock
    {
        ice40.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::Slow));
    }
    
    // Wait for SD card to release DAT[0] line to indicate it's ready
    {
        // Waiting for SD card to be ready...
        for (;;) {
            auto status = _getSDStatus();
            if (status.sdDat() & 0x1) break;
            // Busy
        }
        // Ready
    }
    
    // Issue SD CMD2
    {
        _sendSDCmd(2, 0x00000000);
        _getSDResp();
        // Wait 1000us extra to allow the SD card to finish responding.
        // The SD card response to CMD2 is 136 bits (instead of the typical 48 bits),
        // so the SD card will still be responding at the time that the ice40 thinks
        // that the response is complete.
        HAL_Delay(1);
    }
    
    // Issue SD CMD3
    uint16_t rca = 0;
    {
        _sendSDCmd(3, 0x00000000);
        auto resp = _getSDResp();
        Assert(!resp.sdRespCRCErr());
        // Get the card's RCA from the response
        rca = resp.getBits(39, 24);
    }
    
    // Issue SD CMD7
    {
        _sendSDCmd(7, ((uint32_t)rca)<<16);
        auto resp = _getSDResp();
        Assert(!resp.sdRespCRCErr());
    }
    
    // Issue SD ACMD6
    {
        // CMD55
        {
            _sendSDCmd(55, ((uint32_t)rca)<<16);
            auto resp = _getSDResp();
            Assert(!resp.sdRespCRCErr());
        }
        
        // CMD6
        {
            _sendSDCmd(6, 0x00000002);
            auto resp = _getSDResp();
            Assert(!resp.sdRespCRCErr());
        }
    }
    
    
    
    
    
    // Issue SD CMD6
    {
        // TODO: we need to check that the 'Access Mode' was successfully changed
        //       by looking at the function group 1 of the DAT response
        // Sending SD CMD6
        _sendSDCmd(6, 0x80FFFFF3);
        auto resp = _getSDResp();
        Assert(!resp.sdRespCRCErr());
        // Wait 1000us to allow the SD card to finish writing the 512-bit status on the DAT lines
        // 512 bits / 4 DAT lines = 128 bits per DAT line -> 128 bits * (1/350kHz) = 366us.
        HAL_Delay(1);
    }
    
    
    // Disable SD clock
    {
        ice40.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::None));
    }
    
    // Enable SD fast clock
    {
        ice40.write(SDSetClkSrcMsg(SDSetClkSrcMsg::ClkSrc::Fast));
    }
    
    
    
    // Issue SD ACMD23
    {
        // CMD55
        {
            _sendSDCmd(55, ((uint32_t)rca)<<16);
            auto resp = _getSDResp();
            Assert(!resp.sdRespCRCErr());
        }
        
        // CMD23
        {
            _sendSDCmd(23, 0x00000001);
            auto resp = _getSDResp();
            Assert(!resp.sdRespCRCErr());
        }
    }
    
    
    // Issue SD CMD25
    {
        _sendSDCmd(25, 0);
        auto resp = _getSDResp();
        Assert(!resp.sdRespCRCErr());
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
                Assert(!status.sdDatOutCRCErr());
                break;
            }
            // Busy
        }
    }
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

void System::_iceHandleQSPIEvent(const QSPI::Event& ev) {
}

System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
}

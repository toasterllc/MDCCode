#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "MDCTypes.h"
#include "ICE40Types.h"

#define SleepMs(ms) __delay_cycles((((uint64_t)ms)*16000000) / 1000);
#include "SDCard.h"

using EchoMsg = ICE40::EchoMsg;
using EchoResp = ICE40::EchoResp;
using LEDSetMsg = ICE40::LEDSetMsg;
using SDInitMsg = ICE40::SDInitMsg;
using SDSendCmdMsg = ICE40::SDSendCmdMsg;
using SDStatusMsg = ICE40::SDStatusMsg;
using SDStatusResp = ICE40::SDStatusResp;
using ImgResetMsg = ICE40::ImgResetMsg;
using ImgSetHeaderMsg = ICE40::ImgSetHeaderMsg;
using ImgCaptureMsg = ICE40::ImgCaptureMsg;
using ImgReadoutMsg = ICE40::ImgReadoutMsg;
using ImgI2CTransactionMsg = ICE40::ImgI2CTransactionMsg;
using ImgI2CStatusMsg = ICE40::ImgI2CStatusMsg;
using ImgI2CStatusResp = ICE40::ImgI2CStatusResp;
using ImgCaptureStatusMsg = ICE40::ImgCaptureStatusMsg;
using ImgCaptureStatusResp = ICE40::ImgCaptureStatusResp;

using SDRespType = ICE40::SDSendCmdMsg::RespType;
using SDDatInType = ICE40::SDSendCmdMsg::DatInType;

constexpr uint64_t MCLKFreqHz = 16000000;

#define _delayUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000);
#define _delayMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000);

SDCard _sd;
const uint8_t SDCard::ClkDelaySlow = 7;
const uint8_t SDCard::ClkDelayFast = 0;

static void _clock_init() {
    constexpr uint32_t XT1FreqHz = 32768;
    
    // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
    // Make PA.8 and PA.9 XOUT/XIN
    PASEL1 |=  (BIT8 | BIT9);
    PASEL0 &= ~(BIT8 | BIT9);
    
    do {
        CSCTL7 &= ~(XT1OFFG | DCOFFG); // Clear XT1 and DCO fault flag
        SFRIFG1 &= ~OFIFG;
    } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set XT1 as FLL reference source
        CSCTL3 |= SELREF__XT1CLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        // Set DCO = 16MHz
        CSCTL1 |= DCORSEL_5;
        // DCOCLKDIV = 16MHz
        CSCTL2 = FLLD_0 | ((MCLKFreqHz/XT1FreqHz)-1);
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    
    // MCLK / SMCLK source = DCOCLKDIV
    // ACLK source = XT1
    CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
}

static void _sys_init() {
    // Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // Reset pin states
    {
        PAOUT   = 0x0000;
        PADIR   = 0x0000;
        PASEL0  = 0x0000;
        PASEL1  = 0x0000;
        PAREN   = 0x0000;
    }
    
    // Configure clock system
    {
        _clock_init();
    }
    
    // Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
}

static void _spi_init() {
    // Reset the ICE40 SPI state machine by asserting ice_msp_spi_clk for some period
    {
        constexpr uint64_t ICE40SPIResetDurationUs = 18;
        
        // PA.6 = GPIO output
        PAOUT  &= ~BIT6;
        PADIR  |=  BIT6;
        PASEL1 &= ~BIT6;
        PASEL0 &= ~BIT6;
        
        PAOUT  |=  BIT6;
        _delayUs(ICE40SPIResetDurationUs);
        PAOUT  &= ~BIT6;
    }
    
    // Configure SPI peripheral
    {
        // PA.3 = GPIO output
        PAOUT  &= ~BIT3;
        PADIR  |=  BIT3;
        PASEL1 &= ~BIT3;
        PASEL0 &= ~BIT3;
        
        // PA.4 = GPIO input
        PADIR  &= ~BIT4;
        PASEL1 &= ~BIT4;
        PASEL0 &= ~BIT4;
        
        // PA.5 = UCA0SOMI
        PASEL1 &= ~BIT5;
        PASEL0 |=  BIT5;
        
        // PA.6 = UCA0CLK
        PASEL1 &= ~BIT6;
        PASEL0 |=  BIT6;
        
        // Assert USCI reset
        UCA0CTLW0 |= UCSWRST;
        
        UCA0CTLW0 |=
            // phase=1, polarity=0, MSB first, width=8-bit
            UCCKPH_1 | UCCKPL__LOW | UCMSB_1 | UC7BIT__8BIT |
            // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
            UCMST__MASTER | UCMODE_0 | UCSYNC__SYNC | UCSSEL__SMCLK;
        
        // fBitClock = fBRCLK / 1;
        UCA0BRW = 0;
        // No modulation
        UCA0MCTLW = 0;
        
        // De-assert USCI reset
        UCA0CTLW0 &= ~UCSWRST;
    }
}

static uint8_t _spi_txrx(uint8_t b) {
    // Wait until `UCA0TXBUF` can accept more data
    while (!(UCA0IFG & UCTXIFG));
    // Clear UCRXIFG so we can tell when tx/rx is complete
    UCA0IFG &= ~UCRXIFG;
    // Start the SPI transaction
    UCA0TXBUF = b;
    // Wait for tx completion
    // Wait for UCRXIFG, not UCTXIFG! UCTXIFG signifies that UCA0TXBUF
    // can accept more data, not transfer completion. UCRXIFG signifies
    // rx completion, which implies tx completion.
    while (!(UCA0IFG & UCRXIFG));
    return UCA0RXBUF;
}

static void _ice_transfer(const ICE40::Msg& msg) {
    // PA.4 = UCA0SIMO
    PASEL1 &= ~BIT4;
    PASEL0 |=  BIT4;
    
    // PA.4 level shifter direction = MSP->ICE
    PAOUT |= BIT3;
    
    _spi_txrx(msg.type);
    
    for (uint8_t b : msg.payload) {
        _spi_txrx(b);
    }
    
    // PA.4 = GPIO input
    PASEL1 &= ~BIT4;
    PASEL0 &= ~BIT4;
    
    // PA.4 level shifter direction = MSP<-ICE
    PAOUT &= ~BIT3;
    
    // 8-cycle turnaround
    _spi_txrx(0);
}

static void _ice_transfer(const ICE40::Msg& msg, ICE40::Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & ICE40::MsgType::Resp));
    _ice_transfer(msg);
    // Clock in the response
    if (resp) {
        for (uint8_t& b : resp->payload) {
            b = _spi_txrx(0);
        }
    }
}

//void SDCard::SleepMs(uint32_t ms) {
//    _delayMs(ms);
//}

void SDCard::SetPowerEnabled(bool en) {
    constexpr uint16_t VDD_SD_EN = BITB;
    if (en) {
        PADIR |=  VDD_SD_EN;
        PAOUT |=  VDD_SD_EN;
    } else {
        PADIR |=  VDD_SD_EN;
        PAOUT &= ~VDD_SD_EN;
    }
    
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _delayMs(2);
}

void SDCard::ICETransfer(const ICE40::Msg& msg, ICE40::Resp* resp) {
    _ice_transfer(msg, resp);
}

void _sd_writeImage(uint16_t idx) {
    constexpr uint32_t ImgSDBlockLen = SDCard::CeilToBlockLen(MDC::ImgLen);
    const uint32_t addr = idx*ImgSDBlockLen;
    _sd.writeStart(addr, ImgSDBlockLen);
    
    // Clock out the image on the DAT lines
    _ice_transfer(ImgReadoutMsg(0));
    
    // Wait for writing to finish
    for (;;) {
        auto status = _sd.status();
        if (status.datOutDone()) {
            Assert(!status.datOutCRCErr());
            break;
        }
        // Busy
    }
    
    _sd.writeStop();
    
    // Wait for SD card to indicate that it's ready (DAT0=1)
    for (;;) {
        auto status = _sd.status();
        if (status.dat0Idle()) break;
    }
}

void _img_setPowerEnabled(bool en) {
    constexpr uint16_t VDD_1V9_IMG_EN = BIT0;
    constexpr uint16_t VDD_2V8_IMG_EN = BIT2;
    PADIR |=  VDD_2V8_IMG_EN|VDD_1V9_IMG_EN;
    
    if (en) {
        PAOUT |=  VDD_2V8_IMG_EN;
        _delayUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        PAOUT |=  VDD_1V9_IMG_EN;
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        PAOUT &= ~(VDD_2V8_IMG_EN|VDD_1V9_IMG_EN);
    }
}

ImgI2CStatusResp _img_i2cStatus() {
    ImgI2CStatusResp resp;
    _ice_transfer(ImgI2CStatusMsg(), &resp);
    return resp;
}

uint16_t _img_i2cRead(uint16_t addr) {
    _ice_transfer(ImgI2CTransactionMsg(false, 2, addr, 0));
    
    // Wait for the I2C transaction to complete
    const uint16_t MaxAttempts = 1000;
    for (uint16_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) _delayMs(1);
        const ImgI2CStatusResp status = _img_i2cStatus();
        if (status.err()) abort();
        if (status.done()) return status.readData();
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void _img_i2cWrite(uint16_t addr, uint16_t val) {
    _ice_transfer(ImgI2CTransactionMsg(true, 2, addr, val));
    
    // Wait for the I2C transaction to complete
    const uint16_t MaxAttempts = 1000;
    for (uint16_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) _delayMs(1);
        const ImgI2CStatusResp status = _img_i2cStatus();
        if (status.done()) {
            if (status.err()) abort();
            return;
        }
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void _img_init() {
    _img_setPowerEnabled(true);
    
    // Toggle IMG_RST_
    {
        _ice_transfer(ImgResetMsg(0));
        _delayMs(1);
        _ice_transfer(ImgResetMsg(1));
        // Wait 150k EXTCLK (16MHz) periods
        // (150e3*(1/16e6)) == 9.375ms
        _delayMs(10);
    }
    
    // Configure internal register initialization
    {
        _img_i2cWrite(0x3052, 0xA114);
    }
    
    // Start internal register initialization
    {
        _img_i2cWrite(0x304A, 0x0070);
    }
    
    // Wait 150k EXTCLK (16MHz) periods
    // (150e3*(1/16e6)) == 9.25ms
    {
        _delayMs(10);
    }
    
    // Sanity-check pix comms by reading a known register
    {
        const uint16_t chipVersion = _img_i2cRead(0x3000);
        // TODO: we probably don't want to check the version number in production, in case the version number changes?
        // also the 0x3000 isn't read-only, so in theory it could change
        Assert(chipVersion == 0x2604);
    }
    
    // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
    // (Default value of 0x301A is 0x0058)
    {
        _img_i2cWrite(0x301A, 0x10D8);
    }
    
    // Set pre_pll_clk_div
    {
        _img_i2cWrite(0x302E, 4);        //  /4 (default)
    }
    
    // Set pll_multiplier
    {
        _img_i2cWrite(0x3030, 147);      //  *147
    }
    
    // Set vt_sys_clk_div
    {
        _img_i2cWrite(0x302C, 1);        //  /1 (default)
    }
    
    // Set vt_pix_clk_div
    {
        _img_i2cWrite(0x302A, 6);        //  /6 (default)
    }
    
//        // Set op_pix_clk_div
//        {
//            _img_i2cWrite(0x3036, 0x000C);
//        }
    
    // Set output slew rate
    {
//        _img_i2cWrite(0x306E, 0x0010);  // Slow
//        _img_i2cWrite(0x306E, 0x9010);  // Medium (default)
        _img_i2cWrite(0x306E, 0xFC10);  // Fast
    }
    
    // Set data_pedestal
    {
//        _img_i2cWrite(0x301E, 0x00A8);  // Default
        _img_i2cWrite(0x301E, 0x0000);
    }
    
    // Set test data colors
    {
//            // Set test_data_red
//            _img_i2cWrite(0x3072, 0x0000);
//            
//            // Set test_data_greenr
//            _img_i2cWrite(0x3074, 0x0000);
//            
//            // Set test_data_blue
//            _img_i2cWrite(0x3076, 0x0000);
//            
//            // Set test_data_greenb
//            _img_i2cWrite(0x3078, 0x0000);
            
//            // Set test_data_red
//            _img_i2cWrite(0x3072, 0x0B2A);  // AAA
//            _img_i2cWrite(0x3072, 0x0FFF);  // FFF
//    
//            // Set test_data_greenr
//            _img_i2cWrite(0x3074, 0x0C3B);  // BBB
//            _img_i2cWrite(0x3074, 0x0FFF);  // FFF
//            _img_i2cWrite(0x3074, 0x0000);
//    
//            // Set test_data_blue
//            _img_i2cWrite(0x3076, 0x0D4C);  // CCC
//            _img_i2cWrite(0x3076, 0x0FFF);  // FFF
//            _img_i2cWrite(0x3076, 0x0000);
//    
//            // Set test_data_greenb
//            _img_i2cWrite(0x3078, 0x0C3B);  // BBB
//            _img_i2cWrite(0x3078, 0x0FFF);  // FFF
//            _img_i2cWrite(0x3078, 0x0000);
        
    }
    
    // Set test_pattern_mode
    {
        // 0: Normal operation (generate output data from pixel array)
        // 1: Solid color test pattern.
        // 2: Full color bar test pattern
        // 3: Fade-to-gray color bar test pattern
        // 256: Walking 1s test pattern (12 bit)
//        _img_i2cWrite(0x3070, 0x0000);  // Normal operation (default)
//        _img_i2cWrite(0x3070, 0x0001);  // Solid color
//        _img_i2cWrite(0x3070, 0x0002);  // Color bars
//        _img_i2cWrite(0x3070, 0x0003);  // Fade-to-gray
//        _img_i2cWrite(0x3070, 0x0100);  // Walking 1s
    }
    
    // Set serial_format
    // *** This register write is necessary for parallel mode.
    // *** The datasheet doesn't mention this. :(
    // *** Discovered looking at Linux kernel source.
    {
        _img_i2cWrite(0x31AE, 0x0301);
    }
    
    // Set data_format_bits
    // Datasheet:
    //   "The serial format should be configured using R0x31AC.
    //   This register should be programmed to 0x0C0C when
    //   using the parallel interface."
    {
        _img_i2cWrite(0x31AC, 0x0C0C);
    }
    
    // Set row_speed
    {
//        _img_i2cWrite(0x3028, 0x0000);  // 0 cycle delay
//        _img_i2cWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
    }

    // Set the x-start address
    {
//        _img_i2cWrite(0x3004, 0x0006);  // Default
//        _img_i2cWrite(0x3004, 0x0010);
    }

    // Set the x-end address
    {
//        _img_i2cWrite(0x3008, 0x0905);  // Default
//        _img_i2cWrite(0x3008, 0x01B1);
    }

    // Set the y-start address
    {
//        _img_i2cWrite(0x3002, 0x007C);  // Default
//        _img_i2cWrite(0x3002, 0x007C);
    }

    // Set the y-end address
    {
//        _img_i2cWrite(0x3006, 0x058b);  // Default
//        _img_i2cWrite(0x3006, 0x016B);
    }
    
    // Implement "Recommended Default Register Changes and Sequencer"
    {
        _img_i2cWrite(0x3ED2, 0x0146);
        _img_i2cWrite(0x3EDA, 0x88BC);
        _img_i2cWrite(0x3EDC, 0xAA63);
        _img_i2cWrite(0x305E, 0x00A0);
    }
    
    // Enable/disable embedded_data (2 extra rows of statistical info)
    // See AR0134_RR_D.pdf for info on statistics format
    {
//            _img_i2cWrite(0x3064, 0x1902);  // Stats enabled (default)
        _img_i2cWrite(0x3064, 0x1802);  // Stats disabled
    }
    
    constexpr uint16_t IntTimeMax = 16383;
    constexpr uint16_t GainMax = 63;
    
    constexpr uint16_t intTime = IntTimeMax/10;
    constexpr uint16_t gain = GainMax/10;
    
    // Set coarse_integration_time
    {
        // Normalize intTime to [0,IntTimeMax]
        constexpr uint16_t normVal = (((uint32_t)intTime*IntTimeMax)/UINT16_MAX);
        _img_i2cWrite(0x3012, normVal);
    }
    
    // Set fine_integration_time
    {
        _img_i2cWrite(0x3014, 0);
    }
    
    // Set analog_gain
    {
        // Normalize gain to [0,GainMax]
        constexpr uint16_t normVal = std::max((uint32_t)1, (((uint32_t)gain*GainMax)/UINT16_MAX));
        _img_i2cWrite(0x3060, normVal);
    }
}

void _img_setStreamEnabled(bool en) {
    _img_i2cWrite(0x301A, (en ? 0x10DC : 0x10D8));
}

ImgCaptureStatusResp _img_captureStatus() {
    ImgCaptureStatusResp resp;
    _ice_transfer(ImgCaptureStatusMsg(), &resp);
    return resp;
}

void _img_captureImage() {
    const MDC::ImgHeader header = {
        // Section idx=0
        .version        = 0x4242,
        .imageWidth     = 2304,
        .imageHeight    = 1296,
        ._pad0          = 0,
        // Section idx=1
        .counter        = 0xCAFEBABE,
        ._pad1          = 0,
        // Section idx=2
        .timestamp      = 0xDEADBEEF,
        ._pad2          = 0,
        // Section idx=3
        .exposure       = 0x1111,
        .gain           = 0x2222,
        ._pad3          = 0,
    };
    
    // Set the header of the image
    for (uint8_t i=0, off=0; i<4; i++, off+=8) {
        _ice_transfer(ImgSetHeaderMsg(i, (const uint8_t*)&header+off));
    }
    
    // Tell ICE40 to start capturing an image
    _ice_transfer(ImgCaptureMsg(0));
    
    // Wait for command to be sent
    constexpr uint16_t MaxAttempts = 1000;
    for (uint16_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) _delayMs(1);
        auto status = _img_captureStatus();
        // Try again if the image hasn't been captured yet
        if (!status.done()) continue;
        const uint32_t imgWordCount = status.wordCount();
        Assert(imgWordCount == MDC::ImgLen/sizeof(uint16_t));
        return;
    }
    // Timeout capturing image
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void _ice_init() {
    _spi_init();
    
    // Confirm that we can communicate with the ICE40
    {
        const char str[] = "halla";
        EchoResp resp;
        _ice_transfer(EchoMsg(str), &resp);
        Assert(!memcmp((char*)resp.payload, str, sizeof(str)));
    }
}

int main() {
    // Init system (clock, pins, etc)
    _sys_init();
    // Init ICE40 comms
    _ice_init();
    // Initialize the image sensor
    _img_init();
    // Initialize the SD card
    _sd.init();
    // Enable image streaming
    _img_setStreamEnabled(true);
    
    for (int i=0; i<10; i++) {
        _ice_transfer(LEDSetMsg(i));
        
        // Capture an image to RAM
        _img_captureImage();
        // Write the image to the SD card
        _sd_writeImage(i);
        _delayMs(1000);
    }
    
    for (;;);
    
    return 0;
}

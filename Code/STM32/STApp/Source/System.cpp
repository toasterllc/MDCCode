#include "System.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"
#include "MSP430.h"

using EchoMsg = ICE40::EchoMsg;
using EchoResp = ICE40::EchoResp;
using LEDSetMsg = ICE40::LEDSetMsg;
using SDInitMsg = ICE40::SDInitMsg;
using SDSendCmdMsg = ICE40::SDSendCmdMsg;
using SDStatusMsg = ICE40::SDStatusMsg;
using SDStatusResp = ICE40::SDStatusResp;
using SDReadoutMsg = ICE40::SDReadoutMsg;
using ImgResetMsg = ICE40::ImgResetMsg;
using ImgSetHeader1Msg = ICE40::ImgSetHeader1Msg;
using ImgSetHeader2Msg = ICE40::ImgSetHeader2Msg;
using ImgCaptureMsg = ICE40::ImgCaptureMsg;
using ImgReadoutMsg = ICE40::ImgReadoutMsg;
using ImgI2CTransactionMsg = ICE40::ImgI2CTransactionMsg;
using ImgI2CStatusMsg = ICE40::ImgI2CStatusMsg;
using ImgI2CStatusResp = ICE40::ImgI2CStatusResp;
using ImgCaptureStatusMsg = ICE40::ImgCaptureStatusMsg;
using ImgCaptureStatusResp = ICE40::ImgCaptureStatusResp;

using SDRespTypes = ICE40::SDSendCmdMsg::RespTypes;
using SDDatInTypes = ICE40::SDSendCmdMsg::DatInTypes;

uint8_t MEOWBUF[MEOWBUFLEN] __attribute__((aligned(4))) __attribute__((section(".sram1")));

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
//static uint8_t _buf0[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));
//static uint8_t _buf1[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));

using namespace STApp;

System::System() :
// QSPI clock divider=1 => run QSPI clock at 64 MHz
// QSPI alignment=word for high performance transfers
_qspi(QSPI::Mode::Dual, 1, QSPI::Align::Word, QSPI::ChipSelect::Uncontrolled) {
}

static QSPI_CommandTypeDef _ice40QSPICmd(const ICE40::Msg& msg, size_t respLen) {
    uint8_t b[8];
    static_assert(sizeof(msg) == sizeof(b));
    memcpy(b, &msg, sizeof(b));
    
    // When dual-flash quadspi is enabled, the supplied address is
    // divided by 2, so we left-shift `addr` in anticipation of that.
    // By doing so, we throw out the high bit of `msg`, however we
    // wrote the ICE40 Verilog to fake the first bit as 1, so verify
    // that the first bit is indeed 1.
    AssertArg(b[0] & 0x80);
    
    return QSPI_CommandTypeDef{
        // Use instruction stage to introduce 2 dummy cycles, to workaround an
        // apparent STM32 bug that always sends the first nibble as 0xF.
        .Instruction = 0x00,
        .InstructionMode = QSPI_INSTRUCTION_4_LINES,
        
        // When dual-flash quadspi is enabled, the supplied address is
        // divided by 2, so we left-shift `addr` in anticipation of that.
        .Address = (
            (uint32_t)b[0]<<24  |
            (uint32_t)b[1]<<16  |
            (uint32_t)b[2]<<8   |
            (uint32_t)b[3]<<0
        ) << 1,
//            .Address = 0,
        .AddressSize = QSPI_ADDRESS_32_BITS,
        .AddressMode = QSPI_ADDRESS_4_LINES,
        
        .AlternateBytes = (
            (uint32_t)b[4]<<24  |
            (uint32_t)b[5]<<16  |
            (uint32_t)b[6]<<8   |
            (uint32_t)b[7]<<0
        ),
//            .AlternateBytes = 0,
        .AlternateBytesSize = QSPI_ALTERNATE_BYTES_32_BITS,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_4_LINES,
        
        .DummyCycles = 4,
        
        .NbData = (uint32_t)respLen,
        .DataMode = (respLen ? QSPI_DATA_4_LINES : QSPI_DATA_NONE),
        
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
}

void System::init() {
    _super::init();
    _usb.init();
    
    
//    _qspi.init();
//    
//    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, 0);
//    _ICE_ST_SPI_CS_::Write(1);
//    
//    _iceInit();
//    _mspInit();
//    _sdInit();
}

void System::_handleEvent() {
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.eventChannel.readSelect()) {
        _usb_eventHandle(*x);
    
    } else if (auto x = _usb.resetRecvChannel.readSelect()) {
        _usb_reset(true);
    
    } else if (auto x = _usb.cmdRecvChannel.readSelect()) {
        _usb_cmdHandle(*x);
    
    } else if (auto x = _usb.dataSendChannel.readSelect()) {
        _usb_dataSendHandle(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _sdRead_qspiEventHandle(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
}

void System::_finishCmd(Status status) {
    Assert(!_usbDataBusy);
    
    // Update our state
    _op = Op::None;
}

#pragma mark - USB

void System::_usb_reset(bool usbResetFinish) {
    // Disable interrupts so that resetting is atomic
    IRQState irq;
    irq.disable();
        // Complete USB reset, if the source of the reset was _usb.resetChannel
        if (usbResetFinish) _usb.resetFinish();
        
        // Reset our state
        _qspi.reset();
        
        // Prepare to receive commands
        _usb.cmdRecv();
    irq.restore();
    
    const uint8_t EP1 = 1;
    PCD_HandleTypeDef* hpcd = &_usb._pcd;
    USB_OTG_GlobalTypeDef *USBx = hpcd->Instance;
    uint32_t USBx_BASE = (uint32_t)USBx;
    
    irq.disable();
    USBD_LL_Transmit(&_usb._device, 0x80|EP1, MEOWBUF, MEOWSENDLEN);
    for (;;) {
        extern HAL_StatusTypeDef PCD_WriteEmptyTxFifo(PCD_HandleTypeDef *hpcd, uint32_t epnum);
        PCD_WriteEmptyTxFifo(hpcd, EP1);
        
        uint32_t epint = USB_ReadDevInEPInterrupt(hpcd->Instance, EP1);
        if (epint & USB_OTG_DIEPINT_XFRC) {
            uint32_t fifoemptymsk = (uint32_t)(0x1UL << (EP1 & EP_ADDR_MSK));
            USBx_DEVICE->DIEPEMPMSK &= ~fifoemptymsk;
            CLEAR_IN_EP_INTR(EP1, USB_OTG_DIEPINT_XFRC);
            USBD_LL_Transmit(&_usb._device, 0x80|EP1, MEOWBUF, MEOWSENDLEN);
        }
    }
}

void System::_usb_cmdHandle(const USB::CmdRecv& ev) {
    Assert(_op == Op::None);
    
    Cmd cmd;
    Assert(ev.len == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    // SD Read
    case Op::SDRead:                _sdRead(cmd);   break;
    // Set LED
    case Op::LEDSet:                _ledSet(cmd);   break;
    // Bad command
    default:                        abort();        break;
    }
}

void System::_usb_cmdRecv() {
    // Prepare to receive another command
    _usb.cmdRecv();
}

void System::_usb_eventHandle(const USB::Event& ev) {
    using Type = USB::Event::Type;
    switch (ev.type) {
    case Type::StateChanged: {
        // Handle USB connection
        if (_usb.state() == USB::State::Connected) {
            _usb_reset(false);
        }
        break;
    }
    
    default: {
        // Invalid event type
        abort();
    }}
}

void System::_usb_sendFromBuf() {
}

void System::_usb_dataSendHandle(const USB::DataSend& ev) {
}

#pragma mark - ICE40

void System::_iceInit() {
    // Confirm that we can communicate with the ICE40.
    // Interrupts need to be enabled for this, since _ice40Transfer()
    // waits for a response on qspi.eventChannel.
    EchoResp resp;
    const char str[] = "halla";
    _ice40Transfer(EchoMsg(str), resp);
    Assert(!strcmp((char*)resp.payload, str));
}

void System::_ice40TransferNoCS(const ICE40::Msg& msg) {
    _qspi.command(_ice40QSPICmd(msg, 0));
    _qspi.eventChannel.read(); // Wait for the transfer to complete
}

void System::_ice40Transfer(const ICE40::Msg& msg) {
    _ICE_ST_SPI_CS_::Write(0);
    _ice40TransferNoCS(msg);
    _ICE_ST_SPI_CS_::Write(1);
}

void System::_ice40Transfer(const ICE40::Msg& msg, ICE40::Resp& resp) {
    _ICE_ST_SPI_CS_::Write(0);
    _qspi.read(_ice40QSPICmd(msg, sizeof(resp)), &resp, sizeof(resp));
    _qspi.eventChannel.read(); // Wait for the transfer to complete
    _ICE_ST_SPI_CS_::Write(1);
}

#pragma mark - MSP430

void System::_mspInit() {
    constexpr uint16_t PM5CTL0          = 0x0130;
    constexpr uint16_t PAOUT            = 0x0202;
    
    auto s = _msp.connect();
    Assert(s == _msp.Status::OK);
    
    // Clear LOCKLPM5 in the PM5CTL0 register
    // This is necessary to be able to control the GPIOs
    _msp.write(PM5CTL0, 0x0010);
    
    // Clear PAOUT so everything is driven to 0 by default
    _msp.write(PAOUT, 0x0000);
}

#pragma mark - SD Card

void System::_sdSetPowerEnabled(bool en) {
    constexpr uint16_t BITB         = 0x0800;
    constexpr uint16_t VDD_SD_EN    = BITB;
    constexpr uint16_t PADIR        = 0x0204;
    constexpr uint16_t PAOUT        = 0x0202;
    
    if (en) {
        _msp.write(PADIR, VDD_SD_EN);
        _msp.write(PAOUT, VDD_SD_EN);
    } else {
        _msp.write(PADIR, VDD_SD_EN);
        _msp.write(PAOUT, 0);
    }
}

SDStatusResp System::_sdStatus() {
    using namespace ICE40;
    SDStatusResp resp;
    _ice40Transfer(SDStatusMsg(), resp);
    return resp;
}

SDStatusResp System::_sdSendCmd(uint8_t sdCmd, uint32_t sdArg, SDSendCmdMsg::RespType respType, SDSendCmdMsg::DatInType datInType) {
    _ice40Transfer(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
    
    // Wait for command to be sent
    const uint16_t MaxAttempts = 1000;
    for (uint16_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) HAL_Delay(1);
        auto status = _sdStatus();
        // Try again if the command hasn't been sent yet
        if (!status.cmdDone()) continue;
        // Try again if we expect a response but it hasn't been received yet
        if ((respType==SDRespTypes::Len48||respType==SDRespTypes::Len136) && !status.respDone()) continue;
        // Try again if we expect DatIn but it hasn't been received yet
        if (datInType==SDDatInTypes::Len512x1 && !status.datInDone()) continue;
        return status;
    }
    // Timeout sending SD command
    abort();
}

void System::_sdInit() {
}

void System::_sdRead(const Cmd& cmd) {
    // Update state
    _op = cmd.op;
    _opDataRem = 0xFFFFFE00; // divisible by 512
    
    // ====================
    // CMD18 | READ_MULTIPLE_BLOCK
    //   State: Transfer -> Send Data
    //   Read blocks of data (1 block == 512 bytes)
    // ====================
    {
        auto status = _sdSendCmd(18, 0, SDRespTypes::Len48, SDDatInTypes::Len4096xN);
        Assert(!status.respCRCErr());
    }
    
    // Send the SDReadout message, which causes us to enter the SD-readout mode until
    // we release the chip select
    _ICE_ST_SPI_CS_::Write(0);
    _ice40TransferNoCS(SDReadoutMsg());
    
    // Advance state machine
    _sdRead_updateState();
}

void System::_sdRead_qspiReadToBuf() {
}

void System::_sdRead_qspiReadToBufSync(void* buf, size_t len) {
    // Assert chip-select so that we stay in the readout state until we release it
    _ICE_ST_SPI_CS_::Write(0);
    
    // Send the SDReadout message, which causes us to enter the SD-readout mode until
    // we release the chip select
    _ice40TransferNoCS(SDReadoutMsg());
    
    // TODO: how do we handle lengths that aren't a multiple of ReadoutLen?
    QSPI_CommandTypeDef qspiCmd = {
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        .AddressMode = QSPI_ADDRESS_NONE,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
        .DummyCycles = 8,
        .NbData = (uint32_t)len,
        .DataMode = QSPI_DATA_4_LINES,
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
    
    _qspi.read(qspiCmd, buf, len);
    _qspi.eventChannel.read(); // Wait for the transfer to complete
    
    _ICE_ST_SPI_CS_::Write(1);
}

void System::_sdRead_qspiEventHandle(const QSPI::Signal& ev) {
}

void System::_sdRead_usbDataSendHandle(const USB::DataSend& ev) {
    Assert(_op == Op::SDRead);
    // Advance state machine
    _sdRead_updateState();
}






void System::_sdRead_updateState() {
}

void System::_sdRead_finish() {
    _ICE_ST_SPI_CS_::Write(1);
    _finishCmd(Status::OK);
}

#pragma mark - Other Commands

void System::_ledSet(const Cmd& cmd) {
    switch (cmd.arg.LEDSet.idx) {
//    case 0: _LED0::Write(cmd.arg.LEDSet.on); break;
    case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    _finishCmd(Status::OK);
}

System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
    return 0;
}

[[noreturn]] void abort() {
    Sys.abort();
}

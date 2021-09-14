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

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
static uint8_t _buf0[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));
static uint8_t _buf1[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));

using namespace STApp;

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

System::System() :
// QSPI clock divider=1 => run QSPI clock at 64 MHz
// QSPI alignment=word for high performance transfers
_qspi(QSPI::Mode::Dual, 1, QSPI::Align::Word, QSPI::ChipSelect::Uncontrolled),
_bufs(_buf0, _buf1) {
}

void System::init() {
    _super::init();
    _usb.init();
    _qspi.init();
    
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, 0);
    _ICE_ST_SPI_CS_::Write(1);
    
//    _iceInit();
//    _mspInit();
//    _sdInit();
}

void System::_handleEvent() {
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.cmdRecvChannel.readSelect()) {
        _usb_cmdHandle(*x);
    
    } else if (auto x = _usb.dataSendReadyChannel.readSelect()) {
        _usb_dataSendReady(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _sdRead_qspiEventHandle(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
    ChannelSelect::End();
}

void System::_reset(const Cmd& cmd) {
    _op = Op::None;
    _usb.dataSendReset();
    _finishCmd(true);
}

void System::_finishCmd(bool status) {
    // Send our response
    _usb.cmdSendStatus(status);
}

#pragma mark - USB

void System::_usb_cmdHandle(const USB::CmdRecv& ev) {
    Cmd cmd;
    Assert(ev.len == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    case Op::Reset:     _reset(cmd);    break;
    case Op::SDRead:    _sdRead(cmd);   break;
    case Op::LEDSet:    _ledSet(cmd);   break;
    // Bad command
    default:            abort();        break;
    }
}

void System::_usb_sendFromBuf() {
    Assert(!_bufs.empty());
    Assert(_usb.dataSendReady());
    
    const auto& buf = _bufs.front();
    _usb.dataSend(buf.data, buf.len);
}

void System::_usb_dataSendReady(const USB::DataSend& ev) {
    switch (_op) {
    case Op::SDRead:    _sdRead_usbDataSendReady(ev);  break;
    default:                                           break;
    }
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
    const uint8_t SDClkDelaySlow = 7;
    const uint8_t SDClkDelayFast = 0;
    
    // Disable SDController clock
    _ice40Transfer(SDInitMsg(SDInitMsg::Action::Nop,        SDInitMsg::ClkSpeed::Off,   SDClkDelaySlow));
    HAL_Delay(1);
    
    // Enable slow SDController clock
    _ice40Transfer(SDInitMsg(SDInitMsg::Action::Nop,        SDInitMsg::ClkSpeed::Slow,  SDClkDelaySlow));
    HAL_Delay(1);
    
    // Enter the init mode of the SDController state machine
    _ice40Transfer(SDInitMsg(SDInitMsg::Action::Reset,      SDInitMsg::ClkSpeed::Slow,  SDClkDelaySlow));
    
    // Turn off SD card power and wait for it to reach 0V
    _sdSetPowerEnabled(false);
    HAL_Delay(2);
    
    // Turn on SD card power and wait for it to reach 2.8V
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _sdSetPowerEnabled(true);
    HAL_Delay(2);
    
    // Trigger the SD card low voltage signalling (LVS) init sequence
    _ice40Transfer(SDInitMsg(SDInitMsg::Action::Trigger,    SDInitMsg::ClkSpeed::Slow,  SDClkDelaySlow));
    // Wait 6ms for the LVS init sequence to complete (LVS spec specifies 5ms, and ICE40 waits 5.5ms)
    HAL_Delay(6);
    
    // ====================
    // CMD0 | GO_IDLE_STATE
    //   State: X -> Idle
    //   Go to idle state
    // ====================
    {
        // SD "Initialization sequence": wait max(1ms, 74 cycles @ 400 kHz) == 1ms
        HAL_Delay(1);
        // Send CMD0
        _sdSendCmd(0, 0, SDRespTypes::None);
        // There's no response to CMD0
    }
    
    // ====================
    // CMD8 | SEND_IF_COND
    //   State: Idle -> Idle
    //   Send interface condition
    // ====================
    {
        constexpr uint32_t Voltage       = 0x00000002; // 0b0010 == 'Low Voltage Range'
        constexpr uint32_t CheckPattern  = 0x000000AA; // "It is recommended to use '10101010b' for the 'check pattern'"
        auto status = _sdSendCmd(8, (Voltage<<8)|(CheckPattern<<0));
        Assert(!status.respCRCErr());
        const uint8_t replyVoltage = status.respGetBits(19,16);
        Assert(replyVoltage == Voltage);
        const uint8_t replyCheckPattern = status.respGetBits(15,8);
        Assert(replyCheckPattern == CheckPattern);
    }
    
    // ====================
    // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
    //   State: Idle -> Ready
    //   Initialize
    // ====================
    for (;;) {
        // CMD55
        {
            auto status = _sdSendCmd(55, 0);
            Assert(!status.respCRCErr());
        }
        
        // CMD41
        {
            auto status = _sdSendCmd(41, 0x51008000);
            
            // Don't check CRC with .respCRCOK() (the CRC response to ACMD41 is all 1's)
            
            if (status.respGetBits(45,40) != 0x3F) {
                for (volatile int i=0; i<10; i++);
                continue;
            }
            
            // TODO: determine if the wrong CRC in the ACMD41 response is because `SDClkDelaySlow` needs tuning
            if (status.respGetBits(7,1) != 0x7F) {
                for (volatile int i=0; i<10; i++);
                continue;
            }
            
            // Check if card is ready. If it's not, retry ACMD41.
            const bool ready = status.respGetBit(39);
            if (!ready) continue;
            // Check S18A; for LVS initialization, it's expected to be 0
            const bool S18A = status.respGetBit(32);
            Assert(S18A == 0);
            break;
        }
    }
    
    // ====================
    // CMD2 | ALL_SEND_CID
    //   State: Ready -> Identification
    //   Get card identification number (CID)
    // ====================
    {
        // The response to CMD2 is 136 bits, instead of the usual 48 bits
        _sdSendCmd(2, 0, SDRespTypes::Len136);
        // Don't check the CRC because the R2 CRC isn't calculated in the typical manner,
        // so it'll be flagged as incorrect.
    }
    
    // ====================
    // CMD3 | SEND_RELATIVE_ADDR
    //   State: Identification -> Standby
    //   Publish a new relative address (RCA)
    // ====================
    {
        auto status = _sdSendCmd(3, 0);
        Assert(!status.respCRCErr());
        // Get the card's RCA from the response
        _sdRCA = status.respGetBits(39,24);
    }
    
    // ====================
    // CMD7 | SELECT_CARD/DESELECT_CARD
    //   State: Standby -> Transfer
    //   Select card
    // ====================
    {
        auto status = _sdSendCmd(7, ((uint32_t)_sdRCA)<<16);
        Assert(!status.respCRCErr());
    }
    
    // ====================
    // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
    //   State: Transfer -> Transfer
    //   Set bus width to 4 bits
    // ====================
    {
        // CMD55
        {
            auto status = _sdSendCmd(55, ((uint32_t)_sdRCA)<<16);
            Assert(!status.respCRCErr());
        }
        
        // CMD6
        {
            auto status = _sdSendCmd(6, 0x00000002);
            Assert(!status.respCRCErr());
        }
    }
    
    // ====================
    // CMD6 | SWITCH_FUNC
    //   State: Transfer -> Data -> Transfer (automatically returns to Transfer state after sending 512 bits of data)
    //   Switch to SDR104
    // ====================
    {
        // Mode = 1 (switch function)  = 0x80
        // Group 6 (Reserved)          = 0xF (no change)
        // Group 5 (Reserved)          = 0xF (no change)
        // Group 4 (Current Limit)     = 0xF (no change)
        // Group 3 (Driver Strength)   = 0xF (no change; 0x0=TypeB[1x], 0x1=TypeA[1.5x], 0x2=TypeC[.75x], 0x3=TypeD[.5x])
        // Group 2 (Command System)    = 0xF (no change)
        // Group 1 (Access Mode)       = 0x3 (SDR104)
        auto status = _sdSendCmd(6, 0x80FFFFF3, SDRespTypes::Len48, SDDatInTypes::Len512x1);
        Assert(!status.respCRCErr());
        Assert(!status.datInCRCErr());
        
        // Verify that the access mode was successfully changed
        // TODO: properly handle this failing, see CMD6 docs
        _sdRead_qspiReadToBufSync(_buf0, 512/8); // Read DatIn data into _buf0
        Assert((_buf0[16]&0x0F) == 0x03);
    }
    
    // SDClock=Off
    {
        _ice40Transfer(SDInitMsg(SDInitMsg::Action::Nop,    SDInitMsg::ClkSpeed::Off,   SDClkDelaySlow));
    }
    
    // SDClockDelay=FastDelay
    {
        _ice40Transfer(SDInitMsg(SDInitMsg::Action::Nop,    SDInitMsg::ClkSpeed::Off,   SDClkDelayFast));
    }
    
    // SDClock=FastClock
    {
        _ice40Transfer(SDInitMsg(SDInitMsg::Action::Nop,    SDInitMsg::ClkSpeed::Fast,   SDClkDelayFast));
    }
    
    
//    {
//        // Update state
//        _op = Op::SDRead;
//        _opDataRem = 0xFFFFFE00; // divisible by 512
//        
//        // ====================
//        // CMD18 | READ_MULTIPLE_BLOCK
//        //   State: Transfer -> Send Data
//        //   Read blocks of data (1 block == 512 bytes)
//        // ====================
//        {
//            auto status = _sdSendCmd(18, 0, SDRespTypes::Len48, SDDatInTypes::Len4096xN);
//            Assert(!status.respCRCErr());
//        }
//        
//        // Send the SDReadout message, which causes us to enter the SD-readout mode until
//        // we release the chip select
//        _ICE_ST_SPI_CS_::Write(0);
//        _ice40TransferNoCS(SDReadoutMsg());
//        
//        // Advance state machine
//        _sdRead_updateState();
//    }
    
    
    
//    bool on = true;
//    for (volatile uint32_t iter=0;; iter++) {
//        // ====================
//        // ACMD23 | SET_WR_BLK_ERASE_COUNT
//        //   State: Transfer -> Transfer
//        //   Set the number of blocks to be
//        //   pre-erased before writing
//        // ====================
//        {
//            // CMD55
//            {
//                auto status = _sdSendCmd(55, ((uint32_t)_sdRCA)<<16);
//                Assert(!status.respCRCErr());
//            }
//            
//            // CMD23
//            {
//                auto status = _sdSendCmd(23, 0x00000001);
//                Assert(!status.respCRCErr());
//            }
//        }
//        
//        // ====================
//        // CMD25 | WRITE_MULTIPLE_BLOCK
//        //   State: Transfer -> Receive Data
//        //   Write blocks of data (1 block == 512 bytes)
//        // ====================
//        {
//            auto status = _sdSendCmd(25, 0);
//            Assert(!status.respCRCErr());
//        }
//        
//        // Clock out data on DAT lines
//        {
//            _ice40Transfer(PixReadoutMsg(0));
//        }
//        
//        // Wait until we're done clocking out data on DAT lines
//        {
//            // Waiting for writing to finish
//            for (;;) {
//                auto status = _sdStatus();
//                if (status.datOutDone()) {
//                    if (status.datOutCRCErr()) {
//                        _led3.write(true);
//                        for (;;);
//                    }
//                    break;
//                }
//                // Busy
//            }
//        }
//        
//        // ====================
//        // CMD12 | STOP_TRANSMISSION
//        //   State: Receive Data -> Programming
//        //   Finish writing
//        // ====================
//        {
//            auto status = _sdSendCmd(12, 0);
//            Assert(!status.respCRCErr());
//            
//            // Wait for SD card to indicate that it's ready (DAT0=1)
//            for (;;) {
//                if (status.dat0Idle()) break;
//                status = _sdStatus();
//            }
//        }
//        
//        _led0.write(on);
//        on = !on;
//    }
}

void System::_sdRead(const Cmd& cmd) {
    _usb.dataSend(_buf0, 512);
    _finishCmd(true);
}

void System::_sdRead_qspiReadToBuf() {
    Assert(_op == Op::SDRead);
    Assert(!_bufs.full());
    Assert(_opDataRem);
    Assert(!_qspiBusy);
    
    auto& buf = _bufs.back();
    
    #warning TODO: uncomment
//    // Wait for ICE40 to signal that data is ready
//    while (!_ICE_ST_SPI_D_READY::Read());
    
    // TODO: how do we handle lengths that aren't a multiple of ReadoutLen?
    const size_t len = SDReadoutMsg::ReadoutLen;
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
    
    _qspi.read(qspiCmd, buf.data+buf.len, len);
    buf.len += len;
    
    _qspiBusy = true;
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
    Assert(_op == Op::SDRead);
    Assert(_qspiBusy);
    
    auto& buf = _bufs.back();
    _qspiBusy = false;
    
    // If we can't read any more data into the producer buffer,
    // push it so the data will be sent over USB
    if (buf.cap-buf.len < SDReadoutMsg::ReadoutLen) {
        _opDataRem -= buf.len;
        _bufs.push();
    }
    
    // Advance state machine
    _sdRead_updateState();
}

void System::_sdRead_usbDataSendReady(const USB::DataSend& ev) {
    Assert(_op == Op::SDRead);
    _usb.dataSend(_buf0, 512);
    _op = Op::None;
}






//// Arrange for pix data to be received from ICE40
//void System::_recvPixDataFromICE40() {
//    Assert(!_bufs.full());
//    
//    // TODO: ensure that the byte length is aligned to a u32 boundary, since QSPI requires that!
//    const size_t len = std::min(_pixRemLen, _bufs.back().cap);
//    // Determine whether this is the last readout, and therefore the ice40 should automatically
//    // capture the next image when readout is done.
////    const bool captureNext = (len == _pixRemLen);
//    const bool captureNext = false;
//    _bufs.back().len = len;
//    
//    _ice40TransferAsync(_qspi, PixReadoutMsg(0, captureNext, len/sizeof(Pixel)),
//        _bufs.back().data,
//        _bufs.back().len);
//}

//// Arrange for pix data to be sent over USB
//void System::_sendPixDataOverUSB() {
//    Assert(!_bufs.empty());
//    const auto& buf = _bufs.front();
//    _usb.pixSend(buf.data, buf.len);
//}

void System::_sdRead_updateState() {
    // Read data into the producer buffer when:
    //   - there's more data to be read, and
    //   - there's space in the queue, and
    //   - QSPI isn't currently reading data into the queue
    if (_opDataRem && !_bufs.full() && !_qspiBusy) {
        _sdRead_qspiReadToBuf();
    }
    
    // Send data from the consumer buffer when:
    //   - we have data to write, and
    //   - we're not currently sending data over USB
    if (!_bufs.empty() && _usb.dataSendReady()) {
        _usb_sendFromBuf();
    }
    
    // We're done when:
    //   - there's no more data to be read, and
    //   - there's no more data to send over USB
    if (!_opDataRem && _bufs.empty()) {
        _sdRead_finish();
    }
}

void System::_sdRead_finish() {
    _ICE_ST_SPI_CS_::Write(1);
}

#pragma mark - Other Commands

void System::_ledSet(const Cmd& cmd) {
    switch (cmd.arg.LEDSet.idx) {
    case 0: _finishCmd(false); return;
    case 1: _LED1::Write(cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(cmd.arg.LEDSet.on); break;
    }
    
    _finishCmd(true);
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

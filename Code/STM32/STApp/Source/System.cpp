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
using ReadoutMsg = ICE40::ReadoutMsg;
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

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
alignas(4) static uint8_t _buf0[63*1024] __attribute__((section(".sram1")));
alignas(4) static uint8_t _buf1[63*1024] __attribute__((section(".sram1")));

using namespace STApp;

System::System() :
// QSPI clock divider=1 => run QSPI clock at 64 MHz
// QSPI alignment=word for high performance transfers
_qspi(QSPI::Mode::Dual, 1, QSPI::Align::Word, QSPI::ChipSelect::Uncontrolled),
_bufs(_buf0, _buf1)
{}

void System::init() {
    _super::init();
    _usb.init();
    _qspi.init();
    
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, 0);
    _ICE_ST_SPI_CS_::Write(1);
    
    _ice_init();
    _msp_init();
    
    _resetTasks();
}

void System::run() {
    Task::Run(_tasks);
}

void System::_resetTasks() {
    // De-assert the SPI chip select
    // This is necessary because the readout task asserts the SPI chip select,
    // but has no way to deassert it, because it continues indefinitely
    _ICE_ST_SPI_CS_::Write(1);
    
    for (Task& t : _tasks) {
        if (&t == &_usbCmdTask) continue; // Never pause the USB command task
        t.pause();
    }
}

#pragma mark - USB

void System::_usbCmd_task() {
    TaskBegin();
    for (;;) {
        auto usbCmd = *TaskWait(_usb.cmdRecv());
        
        // Reject command if the length isn't valid
        if (usbCmd.len != sizeof(_cmd)) {
            _usb.cmdAccept(false);
            continue;
        }
        
        memcpy(&_cmd, usbCmd.data, usbCmd.len);
        
        // Stop all tasks
        _resetTasks();
        
        // Specially handle the Reset command -- it's the only command that doesn't
        // require the endpoints to be ready.
        if (_cmd.op == Op::Reset) {
            _resetTask.start();
            continue;
        }
        
        // Reject command if the endpoints aren't ready
        if (!_usb.ready(Endpoints::DataIn)) {
            _usb.cmdAccept(false);
            continue;
        }
        
        switch (_cmd.op) {
        case Op::Bootloader:    _bootloader();              break;
        case Op::SDRead:        _sdReadTask.start();        break;
        case Op::ImgI2C:        _imgI2CTask.start();        break;
        case Op::ImgCapture:    _imgCaptureTask.start();    break;
        case Op::LEDSet:        _ledSet();                  break;
        // Bad command
        default:                _usb.cmdAccept(false);      break;
        }
    }
}

// _usbDataIn_task: writes buffers from _bufs to the DataIn endpoint, and pops them from _bufs
void System::_usbDataIn_task() {
    TaskBegin();
    
    for (;;) {
        TaskWait(!_bufs.empty());
        
        // Send the data and wait until the transfer is complete
        _usb.send(Endpoints::DataIn, _bufs.front().data, _bufs.front().len);
        TaskWait(_usb.ready(Endpoints::DataIn));
        
        _bufs.front().len = 0;
        _bufs.pop();
    }
}

#pragma mark - Reset

void System::_reset_task() {
    TaskBegin();
    // Accept command
    _usb.cmdAccept(true);
    // Reset endpoints
    _usb.reset(Endpoints::DataIn);
    TaskWait(_usb.ready(Endpoints::DataIn));
}

#pragma mark - Readout

void System::_readout_task() {
    TaskBegin();
    
    // Reset state
    _bufs.reset();
    // Start the USB DataIn task
    _usbDataInTask.start();
    
    // Send the Readout message, which causes us to enter the readout mode until
    // we release the chip select
    _ICE_ST_SPI_CS_::Write(0);
    _ice_transferNoCS(ReadoutMsg());
    
    // Read data over QSPI and write it to USB, indefinitely
    for (;;) {
        // Wait until: there's an available buffer, QSPI is ready, and ICE40 says data is available
        TaskWait(!_bufs.full() && _qspi.ready());
        
        const size_t len = std::min(_readoutLen.value_or(SIZE_MAX), ReadoutMsg::ReadoutLen);
        auto& buf = _bufs.back();
        
        // If there's no more data to read, bail
        if (!len) {
            // Before bailing, push the final buffer if it holds data
            if (buf.len) _bufs.push();
            break;
        }
        
        // If we can't read any more data into the producer buffer,
        // push it so the data will be sent over USB
        if (buf.cap-buf.len < len) {
            _bufs.push();
            continue;
        }
        
        // Wait until ICE40 signals that data is ready to be read
        while (!_ICE_ST_SPI_D_READY::Read());
        
        _ice_qspiRead(buf.data+buf.len, len);
        buf.len += len;
        
        if (_readoutLen) *_readoutLen -= len;
    }
}

#pragma mark - Bootloader

void System::_bootloader() {
    _usb.cmdAccept(true);
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

#pragma mark - ICE40

static QSPI_CommandTypeDef _ice_qspiCmd(const ICE40::Msg& msg, size_t respLen) {
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

void System::_ice_init() {
    // Confirm that we can communicate with the ICE40
    EchoResp resp;
    const char str[] = "halla";
    _ice_transfer(EchoMsg(str), resp);
    Assert(!strcmp((char*)resp.payload, str));
}

void System::_ice_transferNoCS(const ICE40::Msg& msg) {
    _qspi.command(_ice_qspiCmd(msg, 0));
    _qspi.wait();
}

void System::_ice_transfer(const ICE40::Msg& msg) {
    _ICE_ST_SPI_CS_::Write(0);
    _ice_transferNoCS(msg);
    _ICE_ST_SPI_CS_::Write(1);
}

void System::_ice_transfer(const ICE40::Msg& msg, ICE40::Resp& resp) {
    _ICE_ST_SPI_CS_::Write(0);
    _qspi.read(_ice_qspiCmd(msg, sizeof(resp)), &resp, sizeof(resp));
    _qspi.wait();
    _ICE_ST_SPI_CS_::Write(1);
}

void System::_ice_qspiRead(void* buf, size_t len) {
    const QSPI_CommandTypeDef qspiCmd = {
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
}

void System::_ice_readout(void* buf, size_t len) {
    // Assert chip-select so that we stay in the readout state until we release it
    _ICE_ST_SPI_CS_::Write(0);
    // Send the Readout message, which causes us to enter the SD-readout mode until
    // we release the chip select
    _ice_transferNoCS(ReadoutMsg());
    _ice_qspiRead(buf, len);
    _qspi.wait();
    _ICE_ST_SPI_CS_::Write(1);
}

#pragma mark - MSP430

void System::_msp_init() {
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

void System::_sd_setPowerEnabled(bool en) {
    constexpr uint16_t BITB         = 1<<0xB;
    constexpr uint16_t VDD_SD_EN    = BITB;
    constexpr uint16_t PADIRAddr    = 0x0204;
    constexpr uint16_t PAOUTAddr    = 0x0202;
    
    const uint16_t PADIR = _msp.read(PADIRAddr);
    const uint16_t PAOUT = _msp.read(PAOUTAddr);
    _msp.write(PADIRAddr, PADIR | VDD_SD_EN);
    
    if (en) {
        _msp.write(PAOUTAddr, PAOUT | VDD_SD_EN);
    } else {
        _msp.write(PAOUTAddr, PAOUT & ~VDD_SD_EN);
    }
    
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    HAL_Delay(2);
}

uint16_t System::_sd_init() {
    const uint8_t SDClkDelaySlow = 7;
    const uint8_t SDClkDelayFast = 0;
    uint16_t rca = 0;
    
    // Disable SDController clock
    _ice_transfer(SDInitMsg(SDInitMsg::Action::Nop,        SDInitMsg::ClkSpeed::Off,   SDClkDelaySlow));
    HAL_Delay(1);
    
    // Enable slow SDController clock
    _ice_transfer(SDInitMsg(SDInitMsg::Action::Nop,        SDInitMsg::ClkSpeed::Slow,  SDClkDelaySlow));
    HAL_Delay(1);
    
    // Enter the init mode of the SDController state machine
    _ice_transfer(SDInitMsg(SDInitMsg::Action::Reset,      SDInitMsg::ClkSpeed::Slow,  SDClkDelaySlow));
    
    // Turn off SD card power and wait for it to reach 0V
    _sd_setPowerEnabled(false);
    
    // Turn on SD card power and wait for it to reach 2.8V
    _sd_setPowerEnabled(true);
    
    // Trigger the SD card low voltage signalling (LVS) init sequence
    _ice_transfer(SDInitMsg(SDInitMsg::Action::Trigger,    SDInitMsg::ClkSpeed::Slow,  SDClkDelaySlow));
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
        _sd_sendCmd(SDSendCmdMsg::CMD0, 0, SDRespType::None);
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
        auto status = _sd_sendCmd(SDSendCmdMsg::CMD8, (Voltage<<8)|(CheckPattern<<0));
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
            auto status = _sd_sendCmd(SDSendCmdMsg::CMD55, 0);
            Assert(!status.respCRCErr());
        }
        
        // CMD41
        {
            auto status = _sd_sendCmd(SDSendCmdMsg::CMD41, 0x51008000);
            
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
        _sd_sendCmd(SDSendCmdMsg::CMD2, 0, SDRespType::Len136);
        // Don't check the CRC because the R2 CRC isn't calculated in the typical manner,
        // so it'll be flagged as incorrect.
    }
    
    // ====================
    // CMD3 | SEND_RELATIVE_ADDR
    //   State: Identification -> Standby
    //   Publish a new relative address (RCA)
    // ====================
    {
        auto status = _sd_sendCmd(SDSendCmdMsg::CMD3, 0);
        Assert(!status.respCRCErr());
        // Get the card's RCA from the response
        rca = status.respGetBits(39,24);
    }
    
    // ====================
    // CMD7 | SELECT_CARD/DESELECT_CARD
    //   State: Standby -> Transfer
    //   Select card
    // ====================
    {
        auto status = _sd_sendCmd(SDSendCmdMsg::CMD7, ((uint32_t)rca)<<16);
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
            auto status = _sd_sendCmd(SDSendCmdMsg::CMD55, ((uint32_t)rca)<<16);
            Assert(!status.respCRCErr());
        }
        
        // CMD6
        {
            auto status = _sd_sendCmd(SDSendCmdMsg::CMD6, 0x00000002);
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
        auto status = _sd_sendCmd(SDSendCmdMsg::CMD6, 0x80FFFFF3, SDRespType::Len48, SDDatInType::Len512x1);
        Assert(!status.respCRCErr());
        Assert(!status.datInCRCErr());
        
        // Verify that the access mode was successfully changed
        // TODO: properly handle this failing, see CMD6 docs
        _ice_readout(_buf0, 512/8); // Read DatIn data into _buf0
        Assert((_buf0[16]&0x0F) == 0x03);
    }
    
    // SDClock=Off
    {
        _ice_transfer(SDInitMsg(SDInitMsg::Action::Nop,    SDInitMsg::ClkSpeed::Off,   SDClkDelaySlow));
    }
    
    // SDClockDelay=FastDelay
    {
        _ice_transfer(SDInitMsg(SDInitMsg::Action::Nop,    SDInitMsg::ClkSpeed::Off,   SDClkDelayFast));
    }
    
    // SDClock=FastClock
    {
        _ice_transfer(SDInitMsg(SDInitMsg::Action::Nop,    SDInitMsg::ClkSpeed::Fast,   SDClkDelayFast));
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
//            auto status = _sd_sendCmd(SDSendCmdMsg::CMD18, 0, SDRespType::Len48, SDDatInType::Len4096xN);
//            Assert(!status.respCRCErr());
//        }
//        
//        // Send the Readout message, which causes us to enter the SD-readout mode until
//        // we release the chip select
//        _ICE_ST_SPI_CS_::Write(0);
//        _ice_transferNoCS(ReadoutMsg());
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
//                auto status = _sd_sendCmd(SDSendCmdMsg::CMD55, ((uint32_t)rca)<<16);
//                Assert(!status.respCRCErr());
//            }
//            
//            // CMD23
//            {
//                auto status = _sd_sendCmd(SDSendCmdMsg::CMD23, 0x00000001);
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
//            auto status = _sd_sendCmd(SDSendCmdMsg::CMD25, 0);
//            Assert(!status.respCRCErr());
//        }
//        
//        // Clock out data on DAT lines
//        {
//            _ice_transfer(PixReadoutMsg(0));
//        }
//        
//        // Wait until we're done clocking out data on DAT lines
//        {
//            // Waiting for writing to finish
//            for (;;) {
//                auto status = _sd_status();
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
//            auto status = _sd_sendCmd(SDSendCmdMsg::CMD12, 0);
//            Assert(!status.respCRCErr());
//            
//            // Wait for SD card to indicate that it's ready (DAT0=1)
//            for (;;) {
//                if (status.dat0Idle()) break;
//                status = _sd_status();
//            }
//        }
//        
//        _led0.write(on);
//        on = !on;
//    }
    
    return rca;
}

SDStatusResp System::_sd_status() {
    using namespace ICE40;
    SDStatusResp resp;
    _ice_transfer(SDStatusMsg(), resp);
    return resp;
}

SDStatusResp System::_sd_sendCmd(
    uint8_t sdCmd,
    uint32_t sdArg,
    SDSendCmdMsg::RespType respType,
    SDSendCmdMsg::DatInType datInType
) {
    _ice_transfer(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
    
    // Wait for command to be sent
    const uint16_t MaxAttempts = 1000;
    for (uint16_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) HAL_Delay(1);
        auto status = _sd_status();
        // Try again if the command hasn't been sent yet
        if (!status.cmdDone()) continue;
        // Try again if we expect a response but it hasn't been received yet
        if ((respType==SDRespType::Len48||respType==SDRespType::Len136) && !status.respDone()) continue;
        // Try again if we expect DatIn but it hasn't been received yet
        if (datInType==SDDatInType::Len512x1 && !status.datInDone()) continue;
        return status;
    }
    // Timeout sending SD command
    abort();
}

void System::_sd_readTask() {
    static bool init = false;
    static bool reading = false;
    static uint16_t rca = 0;
    const auto& arg = _cmd.arg.SDRead;
    
    TaskBegin();
    
    // Accept command
    _usb.cmdAccept(true);
    
    // Initialize the SD card if we haven't done so
    if (!init) {
        rca = _sd_init();
        init = true;
    }
    
    // Stop reading from the SD card if a read is in progress
    if (reading) {
        _ICE_ST_SPI_CS_::Write(1);
        
        // ====================
        // CMD12 | STOP_TRANSMISSION
        //   State: Send Data -> Transfer
        //   Finish reading
        // ====================
        {
            auto status = _sd_sendCmd(SDSendCmdMsg::CMD12, 0);
            Assert(!status.respCRCErr());
        }
        
        reading = false;
    }
    
    // Reset DataIn endpoint (which sends a 2xZLP+sentinel sequence)
    _usb.reset(Endpoints::DataIn);
    // Wait until we're done resetting the DataIn endpoint
    TaskWait(_usb.ready(Endpoints::DataIn));
    
    // Update state
    reading = true;
    
    // ====================
    // CMD18 | READ_MULTIPLE_BLOCK
    //   State: Transfer -> Send Data
    //   Read blocks of data (1 block == 512 bytes)
    // ====================
    {
        auto status = _sd_sendCmd(SDSendCmdMsg::CMD18, arg.addr, SDRespType::Len48, SDDatInType::Len4096xN);
        Assert(!status.respCRCErr());
    }
    
    // Start the Readout task
    _readoutLen = std::nullopt;
    _readoutTask.start();
}

#pragma mark - Img

void System::_img_setPowerEnabled(bool en) {
    constexpr uint16_t BIT0             = 1<<0;
    constexpr uint16_t BIT2             = 1<<2;
    constexpr uint16_t VDD_1V9_IMG_EN   = BIT0;
    constexpr uint16_t VDD_2V8_IMG_EN   = BIT2;
    constexpr uint16_t PADIRAddr       = 0x0204;
    constexpr uint16_t PAOUTAddr       = 0x0202;
    
    const uint16_t PADIR = _msp.read(PADIRAddr);
    const uint16_t PAOUT = _msp.read(PAOUTAddr);
    _msp.write(PADIRAddr, PADIR | (VDD_2V8_IMG_EN | VDD_1V9_IMG_EN));
    
    if (en) {
        _msp.write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN));
        HAL_Delay(1); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        _msp.write(PAOUTAddr, PAOUT | (VDD_2V8_IMG_EN|VDD_1V9_IMG_EN));
    
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        _msp.write(PAOUTAddr, PAOUT & ~(VDD_2V8_IMG_EN|VDD_1V9_IMG_EN));
    }
    
    #warning TODO: measure how long it takes for IMG rails to rise
    // The TPS22919 takes 1ms for VDD_2V8_IMG VDD to reach 2.8V (empirically measured)
    HAL_Delay(2);
}

void System::_img_init() {
    _img_setPowerEnabled(true);
    
    _ice_transfer(ImgResetMsg(0));
    HAL_Delay(1);
    _ice_transfer(ImgResetMsg(1));
    // Wait 150k EXTCLK (16MHz) periods
    // (150e3*(1/16e6)) == 9.375ms
    HAL_Delay(10);
}

ImgI2CStatusResp System::_imgI2CStatus() {
    ImgI2CStatusResp resp;
    _ice_transfer(ImgI2CStatusMsg(), resp);
    return resp;
}

ImgCaptureStatusResp System::_imgCaptureStatus() {
    ImgCaptureStatusResp resp;
    _ice_transfer(ImgCaptureStatusMsg(), resp);
    return resp;
}

ImgI2CStatusResp System::_imgI2C(bool write, uint16_t addr, uint16_t val) {
    _ice_transfer(ImgI2CTransactionMsg(write, 2, addr, 0));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) HAL_Delay(1);
        const ImgI2CStatusResp status = _imgI2CStatus();
        if (status.err() || status.done()) return status;
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

ImgI2CStatusResp System::_imgI2CRead(uint16_t addr) {
    return _imgI2C(false, addr, 0);
}

ImgI2CStatusResp System::_imgI2CWrite(uint16_t addr, uint16_t val) {
    return _imgI2C(true, addr, val);
}

void System::_img_i2cTask() {
    static bool init = false;
    static ImgI2CStatus status = {};
    const auto& arg = _cmd.arg.ImgI2C;
    
    TaskBegin();
    _usb.cmdAccept(true);
    
    // Initialize image sensor if we haven't done so already
    if (!init) {
        _img_init();
        init = true;
    }
    
    {
        const ImgI2CStatusResp s = _imgI2C(arg.write, arg.addr, arg.val);
        status.ok = !s.err();
        status.readData = s.readData();
    }
    
    {
        _usb.send(Endpoints::DataIn, &status, sizeof(status));
        TaskWait(_usb.ready(Endpoints::DataIn));
    }
}

void System::_img_captureTask() {
    static ImgCaptureStatus status = {};
    TaskBegin();
    _usb.cmdAccept(true);
    
    _ice_transfer(ImgCaptureMsg(0));
    
    // Wait a max of `MaxDelayMs` for the the capture to be ready for readout
    constexpr uint32_t MaxDelayMs = 1000;
    const uint32_t startTime = HAL_GetTick();
    ImgCaptureStatusResp s;
    for (;;) {
        s = _imgCaptureStatus();
        if (s.done() || (HAL_GetTick()-startTime)>=MaxDelayMs) break;
    }
    
    status.ok               = s.done();
    status.wordCount        = s.wordCount();
    status.highlightCount   = s.highlightCount();
    status.shadowCount      = s.shadowCount();
    
    _usb.send(Endpoints::DataIn, &status, sizeof(status));
    TaskWait(_usb.ready(Endpoints::DataIn));
    
    // Bail if the capture failed
    if (!status.ok) return;
    
    // Start the Readout task
    _readoutLen = (size_t)status.wordCount;
    _readoutTask.start();
}

#pragma mark - Other Commands

void System::_ledSet() {
    switch (_cmd.arg.LEDSet.idx) {
    case 0: _usb.cmdAccept(false); return;
    case 1: _LED1::Write(_cmd.arg.LEDSet.on); break;
    case 2: _LED2::Write(_cmd.arg.LEDSet.on); break;
    case 3: _LED3::Write(_cmd.arg.LEDSet.on); break;
    }
    
    _usb.cmdAccept(true);
}

System Sys;

bool IRQState::SetInterruptsEnabled(bool en) {
    const bool prevEn = !__get_PRIMASK();
    if (en) __enable_irq();
    else __disable_irq();
    return prevEn;
}

void IRQState::WaitForInterrupt() {
    __WFI();
}

int main() {
    Sys.init();
    Sys.run();
    return 0;
}

[[noreturn]] void abort() {
    Sys.abort();
}

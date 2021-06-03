#include "System.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
static uint8_t _pixBuf0[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));
static uint8_t _pixBuf1[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));

using namespace STApp;

using EchoMsg = ICE40::EchoMsg;
using EchoResp = ICE40::EchoResp;
using SDClkSrcMsg = ICE40::SDClkSrcMsg;
using SDSendCmdMsg = ICE40::SDSendCmdMsg;
using SDGetStatusMsg = ICE40::SDGetStatusMsg;
using SDGetStatusResp = ICE40::SDGetStatusResp;
using PixResetMsg = ICE40::PixResetMsg;
using PixCaptureMsg = ICE40::PixCaptureMsg;
using PixReadoutMsg = ICE40::PixReadoutMsg;
using PixI2CTransactionMsg = ICE40::PixI2CTransactionMsg;
using PixI2CStatusMsg = ICE40::PixI2CStatusMsg;
using PixI2CStatusResp = ICE40::PixI2CStatusResp;
using PixCaptureStatusMsg = ICE40::PixCaptureStatusMsg;
using PixCaptureStatusResp = ICE40::PixCaptureStatusResp;

using SDRespTypes = ICE40::SDSendCmdMsg::RespTypes;
using SDDatInTypes = ICE40::SDSendCmdMsg::DatInTypes;

System::System() :
// QSPI clock divider=1 => run QSPI clock at 64 MHz
// QSPI alignment=word for high performance transfers
_qspi(QSPI::Mode::Dual, 1, QSPI::Align::Word),
_pixBufs(_pixBuf0, _pixBuf1) {
}

static QSPI_CommandTypeDef _ice40QSPICmd(const ICE40::Msg& msg, size_t respLen) {
    uint8_t b[8];
    static_assert(sizeof(msg) == sizeof(b));
    memcpy(b, &msg, sizeof(b));
    
    // When dual-flash quadspi is enabled, the supplied address is
    // divided by 2, so we left-shift `addr` in anticipation of that.
    // But by doing so, we throw out the high bit of `msg`, so we
    // require it to be 0.
    AssertArg(!(b[0] & 0x80));
    
    return QSPI_CommandTypeDef{
        .Instruction = 0xFF,
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

static void _ice40Transfer(QSPI& qspi, const ICE40::Msg& msg) {
    qspi.command(_ice40QSPICmd(msg, 0));
    qspi.eventChannel.read(); // Wait for the transfer to complete
}

template <typename T>
static T _ice40Transfer(QSPI& qspi, const ICE40::Msg& msg) {
    T resp;
    qspi.read(_ice40QSPICmd(msg, sizeof(resp)), &resp, sizeof(resp));
    qspi.eventChannel.read(); // Wait for the transfer to complete
    return resp;
}

static void _ice40Transfer(QSPI& qspi, const ICE40::Msg& msg, void* resp, size_t respLen) {
    qspi.read(_ice40QSPICmd(msg, respLen), resp, respLen);
    qspi.eventChannel.read(); // Wait for the transfer to complete
}

static void _ice40TransferAsync(QSPI& qspi, const ICE40::Msg& msg, void* resp, size_t respLen) {
    qspi.read(_ice40QSPICmd(msg, respLen), resp, respLen);
}

class MSP430 {
private:
    using TMS = bool;
    static constexpr TMS TMS0 = false;
    static constexpr TMS TMS1 = true;
    static constexpr TMS TMSX = false; // Don't care
    
    using TDI = bool;
    static constexpr TDI TDI0 = false;
    static constexpr TDI TDI1 = true;
    static constexpr TDI TDIX = false; // Don't care
    
    using TDO = bool;
    static constexpr TDO TDO0 = false;
    static constexpr TDO TDO1 = true;
    static constexpr TDO TDOX = false; // Don't care
    
    static void _delay() {
        constexpr uint32_t SpyBiWireDelayCount = 0;
        for (volatile uint32_t i=0; i<SpyBiWireDelayCount; i++);
    }
    
    // Perform a single Spy-bi-wire I/O cycle
    TDO _sbwio(TMS tms, TDI tdi) {
        // ## Write TMS
        {
            _sbwTDIO.write(tms);
            _delay();
            
            _sbwTCK.write(0);
            _delay();
            _sbwTCK.write(1);
            _delay();
        }
        
        // ## Write TDI
        {
            _sbwTDIO.write(tdi);
            _delay();
            
            _sbwTCK.write(0);
            _delay();
            _sbwTCK.write(1);
            // Stop driving SBWTDIO, in preparation for the slave to start driving it
            _sbwTDIO.config(GPIO_MODE_INPUT, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
            _delay();
        }
        
        // ## Read TDO
        TDO tdo = TDO0;
        {
            _sbwTCK.write(0);
            _delay();
            // Read the TDO value, driven by the slave, while SBWTCK=0
            tdo = _sbwTDIO.read();
            _sbwTCK.write(1);
            _delay();
            _sbwTDIO.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0); // Start driving SBWTDIO again
        }
        
        return tdo;
    }
    
    void _startShiftIR() {
        // <-- Run-Test/Idle
        _sbwio(TMS1, TDIX);
        // <-- Select DR-Scan
        _sbwio(TMS1, TDIX);
        // <-- Select IR-Scan
        _sbwio(TMS0, TDIX);
        // <-- Capture-IR
        _sbwio(TMS0, TDIX);
        // <-- Shift-IR
    }
    
    void _startShiftDR() {
        // <-- Run-Test/Idle
        _sbwio(TMS1, TDIX);
        // <-- Select DR-Scan
        _sbwio(TMS0, TDIX);
        // <-- Capture-IR
        _sbwio(TMS0, TDIX);
        // <-- Shift-DR
    }
    
    template <typename T>
    T _shift(T dout) {
        // <-- Shift-DR / Shift-IR
        T din = 0;
        for (size_t i=0; i<sizeof(T)*8; i++) {
            const TMS tms = (i<((sizeof(T)*8)-1) ? TMS0 : TMS1); // Final bit needs TMS=1
            din <<= 1;
            din |= _sbwio(tms, dout&0x1);
            dout >>= 1;
        }
        
        // <-- Exit1-DR / Exit1-IR
        _sbwio(TMS1, TDOX);
        // <-- Update-DR / Update-IR
        _sbwio(TMS0, TDOX);
        // <-- Run-Test/Idle
        
        return din;
    }
    
    GPIO& _mspTest;
    GPIO& _mspRst_;
    GPIO& _sbwTCK;
    GPIO& _sbwTDIO;
    
public:
    MSP430(GPIO& mspTest, GPIO& mspRst_) :
    _mspTest(mspTest), _mspRst_(mspRst_),
    _sbwTCK(mspTest), _sbwTDIO(mspRst_)
    {}
    
    void go() {
        IRQState state;
        state.disable();
        
        // ## JTAG entry, attempt 1
        {
            // ## Reset pin states
            {
                _mspTest.write(0);
                _mspRst_.write(1);
                for (uint32_t i=0; i<65535; i++) {
                    _delay();
                }
            }
            
            // ## Reset the MSP430 so that it starts from a known state
            {
                _mspRst_.write(0);
                _delay();
                _mspRst_.write(1);
                _delay();
            }
            
            // ## Enable SBW interface
            {
                // Assert TEST
                _mspTest.write(1);
                _delay();
            }
            
            // ## Choose 2-wire/Spy-bi-wire mode
            {
                // SBWTDIO=1, and apply a single clock to SBWTCK
                _sbwTDIO.write(1);
                _delay();
                _sbwTCK.write(0);
                _delay();
                _sbwTCK.write(1);
                _delay();
            }

            // ## Reset JTAG state machine
            {
                // TMS=1 for 6 clocks
                for (int i=0; i<100; i++) {
                    _sbwio(TMS1, TDIX);
                }
                // <-- Test-Logic-Reset
                
                // TMS=0 for 1 clock
                _sbwio(TMS0, TDIX);
                // <-- Run-Test/Idle
                
                // Fuse check: toggle TMS twice
                _sbwio(TMS1, TDIX);
                // <-- Select DR-Scan
                _sbwio(TMS0, TDIX);
                // <-- Capture DR
                _sbwio(TMS1, TDIX);
                // <-- Exit1-DR
                _sbwio(TMS0, TDIX);
                // <-- Pause-DR
                _sbwio(TMS1, TDIX);
                // <-- Exit2-DR
                
                // In SBW mode, the fuse check causes the JTAG state machine to change states,
                // so we need to explicitly return to the Run-Test/Idle state.
                // (This isn't necessary in 4-wire JTAG mode, since the state machine doesn't
                // change states when performing the fuse check.)
                _sbwio(TMS1, TDIX);
                // <-- Update-DR
                _sbwio(TMS0, TDIX);
                // <-- Run-Test/Idle
            }
            
            // Try to read JTAG ID
            {
                #define IR_CNTRL_SIG_16BIT	0xC8	/* 0x13 */
                #define IR_CNTRL_SIG_CAPTURE	0x28	/* 0x14 */
//                #define IR_CNTRL_SIG_16BIT	0x13
//                #define IR_CNTRL_SIG_CAPTURE	0x14
                _startShiftIR();
                _shift<uint8_t>(IR_CNTRL_SIG_16BIT);
                
                _startShiftDR();
                _shift<uint16_t>(0x2401);
                
                volatile uint8_t jtagID = _shift<uint8_t>(IR_CNTRL_SIG_CAPTURE);
                for (;;);
            }
        }        
    }
};

void System::init() {
    _super::init();
    _usb.init();
    _qspi.init();
    
    MSP430 msp(_mspTest, _mspRst_);
    msp.go();
}




//// Test QSPI
//void System::_handleEvent() {
//    // Confirm that we can communicate with the ICE40
//    {
//        char str[] = "halla";
//        volatile auto status = _ice40Transfer<EchoResp>(_qspi, EchoMsg(str));
//        Assert(!strcmp((char*)status.payload, str));
//    }
//    
//    // Test reading a chunk of data
//    for (;;) {
//        static uint8_t respDataChunk[65532];
//        Msg msg;
//        msg.type = 0x01;
//        _ice40Transfer(_qspi, msg, (void*)respDataChunk, sizeof(respDataChunk));
//        // Confirm the data is what we expect
//        for (size_t i=0; i<sizeof(respDataChunk); i++) {
//            if (!(i % 2))   Assert(respDataChunk[i] == 0x37);
//            else            Assert(respDataChunk[i] == 0x42);
//        }
//    }
//    
//    for (;;);
//}

// Test QSPI perf
//
// *** NOTE ***
//   HAL_SuspendTick/HAL_ResumeTick must be commented-out
//   in IRQState.h to accurately track time!
//void System::_handleEvent() {
//    const uint32_t iterCount = 2048;
//    ICE40::Msg msg;
//    msg.type = 0x01;
//    
//    uint32_t startTime = HAL_GetTick();
//        for (uint32_t i=0; i<iterCount; i++) {
//            _ice40Transfer(_qspi, msg, (void*)_pixBuf0, sizeof(_pixBuf0));
//        }
//    uint32_t endTime = HAL_GetTick();
//    
//    uint64_t bytes = sizeof(_pixBuf0)*iterCount;
//    uint64_t durationMs = endTime-startTime;
//    volatile uint64_t bytesPerSecond = ((bytes*UINT64_C(1000))/durationMs);
//    for (;;);
//}

SDGetStatusResp System::_sdGetStatus() {
    return _ice40Transfer<SDGetStatusResp>(_qspi, SDGetStatusMsg());
}

SDGetStatusResp System::_sdSendCmd(uint8_t sdCmd, uint32_t sdArg,
    SDSendCmdMsg::RespType respType, SDSendCmdMsg::DatInType datInType) {
    
    _ice40Transfer(_qspi, SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
    
    // Wait for command to be sent
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) HAL_Delay(1);
        auto status = _sdGetStatus();
        // Continue if the command hasn't been sent yet
        if (!status.sdCmdDone()) continue;
        // Continue if we expect a response but it hasn't been received yet
        if (respType!=SDRespTypes::None && !status.sdRespDone()) continue;
        // Continue if we expect DatIn but it hasn't been received yet
        if (datInType!=SDDatInTypes::None && !status.sdDatInDone()) continue;
        return status;
    }
}

//// Test SD card bulk DatOut writing
//void System::_handleEvent() {
//    const uint8_t SDClkSlowDelay = 15;
//    const uint8_t SDClkFastDelay = 2;
//    
//    // Confirm that we can communicate with the ICE40
//    {
//        char str[] = "halla";
//        auto status = _ice40Transfer<EchoResp>(_qspi, EchoMsg(str));
//        Assert(!strcmp((char*)status.payload, str));
//    }
//    
//    // Disable SD clock
//    {
//        _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
//    }
//    
//    // Enable SD slow clock
//    {
//        _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Slow, SDClkSlowDelay));
//    }
//    
//    // ====================
//    // CMD0 | GO_IDLE_STATE
//    //   State: X -> Idle
//    //   Go to idle state
//    // ====================
//    {
//        _sdSendCmd(0, 0, SDRespTypes::None);
//        // There's no response to CMD0
//    }
//    
//    // ====================
//    // CMD8 | SEND_IF_COND
//    //   State: Idle -> Idle
//    //   Send interface condition
//    // ====================
//    {
//        auto status = _sdSendCmd(8, 0x000001AA);
//        Assert(!status.sdRespCRCErr());
//        Assert(status.sdRespGetBits(15,8) == 0xAA); // Verify the response pattern is what we sent
//    }
//    
//    // ====================
//    // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
//    //   State: Idle -> Ready
//    //   Initialize
//    // ====================
//    bool switchTo1V8 = false;
//    for (;;) {
//        // CMD55
//        {
//            auto status = _sdSendCmd(55, 0);
//            Assert(!status.sdRespCRCErr());
//        }
//        
//        // CMD41
//        {
//            auto status = _sdSendCmd(41, 0x51008000);
//            // Don't check CRC with .sdRespCRCOK() (the CRC response to ACMD41 is all 1's)
//            Assert(status.sdRespGetBits(45,40) == 0x3F); // Command should be 6'b111111
//            Assert(status.sdRespGetBits(7,1) == 0x7F); // CRC should be 7'b1111111
//            // Check if card is ready. If it's not, retry ACMD41.
//            if (!status.sdRespGetBit(39)) continue;
//            // Check if we can switch to 1.8V
//            // If not, we'll assume we're already in 1.8V mode
//            switchTo1V8 = status.sdRespGetBit(32);
//            break;
//        }
//    }
//    
//    if (switchTo1V8) {
//        // ====================
//        // CMD11 | VOLTAGE_SWITCH
//        //   State: Ready -> Ready
//        //   Switch to 1.8V signaling voltage
//        // ====================
//        {
//            auto status = _sdSendCmd(11, 0);
//            Assert(!status.sdRespCRCErr());
//        }
//        
//        // Disable SD clock for 5ms (SD clock source = none)
//        {
//            _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
//            HAL_Delay(5);
//        }
//        
//        // Re-enable the SD clock
//        {
//            _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Slow, SDClkSlowDelay));
//        }
//        
//        // Wait for SD card to indicate that it's ready (DAT0=1)
//        {
//            for (;;) {
//                auto status = _sdGetStatus();
//                if (status.sdDat0Idle()) break;
//                // Busy
//            }
//            // Ready
//        }
//    }
//    
//    
//    
//    
//    // ====================
//    // CMD2 | ALL_SEND_CID
//    //   State: Ready -> Identification
//    //   Get card identification number (CID)
//    // ====================
//    {
//        // The response to CMD2 is 136 bits, instead of the usual 48 bits
//        _sdSendCmd(2, 0, SDRespTypes::Len136);
//        // Don't check the CRC because the R2 CRC isn't calculated in the typical manner,
//        // so it'll be flagged as incorrect.
//    }
//    
//    // ====================
//    // CMD3 | SEND_RELATIVE_ADDR
//    //   State: Identification -> Standby
//    //   Publish a new relative address (RCA)
//    // ====================
//    uint16_t rca = 0;
//    {
//        auto status = _sdSendCmd(3, 0);
//        Assert(!status.sdRespCRCErr());
//        // Get the card's RCA from the response
//        rca = status.sdRespGetBits(39,24);
//    }
//    
//    // ====================
//    // CMD7 | SELECT_CARD/DESELECT_CARD
//    //   State: Standby -> Transfer
//    //   Select card
//    // ====================
//    {
//        auto status = _sdSendCmd(7, ((uint32_t)rca)<<16);
//        Assert(!status.sdRespCRCErr());
//    }
//    
//    // ====================
//    // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
//    //   State: Transfer -> Transfer
//    //   Set bus width to 4 bits
//    // ====================
//    {
//        // CMD55
//        {
//            auto status = _sdSendCmd(55, ((uint32_t)rca)<<16);
//            Assert(!status.sdRespCRCErr());
//        }
//        
//        // CMD6
//        {
//            auto status = _sdSendCmd(6, 0x00000002);
//            Assert(!status.sdRespCRCErr());
//        }
//    }
//    
//    // ====================
//    // CMD6 | SWITCH_FUNC
//    //   State: Transfer -> Data
//    //   Switch to SDR104
//    // ====================
//    {
//        // Mode = 1 (switch function)  = 0x80
//        // Group 6 (Reserved)          = 0xF (no change)
//        // Group 5 (Reserved)          = 0xF (no change)
//        // Group 4 (Current Limit)     = 0xF (no change)
//        // Group 3 (Driver Strength)   = 0xF (no change; 0x0=TypeB[1x], 0x1=TypeA[1.5x], 0x2=TypeC[.75x], 0x3=TypeD[.5x])
//        // Group 2 (Command System)    = 0xF (no change)
//        // Group 1 (Access Mode)       = 0x3 (SDR104)
//        auto status = _sdSendCmd(6, 0x80FFFFF3, SDRespTypes::Len48, SDDatInTypes::Len512);
//        Assert(!status.sdRespCRCErr());
//        Assert(!status.sdDatInCRCErr());
//        // Verify that the access mode was successfully changed
//        // TODO: properly handle this failing, see CMD6 docs
//        Assert(status.sdDatInCMD6AccessMode() == 0x03);
//    }
//    
//    // Disable SD clock
//    {
//        _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
//    }
//    
//    // Switch to the fast delay
//    {
//        _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkFastDelay));
//    }
//    
//    // Enable SD fast clock
//    {
//        _ice40Transfer(_qspi, SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Fast, SDClkFastDelay));
//    }
//    
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
//                auto status = _sdSendCmd(55, ((uint32_t)rca)<<16);
//                Assert(!status.sdRespCRCErr());
//            }
//            
//            // CMD23
//            {
//                auto status = _sdSendCmd(23, 0x00000001);
//                Assert(!status.sdRespCRCErr());
//            }
//        }
//        
//        // ====================
//        // CMD25 | WRITE_MULTIPLE_BLOCK
//        //   State: Transfer -> Receive Data
//        //   Write blocks of data
//        // ====================
//        {
//            auto status = _sdSendCmd(25, 0);
//            Assert(!status.sdRespCRCErr());
//        }
//        
//        // Clock out data on DAT lines
//        {
//            _ice40Transfer(_qspi, PixReadoutMsg(0));
//        }
//        
//        // Wait until we're done clocking out data on DAT lines
//        {
//            // Waiting for writing to finish
//            for (;;) {
//                auto status = _sdGetStatus();
//                if (status.sdDatOutDone()) {
//                    if (status.sdDatOutCRCErr()) {
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
//            Assert(!status.sdRespCRCErr());
//            
//            // Wait for SD card to indicate that it's ready (DAT0=1)
//            for (;;) {
//                if (status.sdDat0Idle()) break;
//                status = _sdGetStatus();
//            }
//        }
//        
//        _led0.write(on);
//        on = !on;
//    }
//    
//    for (;;);
//}




ICE40::PixI2CStatusResp System::_pixI2CStatus() {
    return _ice40Transfer<PixI2CStatusResp>(_qspi, PixI2CStatusMsg());
}

void System::_pixI2CRead(uint16_t addr) {
    _ice40Transfer(_qspi, PixI2CTransactionMsg(false, 2, addr, 0));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) HAL_Delay(1);
        auto status = _pixI2CStatus();
        _pixStatus.i2cErr = status.err();
        if (_pixStatus.i2cErr) return;
        if (status.done()) {
            _pixStatus.i2cReadVal = status.readData();
            return;
        }
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void System::_pixI2CWrite(uint16_t addr, uint16_t val) {
    _ice40Transfer(_qspi, PixI2CTransactionMsg(true, 2, addr, val));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) HAL_Delay(1);
        auto status = _pixI2CStatus();
        _pixStatus.i2cErr = status.err();
        if (_pixStatus.i2cErr) return;
        if (status.done()) return;
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

ICE40::PixCaptureStatusResp System::_pixCaptureStatus() {
    return _ice40Transfer<PixCaptureStatusResp>(_qspi, PixCaptureStatusMsg());
}



//// Test image capture
//void System::_handleEvent() {
//    // Confirm that we can communicate with the ICE40
//    {
//        char str[] = "halla";
//        auto status = _ice40Transfer<EchoResp>(_qspi, EchoMsg(str));
//        Assert(!strcmp((char*)status.payload, str));
//    }
//    
//    // Assert/deassert pix reset
//    {
//        _ice40Transfer(_qspi, PixResetMsg(false));
//        HAL_Delay(1);
//        _ice40Transfer(_qspi, PixResetMsg(true));
//        // Wait 150k EXTCLK (24MHz) periods
//        // (150e3*(1/24e6)) == 6.25ms
//        HAL_Delay(7);
//    }
//    
//    // Sanity-check pix comms by reading a known register
//    {
//        const uint16_t chipVersion = _pixI2CRead(0x3000);
//        // TODO: we probably don't want to check the version number in production, in case the version number changes?
//        // also the 0x3000 isn't read-only, so in theory it could change
//        Assert(chipVersion == 0x2604);
//    }
//    
//    // Configure internal register initialization
//    {
//        _pixI2CWrite(0x3052, 0xA114);
//    }
//    
//    // Start internal register initialization
//    {
//        _pixI2CWrite(0x304A, 0x0070);
//    }
//    
//    // Wait 150k EXTCLK (24MHz) periods
//    // (150e3*(1/24e6)) == 6.25ms
//    {
//        HAL_Delay(7);
//    }
//    
//    // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
//    // (Default value of 0x301A is 0x0058)
//    {
//        _pixI2CWrite(0x301A, 0x10D8);
//    }
//    
//    // Set pre_pll_clk_div
//    {
////        _pixI2CWrite(0x302E, 0x0002);  // /2 -> CLK_OP=98 MHz
////        _pixI2CWrite(0x302E, 0x0004);  // /4 -> CLK_OP=49 MHz (Default)
////        _pixI2CWrite(0x302E, 0x003F);  // /63
//    }
//    
//    // Set pll_multiplier
//    {
////        _pixI2CWrite(0x3030, 0x0062);  // *98 (Default)
////        _pixI2CWrite(0x3030, 0x0031);  // *49
//    }
//    
//    // Set vt_pix_clk_div
//    {
////        _pixI2CWrite(0x302A, 0x0006);  // /6 (Default)
////        _pixI2CWrite(0x302A, 0x001F);  // /31
//    }
//    
//    // Set op_pix_clk_div
//    {
////        _pixI2CWrite(0x3036, 0x000A);
//    }
//    
//    // Set output slew rate
//    {
////        _pixI2CWrite(0x306E, 0x0010);  // Slow
////        _pixI2CWrite(0x306E, 0x9010);  // Medium (default)
//        _pixI2CWrite(0x306E, 0xFC10);  // Fast
//    }
//    
//    // Set data_pedestal
//    {
////        _pixI2CWrite(0x301E, 0x00A8);  // Default
////        _pixI2CWrite(0x301E, 0x0000);
//    }
//    
//    // Set test data colors
//    {
////        // Set test_data_red
////        _pixI2CWrite(0x3072, 0x0B2A);  // AAA
////        _pixI2CWrite(0x3072, 0x0FFF);  // FFF
////
////        // Set test_data_greenr
////        _pixI2CWrite(0x3074, 0x0C3B);  // BBB
////        _pixI2CWrite(0x3074, 0x0FFF);  // FFF
////
////        // Set test_data_blue
////        _pixI2CWrite(0x3076, 0x0D4C);  // CCC
////        _pixI2CWrite(0x3076, 0x0FFF);  // FFF
////
////        // Set test_data_greenb
////        _pixI2CWrite(0x3078, 0x0C3B);  // BBB
////        _pixI2CWrite(0x3078, 0x0FFF);  // FFF
//    }
//    
//    // Set test_pattern_mode
//    {
//        // 0: Normal operation (generate output data from pixel array)
//        // 1: Solid color test pattern.
//        // 2: Full color bar test pattern
//        // 3: Fade-to-gray color bar test pattern
//        // 256: Walking 1s test pattern (12 bit)
////        _pixI2CWrite(0x3070, 0x0000);  // Normal operation
////        _pixI2CWrite(0x3070, 0x0001);  // Solid color
////        _pixI2CWrite(0x3070, 0x0002);  // Color bars
////        _pixI2CWrite(0x3070, 0x0003);  // Fade-to-gray
////        _pixI2CWrite(0x3070, 0x0100);  // Walking 1s
//    }
//    
//    // Set serial_format
//    // *** This register write is necessary for parallel mode.
//    // *** The datasheet doesn't mention this. :(
//    // *** Discovered looking at Linux kernel source.
//    {
//        _pixI2CWrite(0x31AE, 0x0301);
//    }
//    
//    // Set data_format_bits
//    // Datasheet:
//    //   "The serial format should be configured using R0x31AC.
//    //   This register should be programmed to 0x0C0C when
//    //   using the parallel interface."
//    {
//        _pixI2CWrite(0x31AC, 0x0C0C);
//    }
//    
//    // Set row_speed
//    {
////        _pixI2CWrite(0x3028, 0x0000);  // 0 cycle delay
////        _pixI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
//    }
//
//    // Set the x-start address
//    {
////        _pixI2CWrite(0x3004, 0x0006);  // Default
////        _pixI2CWrite(0x3004, 0x0010);
//    }
//
//    // Set the x-end address
//    {
////        _pixI2CWrite(0x3008, 0x0905);  // Default
////        _pixI2CWrite(0x3008, 0x01B1);
//    }
//
//    // Set the y-start address
//    {
////        _pixI2CWrite(0x3002, 0x007C);  // Default
////        _pixI2CWrite(0x3002, 0x007C);
//    }
//
//    // Set the y-end address
//    {
////        _pixI2CWrite(0x3006, 0x058b);  // Default
////        _pixI2CWrite(0x3006, 0x016B);
//    }
//    
//    // Implement "Recommended Default Register Changes and Sequencer"
//    {
//        _pixI2CWrite(0x3ED2, 0x0146);
//        _pixI2CWrite(0x3EDA, 0x88BC);
//        _pixI2CWrite(0x3EDC, 0xAA63);
//        _pixI2CWrite(0x305E, 0x00A0);
//    }
//    
//    // Disable embedded_data (first 2 rows of statistic info)
//    // See AR0134_RR_D.pdf for info on statistics format
//    {
////        _pixI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
//        _pixI2CWrite(0x3064, 0x1802);  // Stats disabled
//    }
//    
//    // Start streaming
//    // (Previous value of 0x301A is 0x10D8, as set above)
//    {
//        _pixI2CWrite(0x301A, 0x10DC);
//    }
//    
//    // Capture a frame
//    for (bool ledOn=true;; ledOn=!ledOn) {
//        _led0.write(ledOn);
//        _ice40Transfer(_qspi, PixCaptureMsg(0));
//        for (int i=0; i<10; i++) {
//            auto status = _pixGetStatus();
//            Assert(!status.capturePixelDropped());
//            if (status.captureDone()) break;
//            Assert(i < 10);
//        }
//        HAL_Delay(33);
//    }
//    
//    for (;;);
//}

void System::_reset(bool usbResetFinish) {
    // Disable interrupts so that resetting is atomic
    IRQState irq;
    irq.disable();
        // Complete USB reset, if the source of the reset was _usb.resetChannel
        if (usbResetFinish) _usb.resetFinish();
        
        // Reset our state
        _qspi.reset();
        _pixStatus.state = PixState::Idle;
        _pixBufs.reset();
        
        // Prepare to receive commands
        _usb.cmdRecv();
    irq.restore();
    
    // Confirm that we can communicate with the ICE40.
    // Interrupts need to be enabled for this, since _ice40Transfer()
    // waits for a response on qspi.eventChannel.
    char str[] = "halla";
    auto status = _ice40Transfer<EchoResp>(_qspi, EchoMsg(str));
    Assert(!strcmp((char*)status.payload, str));
}

void System::_handleEvent() {
    // Wait for an event to occur on one of our channels
    ChannelSelect::Start();
    if (auto x = _usb.eventChannel.readSelect()) {
        _handleUSBEvent(*x);
    
    } else if (auto x = _usb.resetChannel.readSelect()) {
        _reset(true);
    
    } else if (auto x = _usb.cmdChannel.readSelect()) {
        _handleCmd(*x);
    
    } else if (auto x = _qspi.eventChannel.readSelect()) {
        _handleQSPIEvent(*x);
    
    } else if (auto x = _usb.pixChannel.readSelect()) {
        _handlePixUSBEvent(*x);
    
    } else {
        // No events, go to sleep
        ChannelSelect::Wait();
    }
}

void System::_handleUSBEvent(const USB::Event& ev) {
    using Type = USB::Event::Type;
    switch (ev.type) {
    case Type::StateChanged: {
        // Handle USB connection
        if (_usb.state() == USB::State::Connected) {
            _reset(false);
        }
        break;
    }
    
    default: {
        // Invalid event type
        abort();
    }}
}

void System::_handleCmd(const USB::Cmd& ev) {
    Cmd cmd;
    Assert(ev.len == sizeof(cmd)); // TODO: handle errors
    memcpy(&cmd, ev.data, ev.len);
    
    switch (cmd.op) {
    // PixGetStatus
    case Cmd::Op::PixGetStatus: {
        _usb.cmdSend(&_pixStatus, sizeof(_pixStatus));
        break;
    }
    
    // PixReset
    case Cmd::Op::PixReset: {
        _pixReset();
        break;
    }
    
    // PixI2CTransaction
    case Cmd::Op::PixI2CTransaction: {
        auto& arg = cmd.arg.pixI2CTransaction;
        if (arg.write)  _pixI2CWrite(arg.addr, arg.val);
        else            _pixI2CRead(arg.addr);
        break;
    }
    
    // PixCapture
    case Cmd::Op::PixCapture: {
        if (_pixStatus.state == PixState::Idle) {
            _pixCapture();
        }
        break;
    }
    
    // LEDSet
    case Cmd::Op::LEDSet: {
        switch (cmd.arg.ledSet.idx) {
//        case 0: _led0.write(cmd.arg.ledSet.on); break;
//        case 1: _led1.write(cmd.arg.ledSet.on); break;
        case 2: _led2.write(cmd.arg.ledSet.on); break;
        case 3: _led3.write(cmd.arg.ledSet.on); break;
        }
        
        break;
    }
    
    // Bad command
    default: {
        break;
    }}
    
    // Prepare to receive another command
    _usb.cmdRecv(); // TODO: handle errors
}

void System::_handleQSPIEvent(const QSPI::Signal& ev) {
    Assert(_pixStatus.state == PixState::Capturing); // We should only be called while capturing
    Assert(_pixBufs.writable());
    
    const bool wasReadable = _pixBufs.readable();
    
    // Enqueue the buffer
    {
        // Update the number of remaining bytes to receive from the image sensor
        _pixRemLen -= _pixBufs.writeBuf().len;
        _pixBufs.writeEnqueue();
    }
    
    // Start a USB transaction when we go from 0->1 buffers
    if (!wasReadable) {
        _sendPixDataOverUSB();
    }
    
    // Prepare to receive more data if we're expecting more,
    // and we have a buffer to store the data in
    if (_pixRemLen && _pixBufs.writable()) {
        _recvPixDataFromICE40();
    }
}

void System::_handlePixUSBEvent(const USB::Signal& ev) {
    Assert(_pixStatus.state == PixState::Capturing); // We should only be called while capturing
    Assert(_pixBufs.readable());
    const bool wasWritable = _pixBufs.writable();
    
    // Dequeue the buffer
    _pixBufs.readDequeue();
    
    // Start another USB transaction if there's more data to write
    if (_pixBufs.readable()) {
        _sendPixDataOverUSB();
    }
    
    if (_pixRemLen) {
        // Prepare to receive more data if we're expecting more,
        // and we were previously un-writable
        if (!wasWritable) {
            _recvPixDataFromICE40();
        }
    } else if (!_pixBufs.readable()) {
        _pixStatus.state = PixState::Idle;
        
        // We're done sending this image, start the next one
//        _pixCapture();
    }
}

// Arrange for pix data to be received from ICE40
void System::_recvPixDataFromICE40() {
    Assert(_pixBufs.writable());
    
    // TODO: ensure that the byte length is aligned to a u32 boundary, since QSPI requires that!
    const size_t len = std::min(_pixRemLen, _pixBufs.writeBuf().cap);
    // Determine whether this is the last readout, and therefore the ice40 should automatically
    // capture the next image when readout is done.
//    const bool captureNext = (len == _pixRemLen);
    const bool captureNext = false;
    _pixBufs.writeBuf().len = len;
    
    _ice40TransferAsync(_qspi, PixReadoutMsg(0, captureNext, len/sizeof(Pixel)),
        _pixBufs.writeBuf().data,
        _pixBufs.writeBuf().len);
}

// Arrange for pix data to be sent over USB
void System::_sendPixDataOverUSB() {
    Assert(_pixBufs.readable());
    const auto& buf = _pixBufs.readBuf();
    _usb.pixSend(buf.data, buf.len);
}

void System::_pixReset() {
    _ice40Transfer(_qspi, PixResetMsg(false));
    HAL_Delay(1);
    _ice40Transfer(_qspi, PixResetMsg(true));
    // Wait 150k EXTCLK (24MHz) periods
    // (150e3*(1/24e6)) == 6.25ms
    HAL_Delay(7);
}

//void System::_pixConfig() {
//    // Confirm that we can communicate with the ICE40
//    {
//        char str[] = "halla";
//        auto status = _ice40Transfer<EchoResp>(_qspi, EchoMsg(str));
//        Assert(!strcmp((char*)status.payload, str));
//    }
//    
//    // Assert/deassert pix reset
//    {
//        _ice40Transfer(_qspi, PixResetMsg(false));
//        HAL_Delay(1);
//        _ice40Transfer(_qspi, PixResetMsg(true));
//        // Wait 150k EXTCLK (24MHz) periods
//        // (150e3*(1/24e6)) == 6.25ms
//        HAL_Delay(7);
//    }
//    
//    // Sanity-check pix comms by reading a known register
//    {
//        const uint16_t chipVersion = _pixI2CRead(0x3000);
//        // TODO: we probably don't want to check the version number in production, in case the version number changes?
//        // also the 0x3000 isn't read-only, so in theory it could change
//        Assert(chipVersion == 0x2604);
//    }
//    
//    // Configure internal register initialization
//    {
//        _pixI2CWrite(0x3052, 0xA114);
//    }
//    
//    // Start internal register initialization
//    {
//        _pixI2CWrite(0x304A, 0x0070);
//    }
//    
//    // Wait 150k EXTCLK (24MHz) periods
//    // (150e3*(1/24e6)) == 6.25ms
//    {
//        HAL_Delay(7);
//    }
//    
//    // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
//    // (Default value of 0x301A is 0x0058)
//    {
//        _pixI2CWrite(0x301A, 0x10D8);
//    }
//    
//    // Set pre_pll_clk_div
//    {
////        _pixI2CWrite(0x302E, 0x0002);  // /2 -> CLK_OP=98 MHz
////        _pixI2CWrite(0x302E, 0x0004);  // /4 -> CLK_OP=49 MHz (Default)
////        _pixI2CWrite(0x302E, 0x003F);  // /63
//    }
//    
//    // Set pll_multiplier
//    {
////        _pixI2CWrite(0x3030, 0x0062);  // *98 (Default)
////        _pixI2CWrite(0x3030, 0x0031);  // *49
//    }
//    
//    // Set vt_pix_clk_div
//    {
////        _pixI2CWrite(0x302A, 0x0006);  // /6 (Default)
////        _pixI2CWrite(0x302A, 0x001F);  // /31
//    }
//    
//    // Set op_pix_clk_div
//    {
////        _pixI2CWrite(0x3036, 0x000A);
//    }
//    
//    // Set output slew rate
//    {
////        _pixI2CWrite(0x306E, 0x0010);  // Slow
////        _pixI2CWrite(0x306E, 0x9010);  // Medium (default)
//        _pixI2CWrite(0x306E, 0xFC10);  // Fast
//    }
//    
//    // Set data_pedestal
//    {
////        _pixI2CWrite(0x301E, 0x00A8);  // Default
////        _pixI2CWrite(0x301E, 0x0000);
//    }
//    
//    // Set test data colors
//    {
////        // Set test_data_red
////        _pixI2CWrite(0x3072, 0x0B2A);  // AAA
////        _pixI2CWrite(0x3072, 0x0FFF);  // FFF
////
////        // Set test_data_greenr
////        _pixI2CWrite(0x3074, 0x0C3B);  // BBB
////        _pixI2CWrite(0x3074, 0x0FFF);  // FFF
////
////        // Set test_data_blue
////        _pixI2CWrite(0x3076, 0x0D4C);  // CCC
////        _pixI2CWrite(0x3076, 0x0FFF);  // FFF
////
////        // Set test_data_greenb
////        _pixI2CWrite(0x3078, 0x0C3B);  // BBB
////        _pixI2CWrite(0x3078, 0x0FFF);  // FFF
//    }
//    
//    // Set test_pattern_mode
//    {
//        // 0: Normal operation (generate output data from pixel array)
//        // 1: Solid color test pattern.
//        // 2: Full color bar test pattern
//        // 3: Fade-to-gray color bar test pattern
//        // 256: Walking 1s test pattern (12 bit)
////        _pixI2CWrite(0x3070, 0x0000);  // Normal operation
////        _pixI2CWrite(0x3070, 0x0001);  // Solid color
////        _pixI2CWrite(0x3070, 0x0002);  // Color bars
////        _pixI2CWrite(0x3070, 0x0003);  // Fade-to-gray
////        _pixI2CWrite(0x3070, 0x0100);  // Walking 1s
//    }
//    
//    // Set serial_format
//    // *** This register write is necessary for parallel mode.
//    // *** The datasheet doesn't mention this. :(
//    // *** Discovered looking at Linux kernel source.
//    {
//        _pixI2CWrite(0x31AE, 0x0301);
//    }
//    
//    // Set data_format_bits
//    // Datasheet:
//    //   "The serial format should be configured using R0x31AC.
//    //   This register should be programmed to 0x0C0C when
//    //   using the parallel interface."
//    {
//        _pixI2CWrite(0x31AC, 0x0C0C);
//    }
//    
//    // Set row_speed
//    {
////        _pixI2CWrite(0x3028, 0x0000);  // 0 cycle delay
////        _pixI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
//    }
//
//    // Set the x-start address
//    {
////        _pixI2CWrite(0x3004, 0x0006);  // Default
////        _pixI2CWrite(0x3004, 0x0010);
//    }
//
//    // Set the x-end address
//    {
////        _pixI2CWrite(0x3008, 0x0905);  // Default
////        _pixI2CWrite(0x3008, 0x01B1);
//    }
//
//    // Set the y-start address
//    {
////        _pixI2CWrite(0x3002, 0x007C);  // Default
////        _pixI2CWrite(0x3002, 0x007C);
//    }
//
//    // Set the y-end address
//    {
////        _pixI2CWrite(0x3006, 0x058b);  // Default
////        _pixI2CWrite(0x3006, 0x016B);
//    }
//    
//    // Implement "Recommended Default Register Changes and Sequencer"
//    {
//        _pixI2CWrite(0x3ED2, 0x0146);
//        _pixI2CWrite(0x3EDA, 0x88BC);
//        _pixI2CWrite(0x3EDC, 0xAA63);
//        _pixI2CWrite(0x305E, 0x00A0);
//    }
//    
//    // Disable embedded_data (first 2 rows of statistic info)
//    // See AR0134_RR_D.pdf for info on statistics format
//    {
////        _pixI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
//        _pixI2CWrite(0x3064, 0x1802);  // Stats disabled
//    }
//    
//    // Start streaming
//    // (Previous value of 0x301A is 0x10D8, as set above)
//    {
//        _pixI2CWrite(0x301A, 0x10DC);
//    }
//    
//    // Tell ICE40 to do a capture
//    {
//        _ice40Transfer(_qspi, PixCaptureMsg(0));
//    }
//}

void System::_pixCapture() {
    Assert(_pixStatus.state == PixState::Idle); // We should only be called while idle
    
    _pixStatus.state = PixState::Capturing;
    
    // Tell ice40 to perform a capture
    _ice40Transfer(_qspi, PixCaptureMsg(0));
    
    // Wait a max of `MaxDelayMs` for the the capture to be ready for readout
    const uint32_t MaxDelayMs = 1000;
    const uint32_t startTime = HAL_GetTick();
    ICE40::PixCaptureStatusResp status;
    for (;;) {
        status = _pixCaptureStatus();
        if (status.done() || (HAL_GetTick()-startTime)>=MaxDelayMs) break;
    }
    
    // If readout isn't ready after our timeout, set our error state for the host to observe
    if (!status.done()) {
        _pixStatus.state = PixState::Error;
        return;
    }
    
    const uint16_t imageWidth = status.imageWidth();
    const uint16_t imageHeight = status.imageHeight();
    
    // Enqueue the PixHeader to be sent over USB
    auto& buf = _pixBufs.writeBuf();
    PixHeader& hdr = *((PixHeader*)buf.data);
    hdr = PixHeader{
        .width = imageWidth,
        .height = imageHeight,
        .highlightCount = status.highlightCount(),
        .shadowCount = status.shadowCount(),
    };
    buf.len = sizeof(PixHeader);
    _pixBufs.writeEnqueue();
    _sendPixDataOverUSB();
    
    // Start readout from ice40
    _pixRemLen = imageWidth*imageHeight*sizeof(Pixel);
    _recvPixDataFromICE40();
}

[[noreturn]] void System::_abort() {
    for (bool x=true;; x=!x) {
//        _led0.write(x);
//        _led1.write(x);
        _led2.write(x);
        _led3.write(x);
        HAL_Delay(500);
    }
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
    Sys._abort();
}

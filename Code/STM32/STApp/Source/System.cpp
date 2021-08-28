#include "System.h"
#include "Assert.h"
#include "SystemClock.h"
#include "Startup.h"
#include "MSP430.h"

// We're using 63K buffers instead of 64K, because the
// max DMA transfer is 65535 bytes, not 65536.
static uint8_t _buf0[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));
static uint8_t _buf1[63*1024] __attribute__((aligned(4))) __attribute__((section(".sram1")));

using namespace STApp;

System::System() :
// QSPI clock divider=1 => run QSPI clock at 64 MHz
// QSPI alignment=word for high performance transfers
_qspi(QSPI::Mode::Dual, 1, QSPI::Align::Word, QSPI::ChipSelect::Uncontrolled),
_bufs(_buf0, _buf1) {
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

//static void _ice40Transfer(QSPI& qspi, const ICE40::Msg& msg, void* resp, size_t respLen) {
//    qspi.read(_ice40QSPICmd(msg, respLen), resp, respLen);
//    qspi.eventChannel.read(); // Wait for the transfer to complete
//}
//
//static void _ice40TransferAsync(QSPI& qspi, const ICE40::Msg& msg, void* resp, size_t respLen) {
//    qspi.read(_ice40QSPICmd(msg, respLen), resp, respLen);
//}

void System::init() {
    _super::init();
    _usb.init();
    _qspi.init();
    
    _ICE_ST_SPI_CS_::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, 0);
    _ICE_ST_SPI_CS_::Write(1);
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
    Assert(!_bufs.full());
    Assert(!_usbDataBusy);
    
    // Update our state
    _op = Op::None;
    
    // Send our response
    auto& buf = _bufs.back();
    memcpy(buf.data, &status, sizeof(status));
    buf.len = sizeof(status);
    _bufs.push();
    _usb_sendFromBuf();
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

#pragma mark - USB

void System::_usb_reset(bool usbResetFinish) {
    // Disable interrupts so that resetting is atomic
    IRQState irq;
    irq.disable();
        // Complete USB reset, if the source of the reset was _usb.resetChannel
        if (usbResetFinish) _usb.resetFinish();
        
        // Reset our state
        _qspi.reset();
        _bufs.reset();
        
        // Prepare to receive commands
        _usb.cmdRecv();
    irq.restore();
    
    // Confirm that we can communicate with the ICE40.
    // Interrupts need to be enabled for this, since _ice40Transfer()
    // waits for a response on qspi.eventChannel.
    ICE40::EchoResp resp;
    const char str[] = "halla";
    _ice40Transfer(ICE40::EchoMsg(str), resp);
    Assert(!strcmp((char*)resp.payload, str));
    
    
    // Update state
    _op = Op::SDRead;
    _opDataRem = 0xFFFFFE00; // divisible by 512
    
    // Send the SDReadout message, which causes us to enter the SD-readout mode until
    // we release the chip select
    _ICE_ST_SPI_CS_::Write(0);
    _ice40TransferNoCS(ICE40::SDReadoutMsg());
    
    // Advance state machine
    _sdRead_updateState();
    
    
    
//    uint8_t i = 0;
//    for (uint8_t& x : _buf0) {
//        x = i;
//        i++;
//    }
//    
//    _usb.dataSend(_buf0, sizeof(_buf0));
    
    
//    USB_OTG_GlobalTypeDef* USBx = USB_OTG_HS;
//    uint32_t USBx_BASE = (uint32_t)USBx;
//    volatile uint16_t freeSpace1 = 4*(USBx_INEP(1)->DTXFSTS & USB_OTG_DTXFSTS_INEPTFSAV);
//    volatile auto& USBDEV = *((USB_OTG_DeviceTypeDef*)(USBx_BASE + USB_OTG_DEVICE_BASE));
//    uint8_t* FIFODATA = (uint8_t*)(USBx_BASE+0x20000);
//    
//    constexpr uint32_t Len = 6*512;
//    uint32_t* buf32 = (uint32_t*)_buf0;
//    uint32_t off = 0;
//    for (uint32_t i=0; i<(512/sizeof(uint32_t)); off++, i++) buf32[off] = 0xAAAAAAAA;
//    for (uint32_t i=0; i<(512/sizeof(uint32_t)); off++, i++) buf32[off] = 0xBBBBBBBB;
//    for (uint32_t i=0; i<(512/sizeof(uint32_t)); off++, i++) buf32[off] = 0xCCCCCCCC;
//    for (uint32_t i=0; i<(512/sizeof(uint32_t)); off++, i++) buf32[off] = 0xDDDDDDDD;
//    for (uint32_t i=0; i<(512/sizeof(uint32_t)); off++, i++) buf32[off] = 0xEEEEEEEE;
//    for (uint32_t i=0; i<(512/sizeof(uint32_t)); off++, i++) buf32[off] = 0xFFFFFFFF;
//    _usb.dataSend(_buf0, Len);
//    
//    for (;;) {
//        constexpr uint8_t EP1 = 1;
//        volatile auto& INEP1 = *USBx_INEP(EP1);
//        volatile auto& DIEPTXF = USBx->DIEPTXF[EP1-1];
//        const uint16_t INEPTXSA = (DIEPTXF & USB_OTG_DIEPTXF_INEPTXSA_Msk) >> USB_OTG_DIEPTXF_INEPTXSA_Pos;
//        const uint16_t INEPTXFD = (DIEPTXF & USB_OTG_DIEPTXF_INEPTXFD_Msk) >> USB_OTG_DIEPTXF_INEPTXFD_Pos;
//        volatile uint32_t XFRSIZ = (USBx_INEP(EP1)->DIEPTSIZ & USB_OTG_DIEPTSIZ_XFRSIZ) >> 0;
//        volatile uint32_t PKTCNT = (USBx_INEP(EP1)->DIEPTSIZ & USB_OTG_DIEPTSIZ_PKTCNT) >> 19;
//        volatile uint32_t DIEPINT = USBx_INEP(EP1)->DIEPINT;
//        volatile uint16_t freeSpace2 = 4*(USBx_INEP(EP1)->DTXFSTS & USB_OTG_DTXFSTS_INEPTFSAV);
//        
////        #define USBx_DEVICE     ((USB_OTG_DeviceTypeDef *)(USBx_BASE + USB_OTG_DEVICE_BASE))
////        USB_OTG_GLOBAL_BASE
//        
//        for (volatile int i=0; i<1; i++);
//    }
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
    Assert(!_bufs.empty());
    Assert(!_usbDataBusy);
    
    const auto& buf = _bufs.front();
    _usb.dataSend(buf.data, buf.len);
    _usbDataBusy = true;
}

void System::_usb_dataSendHandle(const USB::DataSend& ev) {
//    _usb.dataSend(_buf0, sizeof(_buf0));
    
    Assert(_usbDataBusy);
    Assert(!_bufs.empty());
    
    // Reset the buffer length so it's back in its default state
    _bufs.front().len = 0;
    // Pop the buffer, which we just finished sending over USB
    _bufs.pop();
    _usbDataBusy = false;
    
    switch (_op) {
    case Op::SDRead:    _sdRead_usbDataSendHandle(ev);  break;
    // The host received the status response;
    // arrange to receive another command
    case Op::None:      _usb_cmdRecv();                 break;
    default:            abort();                        break;
    }
}










#pragma mark - SD Reading

void System::_sdRead(const Cmd& cmd) {
    // Update state
    _op = cmd.op;
    _opDataRem = 0xFFFFFE00; // divisible by 512
    
    // Send the SDReadout message, which causes us to enter the SD-readout mode until
    // we release the chip select
    _ICE_ST_SPI_CS_::Write(0);
    _ice40TransferNoCS(ICE40::SDReadoutMsg());
    
    // Advance state machine
    _sdRead_updateState();
}

void System::_sdRead_qspiReadToBuf() {
    Assert(_op == Op::SDRead);
    Assert(!_bufs.full());
    Assert(_opDataRem);
    Assert(!_qspiBusy);
    
    auto& buf = _bufs.back();
    
    HAL_Delay(1);
    
//    // Wait for ICE40 to signal that data is ready
//    while (!_ICE_ST_SPI_D_READY::Read());
    
    // TODO: ensure that the byte length is aligned to a u32 boundary, since QSPI requires that!
    // TODO: how do we handle lengths that aren't a multiple of ReadoutLen?
    const size_t len = ICE40::SDReadoutMsg::ReadoutLen;
    QSPI_CommandTypeDef qspiCmd = {
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        .AddressMode = QSPI_ADDRESS_NONE,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
        .DummyCycles = 4,
        .NbData = (uint32_t)len,
        .DataMode = QSPI_DATA_4_LINES,
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
    _qspi.read(qspiCmd, buf.data+buf.len, len);
    buf.len += len;
    
    _qspiBusy = true;
    
//    _opDataRem -= len;
//    buf.len = len;
//    _bufs.push();
}

void System::_sdRead_qspiEventHandle(const QSPI::Signal& ev) {
    Assert(_op == Op::SDRead);
    Assert(_qspiBusy);
    
    auto& buf = _bufs.back();
    _qspiBusy = false;
    
    // If we can't read any more data into the producer buffer,
    // push it so the data will be sent over USB
    if (buf.cap-buf.len < ICE40::SDReadoutMsg::ReadoutLen) {
        _opDataRem -= buf.len;
        _bufs.push();
    }
    
    // Advance state machine
    _sdRead_updateState();
}

void System::_sdRead_usbDataSendHandle(const USB::DataSend& ev) {
    Assert(_op == Op::SDRead);
    // Advance state machine
    _sdRead_updateState();
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
    if (!_bufs.empty() && !_usbDataBusy) {
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

#include <stdint.h>
#include <assert.h>
#include <libftdi1/ftdi.h>
#include <memory>
#include <string>
#include <sstream>
#include <iomanip>

// Left shift array of bytes by `n` bits
static void lshift(uint8_t* bytes, size_t len, uint8_t n) {
    assert(n <= 8);
    const uint8_t mask = ~((1<<(8-n))-1);
    uint8_t l = 0;
    for (size_t i=len; i; i--) {
        uint8_t& b = bytes[i-1];
        // Remember the high bits that we're losing by left-shifting,
        // which will become the next byte's low bits.
        const uint8_t h = b&mask;
        b <<= n;
        b |= l;
        l = h>>(8-n);
    }
}

// Returns of the index (0-7) of the most significant zero,
// or `nullopt` if there are no zeroes.
static std::optional<uint8_t> msz(uint8_t x) {
    for (uint8_t i=0; i<8; i++) {
        const uint8_t pos = 7-i;
        if (!(x & (1<<pos))) return pos;
    }
    return std::nullopt;
}

class MDCDevice {
public:
    struct Pin {
        uint8_t bit = 0;
        uint8_t dir = 0;
        uint8_t val = 0;
        
        uint8_t dirBit() const { return (dir ? bit : 0); }
        uint8_t valBit() const { return (val ? bit : 0); }
    };
    
    struct Pins {
        Pin CLK     {.bit=1<<0, .dir=1, .val=0};
        Pin DO      {.bit=1<<1, .dir=1, .val=1};
        Pin DI      {.bit=1<<2, .dir=0, .val=0};
        // Unused
        Pin CS      {.bit=1<<4, .dir=1, .val=0};
        // Unused
        Pin CDONE   {.bit=1<<6, .dir=0, .val=0};
        Pin CRST_   {.bit=1<<7, .dir=1, .val=1};
        
        uint8_t dirBits() const {
            return  CLK.dirBit()    |
                    DO.dirBit()     |
                    DI.dirBit()     |
                    CS.dirBit()     |
                    CDONE.dirBit()  |
                    CRST_.dirBit()  ;
        }
        
        uint8_t valBits() const {
            return  CLK.valBit()    |
                    DO.valBit()     |
                    DI.valBit()     |
                    CS.valBit()     |
                    CDONE.valBit()  |
                    CRST_.valBit()  ;
        }
    };
    
    using MsgType = uint8_t;
    struct Msg {
        MsgType type = 0;
        uint8_t payload[7];
    };
    
    struct Resp {
        uint8_t payload[8];
    };
    
    using MsgPtr = std::unique_ptr<Msg>;
    using RespPtr = std::unique_ptr<Resp>;
    
    MDCDevice() {
        int ir = ftdi_init(&_ftdi);
        assert(!ir);
        
        ir = ftdi_set_interface(&_ftdi, INTERFACE_A);
        assert(!ir);
        
        struct ftdi_device_list* devices = nullptr;
        int devicesCount = ftdi_usb_find_all(&_ftdi, &devices, 0x403, 0x6014);
        assert(devicesCount == 1);
        
        // Open FTDI USB device
        ir = ftdi_usb_open_dev(&_ftdi, devices[0].dev);
        assert(!ir);
        
        // Reset USB device
        ir = ftdi_usb_reset(&_ftdi);
        assert(!ir);
        
        // Set chunk sizes to 64K
        ir = ftdi_read_data_set_chunksize(&_ftdi, 65536);
        assert(!ir);
        
        ir = ftdi_write_data_set_chunksize(&_ftdi, 65536);
        assert(!ir);
        
        // Disable event/error characters
        ir = ftdi_set_event_char(&_ftdi, 0, 0);
        assert(!ir);
        
        // TODO: ftStatus |= FT_SetTimeouts(ftHandle, 0, 5000);
        
        // Set buffer interval ("The FTDI chip keeps data in the internal buffer
        // for a specific amount of time if the buffer is not full yet to decrease
        // load on the usb bus.")
        ir = ftdi_set_latency_timer(&_ftdi, 16);
        assert(!ir);
        
        // Set FTDI mode to MPSSE
        ir = ftdi_set_bitmode(&_ftdi, 0xFF, BITMODE_MPSSE);
        assert(!ir);
        
        // Disable clock divide-by-5, disable adaptive clocking, disable three-phase clocking, disable loopback
        {
            uint8_t cmd[] = {0x8A, 0x97, 0x8D, 0x85};
            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            assert(ir == sizeof(cmd));
        }
        
        // Set the minimum clock divisor for maximum clock rate (30 MHz)
        {
            uint8_t cmd[] = {0x86, 0x00, 0x00};
            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            assert(ir == sizeof(cmd));
        }
        
        // Clear our receive buffer
        // For some reason this needs to happen after our first write (via _flush),
        // otherwise we don't receive anything.
        // This is necessary in case an old process was doing IO and crashed, in which
        // case there could still be data in the buffer.
        for (;;) {
            uint8_t tmp[128];
            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
            assert(ir >= 0);
            if (!ir) break;
        }
        
        _resetPins();
        
        // Wait until MDC is ready, as indicated by it outputting all 1's
        bool ready = false;
        do {
            uint8_t buf[512];
            _mdcRead(_ftdi, buf, sizeof(buf));
            ready = true;
            for (uint8_t b : buf) {
                if (b != 0xFF) {
                    printf("MDC not ready...\n");
                    ready = false;
                    break;
                }
            }
        } while (!ready);
        
        printf("MDC ready!\n");
    }
    
    ~MDCDevice() {
        int ir = ftdi_usb_close(&_ftdi);
        assert(!ir);
        
        ftdi_deinit(&_ftdi);
    }
    
    void _resetPins() {
        // ## Reset our pins states to make CLK=0 and CS=1
        _setPins(Pins{});
    }
    
    void write(const Msg& msg) {
        // Start bit (clock out a single 0)
        {
            uint8_t b[] = {0x13, 0x00, 0x00};
            _ftdiWrite(_ftdi, b, sizeof(b));
        }
        
        // Message payload
        {
            const size_t msgLen = sizeof(msg);
            const uint8_t b[] = {0x11, (uint8_t)((msgLen-1)&0xFF), (uint8_t)(((msgLen-1)&0xFF00)>>8)};
            _ftdiWrite(_ftdi, b, sizeof(b));
            _ftdiWrite(_ftdi, (uint8_t*)&msg, msgLen);
        }
        
        // End bit (clock out a single 1)
        {
            uint8_t b[] = {0x13, 0x00, 0xFF};
            _ftdiWrite(_ftdi, b, sizeof(b));
        }
    }
    
    Resp read() {
        Resp resp;
        uint8_t respBuf[sizeof(resp)+1]; // +1 since the response can start at any bit within
                                         // a byte, so we need an extra byte to make sure we
                                         // can fit the full response.
        size_t respBufLen = 0;
        
        // Read from FTDI until we get the start bit, and fill up `respBuf`
        while (respBufLen < sizeof(respBuf)) {
            uint8_t buf[512];
            _mdcRead(_ftdi, buf, sizeof(buf));
            
            std::optional<size_t> bufOff;
            if (!respBufLen) {
                printf("Searching for response start bit...\n");
                // Response hasn't started yet
                // Find the byte in `buf` containing the start bit
                for (size_t i=0; i<sizeof(buf); i++) {
                    if (buf[i] != 0xFF) {
                        bufOff = i;
                        break;
                    }
                }
            
            } else {
                // Response already started
                // The continuation of the data is at the beginning of `buf`
                bufOff = 0;
            }
            
            // If the response started, copy new bytes into `respBuf`
            if (bufOff) {
                const size_t copyLen = std::min(sizeof(respBuf)-respBufLen, sizeof(buf)-*bufOff);
                memcpy(respBuf+respBufLen, buf+*bufOff, copyLen);
                respBufLen += copyLen;
            }
        }
        
        // Find the index of start bit in `respBuf`
        const auto mszIdx = msz(respBuf[0]);
        assert(mszIdx); // Our logic guarantees a zero
        // Calculate the number of bits we need to shift left
        const uint8_t shiftn = 8-*mszIdx;
        // Left-shift the buffer to remove the start bit
        lshift(respBuf, sizeof(respBuf), shiftn);
        // Copy the shifted bits into `resp`
        memcpy(&resp, respBuf, sizeof(resp));
        return resp;
    }
    
    void _setPins(const Pins& pins) {
        uint8_t b[] = {0x80, pins.valBits(), pins.dirBits()};
        _ftdiWrite(_ftdi, b, sizeof(b));
    }
    
    static void _mdcRead(struct ftdi_context& ftdi, uint8_t* buf, uint16_t len) {
        // Tell FTDI to clock in bytes to fill `buf`
        const uint8_t b[] = {0x20, (uint8_t)((len-1)&0xFF), (uint8_t)(((len-1)&0xFF00)>>8)};
        _ftdiWrite(ftdi, b, sizeof(b));
        
        // Get the bytes from FTDI
        _ftdiRead(ftdi, buf, len);
    }
    
    static void _ftdiRead(struct ftdi_context& ftdi, uint8_t* d, const size_t len) {
        for (size_t off=0; off<len;) {
            const size_t readLen = len-off;
            int ir = ftdi_read_data(&ftdi, d+off, (int)readLen);
            assert(ir>=0 && (size_t)ir<=readLen);
            off += ir;
        }
    }
    
    static void _ftdiWrite(struct ftdi_context& ftdi, const uint8_t* d, const size_t len) {
        int ir = ftdi_write_data(&ftdi, d, (int)len);
        assert(ir>=0 && (size_t)ir==len);
    }
    
private:
    struct ftdi_context _ftdi;
};

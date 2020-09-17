#include <stdint.h>
#include <assert.h>
#include <libftdi1/ftdi.h>
#include <memory>
#include <string>
#include <sstream>
#include <iomanip>

std::vector<uint8_t> getBits(const uint8_t* bytes, size_t len, uint64_t start, uint64_t end) {
    assert(start < len*8);
    assert(start >= end);
    
    const uint8_t rshift = end%8;
    const uint8_t rshiftMask = (1<<rshift)-1;
    const uint8_t lshift = 8-rshift;
    const size_t leftByteIdx = len-(start/8)-1;
    const uint8_t leftByteMask = (1<<((start%8)+1))-1;
    const size_t rightByteIdx = len-(end/8)-1;
    std::vector<uint8_t> r;
    // Collect the bytes
    for (size_t i=rightByteIdx;; i--) {
        r.push_back(bytes[i]);
        if (i == leftByteIdx) break;
    }
    
    // Enforce `leftByteMask`
    r.back() &= leftByteMask;
    
    // Right-shift the bits by `rshift`
    uint8_t h = 0;
    for (auto i=r.rbegin(); i!=r.rend(); i++) {
        // Remember the low bits that we're losing by right-shifting,
        // which will become the next byte's high bits
        const uint8_t l = (*i)&rshiftMask;
        *i >>= rshift;
        *i |= h;
        h = l<<lshift;
    }
    
    // Throw out extra byte if needed
    const size_t byteCount = ((start-end)/8)+1;
    if (r.size() > byteCount) r.pop_back();
    return r;
    
    
//    
//    
//    
//    
////    uint8_t b = 0;
////    for (auto i=r.rbegin(); i!=r.rend(); i++) {
////        const uint8_t highBits = b<<lshift;
////        const uint8_t lowBits = (*i)>>rshift;
////        *i = highBits|lowBits;
////        b = 
////        b<<lshift
////        *i >>= rshift;
////        b = (*i)&;
////    }
//    
////    for (size_t i=rightByteIdx;; i--) {
////        uint8_t b = bytes[i];
////        const uint8_t bnMask = (i-1==leftByteIdx ? leftByteMask : 0xFF);
////        uin8t_t bn = bytes[i-1]&bnMask;
////        b = (b>>rshift) | (bn<<lshift);
////        r.push_back(b);
////        if (i-1 == leftByteIdx) break;
////    }
//    
//    std::optional<uint8_t> pb;
//    for (size_t i=rightByteIdx;; i--) {
//        const uint8_t mask = (i==leftByteIdx ? leftByteMask : 0xFF);
//        const uint8_t b = bytes[i]&mask;
//        if (pb) r.push_back((b<<lshift)|(*pb>>rshift));
//        pb = b;
//        if (i == leftByteIdx) break;
//    }
//    
//    
//    uint8_t l = 0;
//    uint8_t r = 0;
//    for (size_t i=rightByteIdx;; i--) {
//        
//        
//        
//        
//        r >>= rshift;
//        
//        
//        const uint8_t mask = (i==leftByteIdx ? leftByteMask : 0xFF);
//        const uint8_t b = (r>>rshift) | (l<<lshift);
//        vec.push_back(b);
//        r = l;
//        l = bytes[i];
//        
//        const uint8_t mask = (i==leftByteIdx ? leftByteMask : 0xFF);
//        b >>= rshift;
//        b |= (bytes[i]&mask)<<lshift
//        
//        const uint8_t mask = (i==leftByteIdx ? leftByteMask : 0xFF);
//        b |= 
//        
//        b = (bytes[i]&mask)<<lshift;
//        
//        
//        
//        const uint8_t bnMask = (i-1==leftByteIdx ? leftByteMask : 0xFF);
//        uin8t_t bn = bytes[i-1]&bnMask;
//        b = (b>>rshift) | (bn<<lshift);
//        r.push_back(b);
//        if (i-1 == leftByteIdx) break;
//    }
//    
//    
//    return r;
//    
//    
//    
////    assert(start < len*8);
////    assert(start >= end);
////    const size_t leftByteIdx = len-(start/8)-1;
////    const uint8_t leftByteMask = (1<<((start%8)+1))-1;
////    const size_t rightByteIdx = len-(end/8)-1;
////    const uint8_t rightByteMask = ~((1<<(end%8))-1);
////    std::vector<uint8_t> r(((end-start)/8)+1);
////    uint8_t tmp = 0;
////    for (size_t i=leftByteIdx; i<=rightByteIdx; i++) {
////        uint8_t tmp = bytes[i];
////        // Mask-out bits we don't want
////        if (i == leftByteIdx)   tmp &= leftByteMask;
////        if (i == rightByteIdx)  tmp &= rightByteMask;
////        // Make space for the incoming bits
////        if (i == rightByteIdx) {
////            tmp >>= end%8; // Shift right the number of unused bits
////            r <<= 8-(end%8); // Shift left the number of used bits
////        } else {
////            r <<= 8;
////        }
////        // Or the bits into place
////        r |= tmp;
////    }
////    return r;
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
        Pin DO      {.bit=1<<1, .dir=1, .val=0};
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
        
//        // Set FTDI mode to MPSSE
//        ir = ftdi_set_bitmode(&_ftdi, 0xFF, 0);
//        assert(!ir);
        
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
    }
    
    ~MDCDevice() {
        int ir = ftdi_usb_close(&_ftdi);
        assert(!ir);
        
        ftdi_deinit(&_ftdi);
    }
    
    void _resetPins() {
        // ## Reset our pins states to make CLK=0 and CS=1
        Pins pins;
        pins.CS.val = 1;
        _setPins(pins);
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
            uint8_t b[] = {0x13, 0x00, 0x80};
            _ftdiWrite(_ftdi, b, sizeof(b));
        }
    }
    
//    RespPtr _readResp() {
//        size_t off = _inOff;
//        Resp resp;
//        if (_inLen-off < sizeof(resp)) return nullptr;
//        memcpy(&resp, _in+off, sizeof(resp));
//        off += sizeof(resp);
//        
//        if (_inLen-off < hdr.len) return nullptr;
//        
//        MsgPtr msg = _newMsg(hdr.type);
//        assert(msg);
//        
//        // Verify that the incoming message has enough data to fill the type that it claims to be
//        assert(hdr.len >= msg->hdr.len);
//        
//        // Copy the payload into the message, but only the number of bytes that we expect the message to have.
//        memcpy(((uint8_t*)msg.get())+sizeof(MsgHdr), _in+off, msg->hdr.len);
//        
//        off += hdr.len;
//        _inOff = off;
//        return msg;
//    }
    
    Resp read() {
        Resp resp;
        uint8_t respBuf[sizeof(resp)+1];
        size_t respBufLen = 0;
        
        // Read from FTDI until we fill up `respBuf`
        while (respBufLen < sizeof(respBuf)) {
            uint8_t buf[512];
            
            // Tell FTDI to clock in bytes to fill `buf`
            {
                const size_t len = sizeof(buf);
                const uint8_t b[] = {0x20, (uint8_t)((len-1)&0xFF), (uint8_t)(((len-1)&0xFF00)>>8)};
                _ftdiWrite(_ftdi, b, sizeof(b));
            }
            
            // Get the bytes from FTDI
            _ftdiRead(_ftdi, buf, sizeof(buf));
            
            // Find the start byte
            std::optional<size_t> bufOff;
            if (!respBufLen) {
                for (size_t i=0; i<sizeof(buf); i++) {
                    if (buf[i] != 0xFF) {
                        bufOff = i;
                        break;
                    }
                }
            } else {
                bufOff = 0;
            }
            
            // Copy new bytes into `respBuf`
            if (bufOff) {
                const size_t copyLen = std::min(sizeof(respBuf)-respBufLen, sizeof(buf)-*bufOff);
                memcpy(respBuf+respBufLen, buf+*bufOff, copyLen);
                respBufLen += copyLen;
            }
        }
        
        uint8_t startBit = fls(~respBuf[0]);
        getBits(respBuf, sizeof(respBuf), , );
    }
    
    void _setPins(const Pins& pins) {
        uint8_t b[] = {0x80, pins.valBits(), pins.dirBits()};
        _ftdiWrite(_ftdi, b, sizeof(b));
    }
    
    static void _ftdiRead(struct ftdi_context& ftdi, uint8_t* d, const size_t len) {
        for (size_t off=0; off<len;) {
            const size_t readLen = len-off;
            int ir = ftdi_read_data(&ftdi, d+off, (int)readLen);
            
//            if (ir > 0) {
//                printf("====================\n");
//                printf("Read:\n");
//                for (size_t i=0; i<readLen; i++) {
//                    uint8_t byte = *(d+off+i);
////                    if (byte) {
//                        printf("%02x ", byte);
////                    }
//                }
//                printf("\n");
//                printf("====================\n");
//            }
//            exit(0);
            
            assert(ir>=0 && (size_t)ir<=readLen);
            off += ir;
        }
    }
    
    static void _ftdiWrite(struct ftdi_context& ftdi, const uint8_t* d, const size_t len) {
        int ir = ftdi_write_data(&ftdi, d, (int)len);
        assert(ir>=0 && (size_t)ir==len);
    }
    
//private:
public:
    struct ftdi_context _ftdi;
};

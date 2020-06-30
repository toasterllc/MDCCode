#include <stdio.h>
#include <assert.h>
#include <vector>
#include <queue>
#include <algorithm>
#include <unistd.h>
#include <string.h>
#include <libftdi1/ftdi.h>

class MDCDevice {
public:
    enum class Pin : uint8_t {
        CLK     = 1<<0,
        DO      = 1<<1,
        DI      = 1<<2,
        UNUSED1 = 1<<3,
        CS      = 1<<4,
        UNUSED2 = 1<<5,
        CDONE   = 1<<6,
        CRST_   = 1<<7,
    };
    
    enum class Cmd : uint8_t {
        Nop         = 0x00,
        LEDOff      = 0x80,
        LEDOn       = 0x81,
        ReadData    = 0x82,
    };
    
    struct Msg {
        Cmd cmd = Cmd::Nop;
        std::vector<uint8_t> payload;
    };
    
    struct PinConfig {
        Pin pin = (Pin)0;
        uint8_t dir = 0;
        uint8_t val = 0;
    };
    
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
        
        // // Clear incoming data
        // for (;;) {
        //     uint8_t buf[16];
        //     ir = ftdi_read_data(&_ftdi, buf, sizeof(buf));
        //     assert(ir >= 0);
        //     if (ir == 0) {
        //         break;
        //     }
        // }
        
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
        
//        // Flush the read buffer
//        for (;;) {
//            uint8_t tmp[128];
//            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
//            printf("read %d bytes\n", ir);
//            assert(ir >= 0);
//            if (!ir) break;
//        }
        
        // Clear our receive buffer
        // For some reason this needs to happen after our first write (via _flush),
        // otherwise we don't receive anything.
        // This is necessary in case an old process was doing IO and crashed, in which
        // case there could still be data in the buffer.
        for (int i=0; i<10; i++) {
            uint8_t tmp[128];
            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
            printf("AAA FLUSH: %d\n", ir);
            usleep(100000);
        //            assert(ir >= 0);
        //            if (!ir) break;
        }
        
        // Use 60MHz master clock, disable adaptive clocking, disable three-phase clocking, disable loopback
        {
            uint8_t cmd[] = {0x8A, 0x97, 0x8D, 0x85};
            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            assert(ir == sizeof(cmd));
        }
        
        // Set CLK frequency to 1MHz
        {
            uint8_t cmd[] = {0x86, 0x1D, 0x00};
            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
            assert(ir == sizeof(cmd));
        }
        
        // Clear our receive buffer
        // For some reason this needs to happen after our first write (via _flush),
        // otherwise we don't receive anything.
        // This is necessary in case an old process was doing IO and crashed, in which
        // case there could still be data in the buffer.
        for (int i=0; i<10; i++) {
            uint8_t tmp[128];
            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
            printf("BBB FLUSH: %d\n", ir);
            usleep(100000);
//            assert(ir >= 0);
//            if (!ir) break;
        }
        
        _resetPinState();
        
        // Clear our receive buffer
        // For some reason this needs to happen after our first write (via _flush),
        // otherwise we don't receive anything.
        // This is necessary in case an old process was doing IO and crashed, in which
        // case there could still be data in the buffer.
        for (int i=0; i<10; i++) {
            uint8_t tmp[128];
            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
            printf("CCC FLUSH: %d\n", ir);
            usleep(100000);
//            assert(ir >= 0);
//            if (!ir) break;
        }
        
//        // Synchronize with FTDI by sending a bad command and ensuring we get the expected error
//        {
//                const uint8_t cmd[] = {0xAB};
//                _ftdiWrite(_ftdi, cmd, sizeof(cmd));
//
//                // TODO: IIRC, for flushing the buffer to work, we may need to call ftdi_write_data first. otherwise, reading data may not work...
//    //            // Flush the read buffer
//                uint8_t resp[2];
//                for (;;) {
//                    uint8_t tmp[128];
//                    int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
//                    assert(ir >= 0);
//                    for (int i=0; i<ir; i++) {
//                        printf("ZZZ: resp[%d] = 0x%x\n", i, tmp[i]);
//                    }
//                    if (!ir) break;
//                }
//
////            assert(resp[0]==0xFA && resp[1]==0xAB);
//
//
//
//
//
//
//
//
//
//
//
////            for (;;) {
////                auto tmp = _readData(1);
////                printf("read %zu bytes\n", tmp.size());
////            }
//
//
////            for (;;) {
////                const uint8_t cmd[] = {0xAB};
////                _ftdiWrite(_ftdi, cmd, sizeof(cmd));
////
////                // TODO: IIRC, for flushing the buffer to work, we may need to call ftdi_write_data first. otherwise, reading data may not work...
////    //            // Flush the read buffer
////                for (;;) {
////                    sleep(1);
////                    uint8_t tmp[128];
////                    int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
////                    printf("0xAB response: read %d bytes\n", ir);
////                    assert(ir >= 0);
////                    for (int i=0; i<ir; i++) {
////                        printf("ZZZ: resp[%d] = 0x%x\n", i, tmp[i]);
////                    }
////                    if (!ir) break;
////                }
////
//////                printf("XXX\n");
//////                _ftdiWrite(_ftdi, cmd, sizeof(cmd));
//////                printf("YYY\n");
//////
//////    //            uint8_t resp[2];
//////    //            _ftdiRead(_ftdi, resp, sizeof(resp));
//////
//////                uint8_t resp[1];
//////                _ftdiRead(_ftdi, resp, sizeof(resp));
//////
//////                printf("ZZZ: resp[0] = 0x%x\n", resp[0]);
//////                exit(0);
////            }
////
//////            assert(resp[0]==0xFA && resp[1]==0xAB);
//        }
        
//        for (;;) {
//            {
//                printf("ftdi_write_data\n");
//                uint8_t b[] = {0x31, 0x00, 0x00, 0x81};
//                int ir = ftdi_write_data(&_ftdi, b, sizeof(b));
//                assert(ir == sizeof(b));
//
//                sleep(1);
//                for (;;) {
//                    uint8_t tmp[128];
//                    int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
//                    assert(ir >= 0);
//                    printf("Read %d bytes:\n", ir);
//                    for (int i=0; i<ir; i++) {
//                        printf("  [%d] = 0x%x\n", i, tmp[i]);
//                    }
//                    if (!ir) break;
//                }
//            }
//
////            sleep(1);
////            exit(0);
//        }
    }
    
    ~MDCDevice() {
        int ir = ftdi_usb_close(&_ftdi);
        assert(!ir);
        
        ftdi_deinit(&_ftdi);
    }
    
    void _resetPinState() {
        // ## Reset our pin state
        _setPins({
            {.pin=Pin::CLK,     .dir=1,     .val=0},
            {.pin=Pin::DO,      .dir=1,     .val=0},
            {.pin=Pin::DI,      .dir=0,     .val=0},
            {.pin=Pin::CS,      .dir=1,     .val=1},
            {.pin=Pin::CDONE,   .dir=0,     .val=0},
            {.pin=Pin::CRST_,   .dir=1,     .val=1},
        });
    }
    
    void write(const Cmd cmd) {
//        for (;;) {
//            uint8_t tmp[128];
//            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
//            assert(ir >= 0);
//            printf("[BEFORE] Read %d bytes:\n", ir);
//            for (int i=0; i<ir; i++) {
//                printf("  [%d] = 0x%x\n", i, tmp[i]);
//            }
//            if (!ir) break;
//        }
        
        
        _write(std::vector<uint8_t>({(uint8_t)cmd}));
        
//        for (int i=0; i<100; i++) {
//            uint8_t tmp[128];
//            int ir = ftdi_read_data(&_ftdi, tmp, sizeof(tmp));
//            assert(ir >= 0);
//            printf("Read %d bytes:\n", ir);
//            for (int i=0; i<ir; i++) {
//                printf("  [%d] = 0x%x\n", i, tmp[i]);
//            }
////            if (!ir) break;
//        }
        
    }
    
    Msg read() {
        Msg msg;
        uint8_t len = 0;
        _read((uint8_t*)&len, sizeof(len));
        if (len) {
            _read((uint8_t*)&msg.cmd, sizeof(msg.cmd));
            const uint8_t payloadLen = len-1;
            msg.payload.resize(payloadLen);
            _read(msg.payload.data(), payloadLen);
        }
        return msg;
//        Msg msg;
//        uint16_t payloadLen = 0;
//        _read((uint8_t*)&msg.cmd, sizeof(msg.cmd));
//        _read((uint8_t*)&payloadLen, sizeof(payloadLen));
//        msg.payload.resize(payloadLen);
//        _read(msg.payload.data(), payloadLen);
//        return msg;
    }

    void _read(uint8_t* d, const size_t len) {
        for (size_t off=0; off<len;) {
            // Read from the bytes that we've already read from the device
            const size_t readLen = std::min(len-off, _in.size());
            memcpy(d+off, _in.data(), readLen);
            _in.erase(_in.begin(), _in.begin()+readLen);
            off += readLen;
            
            // Write Nop's so that we get `len-off` bytes back
            _write(std::vector<uint8_t>(len-off, (uint8_t)Cmd::Nop));
        }
    }
    
    void _setPins(std::vector<PinConfig> configs) {
        uint8_t pinDirs = 0;
        uint8_t pinVals = 0;
        for (const PinConfig& c : configs) {
            pinDirs = (pinDirs&(~(uint8_t)c.pin))|(c.dir ? (uint8_t)c.pin : 0);
            pinVals = (pinVals&(~(uint8_t)c.pin))|(c.val ? (uint8_t)c.pin : 0);
        }
        
        uint8_t b[] = {0x80, pinVals, pinDirs};
        _ftdiWrite(_ftdi, b, sizeof(b));
    }
    
    void _write(const std::vector<uint8_t>& d) {
        // Short-circuit if there's no data to write
        if (d.empty()) return;
        
        std::vector<uint8_t> tmp = {0x31, (uint8_t)((d.size()-1)&0xFF), (uint8_t)(((d.size()-1)&0xFF00)>>8)};
        tmp.insert(tmp.end(), d.begin(), d.end());
        _ftdiWrite(_ftdi, tmp.data(), tmp.size());
        
//        uint8_t b[] = {0x31, (uint8_t)((d.size()-1)&0xFF), (uint8_t)(((d.size()-1)&0xFF00)>>8)};
//        _ftdiWrite(_ftdi, b, sizeof(b));
//        _ftdiWrite(_ftdi, d.data(), d.size());
        
        // Store the data that was clocked out from the device
        const size_t oldSize = _in.size();
        _in.resize(oldSize+d.size());
        _ftdiRead(_ftdi, _in.data()+oldSize, d.size());
    }
    
    static void _ftdiRead(struct ftdi_context& ftdi, uint8_t* d, const size_t len) {
        for (size_t off=0; off<len;) {
            const size_t readLen = len-off;
            int ir = ftdi_read_data(&ftdi, d+off, (int)readLen);
//            printf("ftdi_read_data: %d\n", ir);
            assert(ir>=0 && (size_t)ir<=readLen);
            off += ir;
        }
    }
    
    static void _ftdiWrite(struct ftdi_context& ftdi, const uint8_t* d, const size_t len) {
        int ir = ftdi_write_data(&ftdi, d, (int)len);
        assert(ir>=0 && (size_t)ir==len);
        printf("_ftdiWrite wrote %d bytes:\n", ir);
        for (int i=0; i<(int)len; i++) {
            printf("  [%d] = 0x%x\n", i, d[i]);
        }
        
//        for (;;) {
//            int ir = ftdi_write_data(&ftdi, d, (int)len);
//            printf("ir: %d\n", ir);
//            if (ir == (int)len) break;
//        }
//        assert(ir>=0 && (size_t)ir==len);
    }
    
private:
    struct ftdi_context _ftdi;
    std::vector<uint8_t> _in;
};

int main() {
    using Cmd = MDCDevice::Cmd;
    
    MDCDevice device;
    
    printf("HALLO\n");
    for (bool on = false;; on = !on) {
        device.write((on ? Cmd::LEDOn : Cmd::LEDOff));
//        device.write(Cmd::Nop);
        printf("led = %d\n", on);
        
        MDCDevice::Msg msg = device.read();
        printf("Msg{cmd: 0x%jx, payload len: %ju}\n",
            (uintmax_t)msg.cmd, (uintmax_t)msg.payload.size());
        
//        usleep(1000000);
    }
    
    return 0;
}

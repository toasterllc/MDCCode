#include <stdio.h>
#include <assert.h>
#include <vector>
#include <queue>
#include <algorithm>
#include <unistd.h>
#include <string.h>
#include <libftdi1/ftdi.h>
#include <optional>
#include <memory>
#include <chrono>
#include <sstream>
#include <iomanip>
#include <iostream>

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
        ReadMem     = 0x82,
    };
    
    struct Msg {
        Cmd cmd = Cmd::Nop;
        uint8_t* payload = nullptr;
        uint8_t payloadLen = 0;
        
        std::string desc() const {
            std::stringstream d;
            
            d << std::setfill('0') << std::setw(2);
            
            d << "Msg{\n";
            d << "  cmd: 0x" << std::hex << (uintmax_t)cmd << "\n";
            d << "  payload (len = " << std::dec << (uintmax_t)payloadLen << "): [ ";
            for (size_t i=0; i<payloadLen; i++) {
                d << std::hex << (uintmax_t)payload[i] << " ";
            }
            d << "]\n}\n\n";
            return d.str();
        }
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
        
        _resetPinState();
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
        _write(std::vector<uint8_t>({(uint8_t)cmd}));
    }
    
    std::optional<Msg> _readMsg() {
        size_t off = _inOff;
        
        Msg msg;
        if (_inLen-off < sizeof(msg.cmd)) return std::nullopt;
        memcpy(&msg.cmd, _in+off, sizeof(msg.cmd));
        off += sizeof(msg.cmd);
        
        if (_inLen-off < sizeof(msg.payloadLen)) return std::nullopt;
        memcpy(&msg.payloadLen, _in+off, sizeof(msg.payloadLen));
        off += sizeof(msg.payloadLen);
        
        if (_inLen-off < msg.payloadLen) return std::nullopt;
        msg.payload = _in+off;
        off += msg.payloadLen;
        
        _inOff = off;
        return msg;
    }
    
    Msg read() {
        auto msg = _readMsg();
        if (msg) return *msg;
        
        // We failed to compose a message, so we need to read more data
        // Move the remaining partial message at the end of the buffer (pointed
        // to by `off`) to the beginning of the buffer.
        memmove(_in, _in+_inOff, _inLen-_inOff);
        _inLen -= _inOff;
        _inOff = 0;
        
        // readLen = length to fill up _in
        const size_t readLen = sizeof(_in)-_inLen;
        // Subtract the number of pending bytes from the number of bytes
        // that we clock out (and clipping to 0).
        const size_t clockOutLen = readLen-std::min(readLen, _inPending);
        
        // Clock out more bytes if needed
        if (clockOutLen) {
            // Create FTDI command to fill the remainder of `buf` with data
            const size_t chunkSize = 0x10000; // Max read size for a single 0x20 command
            const size_t chunks = clockOutLen/chunkSize;
            const size_t rem = clockOutLen%chunkSize;
            uint8_t cmds[(3*chunks) + (rem?3:0)];
            for (size_t i=0; i<chunks; i++) {
                cmds[(i*3)+0] = 0x20;
                cmds[(i*3)+1] = 0xFF;
                cmds[(i*3)+2] = 0xFF;
            }
            
            if (rem) {
                cmds[sizeof(cmds)-3] = 0x20;
                cmds[sizeof(cmds)-2] = (uint8_t)((rem-1)&0xFF);
                cmds[sizeof(cmds)-1] = (uint8_t)(((rem-1)&0xFF00)>>8);
            }
            
            // Reset pin state before performing mass read to ensure DO=0
            _resetPinState();
            _ftdiWrite(_ftdi, cmds, sizeof(cmds));
        }
        
        // Read bytes to fill up _in
        _ftdiRead(_ftdi, _in+_inLen, readLen);
        _inLen += readLen;
        _inPending -= std::min(_inPending, readLen);
        
        msg = _readMsg();
        assert(msg);
        return *msg;
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
        
        uint8_t b[] = {0x31, (uint8_t)((d.size()-1)&0xFF), (uint8_t)(((d.size()-1)&0xFF00)>>8)};
        _ftdiWrite(_ftdi, b, sizeof(b));
        _ftdiWrite(_ftdi, d.data(), d.size());
        
        // Verify that we don't overflow _inPending
        assert(SIZE_MAX-_inPending >= d.size());
        _inPending += d.size();
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
    uint8_t _in[0x100000]; // 1 MB
    size_t _inOff = 0;
    size_t _inLen = 0;
    size_t _inPending = 0; // Number of bytes already available to be read via ftdi_read_data()
};

using TimeInstant = std::chrono::steady_clock::time_point;

static TimeInstant CurrentTime() {
    return std::chrono::steady_clock::now();
}

static uint64_t TimeDurationNs(TimeInstant t1, TimeInstant t2) {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(t2-t1).count();
}

static uint64_t TimeDurationMs(TimeInstant t1, TimeInstant t2) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(t2-t1).count();
}

static void PrintMsg(const MDCDevice::Msg& msg) {
    std::cout << msg.desc();
}

int main() {
    const size_t RAMWordCount = 0x2000000;
    const size_t RAMWordSize = 2;
    const size_t RAMSize = RAMWordCount*RAMWordSize;
    using Cmd = MDCDevice::Cmd;
    using Msg = MDCDevice::Msg;
    
    auto device = std::make_unique<MDCDevice>();
    
    for (;;) {
//        device->write(Cmd::LEDOn);
        device->write(Cmd::ReadMem);
        
        auto startTime = CurrentTime();
        size_t msgCount = 0;
        size_t totalDataLen = 0;
        
        bool during = false;
        for (;;) {
            Msg msg = device->read();
//            if (msg.payloadLen) {
//                during = true;
//            } else {
//                if (during) {
//                    printf("*** Message length == 0\n");
//                }
//            }
//            
//            bool last = (totalDataLen+msg.payloadLen)>=RAMSize;
//            if (!last && during && msg.payloadLen != 254) {
//                printf("*** Bad message length: %ju\n", (uintmax_t)msg.payloadLen);
//                
//                printf("Before:\n");
//                uint8_t* badMessageStart = msg.payload-2;
//                for (uint8_t* p=badMessageStart-10; p<badMessageStart; p++) {
//                    printf("0x%jx ", (uintmax_t)*p);
//                }
//                printf("\n");
//                
//                
//                
//                printf("After:\n");
//                for (uint8_t* p=badMessageStart; p<badMessageStart+10; p++) {
//                    printf("0x%jx ", (uintmax_t)*p);
//                }
//                printf("\n");
//            }
//            
            msgCount++;
            totalDataLen += msg.payloadLen;
            if (!(msgCount % 4000)) {
                printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)totalDataLen);
//                std::cout << msg.desc();
            }
            
//            if (during && msg.payloadLen!=254) {
//                printf("*** Bad message length: %ju\n", (uintmax_t)msg.payloadLen);
//                
//                printf("Before:\n");
//                uint8_t* badMessageStart = msg.payload-2;
//                for (uint8_t* p=badMessageStart-10; p<badMessageStart; p++) {
//                    printf("0x%jx ", (uintmax_t)*p);
//                }
//                printf("\n");
//                
//                
//                
//                printf("After:\n");
//                for (uint8_t* p=badMessageStart; p<badMessageStart+10; p++) {
//                    printf("0x%jx ", (uintmax_t)*p);
//                }
//                printf("\n");
//            }
            
            
//            std::cout << msg.desc();
            
            if (totalDataLen >= RAMSize) break;
        }
        auto stopTime = CurrentTime();
        printf("Success!\n");
        printf("Duration: %ju ms, data length: %ju\n\n", (uintmax_t)TimeDurationMs(startTime, stopTime), totalDataLen);
        assert(totalDataLen == RAMSize);
    }
    
    return 0;
}

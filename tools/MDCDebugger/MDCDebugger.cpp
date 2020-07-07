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
    
    struct Msg {
        template <typename T>
        static std::unique_ptr<T> Cast(std::unique_ptr<Msg> msg) {
            if (msg && msg->type == T{}.type) return std::unique_ptr<T>((T*)msg.release());
            return nullptr;
        }
        
        template <typename T>
        static T* Cast(Msg* msg) {
            if (msg->type == T{}.type) return (T*)msg;
            return nullptr;
        }
        
        using Type = uint8_t;
        Type type = 0;
        uint8_t len = 0;
    };
    
    struct NopMsg : Msg {
        NopMsg() : Msg{.type=0x00, .len=sizeof(*this)-sizeof(Msg)} {}
    };
    
    struct SetLEDMsg : Msg {
        SetLEDMsg() : Msg{.type=0x01, .len=sizeof(*this)-sizeof(Msg)} {}
        uint8_t on = 0;
    };
    
    struct ReadMemMsg : Msg {
        ReadMemMsg() : Msg{.type=0x02, .len=0} {} // Special case `len` in this case
        uint8_t* mem = nullptr;
        
        std::string desc() const {
            std::stringstream d;
            
            d << std::setfill('0') << std::setw(2);
            
            d << "ReadMemMsg{\n";
            d << "  type: 0x" << std::hex << (uintmax_t)type << "\n";
            d << "  payload (len = " << std::dec << (uintmax_t)len << "): [ ";
            for (size_t i=0; i<len; i++) {
                d << std::hex << (uintmax_t)mem[i] << " ";
            }
            d << "]\n}\n\n";
            return d.str();
        }
    };
    
    struct PixReadReg8Msg : Msg {
        PixReadReg8Msg() : Msg{.type=0x03, .len=sizeof(*this)-sizeof(Msg)} {}
        uint16_t addr = 0;
        uint8_t val = 0;
    };
    
    struct PixReadReg16Msg : Msg {
        PixReadReg16Msg() : Msg{.type=0x04, .len=sizeof(*this)-sizeof(Msg)} {}
        uint16_t addr = 0;
        uint16_t val = 0;
    };
    
    struct PixWriteReg8Msg : Msg {
        PixWriteReg8Msg() : Msg{.type=0x05, .len=sizeof(*this)-sizeof(Msg)} {}
        uint16_t addr = 0;
        uint8_t val = 0;
    };
    
    struct PixWriteReg16Msg : Msg {
        PixWriteReg16Msg() : Msg{.type=0x06, .len=sizeof(*this)-sizeof(Msg)} {}
        uint16_t addr = 0;
        uint16_t val = 0;
    };
    
    using MsgPtr = std::unique_ptr<Msg>;
    
    
    
//    enum class Op : uint8_t {
//        Nop             = 0x00,
//        
//        SetLED          = 0x80,
//        
//        ReadMem         = 0x81,
//        
//        PixRegRead8     = 0x82,
//        PixRegRead16    = 0x83,
//        
//        PixRegWrite8    = 0x84,
//        PixRegWrite16   = 0x85,
//    };
//    
//    
//    
//    struct Msg {
//        Op op = Type::Nop;
//        uint8_t payloadLen = 0;
//    };
//    
//    struct SetLED : Msg {
//        uint8_t on = 0;
//    };
//    
//    struct ReadMem : Msg {
//    };
//    
//    struct PixRegRead : Msg {
//        uint16_t addr;
//    };
//    
//    
//    static_assert(sizeof(Cmd)==5, "sizeof(Cmd) must be 5 bytes");
//    
//    
//    
//    
//    
//    
//    
//    
//    
////    struct Cmd {
////        Op op = Type::Nop;
////        
////        union {
////            uint8_t payload[4];
////            
////            struct {
////                bool on;
////            } setLED;
////            
////            struct {
////                uint16_t addr;
////            } pixRegRead;
////            
////            struct {
////                uint16_t addr;
////                uint16_t val;
////            } pixRegWrite;
////        };
////    } __attribute__((packed));
////    static_assert(sizeof(Cmd)==5, "sizeof(Cmd) must be 5 bytes");
//    
//    
//    
//    
//    
//    
//    
//    
//    
//    struct Cmd {
//        Op op = Type::Nop;
//        
//        union {
//            uint8_t payload[4];
//            
//            struct {
//                bool on;
//            } setLED;
//            
//            struct {
//                uint16_t addr;
//            } pixRegRead;
//            
//            struct {
//                uint16_t addr;
//                uint16_t val;
//            } pixRegWrite;
//        };
//    } __attribute__((packed));
//    static_assert(sizeof(Cmd)==5, "sizeof(Cmd) must be 5 bytes");
    
//    struct Msg {
//        Op op = Type::Nop;
//        uint8_t* payload = nullptr;
//        uint8_t payloadLen = 0;
//        
//        std::string desc() const {
//            std::stringstream d;
//            
//            d << std::setfill('0') << std::setw(2);
//            
//            d << "Msg{\n";
//            d << "  op: 0x" << std::hex << (uintmax_t)op << "\n";
//            d << "  payload (len = " << std::dec << (uintmax_t)payloadLen << "): [ ";
//            for (size_t i=0; i<payloadLen; i++) {
//                d << std::hex << (uintmax_t)payload[i] << " ";
//            }
//            d << "]\n}\n\n";
//            return d.str();
//        }
//    };
    
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
    
    void write(const Msg& msg) {
        const size_t msgSize = sizeof(msg)+msg.len;
        uint8_t b[] = {0x31, (uint8_t)((msgSize-1)&0xFF), (uint8_t)(((msgSize-1)&0xFF00)>>8)};
        _ftdiWrite(_ftdi, b, sizeof(b));
        _ftdiWrite(_ftdi, (uint8_t*)&msg, msgSize);
        
        // Verify that we don't overflow _inPending
        assert(SIZE_MAX-_inPending >= msgSize);
        _inPending += msgSize;
    }
    
    MsgPtr _newMsg(Msg::Type type) {
        if (type == NopMsg{}.type) return std::make_unique<NopMsg>();
        if (type == SetLEDMsg{}.type) return std::make_unique<SetLEDMsg>();
        if (type == ReadMemMsg{}.type) return std::make_unique<ReadMemMsg>();
        if (type == PixReadReg8Msg{}.type) return std::make_unique<PixReadReg8Msg>();
        if (type == PixReadReg16Msg{}.type) return std::make_unique<PixReadReg16Msg>();
        if (type == PixWriteReg8Msg{}.type) return std::make_unique<PixWriteReg8Msg>();
        if (type == PixWriteReg8Msg{}.type) return std::make_unique<PixWriteReg8Msg>();
        return nullptr;
    }
    
    MsgPtr _readMsg() {
        size_t off = _inOff;
        
        Msg header;
        if (_inLen-off < sizeof(header)) return nullptr;
        memcpy(&header, _in+off, sizeof(header));
        off += sizeof(header);
        
        if (_inLen-off < header.len) return nullptr;
        
        MsgPtr msg = _newMsg(header.type);
        assert(msg);
        
        // Verify that the incoming message has enough data to fill the type that it claims to be
        assert(header.len >= msg->len);
        
        // Copy the payload into the message, but only the number of bytes that we expect the message to have.
        memcpy(msg.get()+sizeof(Msg), _in+off, msg->len);
        
        // Handle special message types that contain variable amounts of data
        if (auto x = Msg::Cast<ReadMemMsg>(msg.get())) {
            x->mem = _in+off;
        }
        
        off += header.len;
        _inOff = off;
        return msg;
    }
    
    MsgPtr read(size_t maxReadLen=sizeof(_in)) {
        MsgPtr msg = _readMsg();
        if (msg) return msg;
        
        // We failed to compose a message, so we need to read more data
        // Move the remaining partial message at the end of the buffer (pointed
        // to by `off`) to the beginning of the buffer.
        memmove(_in, _in+_inOff, _inLen-_inOff);
        _inLen -= _inOff;
        _inOff = 0;
        
        const size_t maxMsgLen =
            sizeof(Msg) +
            std::numeric_limits<decltype(Msg::len)>::max();
        
        // maxReadLen must be >= the maximum size of a single message (maxMsgLen).
        // Otherwise, we could fail to create a message after reading data into _in,
        // due to not enough data being available.
        maxReadLen = std::max(maxMsgLen, maxReadLen);
        
        // readLen = amount of data to read
        const size_t readLen = std::min(maxReadLen, sizeof(_in)-_inLen);
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
        return msg;
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

static void PrintMsg(const MDCDevice::ReadMemMsg& msg) {
    std::cout << msg.desc();
}

int main() {
    const size_t RAMWordCount = 0x2000000;
    const size_t RAMWordSize = 2;
    const size_t RAMSize = RAMWordCount*RAMWordSize;
    using Msg = MDCDevice::Msg;
    using MsgPtr = MDCDevice::MsgPtr;
    using ReadMemMsg = MDCDevice::ReadMemMsg;
    
    auto device = std::make_unique<MDCDevice>();
    
    printf("Running trials...\n");
    for (uint64_t trial=0;; trial++) {
//        device->write(Cmd::LEDOn);
        device->write(ReadMemMsg{});
        
        auto startTime = CurrentTime();
        size_t dataLen = 0;
        std::optional<uint16_t> lastVal;
        for (size_t msgCount=0; dataLen<RAMSize; msgCount++) {
            if (auto msgPtr = Msg::Cast<ReadMemMsg>(device->read())) {
                const ReadMemMsg& msg = *msgPtr;
                if (!(msg.len % 2)) {
                    for (size_t i=0; i<msg.len; i+=2) {
                        uint16_t val;
                        memcpy(&val, msg.mem+i, sizeof(val));
                        if (lastVal) {
                            uint16_t expected = (uint16_t)(*lastVal+1);
                            if (val != expected) {
                                printf("  Error: value mismatch: expected 0x%jx, got 0x%jx\n", (uintmax_t)expected, (uintmax_t)val);
                            }
                        }
                        lastVal = val;
                    }
                } else {
                    printf("  Error: payload length invalid: expected even, got odd (0x%ju)\n", (uintmax_t)msg.len);
                }
                
                dataLen += msg.len;
    //            if (!(msgCount % 4000)) {
    //                printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)totalDataLen);
    //            }
            }
        }
        auto stopTime = CurrentTime();
        
        if (dataLen != RAMSize) {
            printf("  Error: data length mismatch: expected 0x%jx, got 0x%jx\n",
                (uintmax_t)RAMSize, (uintmax_t)dataLen);
        }
        
        printf("Trial complete | Trial: %06ju | Duration: %ju ms\n",
            (uintmax_t)trial, (uintmax_t)TimeDurationMs(startTime, stopTime));
    }
    
    return 0;
}

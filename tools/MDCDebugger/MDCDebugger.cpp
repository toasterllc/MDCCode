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
        
//        // Perform a single clock
//        {
//            uint8_t cmd[] = {0x8E, 0x00};
//            ir = ftdi_write_data(&_ftdi, cmd, sizeof(cmd));
//            assert(ir == sizeof(cmd));
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
        
//        
//        
//        
//        
//
//        
//        
//        
//        
//        msgCount++;
//        totalDataLen += msg.payloadLen;
//        if (!(msgCount % 1000)) {
////                printf("msgCount: %ju, totalDataLen: %ju\n", (uintmax_t)msgCount, (uintmax_t)totalDataLen);
////                PrintMsg(msg);
//        }
//        
//        
//        
//        
//        
//        const size_t RAMWordCount = 0x2000000;
//        const size_t RAMWordSize = 2;
//        const size_t RAMSize = RAMWordCount*RAMWordSize;
//        const size_t ChunkSize = 0x10000; // Max read size for a single 0x20 command
//        const size_t ChunkCount = 32;
//        const size_t BufCap = ChunkSize*ChunkCount;
//        std::unique_ptr<uint8_t[]> buf(new uint8_t[BufCap]);
//        size_t bufLen = 0;
//        
//        // Reset pin state before performing mass reads to ensure DO=0
//        device._resetPinState();
//        
//        
//        auto startTime = CurrentTime();
//        
//        uint64_t cumulativeProcessTime = 0;
//        uint64_t cumulativeReadWriteTime = 0;
//        
//        size_t msgCount = 0;
//        size_t totalDataLen = 0;
//        for (;;) {
//            auto readWriteStartTime = CurrentTime();
//            
//            auto readWriteStopTime = CurrentTime();
//            cumulativeReadWriteTime += TimeDuration<std::chrono::nanoseconds>(readWriteStartTime, readWriteStopTime);
//            
//            
//            
//            
//            
//            
//            auto processStartTime = CurrentTime();
//            
//            // Process messages
//            size_t off = 0;
//            for (;;) {
//                size_t o = off;
//                Msg msg;
//                
//                if (bufLen-o < sizeof(msg.cmd)) break;
//                memcpy(&msg.cmd, buf.get()+o, sizeof(msg.cmd));
//                o += sizeof(msg.cmd);
//                
//                if (bufLen-o < sizeof(msg.payloadLen)) break;
//                memcpy(&msg.payloadLen, buf.get()+o, sizeof(msg.payloadLen));
//                o += sizeof(msg.payloadLen);
//                
//                if (bufLen-o < msg.payloadLen) break;
//                msg.payload = buf.get()+o;
//                o += msg.payloadLen;
//                
//                off = o;
//                
//                
//                
//                
//                msgCount++;
//                totalDataLen += msg.payloadLen;
//                if (!(msgCount % 1000)) {
//    //                printf("msgCount: %ju, totalDataLen: %ju\n", (uintmax_t)msgCount, (uintmax_t)totalDataLen);
//    //                PrintMsg(msg);
//                }
//                
//    //            PrintMsg(msg);
//            }
//            
//            // Move the remaining partial message at the end of the buffer (pointed
//            // to by `off`) to the beginning of the buffer.
//            bufLen -= off;
//            memmove(buf.get(), buf.get()+off, bufLen);
//            
//            auto processStopTime = CurrentTime();
//            cumulativeProcessTime += TimeDuration<std::chrono::nanoseconds>(processStartTime, processStopTime);
//            
//            if (totalDataLen >= RAMSize) {
//                break;
//            }
//        }
//        
//        auto stopTime = CurrentTime();
//        
//        printf("totalDataLen: %ju\n", (uintmax_t)totalDataLen);
//        printf("cumulativeReadWriteTime: %ju ns\n", (uintmax_t)cumulativeReadWriteTime);
//        printf("cumulativeProcessTime: %ju ns\n", (uintmax_t)cumulativeProcessTime);
//        printf("duration: %ju ms\n", (uintmax_t)TimeDuration<std::chrono::milliseconds>(startTime, stopTime));
    }
    
//    Msg read() {
//        Msg msg;
//
//        // Read command
//        _read((uint8_t*)&msg.cmd, sizeof(msg.cmd));
//
//        // Read payload length
//        uint8_t payloadLen = 0;
//        _read((uint8_t*)&payloadLen, sizeof(payloadLen));
//
//        if (payloadLen) {
//            msg.payload.resize(payloadLen);
//            _read(msg.payload.data(), payloadLen);
//        }
//        return msg;
//    }
    
    
    
    
    
    
//    static void _ftdiMassRead(struct ftdi_context& ftdi, size_t len) {
//        if (!len) return;
//        
//        // Clock in/out a single Nop first, to make DO=0 before the mass read.
//        // Otherwise we'd be clocking out an unknown value on DO during the mass read.
//        const uint8_t nopCmd[] = { 0x31, 0x00, 0x00, (uint8_t)Cmd::Nop };
//        _ftdiWrite(ftdi, nopCmd, sizeof(nopCmd));
//        len--;
//        
//        if (len) {
//            // Clock out `len` bytes
//            const uint8_t massReadCmd[] = { 0x20, (uint8_t)((len-1)&0xFF), (uint8_t)(((len-1)&0xFF00)>>8) };
//            _ftdiWrite(ftdi, massReadCmd, sizeof(massReadCmd));
//        }
//    }
//    
//    void _read(uint8_t* d, const size_t len) {
//        for (size_t off=0; off<len;) {
//            const size_t readLen = len-off;
//            int ir = ftdi_read_data(&_ftdi, d+off, (int)readLen);
//            assert(ir>=0 && (size_t)ir<=len);
//            off += ir;
//            
//            if (off < len) {
//                _ftdiMassRead(_ftdi, len-off);
//            }
//        }
//    }
    
//    void _read(uint8_t* d, const size_t len) {
//        for (size_t off=0; off<len;) {
//            const size_t readLen = len-off;
//            int ir = ftdi_read_data(&_ftdi, d+off, (int)readLen);
//            assert(ir>=0 && (size_t)ir<=len);
//            off += ir;
//            
//            if (off < len) {
//                _ftdiMassRead(_ftdi, len-off);
//            }
//        }
//    }
    
//    Msg read() {
//        std::vector<Msg> msgs;
//        
//        _ftdiMassRead(_ftdi, len);
//        
//        for (size_t i=0; i<len;) {
//            Msg msg;
//            
//            _read((uint8_t*)&msg.cmd, sizeof(msg.cmd));
//            i += sizeof(msg.cmd);
//            
//            uint8_t payloadLen = 0;
//            _read(&payloadLen, sizeof(payloadLen));
//            i += sizeof(payloadLen);
//            
//            if (payloadLen) {
//                msg.payload.resize(payloadLen);
//                _read(msg.payload.data(), payloadLen);
//                i += payloadLen;
//            }
//            
//            msgs.push_back(std::move(msg));
//        }
//        
//        return msgs;
//    }
    
//    std::vector<Msg> read(uint16_t len) {
//        std::vector<Msg> msgs;
//        
//        _ftdiMassRead(_ftdi, len);
//        
//        for (size_t i=0; i<len;) {
//            Msg msg;
//            
//            _read((uint8_t*)&msg.cmd, sizeof(msg.cmd));
//            i += sizeof(msg.cmd);
//            
//            uint8_t payloadLen = 0;
//            _read(&payloadLen, sizeof(payloadLen));
//            i += sizeof(payloadLen);
//            
//            if (payloadLen) {
//                msg.payload.resize(payloadLen);
//                _read(msg.payload.data(), payloadLen);
//                i += payloadLen;
//            }
//            
//            msgs.push_back(std::move(msg));
//        }
//        
//        return msgs;
//        
//        
////        // Clock in/out a single Nop first, to make DO=0 before the mass read.
////        // Otherwise we'd be clocking out an unknown value on DO during the mass read.
////        const uint8_t nopCmd[] = { 0x31, 0x00, 0x00, (uint8_t)Cmd::Nop };
////        _ftdiWrite(_ftdi, nopCmd, sizeof(nopCmd));
////        len--;
////
////        for (;;) {
////            // If we need more than one additional byte, perform a mass read
////            if (len) {
////                // Clock out `len-off` bytes
////                const uint8_t massReadCmd[] = { 0x20, (uint8_t)((len-1)&0xFF), (uint8_t)(((len-1)&0xFF00)>>8) };
////                _ftdiWrite(_ftdi, massReadCmd, sizeof(massReadCmd));
////            }
////
////            for (;;) {
////                Msg msg;
////                int ir = ftdi_read_data(&_ftdi, buf.data()+off, (int)len);
////                assert(ir>=0 && (size_t)ir<=len);
////                off += ir;
////
////
////                _ftdiRead(_ftdi, &msg.cmd, sizeof(msg.cmd));
////
////            }
////        }
////
////
////        _ftdiWrite(_ftdi, b, sizeof(b));
////
////        buf.resize(Len);
////
////        for (size_t off=0; off<Len;) {
////            const size_t readLen = Len-off;
////            int ir = ftdi_read_data(&_ftdi, buf.data()+off, (int)readLen);
////            printf("ftdi_read_data %d\n", ir);
////            assert(ir>=0 && (size_t)ir<=readLen);
////            off += ir;
////        }
////
//////        for (const uint8_t& b : buf) {
//////            printf("%02x\n", b);
//////        }
////
////        return std::vector<Msg>();
//    }
    
    
    
//    std::vector<Msg> read(const uint16_t len) {
//        size_t off = 0;
//        std::vector<uint8_t> buf;
//        buf.resize(len);
//
//        // Read available data first
//        int ir = ftdi_read_data(&_ftdi, buf.data()+off, (int)len);
//        assert(ir>=0 && (size_t)ir<=len);
//        off += ir;
//
//        while (off < len) {
//            const size_t readLen = len-off;
//
//            // Clock in/out a single Nop first, to make DO=0 before the mass read.
//            // Otherwise we'd be clocking out an unknown value on DO during the mass read.
//            const uint8_t nopCmd[] = { 0x31, 0x00, 0x00, (uint8_t)Cmd::Nop };
//            _ftdiWrite(_ftdi, nopCmd, sizeof(nopCmd));
//
//            // If we need more than one additional byte, perform a mass read
//            if (readLen > 1) {
//                // Clock out `len-off` bytes
//                const uint8_t massReadCmd[] = { 0x20, (uint8_t)((readLen-2)&0xFF), (uint8_t)(((readLen-2)&0xFF00)>>8) };
//                _ftdiWrite(_ftdi, massReadCmd, sizeof(massReadCmd));
//            }
//
//            _ftdiRead(_ftdi, buf.data()+off, readLen);
//        }
//
//        for (size_t i=0;;) {
//            Msg msg;
//            msg.cmd = (Cmd)buf[i];
//            msg.payload = buf[i+1];
//        }
//
//
//        _ftdiWrite(_ftdi, b, sizeof(b));
//
//        buf.resize(Len);
//
//        for (size_t off=0; off<Len;) {
//            const size_t readLen = Len-off;
//            int ir = ftdi_read_data(&_ftdi, buf.data()+off, (int)readLen);
//            printf("ftdi_read_data %d\n", ir);
//            assert(ir>=0 && (size_t)ir<=readLen);
//            off += ir;
//        }
//
////        for (const uint8_t& b : buf) {
////            printf("%02x\n", b);
////        }
//
//        return std::vector<Msg>();
//    }
    
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
    
//    void _read(uint8_t* d, const size_t len) {
//        for (size_t off=0; off<len;) {
//            // Read from the bytes that we've already read from the device
//            const size_t readLen = std::min(len-off, _in.size());
//            memcpy(d+off, _in.data(), readLen);
//            _in.erase(_in.begin(), _in.begin()+readLen);
//            off += readLen;
//
//            // Write Nop's so that we get `len-off` bytes back
//            _write(std::vector<uint8_t>(len-off, (uint8_t)Cmd::Nop));
//        }
//    }
    
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
        
//        printf("_ftdiWrite wrote %d bytes:\n", ir);
//        for (int i=0; i<(int)len; i++) {
//            printf("  [%d] = 0x%x\n", i, d[i]);
//        }
    }
    
public:
//private:
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

//template <typename Unit>
//static uint64_t TimeDuration(TimeInstant t1, TimeInstant t2) {
//    return std::chrono::duration_cast<Unit>(t2-t1).count();
//}

static void PrintMsg(const MDCDevice::Msg& msg) {
    printf("Msg{\n");
    printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
    printf("  payload (len = %ju): [ ", (uintmax_t)msg.payloadLen);
    for (size_t i=0; i<msg.payloadLen; i++) {
        printf("%02x ", msg.payload[i]);
    }
    printf("]\n}\n\n");
}

int main() {
    
//    TimeInstant t1 = CurrentTime();
//    sleep(1);
//    TimeInstant t2 = CurrentTime();
//    printf("ticks: %ju\n", (uintmax_t)TimeDuration(t1, t2));
//    return 0;
    
    using Cmd = MDCDevice::Cmd;
    using Msg = MDCDevice::Msg;
    
    MDCDevice device;
    
//    device.write(Cmd::LEDOn);    
    device.write(Cmd::ReadMem);
    
    const size_t RAMWordCount = 0x2000000;
    const size_t RAMWordSize = 2;
    const size_t RAMSize = RAMWordCount*RAMWordSize;
    
    auto startTime = CurrentTime();
    size_t msgCount = 0;
    size_t totalDataLen = 0;
    for (;;) {
        Msg msg = device.read();
        msgCount++;
        totalDataLen += msg.payloadLen;
        if (!(msgCount % 1000)) {
            printf("msgCount: %ju, totalDataLen: %ju\n", (uintmax_t)msgCount, (uintmax_t)totalDataLen);
//            PrintMsg(msg);
        }
        
        if (totalDataLen >= RAMSize) break;
    }
    auto stopTime = CurrentTime();
    printf("duration: %ju ms\n", (uintmax_t)TimeDurationMs(startTime, stopTime));
    
    return 0;
    
////    // Read 2 bytes to clear effects from ReadMem command
////    {
////        device.write(Cmd::Nop);
////        uint8_t tmp[2];
////        MDCDevice::_ftdiRead(device._ftdi, tmp, 2);
////    }
//    
//    const size_t RAMWordCount = 0x2000000;
//    const size_t RAMWordSize = 2;
//    const size_t RAMSize = RAMWordCount*RAMWordSize;
//    const size_t ChunkSize = 0x10000; // Max read size for a single 0x20 command
//    const size_t ChunkCount = 32;
//    const size_t BufCap = ChunkSize*ChunkCount;
//    std::unique_ptr<uint8_t[]> buf(new uint8_t[BufCap]);
//    size_t bufLen = 0;
//    
//    // Reset pin state before performing mass reads to ensure DO=0
//    device._resetPinState();
//    
//    
//    auto startTime = CurrentTime();
//    
//    uint64_t cumulativeProcessTime = 0;
//    uint64_t cumulativeReadWriteTime = 0;
//    
//    size_t msgCount = 0;
//    size_t totalDataLen = 0;
//    for (;;) {
//        auto readWriteStartTime = CurrentTime();
//        
//        // Create FTDI command to fill the remainder of `buf` with data
//        const size_t massReadLen = BufCap-bufLen;
//        const size_t chunks = massReadLen/ChunkSize;
//        const size_t rem = massReadLen%ChunkSize;
//        uint8_t massReadCmd[(3*chunks) + (rem?3:0)];
//        for (size_t i=0; i<chunks; i++) {
//            massReadCmd[(i*3)+0] = 0x20;
//            massReadCmd[(i*3)+1] = 0xFF;
//            massReadCmd[(i*3)+2] = 0xFF;
//        }
//        
//        if (rem) {
//            massReadCmd[sizeof(massReadCmd)-3] = 0x20;
//            massReadCmd[sizeof(massReadCmd)-2] = (uint8_t)((rem-1)&0xFF);
//            massReadCmd[sizeof(massReadCmd)-1] = (uint8_t)(((rem-1)&0xFF00)>>8);
//        }
//        
//        MDCDevice::_ftdiWrite(device._ftdi, massReadCmd, sizeof(massReadCmd));
//        MDCDevice::_ftdiRead(device._ftdi, buf.get()+bufLen, massReadLen);
//        bufLen += massReadLen;
//        
//        auto readWriteStopTime = CurrentTime();
//        cumulativeReadWriteTime += TimeDuration<std::chrono::nanoseconds>(readWriteStartTime, readWriteStopTime);
//        
//        
//        
//        
//        
//        
//        auto processStartTime = CurrentTime();
//        
//        // Process messages
//        size_t off = 0;
//        for (;;) {
//            size_t o = off;
//            Msg msg;
//            
//            if (bufLen-o < sizeof(msg.cmd)) break;
//            memcpy(&msg.cmd, buf.get()+o, sizeof(msg.cmd));
//            o += sizeof(msg.cmd);
//            
//            if (bufLen-o < sizeof(msg.payloadLen)) break;
//            memcpy(&msg.payloadLen, buf.get()+o, sizeof(msg.payloadLen));
//            o += sizeof(msg.payloadLen);
//            
//            if (bufLen-o < msg.payloadLen) break;
//            msg.payload = buf.get()+o;
//            o += msg.payloadLen;
//            
//            off = o;
//            
//            
//            
//            
//            msgCount++;
//            totalDataLen += msg.payloadLen;
//            if (!(msgCount % 1000)) {
////                printf("msgCount: %ju, totalDataLen: %ju\n", (uintmax_t)msgCount, (uintmax_t)totalDataLen);
////                PrintMsg(msg);
//            }
//            
////            PrintMsg(msg);
//        }
//        
//        // Move the remaining partial message at the end of the buffer (pointed
//        // to by `off`) to the beginning of the buffer.
//        bufLen -= off;
//        memmove(buf.get(), buf.get()+off, bufLen);
//        
//        auto processStopTime = CurrentTime();
//        cumulativeProcessTime += TimeDuration<std::chrono::nanoseconds>(processStartTime, processStopTime);
//        
//        if (totalDataLen >= RAMSize) {
//            break;
//        }
//    }
//    
//    auto stopTime = CurrentTime();
//    
//    printf("totalDataLen: %ju\n", (uintmax_t)totalDataLen);
//    printf("cumulativeReadWriteTime: %ju ns\n", (uintmax_t)cumulativeReadWriteTime);
//    printf("cumulativeProcessTime: %ju ns\n", (uintmax_t)cumulativeProcessTime);
//    printf("duration: %ju ms\n", (uintmax_t)TimeDuration<std::chrono::milliseconds>(startTime, stopTime));
//    
//    return 0;
//    
//    
////    printf("HALLO\n");
////
////
////    {
////        const uint8_t cmd[] = {0x31, 0x05, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00};
////        MDCDevice::_ftdiWrite(device._ftdi, cmd, sizeof(cmd));
////    }
////
////    {
////        sleep(1);
////        uint8_t tmp[128];
////        int ir = ftdi_read_data(&device._ftdi, tmp, sizeof(tmp));
////        assert(ir >= 0);
////        printf("Read data:\n");
////        for (int i=0; i<ir; i++) {
////            printf("  [%d]: %jx\n", i, (uintmax_t)tmp[i]);
////        }
////    }
//    
////    for (int i=0; i<10; i++) {
////        device.read();
////    }
//    
////    device.write(Cmd::LEDOn);
////    device.read();
////    device.read();
////    device.read();
//    
//    for (;;) {
//        
////        device.write(Cmd::LEDOn);
//        device.write(Cmd::ReadMem);
//        
////        device.write(Cmd::Nop);
//        
////        std::optional<uint16_t> lastVal;
////
//        uint32_t len = 0;
//        uint32_t msgCount = 0;
//        const size_t bufCap = 0x10000*32;
//        std::unique_ptr<uint8_t[]> buf(new uint8_t[bufCap]);
//        
//        for (;;) {
//            // Clock out `len` bytes
//            const uint8_t massReadCmd[] = {
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//                0x20, 0xFF, 0xFF,
//            };
//            
//            MDCDevice::_ftdiWrite(device._ftdi, massReadCmd, sizeof(massReadCmd));
//            MDCDevice::_ftdiRead(device._ftdi, buf.get(), bufCap);
//            len += bufCap/2;
//            
////            std::vector<Msg> msgs;
////            for (size_t i=0; i<bufCap; i++) {
////                Msg msg;
////                if (bufCap-i < sizeof(msg.cmd)) break;
////                memcpy(&msg.cmd, buf.get()+i, sizeof(msg.cmd));
////
////            }
//            
//            msgCount++;
//            if (!(msgCount % 1)) {
//                printf("%.1f%% complete (%d / %d words)\n", ((float)len/RAMSize)*100, len, RAMSize);
//            }
//            
////            auto msgs = device.read(0xFFFF);
////            for (const Msg& msg : msgs) {
////                if (msg.cmd == Cmd::ReadMem) {
//////                    printf("Msg{\n");
//////                    printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
//////                    printf("  payload: [ ");
//////                    for (const uint8_t& x : msg.payload) {
//////                        printf("%02x ", x);
//////                    }
//////                    printf("]\n}\n\n");
////                    len += msg.payload.size()/2;
////                }
//////                else {
//////                    // Check if our read memory packets ever get interrupted by a NOP or some other packet type
//////                    if (len) {
//////                        abort();
//////                    }
//////                }
////
////                if (len) {
////                    msgCount++;
////                    if (!(msgCount % 1000)) {
////                        printf("%.1f%% complete (%d / %d words)\n", ((float)len/TotalLen)*100, len, TotalLen);
////                    }
////                }
////            }
//            
////            MDCDevice::Msg msg = device.read();
////            if (msg.cmd == Cmd::ReadMem) {
////                assert(!(msg.payload.size() % 2));
////                const size_t valsLen = msg.payload.size()/2;
////                uint16_t vals[valsLen];
////                memcpy(vals, msg.payload.data(), msg.payload.size());
////
//////                printf("Msg{\n");
//////                printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
//////                printf("  payload: [ ");
//////                for (const uint8_t& x : msg.payload) {
//////                    printf("%02x ", x);
//////                }
//////                printf("]\n}\n\n");
////
////                for (const uint16_t& val : vals) {
//////                    printf("%x %x\n", val, *lastVal);
////                    if (lastVal) {
////                        assert(val == (uint16_t)((*lastVal)+1)); // Cast to force overflow
////                    }
////                    lastVal = val;
////                }
////
////                len += valsLen;
////                printf("%.1f complete\n", ((float)len/TotalLen)*100);
////
//////                printf("DATA VALID\n");
////            }
////
////            if (msg.cmd == Cmd::ReadMem) {
////                size_t i = 0;
////                assert(msg.payload.size() == 254);
////                for (const uint8_t& x : msg.payload) {
////                    if (i % 2) assert(x == 0);
////                    else assert(x == i/2);
////                    i++;
////                }
////                printf("DATA VALID\n");
//////                break;
////            }
//        }
//        
////        {
////            uint8_t tmp[10];
////            device._read(tmp, sizeof(tmp));
////            printf("Read data:\n");
////            for (int i=0; i<(int)sizeof(tmp); i++) {
////                printf("  [%d]: %jx\n", i, (uintmax_t)tmp[i]);
////            }
////        }
//        
////        for (int i=0; i<10; i++) {
////            MDCDevice::Msg msg = device.read();
////            printf("Msg{\n");
////            printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
////            printf("  payload: [ ");
////            for (const uint8_t& x : msg.payload) {
////                printf("%02x ", x);
////            }
////            printf("]\n}\n\n");
////            usleep(100000);
////        }
//        
//        
////        device.write(Cmd::LEDOn);
////        device.write(Cmd::LEDOff);
////
////        for (int i=0; i<2; i++) {
////            MDCDevice::Msg msg = device.read();
////            printf("Msg{\n");
////            printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
////            printf("  payload: [ ");
////            for (const uint8_t& x : msg.payload) {
////                printf("%02x ", x);
////            }
////            printf("]\n}\n\n");
////            usleep(100000);
////        }
//        
////        device.write(Cmd::ReadMem);
//        
////        {
////            uint8_t tmp[10];
////            device._read(tmp, sizeof(tmp));
////            printf("Read data:\n");
////            for (int i=0; i<(int)sizeof(tmp); i++) {
////                printf("  [%d]: %jx\n", i, (uintmax_t)tmp[i]);
////            }
////        }
//        
////        for (;;) {
////            MDCDevice::Msg msg = device.read();
////            printf("Msg{\n");
////            printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
////            printf("  payload: [ ");
////            for (const uint8_t& x : msg.payload) {
////                printf("%02x ", x);
////            }
////            printf("]\n}\n\n");
////            usleep(100000);
////        }
//        
//        
//        
//        
////
//////        for (int i=0; i<3; i++) {
//////            MDCDevice::Msg msg = device.read();
//////            printf("Msg{\n");
//////            printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
//////            printf("  payload: [ ");
//////            for (const uint8_t& x : msg.payload) {
//////                printf("%02x ", x);
//////            }
//////            printf("]\n}\n\n");
//////        }
//        
//        
//        
//        
////        static bool on = true;
////        const Cmd cmd = (on ? Cmd::LEDOn : Cmd::LEDOff);
////        device.write(cmd);
////        printf("led = %d\n", on);
////        on = !on;
//        
////        {
////            uint8_t tmp[20];
////            device._read(tmp, sizeof(tmp));
////            printf("Read data:\n");
////            for (int i=0; i<(int)sizeof(tmp); i++) {
////                printf("  [%d]: %jx\n", i, (uintmax_t)tmp[i]);
////            }
////        }
////        usleep(1000000);
//        
////        for (;;) {
////            MDCDevice::Msg msg = device.read();
////            printf("Msg{\n");
////            printf("  cmd: 0x%jx\n", (uintmax_t)msg.cmd);
////            printf("  payload: [ ");
////            for (const uint8_t& x : msg.payload) {
////                printf("%02x ", x);
////            }
////            printf("]\n}\n\n");
////            if (msg.cmd == cmd) break;
////        }
////        usleep(1000000);
//
//        
//        
//        
//////        device.write(Cmd::Nop);
//////        printf("led = %d\n", on);
////
//////        msg = device.read();
//////        printf("Msg{cmd: 0x%jx, payload len: %ju}\n",
//////            (uintmax_t)msg.cmd, (uintmax_t)msg.payload.size());
////
////        usleep(1000000);
//
////        usleep(1000000);
//    }
//    
//    return 0;
}

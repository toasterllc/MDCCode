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
#include <inttypes.h>
#include <fstream>

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
    struct MsgHdr {
        MsgType type = 0;
        uint8_t len = 0;
    };
    
    struct Msg {
        template <typename T>
        static std::unique_ptr<T> Cast(std::unique_ptr<Msg> msg) {
            if (msg && msg->hdr.type == T{}.hdr.type) return std::unique_ptr<T>((T*)msg.release());
            return nullptr;
        }
        
        template <typename T>
        static T* Cast(Msg* msg) {
            if (msg->hdr.type == T{}.hdr.type) return (T*)msg;
            return nullptr;
        }
        
        MsgHdr hdr{.type=0x00, .len=sizeof(*this)-sizeof(MsgHdr)};
    } __attribute__((packed));
    
    struct SetLEDMsg {
        MsgHdr hdr{.type=0x01, .len=sizeof(*this)-sizeof(MsgHdr)};
//        uint8_t on = 0;
        uint8_t payload[255];
    } __attribute__((packed));
    
    struct ReadMemMsg {
        MsgHdr hdr{.type=0x02, .len=0}; // Special case `len` in this case
        uint8_t* mem = nullptr;
        
        std::string desc() const {
            std::stringstream d;
            
            d << std::setfill('0') << std::setw(2);
            
            d << "ReadMemMsg{\n";
            d << "  type: 0x" << std::hex << (uintmax_t)hdr.type << "\n";
            d << "  payload (len = " << std::dec << (uintmax_t)hdr.len << "): [ ";
            for (size_t i=0; i<hdr.len; i++) {
                d << std::hex << (uintmax_t)mem[i] << " ";
            }
            d << "]\n}\n\n";
            return d.str();
        }
    } __attribute__((packed));
    
    struct PixReg8Msg {
        MsgHdr hdr{.type=0x03, .len=sizeof(*this)-sizeof(MsgHdr)};
        uint8_t write = 0;
        uint16_t addr = 0;
        uint8_t val = 0;
        uint8_t ok = 0;
    } __attribute__((packed));
    
    struct PixReg16Msg {
        MsgHdr hdr{.type=0x04, .len=sizeof(*this)-sizeof(MsgHdr)};
        uint8_t write = 0;
        uint16_t addr = 0;
        uint16_t val = 0;
        uint8_t ok = 0;
    } __attribute__((packed));
    
    using MsgPtr = std::unique_ptr<Msg>;
    
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
    
    template <typename T>
    void write(const T& msg) {
        const size_t msgSize = sizeof(msg.hdr)+msg.hdr.len;
        uint8_t b[] = {0x31, (uint8_t)((msgSize-1)&0xFF), (uint8_t)(((msgSize-1)&0xFF00)>>8)};
        _ftdiWrite(_ftdi, b, sizeof(b));
        _ftdiWrite(_ftdi, (uint8_t*)&msg, msgSize);
        
        // Verify that we don't overflow _inPending
        assert(SIZE_MAX-_inPending >= msgSize);
        _inPending += msgSize;
    }
    
    template <typename T>
    MsgPtr _newMsg() { return std::unique_ptr<Msg>((Msg*)new T{}); };
    
    MsgPtr _newMsg(MsgType type) {
        if (type == Msg{}.hdr.type) return _newMsg<Msg>();
        if (type == SetLEDMsg{}.hdr.type) return _newMsg<SetLEDMsg>();
        if (type == ReadMemMsg{}.hdr.type) return _newMsg<ReadMemMsg>();
        if (type == PixReg8Msg{}.hdr.type) return _newMsg<PixReg8Msg>();
        if (type == PixReg16Msg{}.hdr.type) return _newMsg<PixReg16Msg>();
        printf("Unknown msg type: %ju\n", (uintmax_t)type);
        return nullptr;
    }
    
    MsgPtr _readMsg() {
        // Find the first non-zero byte, denoting the first message
        size_t off = _inOff;
        for (; off<_inLen; off++) {
            if (_in[off]) break;
        }
        
        MsgHdr hdr;
        if (_inLen-off < sizeof(hdr)) return nullptr;
        memcpy(&hdr, _in+off, sizeof(hdr));
        off += sizeof(hdr);
        
        if (_inLen-off < hdr.len) return nullptr;
        
        MsgPtr msg = _newMsg(hdr.type);
        assert(msg);
        
        // Verify that the incoming message has enough data to fill the type that it claims to be
        assert(hdr.len >= msg->hdr.len);
        
        // Copy the payload into the message, but only the number of bytes that we expect the message to have.
        memcpy(((uint8_t*)msg.get())+sizeof(MsgHdr), _in+off, msg->hdr.len);
        
        // Handle special message types that contain variable amounts of data
        if (auto x = Msg::Cast<ReadMemMsg>(msg.get())) {
            x->hdr.len = hdr.len;
            x->mem = _in+off;
        }
        
        off += hdr.len;
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
            sizeof(MsgHdr) +
            std::numeric_limits<decltype(MsgHdr::len)>::max();
        
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
            _resetPins();
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
//                for (size_t i=0; i<1024; i++) {
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
//    uint8_t _in[0x400];
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

using Cmd = std::string;
const Cmd SetLEDCmd = "setled";
const Cmd ReadMemCmd = "readmem";
const Cmd VerifyMemCmd = "verifymem";
const Cmd PixReg8Cmd = "pixreg8";
const Cmd PixReg16Cmd = "pixreg16";

void printUsage() {
    using namespace std;
    cout << "MDCDebugger commands:\n";
    cout << " " << SetLEDCmd    << " <0/1>\n";
    cout << " " << ReadMemCmd   << " <file>\n";
    cout << " " << VerifyMemCmd << "\n";
    cout << " " << PixReg8Cmd   << " <addr>\n";
    cout << " " << PixReg8Cmd   << " <addr>=<val8>\n";
    cout << " " << PixReg16Cmd  << " <addr>\n";
    cout << " " << PixReg16Cmd  << " <addr>=<val16>\n";
    cout << "\n";
}

struct RegOp {
    bool write = false;
    uint16_t addr = 0;
    uint16_t val = 0;
};

struct Args {
    Cmd cmd;
    bool on = false;
    std::string filePath;
    RegOp regOp;
};

static RegOp parseRegOp(const std::string str) {
    std::stringstream ss(str);
    std::string part;
    std::vector<std::string> parts;
    while (std::getline(ss, part, '=')) parts.push_back(part);
    
    RegOp regOp;
    
    uintmax_t addr = strtoumax(parts[0].c_str(), nullptr, 0);
    if (addr > UINT16_MAX) throw std::runtime_error("invalid register address");
    regOp.addr = addr;
    
    if (parts.size() > 1) {
        uintmax_t val = strtoumax(parts[1].c_str(), nullptr, 0);
        if (val > UINT16_MAX) throw std::runtime_error("invalid register value");
        regOp.write = true;
        regOp.val = addr;
    }
    
    return regOp;
}

static Args parseArgs(int argc, const char* argv[]) {
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = strs[0];
    
    if (args.cmd == SetLEDCmd) {
        if (strs.size() < 2) throw std::runtime_error("on/off state not specified");
        args.on = atoi(strs[1].c_str());
    
    } else if (args.cmd == ReadMemCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else if (args.cmd == VerifyMemCmd) {
    
    } else if (args.cmd == PixReg8Cmd) {
        if (strs.size() < 2) throw std::runtime_error("no register specified");
        args.regOp = parseRegOp(strs[1]);
        
        // Verify that the register value is a valid uint8
        if (args.regOp.val > UINT8_MAX) throw std::runtime_error("invalid register value");
    
    } else if (args.cmd == PixReg16Cmd) {
        if (strs.size() < 2) throw std::runtime_error("no register specified");
        args.regOp = parseRegOp(strs[1]);
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void setLED(const Args& args, MDCDevice& device) {
    using SetLEDMsg = MDCDevice::SetLEDMsg;
    using Msg = MDCDevice::Msg;
//    device.write(SetLEDMsg{.on = args.on});
//    for (;;) {
//        if (auto msgPtr = Msg::Cast<SetLEDMsg>(device.read())) {
//            return;
//        }
//    }
    
    device.write(SetLEDMsg{});
    for (size_t msgCount=0;;) {
        if (auto msgPtr = Msg::Cast<SetLEDMsg>(device.read())) {
            const auto& msg = *msgPtr;
            for (size_t i=0; i<sizeof(msg.payload); i++) {
                uint8_t val = msg.payload[i];
                uint8_t expected = 255-i;
                if (val != expected) {
                    fprintf(stderr, "Error: value mismatch: expected 0x%jx, got 0x%jx\n", (uintmax_t)expected, (uintmax_t)val);
                }
            }
            
            msgCount++;
            if (!(msgCount % 1000)) {
                printf("Message count: %ju\n", (uintmax_t)msgCount);
            }
        }
    }
}

const size_t RAMWordCount = 127*3;
const size_t RAMWordSize = 2;
const size_t RAMSize = RAMWordCount*RAMWordSize;

static void readMem(const Args& args, MDCDevice& device) {
    using ReadMemMsg = MDCDevice::ReadMemMsg;
    using Msg = MDCDevice::Msg;
    
    std::ofstream outputFile(args.filePath.c_str(), std::ofstream::out|std::ofstream::binary|std::ofstream::trunc);
    if (!outputFile) {
        throw std::runtime_error("failed to open output file: " + args.filePath);
    }
    
    device.write(ReadMemMsg{});
    size_t dataLen = 0;
    for (size_t msgCount=0; dataLen<RAMSize;) {
        if (auto msgPtr = Msg::Cast<ReadMemMsg>(device.read())) {
            const auto& msg = *msgPtr;
            outputFile.write((char*)msg.mem, msg.hdr.len);
            if (!outputFile) throw std::runtime_error("failed to write to output file");
            
            dataLen += msg.hdr.len;
            
            msgCount++;
            if (!(msgCount % 1000)) {
                printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)dataLen);
            }
        }
    }
    
    if (dataLen != RAMSize) {
        throw std::runtime_error("data length mismatch: expected "
            + std::to_string(RAMSize) + ", got " + std::to_string(dataLen));
    }
}

static void verifyMem(const Args& args, MDCDevice& device) {
    using ReadMemMsg = MDCDevice::ReadMemMsg;
    using Msg = MDCDevice::Msg;
    device.write(ReadMemMsg{});
    
    bool ok = true;
    auto startTime = CurrentTime();
    size_t dataLen = 0;
    std::optional<uint16_t> lastVal;
    for (size_t msgCount=0; dataLen<RAMSize; msgCount++) {
        if (auto msgPtr = Msg::Cast<ReadMemMsg>(device.read())) {
            const auto& msg = *msgPtr;
            if (!(msg.hdr.len % 2)) {
                for (size_t i=0; i<msg.hdr.len; i+=2) {
                    uint16_t val;
                    memcpy(&val, msg.mem+i, sizeof(val));
                    if (lastVal) {
                        uint16_t expected = (uint16_t)(*lastVal+1);
                        if (val != expected) {
                            fprintf(stderr, "Error: value mismatch: expected 0x%jx, got 0x%jx\n", (uintmax_t)expected, (uintmax_t)val);
                            ok = false;
                        }
                    }
                    lastVal = val;
                }
            } else {
                fprintf(stderr, "Error: payload length invalid: expected even, got odd (0x%ju)\n", (uintmax_t)msg.hdr.len);
                ok = false;
            }
            
            dataLen += msg.hdr.len;
            if (!(msgCount % 1000)) {
                printf("Message count: %ju, data length: %ju\n", (uintmax_t)msgCount, (uintmax_t)dataLen);
            }
        }
    }
    auto stopTime = CurrentTime();
    
    if (dataLen != RAMSize) {
        fprintf(stderr, "Error: data length mismatch: expected 0x%jx, got 0x%jx\n",
            (uintmax_t)RAMSize, (uintmax_t)dataLen);
        ok = false;
    }
    
    printf("Memory verification finished; duration: %ju ms\n",
        (uintmax_t)TimeDurationMs(startTime, stopTime));
    
    if (!ok) throw std::runtime_error("memory verification failed");
}

static void pixReg8(const Args& args, MDCDevice& device) {
    using PixReg8Msg = MDCDevice::PixReg8Msg;
    using Msg = MDCDevice::Msg;
    
    device.write(PixReg8Msg{
        .write = args.regOp.write,
        .addr = args.regOp.addr,
        .val = (uint8_t)args.regOp.val,
    });
    
    if (auto msgPtr = Msg::Cast<PixReg8Msg>(device.read())) {
        const auto& msg = *msgPtr;
        if (msg.ok) {
            if (!args.regOp.write) {
                printf("0x%04x = 0x%02x\n", msg.addr, msg.val);
            }
        } else {
            throw std::runtime_error("i2c transaction failed");
        }
        return;
    }
}

static void pixReg16(const Args& args, MDCDevice& device) {
    using PixReg16Msg = MDCDevice::PixReg16Msg;
    using Msg = MDCDevice::Msg;
    
    device.write(PixReg16Msg{
        .write = args.regOp.write,
        .addr = args.regOp.addr,
        .val = args.regOp.val,
    });
    
    if (auto msgPtr = Msg::Cast<PixReg16Msg>(device.read())) {
        const auto& msg = *msgPtr;
        if (msg.ok) {
            if (!args.regOp.write) {
                printf("0x%04x = 0x%04x\n", msg.addr, msg.val);
            }
        } else {
            throw std::runtime_error("i2c transaction failed");
        }
        return;
    }
}

int main(int argc, const char* argv[]) {
    Args args;
    try {
        args = parseArgs(argc-1, argv+1);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
        printUsage();
        return 1;
    }
    
    auto device = std::make_unique<MDCDevice>();
    
    try {
        if (args.cmd == SetLEDCmd)          setLED(args, *device);
        else if (args.cmd == ReadMemCmd)    readMem(args, *device);
        else if (args.cmd == VerifyMemCmd)  verifyMem(args, *device);
        else if (args.cmd == PixReg8Cmd)    pixReg8(args, *device);
        else if (args.cmd == PixReg16Cmd)   pixReg16(args, *device);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

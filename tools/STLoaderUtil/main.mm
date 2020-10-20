#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <vector>

enum {
    STLoaderCmdOp_None,
    STLoaderCmdOp_LEDSet,
    STLoaderCmdOp_WriteData,
    STLoaderCmdOp_Reset,
}; typedef uint8_t STLoaderCmdOp;

typedef struct __attribute__((packed)) {
    STLoaderCmdOp op;
    union {
        struct {
            uint8_t idx;
            uint8_t on;
        } ledSet;
        
        struct {
            uint32_t addr;
        } writeData;
        
        struct {
            uint32_t vectorTableAddr;
        } reset;
    } arg;
} STLoaderCmd;

_Static_assert(sizeof(STLoaderCmd)==5, "STLoaderCmd: invalid size");

class SendRight {
public:
    // Default constructor: empty
    SendRight() {}
    // Constructor: assume ownership of a send right
    SendRight(mach_port_t port) : _port(port) {}
    // Copy constructor: illegal
    SendRight(const SendRight&) = delete;
    // Move constructor: use move assignment operator
    SendRight(SendRight&& x) { *this = std::move(x); }
    // Move assignment operator
    SendRight& operator=(SendRight&& x) {
        reset();
        _port = x._port;
        x._port = MACH_PORT_NULL;
        return *this;
    }
    
    ~SendRight() {
        reset();
    }
    
    mach_port_t port() const {
        // We must have a valid port, otherwise blow up
        assert(*this);
        return _port;
    }
    
    operator bool() const { return MACH_PORT_VALID(_port); }
    
    void reset() {
        if (*this) {
//            printf("SendRight dealloc (port: 0x%jx)\n", (uintmax_t)_port);
            kern_return_t kr = mach_port_deallocate(mach_task_self(), _port);
            assert(kr == KERN_SUCCESS);
            _port = MACH_PORT_NULL;
        }
    }
    
private:
    mach_port_t _port = MACH_PORT_NULL;
};

class USBInterface {
public:
    // Default constructor: empty
    USBInterface() {}
    
    // Constructor: take ownership of a IOUSBInterfaceInterface
    USBInterface(IOUSBInterfaceInterface** interface) {
        set(interface);
    }
    
    // Copy constructor: illegal
    USBInterface(const USBInterface&) = delete;
    // Move constructor: use move assignment operator
    USBInterface(USBInterface&& x) { *this = std::move(x); }
    // Move assignment operator
    USBInterface& operator=(USBInterface&& x) {
        // Retain the interface on behalf of `set`
        auto interface = x._interface;
        if (interface) (*interface)->AddRef(interface);
        
        x.set(nullptr); // Reset x's interface first, so that it calls USBInterfaceClose before we call USBInterfaceOpen
        set(interface);
        return *this;
    }
    
    ~USBInterface() {
        set(nullptr);
    }
    
    IOUSBInterfaceInterface** interface() {
        assert(_interface);
        return _interface;
    }
    
    operator bool() const { return _interface; }
    
    IOReturn write(uint8_t pipe, void* buf, size_t len) {
        assert(_interface);
        _openIfNeeded();
        return (*_interface)->WritePipe(_interface, pipe, buf, (uint32_t)len);
    }
    
    std::tuple<size_t, IOReturn> read(uint8_t pipe, void* buf, size_t len) {
        assert(_interface);
        _openIfNeeded();
        uint32_t len32 = (uint32_t)len;
        IOReturn ior = (*_interface)->ReadPipe(_interface, pipe, buf, &len32);
        return std::make_tuple(len32, ior);
    }
    
    // Take ownership of a IOUSBInterfaceInterface
    void set(IOUSBInterfaceInterface** interface) {
        if (_interface) {
            if (_open) (*_interface)->USBInterfaceClose(_interface);
            (*_interface)->Release(_interface);
        }
        
        _interface = interface;
        _open = false;
    }
    
private:
    void _openIfNeeded() {
        if (!_open) {
            (*_interface)->USBInterfaceOpen(_interface);
            _open = true;
        }
    }
    
    IOUSBInterfaceInterface** _interface = nullptr;
    bool _open = false;
};

static USBInterface findUSBInterface(uint8_t interfaceNum) {
    NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBInterfaceClassName));
    match[@kIOPropertyMatchKey] = @{
        @"bInterfaceNumber": @(interfaceNum),
        @"idVendor": @1155,
        @"idProduct": @57105,
    };
    
    io_iterator_t ioServicesIter = MACH_PORT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFDictionaryRef)CFBridgingRetain(match), &ioServicesIter);
    if (kr != KERN_SUCCESS) throw std::runtime_error("IOServiceGetMatchingServices failed");
    
    SendRight servicesIter(ioServicesIter);
    std::vector<SendRight> services;
    while (servicesIter) {
        SendRight service(IOIteratorNext(servicesIter.port()));
        if (!service) break;
        services.push_back(std::move(service));
    }
    
    // Confirm that we have exactly one matching service
    if (services.empty()) throw std::runtime_error("no matching services");
    if (services.size() != 1) throw std::runtime_error("more than 1 matching service");
    
    SendRight& service = services[0];
    
    IOCFPlugInInterface** plugin = nullptr;
    SInt32 score = 0;
    kr = IOCreatePlugInInterfaceForService(service.port(), kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
    if (!plugin) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
    
    IOUSBInterfaceInterface** usbInterface = nullptr;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&usbInterface);
    if (hr) throw std::runtime_error("QueryInterface failed");
    (*plugin)->Release(plugin);
    
    return USBInterface(usbInterface);
}


namespace Endpoint {
    // These values aren't the same as the endpoint addresses in firmware!
    // These values are the determined by the order that the endpoints are
    // listed in the interface descriptor.
    const uint8_t STCmdOut = 1;
    const uint8_t STCmdIn = 2;
    const uint8_t STDataOut = 3;
}


//namespace Endpoint {
//    
//};
//
//using Endpoint = uint8_t;
//
//const Endpoint STCmdOut = 1;
//const Endpoint STCmdIn = 1;
//const Endpoint STCmdIn = 1;
//
//#define ENDPOINT ST_CMD_OUT_ENDPOINT     1
//#define ST_CMD_IN_ENDPOINT     1


















#import <string>
#import <iostream>
#import <IOKit/IOKitLib.h>
using Cmd = std::string;
const Cmd LEDSetCmd = "ledset";
const Cmd STLoadCmd = "stload";
const Cmd ICELoadCmd = "iceload";

void printUsage() {
    using namespace std;
    cout << "STLoaderUtil commands:\n";
    cout << " " << LEDSetCmd    << " <idx> <0/1>\n";
    cout << " " << STLoadCmd    << " <file>\n";
    cout << " " << ICELoadCmd   << " <file>\n";
    cout << "\n";
}

struct Args {
    Cmd cmd;
    struct {
        uint8_t idx;
        uint8_t on;
    } ledSet;
    std::string filePath;
};

static Args parseArgs(int argc, const char* argv[]) {
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = strs[0];
    
    if (args.cmd == LEDSetCmd) {
        if (strs.size() < 3) throw std::runtime_error("LED index/state not specified");
        args.ledSet.idx = std::stoi(strs[1]);
        args.ledSet.on = std::stoi(strs[2]);
    
    } else if (args.cmd == STLoadCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else if (args.cmd == ICELoadCmd) {
        if (strs.size() < 2) throw std::runtime_error("file path not specified");
        args.filePath = strs[1];
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void ledSet(const Args& args, USBInterface& stInterface) {
    STLoaderCmd cmd = {
        .op = STLoaderCmdOp_LEDSet,
        .arg = {
            .ledSet = {
                .idx = args.ledSet.idx,
                .on = args.ledSet.on,
            },
        },
    };
    
    IOReturn ior = stInterface.write(Endpoint::STCmdOut, &cmd, sizeof(cmd));
    if (ior != kIOReturnSuccess) throw std::runtime_error("pipe write failed");
}

static void stLoad(const Args& args, USBInterface& stInterface) {
}

static void iceLoad(const Args& args, USBInterface& stInterface) {
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
    
    USBInterface stInterface;
    try {
        stInterface = findUSBInterface(0);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get ST interface: %s\n", e.what());
        return 1;
    }
    
    try {
        if (args.cmd == LEDSetCmd)          ledSet(args, stInterface);
        else if (args.cmd == STLoadCmd)     stLoad(args, stInterface);
        else if (args.cmd == ICELoadCmd)    iceLoad(args, stInterface);
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

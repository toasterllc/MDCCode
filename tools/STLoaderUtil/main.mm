#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <vector>

enum {
    STM32LoaderCmdOp_None,
    STM32LoaderCmdOp_SetLED,
    STM32LoaderCmdOp_WriteData,
    STM32LoaderCmdOp_Reset,
}; typedef uint8_t STM32LoaderCmdOp;

typedef struct __attribute__((packed)) {
    STM32LoaderCmdOp op;
    union {
        struct {
            uint8_t idx;
            uint8_t on;
        } setLED;
        
        struct {
            uint32_t addr;
        } writeData;
        
        struct {
            uint32_t vectorTableAddr;
        } reset;
    } arg;
} STM32LoaderCmd;

_Static_assert(sizeof(STM32LoaderCmd)==5, "STM32LoaderCmd: invalid size");

class SendRight {
public:
    // Default constructor: empty
    SendRight() {}
    // Assume ownership of a send right
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
            printf("SendRight dealloc (port: 0x%jx)\n", (uintmax_t)_port);
            kern_return_t kr = mach_port_deallocate(mach_task_self(), _port);
            assert(kr == KERN_SUCCESS);
            _port = MACH_PORT_NULL;
        }
    }
    
private:
    mach_port_t _port = MACH_PORT_NULL;
};

#define STM32_ENDPOINT_CMD_OUT      0x01    // OUT endpoint
#define STM32_ENDPOINT_CMD_IN       0x81    // IN endpoint


int main(int argc, const char* argv[]) {
    NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBInterfaceClassName));
    match[@kIOPropertyMatchKey] = @{
        @"bInterfaceNumber": @0,
        @"idVendor": @1155,
        @"idProduct": @57105,
    };
    
    io_iterator_t ioServicesIter = MACH_PORT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFDictionaryRef)CFBridgingRetain(match), &ioServicesIter);
    assert(kr == KERN_SUCCESS);
    SendRight servicesIter(ioServicesIter);
    std::vector<SendRight> services;
    while (servicesIter) {
        SendRight service(IOIteratorNext(servicesIter.port()));
        if (!service) break;
        services.push_back(std::move(service));
    }
    
    for (SendRight& service : services) {
        printf("Matching service: 0x%jx\n", (uintmax_t)service.port());
    }
    
    // Confirm that we have exactly one matching service
    assert(services.size() == 1);
    SendRight& service = services[0];
    
    IOCFPlugInInterface** plugin = nullptr;
    SInt32 score = 0;
    kr = IOCreatePlugInInterfaceForService(service.port(), kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    assert(kr == KERN_SUCCESS);
    assert(plugin);
    
    IOUSBInterfaceInterface** usbInterface = nullptr;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&usbInterface);
    assert(!hr);
    (*plugin)->Release(plugin);
    
    kr = (*usbInterface)->USBInterfaceOpen(usbInterface);
    assert(kr == KERN_SUCCESS);
    
    {
        STM32LoaderCmd cmd = {
            .op = STM32LoaderCmdOp_SetLED,
            .arg = {
                .setLED = {
                    .idx = 3,
                    .on = 1,
                },
            },
        };
        
        IOReturn ior = (*usbInterface)->WritePipe(usbInterface, STM32_ENDPOINT_CMD_OUT, &cmd, sizeof(cmd));
        printf("WritePipe result: 0x%x\n", ior);
    }
    
//    {
//        uint8_t numEndpoints = 0;
//        IOReturn ior = (*usbInterface)->GetNumEndpoints(usbInterface, &numEndpoints);
//        printf("GetNumEndpoints result: 0x%x (numEndpoints: %ju)\n", ior, (uintmax_t)numEndpoints);
//        kIOUSBPipeStalled;
//    }
    
    
    {
        uint8_t buf[1024] = {};
        uint32_t bufLen = sizeof(buf);
        IOReturn ior = (*usbInterface)->ReadPipe(usbInterface, 2, &buf, &bufLen);
        printf("ReadPipe result: 0x%x (data: %s)\n", ior, buf);
        kIOUSBPipeStalled;
    }

//    {
//        uint8_t direction, number, transferType, interval;
//        uint16_t maxPacketSize;
//        IOReturn ior = (*usbInterface)->GetPipeProperties(usbInterface, 0, &direction, &number, &transferType, &maxPacketSize, &interval);
//        printf("GetPipeProperties result: 0x%x\n", ior);
//    }
    
    
    
//    {
//        IOReturn ior = (*usbInterface)->ResetPipe(usbInterface, STM32_ENDPOINT_CMD_OUT);
//        printf("ResetPipe result: 0x%x\n", ior);
//    }
//    
//    {
//        IOReturn ior = (*usbInterface)->ClearPipeStallBothEnds(usbInterface, STM32_ENDPOINT_CMD_OUT);
//        printf("ClearPipeStallBothEnds result: 0x%x\n", ior);
//    }
//    
//    {
//        uint32_t state = 0;
//        IOReturn ior = (*usbInterface)->WritePipe(usbInterface, STM32_ENDPOINT_CMD_OUT, &state, 2);
//        printf("WritePipe result: 0x%x\n", ior);
//    }
//    
//    {
//        IOReturn ior = (*usbInterface)->GetPipeStatus(usbInterface, STM32_ENDPOINT_CMD_OUT);
//        printf("GetPipeStatus result: 0x%x (%s)\n", ior, (ior==kIOUSBPipeStalled ? "kIOUSBPipeStalled" : "unknown"));
//    }
    
    return 0;
}

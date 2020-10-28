#include "GPIO.h"
#include "USB.h"
#include "QSPI.h"
#include "STLoaderTypes.h"

using namespace STLoader;

class System {
public:
    System();
    void init();
    void handleEvent();
    
    // Peripherals
    USB usb;
    QSPI qspi;
    
private:
    void _usbHandleEvent(const USB::Event& ev);
    void _iceHandleQSPIEvent(const QSPI::Event& ev);
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
};

extern System Sys;

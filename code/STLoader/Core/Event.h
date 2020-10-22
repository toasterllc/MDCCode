#include "Channel.h"
#include "STLoaderTypes.h"

struct Event {
    enum class Type : uint8_t {
        None,
        USBDataOut
    };
    
    Type type;
    
    union {
        struct {
            uint8_t endpoint;
            uint8_t* data;
            size_t dataLen;
        } USBDataOut;
    } arg;
};

extern Channel<Event,3> Events;

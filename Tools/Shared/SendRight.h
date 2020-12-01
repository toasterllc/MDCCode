#pragma once
#include <mach/port.h>

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

#pragma once
#include <mach/port.h>

class SendRight {
public:
    struct RetainType {}; static constexpr auto Retain = RetainType();
    
    // Default constructor: empty
    SendRight() {}
    // Constructor: assume ownership of a send right
    SendRight(mach_port_t port) : _port(port) {}
    // Constructor: retain a send right
    SendRight(RetainType, mach_port_t port) : _port(port) {
        if (!*this) return; // Short-circuit if we weren't given a valid port
        kern_return_t kr = mach_port_mod_refs(mach_task_self(), _port, MACH_PORT_RIGHT_SEND, 1);
        // KERN_INVALID_RIGHT is returned when the send right is actually a dead name,
        // so we need to handle that specially, since we still want to retain it.
        assert(kr==KERN_SUCCESS || kr==KERN_INVALID_RIGHT);
        if (kr == KERN_INVALID_RIGHT) {
            kr = mach_port_mod_refs(mach_task_self(), _port, MACH_PORT_RIGHT_DEAD_NAME, 1);
            assert(kr == KERN_SUCCESS);
        }
    }
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
            kern_return_t kr = mach_port_deallocate(mach_task_self(), _port);
            assert(kr == KERN_SUCCESS);
            _port = MACH_PORT_NULL;
        }
    }
    
private:
    mach_port_t _port = MACH_PORT_NULL;
};

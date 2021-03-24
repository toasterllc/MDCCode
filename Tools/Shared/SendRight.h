#pragma once
#include <mach/port.h>
#include <cassert>

class SendRight {
public:
    struct RetainType {}; static constexpr auto Retain = RetainType();
    
    // Default constructor: empty
    SendRight() {}
    // Constructor: assume ownership of a send right
    SendRight(mach_port_t port) { _set(port); }
    // Constructor: retain a send right
    SendRight(RetainType, mach_port_t port) { _set(port, true); }
    // Copy constructor: use copy assignment operator
    SendRight(const SendRight& x) { *this = x; }
    // Copy assignment operator
    SendRight& operator=(const SendRight& x) {
        _set(x._port, true);
        return *this;
    }
    // Move constructor: use move assignment operator
    SendRight(SendRight&& x) { *this = std::move(x); }
    // Move assignment operator
    SendRight& operator=(SendRight&& x) {
        _set(x._port, true);
        x._set(MACH_PORT_NULL);
        return *this;
    }
    
    ~SendRight() {
        _set(MACH_PORT_NULL);
    }
    
    mach_port_t port() const {
        // We must have a valid port, otherwise blow up
        assert(*this);
        return _port;
    }
    
    operator bool() const { return MACH_PORT_VALID(_port); }
    
    void reset() {
        _set(MACH_PORT_NULL);
    }
    
private:
    void _set(mach_port_t p, bool retain=false) {
        if (MACH_PORT_VALID(p) && retain) {
            kern_return_t kr = mach_port_mod_refs(mach_task_self(), p, MACH_PORT_RIGHT_SEND, 1);
            // KERN_INVALID_RIGHT is returned when the send right is actually a dead name,
            // so we need to handle that case specially, since we still want to retain it.
            assert(kr==KERN_SUCCESS || kr==KERN_INVALID_RIGHT);
            if (kr == KERN_INVALID_RIGHT) {
                kr = mach_port_mod_refs(mach_task_self(), p, MACH_PORT_RIGHT_DEAD_NAME, 1);
                assert(kr == KERN_SUCCESS);
            }
        }
        
        // Release the existing port, if we have one
        if (MACH_PORT_VALID(_port)) {
            kern_return_t kr = mach_port_deallocate(mach_task_self(), _port);
            assert(kr == KERN_SUCCESS);
        }
        
        _port = p;
    }
    
    mach_port_t _port = MACH_PORT_NULL;
};

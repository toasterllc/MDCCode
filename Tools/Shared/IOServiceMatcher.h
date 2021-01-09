#pragma once
#include <IOKit/IOKitLib.h>
#include <vector>
#include "SendRight.h"
#include "USBInterface.h"
#include "RuntimeError.h"

class IOServiceMatcher {
public:
    using Handler = void(^)(SendRight&&);
    
    // Default constructor: empty
    IOServiceMatcher() {}
    
    // Constructor
    IOServiceMatcher(dispatch_queue_t queue, NSDictionary* match, Handler handler) {
        try {
            assert(queue);
            assert(match);
            assert(handler);
            dispatch_assert_queue(queue);
            
            _state.queue = queue;
            _state.handler = handler;
            
            _state.notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
            if (!_state.notifyPort) throw RuntimeError("IONotificationPortCreate returned null");
            IONotificationPortSetDispatchQueue(_state.notifyPort, queue);
            
            io_iterator_t ioIter = MACH_PORT_NULL;
            // *** Note ***
            // We pass _state.handler as the context to IOServiceAddMatchingNotification(), not `this`,
            // because we allow IOServiceMatcher's to be moved via the move operator, so `this` would
            // no longer be valid if that happened, but the handler would still be valid.
            kern_return_t kr = IOServiceAddMatchingNotification(_state.notifyPort, kIOMatchedNotification,
                (CFDictionaryRef)CFBridgingRetain(match), _matchingCallback, (__bridge void*)_state.handler, &ioIter);
            if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceAddMatchingNotification failed: 0x%x", kr);
            _state.serviceIter = SendRight(ioIter);
            
            _matchingCallback((void*)_state.handler, ioIter);
        
        } catch (...) {
            _reset();
            throw;
        }
    }
    
    // Copy constructor: illegal
    IOServiceMatcher(const IOServiceMatcher& x) = delete;
    // Move constructor: use move assignment operator
    IOServiceMatcher(IOServiceMatcher&& x) { *this = std::move(x); }
    // Move assignment operator
    IOServiceMatcher& operator=(IOServiceMatcher&& x) {
        _reset();
        _state = std::move(x._state);
        x._state = {};
        return *this;
    }
    
    ~IOServiceMatcher() {
        _reset();
    }
    
private:
    static void _matchingCallback(void* ctx, io_iterator_t iter) {
        Handler handler = (__bridge Handler)ctx;
        while (iter) {
            SendRight service(IOIteratorNext(iter));
            if (!service) break;
            handler(std::move(service));
        }
    }
    
    void _reset() {
        if (_state.queue) dispatch_assert_queue(_state.queue); // We can only be created and destroyed from the target queue
        
        if (_state.notifyPort) {
            IONotificationPortDestroy(_state.notifyPort);
            _state.notifyPort = nullptr;
        }
    }
    
    struct {
        dispatch_queue_t queue = nullptr;
        IONotificationPortRef notifyPort = nullptr;
        SendRight serviceIter;
        Handler handler = nullptr;
    } _state;
};

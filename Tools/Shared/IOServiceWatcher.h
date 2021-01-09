#pragma once
#include <IOKit/IOKitLib.h>
#include <vector>
#include "SendRight.h"
#include "USBInterface.h"
#include "RuntimeError.h"

class IOServiceWatcher {
public:
    using Handler = void(^)(SendRight&&);
    
    // Default constructor: empty
    IOServiceWatcher() {}
    
    // Constructor
    IOServiceWatcher(dispatch_queue_t queue, NSDictionary* match, Handler handler) {
        assert(queue);
        assert(match);
        assert(handler);
        dispatch_assert_queue(queue);
        
        try {
            _state.queue = queue;
            _state.handler = handler;
            
            _state.notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
            if (!_state.notifyPort) throw RuntimeError("IONotificationPortCreate returned null");
            IONotificationPortSetDispatchQueue(_state.notifyPort, queue);
            
            io_iterator_t ioIter = MACH_PORT_NULL;
            // *** Note ***
            // We pass _state.handler as the context to IOServiceAddMatchingNotification(), not `this`,
            // because we allow IOServiceWatcher's to be moved via the move operator, so `this` would
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
    IOServiceWatcher(const IOServiceWatcher& x) = delete;
    // Move constructor: use move assignment operator
    IOServiceWatcher(IOServiceWatcher&& x) { *this = std::move(x); }
    // Move assignment operator
    IOServiceWatcher& operator=(IOServiceWatcher&& x) {
        _reset();
        _state = std::move(x._state);
        x._state = {};
        return *this;
    }
    
    ~IOServiceWatcher() {
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
        
        _state.serviceIter.reset();
        
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

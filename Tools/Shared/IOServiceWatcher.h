#pragma once
#include <IOKit/IOKitLib.h>
#include <vector>
#include "SendRight.h"
#include "USBInterface.h"
#include "RuntimeError.h"

class IOServiceWatcher {
public:
    using Handler = void(^)(uint32_t msgType, void* msgArg);
    
    // Default constructor: empty
    IOServiceWatcher() {}
    
    // Constructor
    IOServiceWatcher(const SendRight& service, dispatch_queue_t queue, Handler handler) {
        try {
            assert(service);
            assert(queue);
            assert(handler);
            dispatch_assert_queue(queue);
            
            _state.service = service;
            _state.queue = queue;
            _state.handler = handler;
            
            _state.notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
            if (!_state.notifyPort) throw RuntimeError("IONotificationPortCreate returned null");
            IONotificationPortSetDispatchQueue(_state.notifyPort, queue);
            
            io_object_t ioNoteObj = MACH_PORT_NULL;
            // *** Note ***
            // We pass _state.handler as the context to IOServiceAddMatchingNotification(), not `this`,
            // because we allow IOServiceWatcher's to be moved via the move operator, so `this` would
            // no longer be valid if that happened, but the handler would still be valid.
            kern_return_t kr = IOServiceAddInterestNotification(_state.notifyPort, _state.service.port(), 
                kIOGeneralInterest, _callback, (__bridge void*)_state.handler, &ioNoteObj);
            if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceAddInterestNotification failed: 0x%x", kr);
            
            _state.noteObj = SendRight(ioNoteObj);
        
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
    static void _callback(void* ctx, io_service_t service, uint32_t msgType, void* msgArg) {
        Handler handler = (__bridge Handler)ctx;
        handler(msgType, msgArg);
    }
    
    void _reset() {
        if (_state.queue) dispatch_assert_queue(_state.queue); // We can only be created and destroyed from the target queue
        
        if (_state.notifyPort) {
            IONotificationPortDestroy(_state.notifyPort);
            _state.notifyPort = nullptr;
        }
    }
    
    struct {
        SendRight service;
        SendRight noteObj;
        dispatch_queue_t queue = nullptr;
        Handler handler = nullptr;
        IONotificationPortRef notifyPort = nullptr;
    } _state;
};

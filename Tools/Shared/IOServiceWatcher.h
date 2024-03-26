#pragma once
#include <IOKit/IOKitLib.h>
#include <vector>
#include "Code/Lib/Toastbox/SendRight.h"
#include "Code/Lib/Toastbox/RuntimeError.h"
#include "Code/Lib/Toastbox/Uniqued.h"

class IOServiceWatcher {
public:
    using SendRight = Toastbox::SendRight;
    using Handler = void(^)(uint32_t msgType, void* msgArg);
    
    IOServiceWatcher(const SendRight& service, dispatch_queue_t queue, Handler handler) {
        assert(service);
        assert(queue);
        assert(handler);
        dispatch_assert_queue(queue);
        
        _service = service;
        _queue = queue;
        _handler = handler;
        
        IONotificationPortRef p = IONotificationPortCreate(kIOMasterPortDefault);
        if (!p) throw Toastbox::RuntimeError("IONotificationPortCreate returned null");
        _notifyPort = p;
        IONotificationPortSetDispatchQueue(_notifyPort, queue);
        
        io_object_t ioNoteObj = MACH_PORT_NULL;
        // *** Note ***
        // We pass _handler as the context to IOServiceAddMatchingNotification(), not `this`,
        // because we allow IOServiceWatcher's to be moved via the move operator, so `this` would
        // no longer be valid if that happened, but the handler would still be valid.
        kern_return_t kr = IOServiceAddInterestNotification(_notifyPort, _service, 
            kIOGeneralInterest, _callback, (__bridge void*)_handler, &ioNoteObj);
        if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddInterestNotification failed: 0x%x", kr);
        
        _noteObj = SendRight(SendRight::NoRetain, ioNoteObj);
    }
    
private:
    static void _callback(void* ctx, io_service_t service, uint32_t msgType, void* msgArg) {
        Handler handler = (__bridge Handler)ctx;
        handler(msgType, msgArg);
    }
    
    using _IONotificationPortRef = Uniqued<IONotificationPortRef, IONotificationPortDestroy>;
    SendRight _service;
    SendRight _noteObj;
    dispatch_queue_t _queue = nullptr;
    Handler _handler = nullptr;
    _IONotificationPortRef _notifyPort;
};

#pragma once
#include <IOKit/IOKitLib.h>
#include <vector>
#include "Code/Lib/Toastbox/SendRight.h"
#include "Code/Lib/Toastbox/RuntimeError.h"
#include "Code/Lib/Toastbox/Uniqued.h"

class IOServiceMatcher {
public:
    using SendRight = Toastbox::SendRight;
    using Handler = void(^)(SendRight&&);
    
    IOServiceMatcher(dispatch_queue_t queue, NSDictionary* match, Handler handler) {
        assert(queue);
        assert(match);
        assert(handler);
        dispatch_assert_queue(queue);
        
        _queue = queue;
        _handler = handler;
        
        IONotificationPortRef p = IONotificationPortCreate(kIOMasterPortDefault);
        if (!p) throw Toastbox::RuntimeError("IONotificationPortCreate returned null");
        _notifyPort = p;
        IONotificationPortSetDispatchQueue(_notifyPort, queue);
        
        io_iterator_t ioIter = MACH_PORT_NULL;
        // *** Note ***
        // We pass _handler as the context to IOServiceAddMatchingNotification(), not `this`,
        // because we allow IOServiceMatcher's to be moved via the move operator, so `this` would
        // no longer be valid if that happened, but the handler would still be valid.
        kern_return_t kr = IOServiceAddMatchingNotification(_notifyPort, kIOMatchedNotification,
            (CFDictionaryRef)CFBridgingRetain(match), _matchingCallback, (__bridge void*)_handler, &ioIter);
        if (kr != KERN_SUCCESS) throw Toastbox::RuntimeError("IOServiceAddMatchingNotification failed: 0x%x", kr);
        _serviceIter = SendRight(SendRight::NoRetain, ioIter);
        
        _matchingCallback((void*)_handler, ioIter);
    }
    
private:
    static void _matchingCallback(void* ctx, io_iterator_t iter) {
        Handler handler = (__bridge Handler)ctx;
        while (iter) {
            SendRight service(SendRight::NoRetain, IOIteratorNext(iter));
            if (!service) break;
            handler(std::move(service));
        }
    }
    
    using _IONotificationPortRef = Uniqued<IONotificationPortRef, IONotificationPortDestroy>;
    dispatch_queue_t _queue = nullptr;
    _IONotificationPortRef _notifyPort;
    SendRight _serviceIter;
    Handler _handler = nullptr;
};

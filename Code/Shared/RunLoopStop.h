// RunLoopStop: mechanism to signal a runloop to stop running.
//
// This is necessary because apparently CFRunLoopStop() alone isn't always enough to
// cause CFRunLoopRunInMode() to return kCFRunLoopRunStopped; sometimes it returns
// kCFRunLoopRunHandledSource instead, even when calling CFRunLoopStop() from the
// runloop itself via CFRunLoopPerformBlock(). This RunLoopStop mechanism works
// around that.

#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

inline void* _RunLoopStopKey() {
    static void* Key = &Key;
    return Key;
}

// RunLoopStop(): returns whether the current runloop should stop
inline bool RunLoopStop() {
    return objc_getAssociatedObject((__bridge id)CFRunLoopGetCurrent(), _RunLoopStopKey());
}

// RunLoopStop(): tells a specific runloop to stop
inline void RunLoopStop(CFRunLoopRef rl) {
    assert(rl);
    CFRunLoopPerformBlock(rl, kCFRunLoopCommonModes, ^{
        objc_setAssociatedObject((__bridge id)rl, _RunLoopStopKey(), @YES, OBJC_ASSOCIATION_ASSIGN);
        CFRunLoopStop(rl);
    });
    CFRunLoopWakeUp(rl);
}

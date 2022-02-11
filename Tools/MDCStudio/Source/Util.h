#pragma once

namespace MDCStudio {

template <typename T>
T* DynamicCast(id obj) {
    if ([obj isKindOfClass:[T class]]) return obj;
    return nil;
}

#define DynamicCastProtocol(proto, obj) (id<proto>)([obj conformsToProtocol:@protocol(proto)] ? obj : nil)

template <typename Fn>
inline void TrackMouse(NSWindow* win, NSEvent* ev, Fn fn) {
    for (;;) @autoreleasepool {
        const bool done = ([ev type] == NSEventTypeLeftMouseUp);
        fn(ev, done);
        if (done) {
            // The mouse-up event needs to propogate into the app to complement the
            // mouse-down event. (The internal Cocoa APIs expect it.)
            [win sendEvent:ev];
            break;
        }
        
        ev = [win nextEventMatchingMask:(NSEventMaskLeftMouseDown|NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp)];
    }
}

} // namespace MDCStudio

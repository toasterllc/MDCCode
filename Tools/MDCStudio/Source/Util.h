#pragma once
#include "Tools/Shared/Color.h"

namespace MDCStudio {

template <typename T>
T* Cast(id obj) {
    assert([obj isKindOfClass:[T class]]);
    return obj;
}

template <typename T>
T* CastOrNil(id obj) {
    if ([obj isKindOfClass:[T class]]) return obj;
    return nil;
}

#define CastProtocol(proto, obj) (id<proto>)([obj conformsToProtocol:@protocol(proto)] ? obj : nil)

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

inline NSDictionary* LayerNullActions = @{
    kCAOnOrderIn: [NSNull null],
    kCAOnOrderOut: [NSNull null],
    @"bounds": [NSNull null],
    @"frame": [NSNull null],
    @"position": [NSNull null],
    @"sublayers": [NSNull null],
    @"transform": [NSNull null],
    @"contents": [NSNull null],
    @"contentsScale": [NSNull null],
    @"hidden": [NSNull null],
    @"fillColor": [NSNull null],
    @"fontSize": [NSNull null],
};

inline struct {
    MDCTools::Color<MDCTools::ColorSpace::SRGB> srgb    = {.118, .122, .129};
    MDCTools::Color<MDCTools::ColorSpace::LSRGB> lsrgb  = srgb;
} WindowBackgroundColor;

} // namespace MDCStudio

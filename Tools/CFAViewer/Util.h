#import <Cocoa/Cocoa.h>

namespace CFAViewer {
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
            
            ev = [win nextEventMatchingMask:
                NSEventMaskLeftMouseDown|NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];
        }
    }
    
    inline NSDictionary* LayerNullActions() {
        static NSDictionary* r = @{
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
        return r;
    }
    
    inline CGColorSpaceRef SRGBColorSpace() {
        static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        return cs;
    }
    
    inline id /* CGColorRef */ SRGBColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
        const CGFloat c[] = {r,g,b,a};
        return CFBridgingRelease(CGColorCreate(SRGBColorSpace(), c));
    }
}

#pragma once
#include <memory>
#include "ImageLibrary.h"
#include "Toastbox/Signal.h"
#include "Toastbox/Atomic.h"

namespace MDCStudio {

inline NSMenu* ImageContextMenu(id target) {
    NSMenu* m = [[NSMenu alloc] initWithTitle:@""];
    
    [m addItemWithTitle:@"Export…"
        action:@selector(_export:) keyEquivalent:@"" atIndex:idx++];
    
    [m setTarget:target];
    
    return m;
}

} // namespace MDCStudio

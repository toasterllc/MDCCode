#pragma once

namespace MDCStudio {

template <typename T>
T* DynamicCast(id obj) {
    if ([obj isKindOfClass:[T class]]) return obj;
    return nil;
}

#define DynamicCastProtocol(proto, obj) (id<proto>)([obj conformsToProtocol:@protocol(proto)] ? obj : nil)

} // namespace MDCStudio

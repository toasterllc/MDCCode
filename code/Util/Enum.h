#pragma once

#define Enum(type, name, group, ...)    \
    using name = type;                  \
    struct group {                      \
        enum : name {                   \
            __VA_ARGS__                 \
        };                              \
    };

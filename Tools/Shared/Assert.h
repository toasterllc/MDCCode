#pragma once
#include <libgen.h>
#include <os/log.h>

#define Assert(condition, ...) ({                                                   \
    bool b = (bool)(condition);                                                     \
    if (!b) {                                                                       \
        char fileNameBuf[MAXPATHLEN];                                               \
        char* fileName = basename_r(__FILE__, fileNameBuf);                         \
        os_log_error(OS_LOG_DEFAULT, "Assertion failed (%s @ %s:%ju): %s",          \
             __PRETTY_FUNCTION__, fileName, (uintmax_t)__LINE__, (#condition));     \
        __VA_ARGS__;                                                                \
    }                                                                               \
})

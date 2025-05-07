#pragma once
#include <cstdio>
#include <string>
#include "STM.h"
#include "Lib/Toastbox/RuntimeError.h"
#include "Lib/Toastbox/Defer.h"

namespace STM {

inline const char* _StringForStatusMode(const STM::Status::Mode mode) {
    using namespace STM;
    switch (mode) {
    case STM::Status::Mode::STMLoader:  return "STMLoader";
    case STM::Status::Mode::STMApp:     return "STMApp";
    default:                            return "<Invalid>";
    }
}

inline std::string StringForStatus(const STM::Status& x) {
    char* buf = nullptr;
    size_t bufLen = 0;
    FILE* f = open_memstream(&buf, &bufLen);
    if (!f) throw Toastbox::RuntimeError("open_memstream failed: %s", strerror(errno));
    Defer( fclose(f); free(buf); );
    
    fprintf(f, "header\n");
    fprintf(f, "  magic:    0x%08jx\n", (uintmax_t)x.header.magic);
    fprintf(f, "  version:  %ju\n", (uintmax_t)x.header.version);
    fprintf(f, "mspVersion: %ju\n", (uintmax_t)x.mspVersion);
    fprintf(f, "mode:       %s\n", _StringForStatusMode(x.mode));
    
    // Flush the stream to so that `buf` is assigned to the FILE's internal buffer
    fflush(f);
    return buf;
}

} // namespace MSP

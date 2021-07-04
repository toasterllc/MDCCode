#pragma once
#include <sstream>

class RuntimeError : public std::runtime_error {
public:
    template <typename ...Args>
    RuntimeError(const char* fmt, Args&& ...args) : std::runtime_error(fmtMsg(fmt, args...)) {}
    
private:
    static std::string fmtMsg(const char* str) {
        char msg[256];
        int sr = snprintf(msg, sizeof(msg), "%s", str);
        if (sr<0 || (size_t)sr>=(sizeof(msg)-1)) throw std::runtime_error("failed to create RuntimeError");
        return msg;
    }
    
    template <typename ...Args>
    static std::string fmtMsg(const char* fmt, Args&& ...args) {
        char msg[256];
        int sr = snprintf(msg, sizeof(msg), fmt, args...);
        if (sr<0 || (size_t)sr>=(sizeof(msg)-1)) throw std::runtime_error("failed to create RuntimeError");
        return msg;
    }
};

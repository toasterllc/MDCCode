#import <sstream>
#import <IOKit/IOKitLib.h>

class SystemError : public std::runtime_error {
public:
    SystemError(int32_t code, const std::string& msg) : std::runtime_error(fmtMsg((uint32_t)code, msg)) {}
    SystemError(uint32_t code, const std::string& msg) : std::runtime_error(fmtMsg((uint32_t)code, msg)) {}
    SystemError(int64_t code, const std::string& msg) : std::runtime_error(fmtMsg((uint64_t)code, msg)) {}
    SystemError(uint64_t code, const std::string& msg) : std::runtime_error(fmtMsg((uint64_t)code, msg)) {}
    
private:
    static std::string fmtMsg(uint64_t code, const std::string& msg) {
        std::stringstream ss;
        ss << msg << ": 0x" << std::hex << code;
        return ss.str();
    }
};

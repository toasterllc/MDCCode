#include <vector>
#include <iostream>
#include <fstream>
#include <algorithm>
#include <cstring>
#include "Lib/Toastbox/RuntimeError.h"
#include "Lib/Toastbox/NumForStr.h"
#include "Lib/Toastbox/DurationString.h"
#include "Lib/Toastbox/String.h"
#include "Lib/Toastbox/Cast.h"
#include "Shared/STM.h"
#include "Shared/STMDebug.h"
#include "Shared/ChecksumFletcher32.h"
#include "Shared/Img.h"
#include "Shared/SD.h"
#include "Shared/ImgSD.h"
#include "Shared/MSP.h"
#include "Shared/MSPDebug.h"
#include "Shared/Time.h"
#include "Shared/TimeAdjustment.h"
#include "Shared/TimeString.h"
#include "Shared/Clock.h"
#include "Shared/MDCUSBDevice.h"
#include "Shared/ELF32Binary.h"
#include "date/date.h"
#include "date/tz.h"

#if __APPLE__
#include <mach-o/dyld.h> // For _NSGetExecutablePath()
#endif

using CmdStr = std::string;

// Common Commands
const CmdStr ResetCmd               = "Reset";
const CmdStr StatusGetCmd           = "StatusGet";
const CmdStr BatteryStatusGetCmd    = "BatteryStatusGet";
const CmdStr BootloaderInvokeCmd    = "BootloaderInvoke";
const CmdStr LEDSetCmd              = "LEDSet";

// STMLoader Commands
const CmdStr STMRAMWriteCmd         = "STMRAMWrite";
const CmdStr STMRAMWriteLegacyCmd   = "STMRAMWriteLegacy";

// STMApp Commands
const CmdStr STMFlashWriteCmd       = "STMFlashWrite";
const CmdStr HostModeSetCmd         = "HostModeSet";
const CmdStr ICERAMWriteCmd         = "ICERAMWrite";
const CmdStr ICEFlashReadCmd        = "ICEFlashRead";
const CmdStr ICEFlashWriteCmd       = "ICEFlashWrite";
const CmdStr MSPStateReadCmd        = "MSPStateRead";
const CmdStr MSPStateWriteCmd       = "MSPStateWrite";
const CmdStr MSPTimeGetCmd          = "MSPTimeGet";
const CmdStr MSPTimeInitCmd         = "MSPTimeInit";
const CmdStr MSPTimeAdjustCmd       = "MSPTimeAdjust";
const CmdStr MSPSBWReadCmd          = "MSPSBWRead";
const CmdStr MSPSBWWriteCmd         = "MSPSBWWrite";
const CmdStr MSPSBWEraseCmd         = "MSPSBWErase";
const CmdStr MSPSBWDebugLogCmd      = "MSPSBWDebugLog";
const CmdStr SDReadCmd              = "SDRead";
const CmdStr SDEraseCmd             = "SDErase";
const CmdStr ImgReadFullCmd         = "ImgReadFull";
const CmdStr ImgReadThumbCmd        = "ImgReadThumb";
const CmdStr ImgCaptureCmd          = "ImgCapture";

static void printUsage() {
    using namespace std;
    cout << "MDCUtil commands:\n";
    
    // Common Commands
    cout << "  " << ResetCmd                << "\n";
    cout << "  " << StatusGetCmd            << "\n";
    cout << "  " << BatteryStatusGetCmd     << "\n";
    cout << "  " << BootloaderInvokeCmd     << "\n";
    cout << "  " << LEDSetCmd               << " <idx> <0/1>\n";
    
    // STMLoader Commands
    cout << "  " << STMRAMWriteCmd          << " <file>\n";
    cout << "  " << STMRAMWriteLegacyCmd    << " <file>\n";
    
    // STMApp Commands
    cout << "  " << STMFlashWriteCmd        << " <file>\n";
    
    cout << "  " << HostModeSetCmd          << " <0/1>\n";
    
    cout << "  " << ICERAMWriteCmd          << " <file>\n";
    cout << "  " << ICEFlashReadCmd         << " <addr> <len>\n";
    cout << "  " << ICEFlashWriteCmd        << " <file>\n";
    
    cout << "  " << MSPStateReadCmd         << "\n";
    cout << "  " << MSPStateWriteCmd        << "\n";
    cout << "  " << MSPTimeGetCmd           << "\n";
    cout << "  " << MSPTimeInitCmd          << "\n";
    cout << "  " << MSPTimeAdjustCmd        << "\n";
    
    cout << "  " << MSPSBWReadCmd           << " <addr> <len>\n";
    cout << "  " << MSPSBWWriteCmd          << " <file>\n";
    cout << "  " << MSPSBWEraseCmd          << "\n";
    cout << "  " << MSPSBWDebugLogCmd       << "\n";
    
    cout << "  " << SDReadCmd               << " <addr> <blockcount> <output>\n";
    cout << "  " << SDEraseCmd              << " <addr> <blockcount>\n";
    
    cout << "  " << ImgReadFullCmd          << " <id> <output>\n";
    cout << "  " << ImgReadThumbCmd         << " <id> <output>\n";
    cout << "  " << ImgCaptureCmd           << " <output.cfa>\n";
    
    cout << "\n";
}

struct Args {
    CmdStr cmd = "";
    
    struct {
        uint8_t idx = 0;
        uint8_t on = 0;
    } LEDSet = {};
    
    struct {
        std::string filePath;
    } STMRAMWrite = {};
    
    struct {
        std::string filePath;
    } STMRAMWriteLegacy = {};
    
    struct {
        std::string filePath;
    } STMFlashWrite = {};
    
    struct {
        bool en;
    } HostModeSet = {};
    
    struct {
        std::string filePath;
    } ICERAMWrite = {};
    
    struct {
        uintptr_t addr = 0;
        size_t len = 0;
    } ICEFlashRead = {};
    
    struct {
        std::string filePath;
    } ICEFlashWrite = {};
    
    struct {
        uintptr_t addr = 0;
        size_t len = 0;
    } MSPSBWRead = {};
    
    struct {
        std::string filePath;
    } MSPSBWWrite = {};
    
    struct {
        SD::Block addr = 0;
        SD::Block count = 0;
        std::string filePath;
    } SDRead = {};
    
    struct {
        SD::Block addr = 0;
        SD::Block count = 0;
    } SDErase = {};
    
    struct {
        Img::Id id = 0;
        std::string filePath;
    } ImgReadFull = {};
    
    struct {
        Img::Id id = 0;
        std::string filePath;
    } ImgReadThumb = {};
    
    struct {
        std::string filePath;
    } ImgCapture = {};
};

static std::string lower(const std::string& str) {
    std::string r = str;
    std::transform(r.begin(), r.end(), r.begin(), ::tolower);
    return r;
}

static Args parseArgs(int argc, const char* argv[]) {
    using namespace Toastbox;
    
    std::vector<std::string> strs;
    for (int i=0; i<argc; i++) strs.push_back(argv[i]);
    
    Args args;
    if (strs.size() < 1) throw std::runtime_error("no command specified");
    args.cmd = lower(strs[0]);
    
    if (args.cmd == lower(ResetCmd)) {
    
    } else if (args.cmd == lower(StatusGetCmd)) {
    
    } else if (args.cmd == lower(BatteryStatusGetCmd)) {
    
    } else if (args.cmd == lower(BootloaderInvokeCmd)) {
    
    } else if (args.cmd == lower(LEDSetCmd)) {
        if (strs.size() < 3) throw std::runtime_error("missing argument: LED index/state");
        IntForStr(args.LEDSet.idx, strs[1]);
        IntForStr(args.LEDSet.on, strs[2]);
    
    } else if (args.cmd == lower(STMRAMWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.STMRAMWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(STMRAMWriteLegacyCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.STMRAMWriteLegacy.filePath = strs[1];
    
    } else if (args.cmd == lower(STMFlashWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.STMFlashWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(HostModeSetCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: host mode state");
        IntForStr(args.HostModeSet.en, strs[1]);
    
    } else if (args.cmd == lower(ICERAMWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.ICERAMWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(ICEFlashReadCmd)) {
        if (strs.size() < 3) throw std::runtime_error("missing argument: address/length");
        IntForStr(args.ICEFlashRead.addr, strs[1]);
        IntForStr(args.ICEFlashRead.len, strs[2]);
    
    } else if (args.cmd == lower(ICEFlashWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.ICEFlashWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(MSPStateReadCmd)) {
    
    } else if (args.cmd == lower(MSPStateWriteCmd)) {
    
    } else if (args.cmd == lower(MSPTimeGetCmd)) {
    
    } else if (args.cmd == lower(MSPTimeInitCmd)) {
    
    } else if (args.cmd == lower(MSPTimeAdjustCmd)) {
    
    } else if (args.cmd == lower(MSPSBWReadCmd)) {
        if (strs.size() < 3) throw std::runtime_error("missing argument: address/length");
        IntForStr(args.MSPSBWRead.addr, strs[1]);
        IntForStr(args.MSPSBWRead.len, strs[2]);
    
    } else if (args.cmd == lower(MSPSBWWriteCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.MSPSBWWrite.filePath = strs[1];
    
    } else if (args.cmd == lower(MSPSBWEraseCmd)) {
    
    } else if (args.cmd == lower(MSPSBWDebugLogCmd)) {
    
    } else if (args.cmd == lower(SDReadCmd)) {
        if (strs.size() < 4) throw std::runtime_error("missing argument: address/length/file");
        IntForStr(args.SDRead.addr, strs[1]);
        IntForStr(args.SDRead.count, strs[2]);
        args.SDRead.filePath = strs[3];
    
    } else if (args.cmd == lower(SDEraseCmd)) {
        if (strs.size() < 3) throw std::runtime_error("missing argument: address/length");
        IntForStr(args.SDErase.addr, strs[1]);
        IntForStr(args.SDErase.count, strs[2]);
    
    } else if (args.cmd == lower(ImgReadFullCmd)) {
        if (strs.size() < 3) throw std::runtime_error("missing argument: id/file path");
        IntForStr(args.ImgReadFull.id, strs[1]);
        args.ImgReadFull.filePath = strs[2];
    
    } else if (args.cmd == lower(ImgReadThumbCmd)) {
        if (strs.size() < 3) throw std::runtime_error("missing argument: id/file path");
        IntForStr(args.ImgReadThumb.id, strs[1]);
        args.ImgReadThumb.filePath = strs[2];
    
    } else if (args.cmd == lower(ImgCaptureCmd)) {
        if (strs.size() < 2) throw std::runtime_error("missing argument: file path");
        args.ImgCapture.filePath = strs[1];
    
    } else {
        throw std::runtime_error("invalid command");
    }
    
    return args;
}

static void Reset(const Args& args, MDCUSBDevice& device) {
    printf("Resetting...\n");
    device.reset();
    printf("-> OK\n\n");
}

static void StatusGet(const Args& args, MDCUSBDevice& device) {
    using namespace STM;
    Status status = device.statusGet();
    std::cout << STM::StringForStatus(status) << "\n";
}

static const char* _StringForChargeStatus(MSP::ChargeStatus status) {
    using namespace MSP;
    switch (status) {
    case ChargeStatus::Invalid:  return "invalid";
    case ChargeStatus::Shutdown: return "shutdown";
    case ChargeStatus::Underway: return "underway";
    case ChargeStatus::Complete: return "complete";
    }
    abort();
}

static std::string _StringForBatteryLevel(MSP::BatteryLevelMv level) {
    using namespace STM;
    
    const MSP::BatteryLevel levelLinear = MSP::BatteryLevelLinearize(level);
    if (levelLinear == MSP::BatteryLevelMvInvalid) return "invalid";
    
    const uint32_t percent = (((uint32_t)levelLinear-MSP::BatteryLevelMin)*100) / (MSP::BatteryLevelMax-MSP::BatteryLevelMin);
    return std::to_string(percent) + "%";
}

static void BatteryStatusGet(const Args& args, MDCUSBDevice& device) {
    using namespace STM;
    BatteryStatus status = device.batteryStatusGet();
    
    printf("Battery status:\n");
    printf("  Charge status: %s\n", _StringForChargeStatus(status.chargeStatus));
    printf("  Battery level: %s (%ju mV)\n", _StringForBatteryLevel(status.level).c_str(), (uintmax_t)status.level);
    printf("\n");
}

static void BootloaderInvoke(const Args& args, MDCUSBDevice& device) {
    device.bootloaderInvoke();
}

static void LEDSet(const Args& args, MDCUSBDevice& device) {
    device.ledSet(args.LEDSet.idx, args.LEDSet.on);
}

static void STMRAMWrite(const Args& args, MDCUSBDevice& device) {
    ELF32Binary elf(args.STMRAMWrite.filePath.c_str());
    device.stmRAMWrite(elf);
}

static void STMRAMWriteLegacy(const Args& args, MDCUSBDevice& device) {
    ELF32Binary elf(args.STMRAMWriteLegacy.filePath.c_str());
    device.stmRAMWriteLegacy(elf);
}

static void STMFlashWrite(const Args& args, MDCUSBDevice& device) {
    ELF32Binary elf(args.STMFlashWrite.filePath.c_str());
    device.stmFlashWrite(elf);
}

static void HostModeSet(const Args& args, MDCUSBDevice& device) {
    printf("HostModeSet: %d\n", (int)args.HostModeSet.en);
    device.hostModeSet(args.HostModeSet.en);
}

static void ICERAMWrite(const Args& args, MDCUSBDevice& device) {
    Toastbox::Mmap mmap(args.ICERAMWrite.filePath.c_str());
    
    // Send the ICE40 binary
    printf("ICERAMWrite: Writing %ju bytes\n", (uintmax_t)mmap.len());
    device.iceRAMWrite(mmap.data(), mmap.len());
}

static void ICEFlashRead(const Args& args, MDCUSBDevice& device) {
    printf("Reading [0x%08jx,0x%08jx):\n",
        (uintmax_t)args.ICEFlashRead.addr,
        (uintmax_t)(args.ICEFlashRead.addr+args.ICEFlashRead.len)
    );
    
    auto buf = std::make_unique<uint8_t[]>(args.ICEFlashRead.len);
    device.iceFlashRead(args.ICEFlashRead.addr, buf.get(), args.ICEFlashRead.len);
    
    for (size_t i=0; i<args.ICEFlashRead.len; i++) {
        printf("%02jx ", (uintmax_t)buf[i]);
    }
    
    printf("\n");
}

static void ICEFlashWrite(const Args& args, MDCUSBDevice& device) {
    Toastbox::Mmap mmap(args.ICEFlashWrite.filePath.c_str());
    
    const size_t len = mmap.len();
    
    // Send the ICE40 binary
    printf("ICEFlashWrite: Writing %ju bytes\n", (uintmax_t)mmap.len());
    device.iceFlashWrite(0, mmap.data(), len);
    
    // Send the ICE40 binary
    printf("ICEFlashWrite: Verifying %ju bytes\n", (uintmax_t)mmap.len());
    auto buf = std::make_unique<uint8_t[]>(len);
    device.iceFlashRead(0, buf.get(), len);
    if (memcmp(mmap.data(), buf.get(), len)) {
        constexpr const char* ReadBackDataFilename = "ICEFlashWrite-ReadBack.bin";
        std::ofstream f;
        f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
        f.open(ReadBackDataFilename);
        f.write((char*)buf.get(), len);
        throw Toastbox::RuntimeError("data written doesn't match data read (wrote to %s)", ReadBackDataFilename);
    }
}

static std::filesystem::path _ExecutableDir() {
#if __APPLE__
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::string exePath(size, 0);
    _NSGetExecutablePath(exePath.data(), &size);

#elif __linux__
    char exePath[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exePath, sizeof(exePath)-1);
    if (len < 0) throw Toastbox::RuntimeError("readlink failed: %s", strerror(errno));
    exePath[len] = 0;
#endif
    
    return std::filesystem::path(exePath).parent_path();
}

static std::filesystem::path _MSPAppPath() {
    return _ExecutableDir() / "../../../../Code/MSP430/MSPApp/Build/MSPApp.elf";
}

static std::string _Run(const char* cmd) {
    std::string r;
    FILE* p = popen(cmd, "r");
    if (!p) throw std::runtime_error("popen failed");
    
    char tmp[128];
    while (fgets(tmp, sizeof(tmp), p)) r += tmp;
    
    const int ir = pclose(p);
    if (!WIFEXITED(ir) || WEXITSTATUS(ir)) throw Toastbox::RuntimeError("command failed: %s", cmd);
    
    return r;
}

static std::string _MSPLineForAddr(uint16_t addr) {
    const std::filesystem::path mspAppPath = _MSPAppPath();
    char cmd[256];
    const int ir = snprintf(cmd, sizeof(cmd),
        "dwarfdump %s --lookup 0x%jx 2>&1 | grep -e DW_AT_call | xargs", mspAppPath.c_str(), (uintmax_t)addr);
    if (ir<0 || ir>=sizeof(cmd)) throw std::runtime_error("snprintf failed");
    auto lines = Toastbox::String::Split(Toastbox::String::Trim(_Run(cmd)), "\n");
    if (lines.empty()) throw std::runtime_error("dwarfdump returned no output");
    return lines.back();
}

static void MSPStateRead(const Args& args, MDCUSBDevice& device) {
    // Read the device state
    const MSP::State state = device.mspStateRead();
    std::cout << MSP::StringForState(state, _MSPLineForAddr) << "\n";
}

static void MSPStateWrite(const Args& args, MDCUSBDevice& device) {
    throw Toastbox::RuntimeError("unimplemented");
}

static void MSPTimeGet(const Args& args, MDCUSBDevice& device) {
    using namespace std::chrono;
    using namespace date;
    
    std::cout << "MSPTimeGet:\n";
    const MSP::TimeState ts = device.mspTimeGet();
    std::cout << Time::StringForTimeState(ts);
}

static void MSPTimeInit(const Args& args, MDCUSBDevice& device) {
//    struct [[gnu::packed]] TimeState {
//        Time::Instant start;
//        Time::Instant time;
//        struct [[gnu::packed]] {
//            int32_t value;          // Current adjustment to `time`
//            Time::Ticks32 counter;  // Counts ticks until `counter >= `interval`
//            Time::Ticks32 interval; // Interval upon which we perform `value += delta`
//            int16_t delta;          // Amount to add to `value` when `counter >= interval`
//        } adjustment;
//    };
    
    std::cout << "MSPTimeInit:\n\n";
    const MSP::TimeState ts = device.mspTimeInit();
    std::cout << Time::StringForTimeState(ts) << "\n";
}

static void MSPTimeAdjust(const Args& args, MDCUSBDevice& device) {
    std::cout << "MSPTimeAdjust:\n\n";
    device.mspTimeAdjust();
}

static void MSPSBWRead(const Args& args, MDCUSBDevice& device) {
    device.mspLock();
    device.mspSBWConnect();
    device.mspSBWHalt();
    
    printf("Reading [0x%08jx,0x%08jx):\n",
        (uintmax_t)args.MSPSBWRead.addr,
        (uintmax_t)(args.MSPSBWRead.addr+args.MSPSBWRead.len)
    );
    
    auto buf = std::make_unique<uint8_t[]>(args.MSPSBWRead.len);
    device.mspSBWRead(args.MSPSBWRead.addr, buf.get(), args.MSPSBWRead.len);
    
    for (size_t i=0; i<args.MSPSBWRead.len; i++) {
        printf("%02jx ", (uintmax_t)buf[i]);
    }
    
    printf("\n");
    
    device.mspSBWReset();
    device.mspSBWDisconnect();
    device.mspUnlock();
}

static void MSPSBWWrite(const Args& args, MDCUSBDevice& device) {
    ELF32Binary elf(args.MSPSBWWrite.filePath.c_str());
    device.mspSBWWrite(elf);
}

static void MSPSBWErase(const Args& args, MDCUSBDevice& device) {
    std::cout << "MSPSBWErase\n";
    device.mspLock();
    device.mspSBWErase();
    device.mspUnlock();
    std::cout << "-> OK\n\n";
}

static size_t _Width(MSP::DebugLogPacket::Type x) {
    using X = MSP::DebugLogPacket::Type;
    switch (x) {
    case X::Dec16: return 2;
    case X::Dec32: return 4;
    case X::Dec64: return 8;
    case X::Hex16: return 2;
    case X::Hex32: return 4;
    case X::Hex64: return 8;
    default:       return 0;
    }
}

static void _Print(MSP::DebugLogPacket::Type t, uint64_t x) {
    using X = MSP::DebugLogPacket::Type;
    switch (t) {
    case X::Dec16:
    case X::Dec32:
    case X::Dec64:
        printf("%ju", (uintmax_t)x);
        return;
    case X::Hex16:
        printf("0x%04jx", (uintmax_t)x);
        return;
    case X::Hex32:
        printf("0x%08jx", (uintmax_t)x);
        return;
    case X::Hex64:
        printf("0x%016jx", (uintmax_t)x);
        return;
    default:
        abort();
    }
}

static void MSPSBWDebugLog(const Args& args, MDCUSBDevice& device) {
    using DebugLogPacket = MSP::DebugLogPacket;
    DebugLogPacket log[Toastbox::USB::Endpoint::SpeedHigh::MaxPacketSizeBulk / sizeof(DebugLogPacket)];
    
    std::cout << "MSPSBWDebugLog\n";
//    device.mspLock();
    device.mspSBWConnect();
    device.mspSBWDebugLog();
    std::cout << "-> OK:\n\n";
    
    struct {
        DebugLogPacket::Type type = DebugLogPacket::Type::Chars;
        size_t off = 0;
        union {
            uint8_t u8[8];
            uint64_t u64 = 0;
        };
    } state;
    
    for (;;) {
        const size_t count = device.readout(log, sizeof(log)) / sizeof(DebugLogPacket);
        for (size_t i=0; i<count; i++) {
            DebugLogPacket& p = log[i];
            
            // Chars state
            if (state.type == DebugLogPacket::Type::Chars) {
                // Chars packet: print newline
                if (p.type == DebugLogPacket::Type::Chars) {
                    printf("\n");
                
                // DecXXX/HexXXX packet: enter the Int state
                } else if (_Width(p.type)) {
                    printf("\n");
                    state = { .type = p.type };
                
                // Chars payload packet: print characters
                } else {
                    for (uint8_t c : p.u8) {
                        if (!c) break;
                        std::cout << (char)c;
                    }
                }
                
            // Int state
            } else {
                state.u8[state.off+0] = p.u8[0];
                state.u8[state.off+1] = p.u8[1];
                state.off += 2;
                if (state.off == _Width(state.type)) {
                    // Done with current int, print it
                    _Print(state.type, state.u64);
                    // Reset state
                    state = {};
                }
            }
        }
        
        std::cout << std::flush;
//        break;
    }
    
    #warning TODO: handle signal to cleanup
    device.reset();
//    device.mspSBWDisconnect();
//    device.mspSBWUnlock();
}

static void SDRead(const Args& args, MDCUSBDevice& device) {
    static_assert(!(SD::BlockLen % Toastbox::USB::Endpoint::SpeedHigh::MaxPacketSizeBulk));
    const size_t len = (size_t)args.SDRead.count * (size_t)SD::BlockLen;
    
    printf("Sending SDInit command...\n");
    device.sdInit();
    printf("-> OK\n\n");
    
    printf("Sending SDRead command...\n");
    device.sdRead(args.SDRead.addr);
    printf("-> OK\n\n");
    
    printf("Reading data (%ju bytes)...\n", (uintmax_t)len);
    
    auto buf = std::make_unique<uint8_t[]>(len);
    auto timeStart = std::chrono::steady_clock::now();
    device.readout(buf.get(), len);
    auto duration = std::chrono::steady_clock::now() - timeStart;
    auto durationUs = std::chrono::duration_cast<std::chrono::microseconds>(duration);
    const float throughputMBPerSec = (((double)(len*(uint64_t)1000000)) / durationUs.count()) / (1024*1024);
    printf("-> OK (throughput: %.1f MB/sec)\n\n", throughputMBPerSec);
    
    // Write data
    printf("Writing data (%ju bytes)...\n", (uintmax_t)len);
    std::ofstream f;
    f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
    f.open(args.SDRead.filePath.c_str());
    f.write((char*)buf.get(), len);
    printf("-> Wrote %ju blocks (%ju bytes)\n", (uintmax_t)args.SDRead.count, (uintmax_t)len);
}

static void SDErase(const Args& args, MDCUSBDevice& device) {
    if (args.SDErase.count <= 0) throw Toastbox::RuntimeError("invalid block count: %ju", (uintmax_t)args.SDErase.count);
    
    printf("Sending SDInit command...\n");
    device.sdInit();
    printf("-> OK\n\n");
    
    printf("Sending SDErase command...\n");
    device.sdErase(args.SDErase.addr, args.SDErase.addr+args.SDErase.count-1);
    printf("-> OK\n\n");
}

static void _ImgRead(MDCUSBDevice& device, const std::string& filePath, SD::Block block, size_t len) {
    static_assert(!(SD::BlockLen % Toastbox::USB::Endpoint::SpeedHigh::MaxPacketSizeBulk));
    
    printf("Sending SDInit command...\n");
    device.sdInit();
    printf("-> OK\n\n");
    
    printf("Sending SDRead command...\n");
    device.sdRead(block);
    printf("-> OK\n\n");
    
    printf("Reading data (%ju bytes)...\n", (uintmax_t)len);
    auto buf = std::make_unique<uint8_t[]>(len);
    device.readout(buf.get(), len);
    printf("-> OK\n\n");
    
    // Write data
    printf("Writing data...\n");
    std::ofstream f;
    f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
    f.open(filePath.c_str());
    f.write((char*)buf.get(), len);
    printf("-> OK\n");
}

static void ImgReadFull(const Args& args, MDCUSBDevice& device) {
    const auto& a = args.ImgReadFull;
    const MSP::State mspState = device.mspStateRead();
    const uint32_t idx = a.id % mspState.sd.imgCap;
    const SD::Block block = MSP::SDBlockStart(mspState.sd.baseFull, ImgSD::Full::ImageBlockCount, idx);
    _ImgRead(device, a.filePath, block, ImgSD::Full::ImagePaddedLen);
}

static void ImgReadThumb(const Args& args, MDCUSBDevice& device) {
    const auto& a = args.ImgReadThumb;
    const MSP::State mspState = device.mspStateRead();
    const uint32_t idx = a.id % mspState.sd.imgCap;
    const SD::Block block = MSP::SDBlockStart(mspState.sd.baseThumb, ImgSD::Thumb::ImageBlockCount, idx);
    _ImgRead(device, a.filePath, block, ImgSD::Thumb::ImagePaddedLen);
}

static void ImgCapture(const Args& args, MDCUSBDevice& device) {
    printf("Sending ImgInit command...\n");
    device.imgInit();
    printf("-> OK\n\n");
    
    printf("Sending ImgCapture command...\n");
    STM::ImgCaptureStats stats = device.imgCapture(0, 0, Img::Size::Full);
    printf("-> OK (len: %ju)\n\n", (uintmax_t)stats.len);
    
    printf("Reading image...\n");
    auto img = device.imgReadout(Img::Size::Full);
    printf("-> OK\n\n");
    
    // Write image
    printf("Writing image...\n");
    std::ofstream f;
    f.exceptions(std::ifstream::failbit | std::ifstream::badbit);
    f.open(args.ImgCapture.filePath.c_str());
    f.write((char*)img.get(), Img::Full::ImageLen);
    printf("-> Wrote (len: %ju)\n", (uintmax_t)Img::Full::ImageLen);
}

int main(int argc, const char* argv[]) {
    Args args;
    try {
        args = parseArgs(argc-1, argv+1);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Bad arguments: %s\n\n", e.what());
        printUsage();
        return 1;
    }
    
    std::vector<MDCUSBDevicePtr> devices;
    try {
        devices = MDCUSBDevice::DevicesGet();
    } catch (const std::exception& e) {
        fprintf(stderr, "Failed to get MDC loader devices: %s\n\n", e.what());
        return 1;
    }
    
    if (devices.empty()) {
        fprintf(stderr, "No matching MDC devices\n\n");
        return 1;
    } else if (devices.size() > 1) {
        fprintf(stderr, "Too many matching MDC devices\n\n");
        return 1;
    }
    
    MDCUSBDevice& device = *(devices[0]);
    
//    const size_t LenCap = 1024;
//    auto buf = std::make_unique<uint8_t[]>(LenCap);
//    IOUSBDevRequest req = {
//        .bmRequestType  = USBmakebmRequestType(kUSBIn, kUSBStandard, kUSBDevice),
//        .bRequest       = kUSBRqGetDescriptor,
//        .wValue         = kUSBConfDesc<<8,
//        .wIndex         = 0,
//        .wLength        = LenCap,
//        .pData          = buf.get(),
//    };
//    
//    IOReturn ior = device.dev().iokitExec<&IOUSBDeviceInterface::DeviceRequest>(&req);
//    device.dev()._CheckErr(ior, "DeviceRequest failed");
    
    try {
        if (args.cmd == lower(ResetCmd))                    Reset(args, device);
        else if (args.cmd == lower(StatusGetCmd))           StatusGet(args, device);
        else if (args.cmd == lower(BatteryStatusGetCmd))    BatteryStatusGet(args, device);
        else if (args.cmd == lower(BootloaderInvokeCmd))    BootloaderInvoke(args, device);
        else if (args.cmd == lower(LEDSetCmd))              LEDSet(args, device);
        else if (args.cmd == lower(STMRAMWriteCmd))         STMRAMWrite(args, device);
        else if (args.cmd == lower(STMRAMWriteLegacyCmd))   STMRAMWriteLegacy(args, device);
        else if (args.cmd == lower(STMFlashWriteCmd))       STMFlashWrite(args, device);
        else if (args.cmd == lower(HostModeSetCmd))         HostModeSet(args, device);
        else if (args.cmd == lower(ICERAMWriteCmd))         ICERAMWrite(args, device);
        else if (args.cmd == lower(ICEFlashReadCmd))        ICEFlashRead(args, device);
        else if (args.cmd == lower(ICEFlashWriteCmd))       ICEFlashWrite(args, device);
        else if (args.cmd == lower(MSPStateReadCmd))        MSPStateRead(args, device);
        else if (args.cmd == lower(MSPStateWriteCmd))       MSPStateWrite(args, device);
        else if (args.cmd == lower(MSPTimeGetCmd))          MSPTimeGet(args, device);
        else if (args.cmd == lower(MSPTimeInitCmd))         MSPTimeInit(args, device);
        else if (args.cmd == lower(MSPTimeAdjustCmd))       MSPTimeAdjust(args, device);
        else if (args.cmd == lower(MSPSBWReadCmd))          MSPSBWRead(args, device);
        else if (args.cmd == lower(MSPSBWWriteCmd))         MSPSBWWrite(args, device);
        else if (args.cmd == lower(MSPSBWEraseCmd))         MSPSBWErase(args, device);
        else if (args.cmd == lower(MSPSBWDebugLogCmd))      MSPSBWDebugLog(args, device);
        else if (args.cmd == lower(SDReadCmd))              SDRead(args, device);
        else if (args.cmd == lower(SDEraseCmd))             SDErase(args, device);
        else if (args.cmd == lower(ImgReadFullCmd))         ImgReadFull(args, device);
        else if (args.cmd == lower(ImgReadThumbCmd))        ImgReadThumb(args, device);
        else if (args.cmd == lower(ImgCaptureCmd))          ImgCapture(args, device);
    
    } catch (const std::exception& e) {
        fprintf(stderr, "Error: %s\n", e.what());
        return 1;
    }
    
    return 0;
}

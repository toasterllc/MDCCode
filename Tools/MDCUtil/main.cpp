#include <vector>
#include <iostream>
#include <fstream>
#include <algorithm>
#include <cstring>
#include "STM.h"
#include "MDCUSBDevice.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/NumForStr.h"
#include "Toastbox/DurationString.h"
#include "Toastbox/String.h"
#include "Toastbox/Cast.h"
#include "ChecksumFletcher32.h"
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"
#include "MSP.h"
#include "ELF32Binary.h"
#include "Time.h"
#include "TimeAdjustment.h"
#include "TimeString.h"
#include "Clock.h"
#include "date/date.h"
#include "date/tz.h"

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
const CmdStr MSPTimeSetCmd          = "MSPTimeSet";
const CmdStr MSPTimeAdjustCmd       = "MSPTimeAdjust";
const CmdStr MSPSBWReadCmd          = "MSPSBWRead";
const CmdStr MSPSBWWriteCmd         = "MSPSBWWrite";
const CmdStr MSPSBWEraseCmd         = "MSPSBWErase";
const CmdStr MSPSBWDebugLogCmd      = "MSPSBWDebugLog";
const CmdStr SDReadCmd              = "SDRead";
const CmdStr SDEraseCmd             = "SDErase";
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
    cout << "  " << MSPTimeSetCmd           << "\n";
    cout << "  " << MSPTimeAdjustCmd        << "\n";
    
    cout << "  " << MSPSBWReadCmd           << " <addr> <len>\n";
    cout << "  " << MSPSBWWriteCmd          << " <file>\n";
    cout << "  " << MSPSBWEraseCmd          << "\n";
    cout << "  " << MSPSBWDebugLogCmd       << "\n";
    
    cout << "  " << SDReadCmd               << " <addr> <blockcount> <output>\n";
    cout << "  " << SDEraseCmd              << " <addr> <blockcount> <output>\n";
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
    
    } else if (args.cmd == lower(MSPTimeSetCmd)) {
    
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

static const char* _StringForStatusMode(const STM::Status::Mode mode) {
    using namespace STM;
    switch (mode) {
    case STM::Status::Mode::STMLoader:  return "STMLoader";
    case STM::Status::Mode::STMApp:     return "STMApp";
    default:                            return "<Invalid>";
    }
}

static void StatusGet(const Args& args, MDCUSBDevice& device) {
    using namespace STM;
    Status status = device.statusGet();
    printf("Status:\n");
    printf("  header:\n");
    printf("    magic:    0x%08jx\n", (uintmax_t)status.header.magic);
    printf("    version:  %ju\n", (uintmax_t)status.header.version);
    printf("  mspVersion: %ju\n", (uintmax_t)status.mspVersion);
    printf("  mode:       %s\n", _StringForStatusMode(status.mode));
    printf("\n");
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
    printf("  Battery level: %s (%ju mv)\n", _StringForBatteryLevel(status.level).c_str(), (uintmax_t)status.level);
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
    
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("STMRAMWrite: Writing %12s @ 0x%08jx    size: 0x%08jx    vaddr: 0x%08jx\n",
            name, (uintmax_t)paddr, (uintmax_t)size, (uintmax_t)vaddr);
        
        device.stmRAMWrite(paddr, data, size);
    });
    
    // Reset the device, triggering it to load the program we just wrote
    printf("STMRAMWrite: Resetting device\n");
    device.stmReset(elf.entryPointAddr());
}

static void STMRAMWriteLegacy(const Args& args, MDCUSBDevice& device) {
    ELF32Binary elf(args.STMRAMWriteLegacy.filePath.c_str());
    
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("STMRAMWriteLegacy: Writing %12s @ 0x%08jx    size: 0x%08jx    vaddr: 0x%08jx\n",
            name, (uintmax_t)paddr, (uintmax_t)size, (uintmax_t)vaddr);
        
        device.stmRAMWriteLegacy(paddr, data, size);
    });
    
    // Reset the device, triggering it to load the program we just wrote
    printf("STMRAMWriteLegacy: Resetting device\n");
    device.stmReset(elf.entryPointAddr());
}

static void STMFlashWrite(const Args& args, MDCUSBDevice& device) {
    ELF32Binary elf(args.STMFlashWrite.filePath.c_str());
    
    device.stmFlashWriteInit();
    
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("STMFlashWrite: Writing %12s @ 0x%08jx    size: 0x%08jx    vaddr: 0x%08jx\n",
            name, (uintmax_t)paddr, (uintmax_t)size, (uintmax_t)vaddr);
        
        device.stmFlashWrite(paddr, data, size);
    });
    
    // Invoke the bootloader, triggering it to load the program we just wrote
    printf("STMFlashWrite: invoking bootloader\n");
    device.bootloaderInvoke();
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

static const char* _StringForRepeatType(MSP::Repeat::Type x) {
    using X = MSP::Repeat::Type;
    switch (x) {
    case X::Never:  return "Never";  break;
    case X::Daily:  return "Daily";  break;
    case X::Weekly: return "Weekly"; break;
    case X::Yearly: return "Yearly"; break;
    }
    return "unknown";
}

static const char* _StringForTriggerEventType(MSP::Triggers::Event::Type x) {
    using X = MSP::Triggers::Event::Type;
    switch (x) {
    case X::TimeTrigger:  return "TimeTrigger";
    case X::MotionEnable: return "MotionEnable";
    }
    return "unknown";
}

static const char* _StringForResetType(MSP::Reset::Type x) {
    switch (x) {
    case MSP::Reset::Type::Reset:         return "reset";
    case MSP::Reset::Type::Abort:         return "abort";
    case MSP::Reset::Type::StackOverflow: return "stack overflow";
    }
    return "unknown";
}

static const char* _StringForResetReason(uint16_t x) {
    switch (x) {
    case 0x0000: return "NONE";
    case 0x0002: return "BOR";
    case 0x0004: return "RSTNMI";
    case 0x0006: return "DOBOR";
    case 0x0008: return "LPM5WU";
    case 0x000A: return "SECYV";
    case 0x000C: return "RES12";
    case 0x000E: return "SVSHIFG";
    case 0x0010: return "RES16";
    case 0x0012: return "RES18";
    case 0x0014: return "DOPOR";
    case 0x0016: return "WDTTO";
    case 0x0018: return "WDTKEY";
    case 0x001A: return "FRCTLPW";
    case 0x001C: return "UBDIFG";
    case 0x001E: return "PERF";
    case 0x0020: return "PMMPW";
    case 0x0024: return "FLLUL";
    }
    return "unknown";
}

static float _SecondsForTicks(uint32_t ticks) {
    // Check our assumption that Time::TicksFreq is an integer
    static_assert(Time::TicksFreq::den == 1);
    return (float)ticks / Time::TicksFreq::num;
}

static std::filesystem::path _MSPAppPath() {
    using namespace std::filesystem;
    path home = getenv("HOME");
    return home / "repos/MDCCode/Code/MSP430/MSPApp/Release/MSPApp.out";
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

static std::string __MSPLineForAddr(uint16_t addr) {
    const std::filesystem::path mspAppPath = _MSPAppPath();
    char cmd[256];
    const int ir = snprintf(cmd, sizeof(cmd), "dwarfdump %s --lookup 0x%jx 2>&1", mspAppPath.c_str(), (uintmax_t)addr);
    if (ir<0 || ir>=sizeof(cmd)) throw std::runtime_error("snprintf failed");
    auto lines = Toastbox::String::Split(Toastbox::String::Trim(_Run(cmd)), "\n");
    if (lines.empty()) throw std::runtime_error("dwarfdump returned no output");
    return lines.back();
}

static std::string _MSPLineForAddr(uint16_t addr) {
    try {
        return __MSPLineForAddr(addr);
    } catch (const std::exception& e) {
        return std::string("address lookup failed: ") + e.what();
    }
}

static void MSPStateRead(const Args& args, MDCUSBDevice& device) {
    // Read the device state
    MSP::State state = device.mspStateRead();
    
    printf(         "header\n");
    printf(         "  magic:                   0x%08jx\n",             (uintmax_t)state.header.magic);
    printf(         "  version:                 0x%04jx\n",             (uintmax_t)state.header.version);
    printf(         "  length:                  0x%04jx\n",             (uintmax_t)state.header.length);
    printf(         "\n");
    
    printf(         "sd\n");
    printf(         "  cardId\n");
    printf(         "    manufacturerId:        0x%02jx\n",             (uintmax_t)state.sd.cardId.manufacturerId);
    printf(         "    oemId:                 0x%02jx\n",             (uintmax_t)state.sd.cardId.oemId);
    printf(         "    productName:           %c%c%c%c%c\n",          state.sd.cardId.productName[0],
                                                                        state.sd.cardId.productName[1],
                                                                        state.sd.cardId.productName[2],
                                                                        state.sd.cardId.productName[3],
                                                                        state.sd.cardId.productName[4]);
    printf(         "    productRevision:       0x%02jx\n",             (uintmax_t)state.sd.cardId.productRevision);
    printf(         "    productSerialNumber:   0x%08jx\n",             (uintmax_t)state.sd.cardId.productSerialNumber);
    printf(         "    manufactureDate:       0x%04jx\n",             (uintmax_t)state.sd.cardId.manufactureDate);
    printf(         "    crc:                   0x%02jx\n",             (uintmax_t)state.sd.cardId.crc);
    
    printf(         "  imgCap:                  %ju\n",                 (uintmax_t)state.sd.imgCap);
    printf(         "  baseFull:                %ju\n",                 (uintmax_t)state.sd.baseFull);
    printf(         "  baseThumb:               %ju\n",                 (uintmax_t)state.sd.baseThumb);
    
    printf(         "  imgRingBufs[0]\n");
    printf(         "    buf\n");
    printf(         "      id:                  %ju\n",                 (uintmax_t)state.sd.imgRingBufs[0].buf.id);
    printf(         "      idx:                 %ju\n",                 (uintmax_t)state.sd.imgRingBufs[0].buf.idx);
    printf(         "    valid:                 %ju\n",                 (uintmax_t)state.sd.imgRingBufs[0].valid);
    
    printf(         "  imgRingBufs[1]\n");
    printf(         "    buf\n");
    printf(         "      id:                  %ju\n",                 (uintmax_t)state.sd.imgRingBufs[1].buf.id);
    printf(         "      idx:                 %ju\n",                 (uintmax_t)state.sd.imgRingBufs[1].buf.idx);
    printf(         "    valid:                 %ju\n",                 (uintmax_t)state.sd.imgRingBufs[1].valid);
    printf(         "\n");
    
    printf(         "settings\n");
    printf(         "  triggers\n");
    
    const auto& triggers = state.settings.triggers;
    
    printf(         "    event\n");
    for (auto it=std::begin(triggers.event); it!=std::begin(triggers.event)+triggers.eventCount; it++) {
        printf(     "      #%ju\n",                                     (uintmax_t)(&*it-triggers.event));
        printf(     "        time:                  %s\n",              Time::StringForTimeInstant(it->time).c_str());
        printf(     "        type:                  %s\n",              _StringForTriggerEventType(it->type));
        printf(     "        repeat\n");
        printf(     "          type:                %s\n",              _StringForRepeatType(it->repeat.type));
        printf(     "          arg:                 0x%jx\n",           (uintmax_t)it->repeat.Daily.interval);
        printf(     "        idx:                   %ju\n",             (uintmax_t)it->idx);
    }
    
    printf(         "    timeTrigger\n");
    for (auto it=std::begin(triggers.timeTrigger); it!=std::begin(triggers.timeTrigger)+triggers.timeTriggerCount; it++) {
        printf(     "      #%ju\n",                                     (uintmax_t)(&*it-triggers.timeTrigger));
        printf(     "        capture\n");
        printf(     "          delayTicks:          %ju (%.1f)\n",      (uintmax_t)it->capture.delayTicks, _SecondsForTicks(it->capture.delayTicks));
        printf(     "          count:               %ju\n",             (uintmax_t)it->capture.count);
        printf(     "          ledFlash:            %ju\n",             (uintmax_t)it->capture.ledFlash);
    }
    
    printf(         "    motionTrigger\n");
    for (auto it=std::begin(triggers.motionTrigger); it!=std::begin(triggers.motionTrigger)+triggers.motionTriggerCount; it++) {
        printf(     "      #%ju\n",                                     (uintmax_t)(&*it-triggers.motionTrigger));
        printf(     "        capture\n");
        printf(     "          delayTicks:          %ju (%.1f)\n",      (uintmax_t)it->capture.delayTicks, _SecondsForTicks(it->capture.delayTicks));
        printf(     "          count:               %ju\n",             (uintmax_t)it->capture.count);
        printf(     "          ledFlash:            %ju\n",             (uintmax_t)it->capture.ledFlash);
        printf(     "        count:                 %ju\n",             (uintmax_t)it->count);
        printf(     "        durationTicks:         %ju (%.1f)\n",      (uintmax_t)it->durationTicks, _SecondsForTicks(it->durationTicks));
        printf(     "        suppressTicks:         %ju (%.1f)\n",      (uintmax_t)it->suppressTicks, _SecondsForTicks(it->suppressTicks));
    }
    
    printf(         "    buttonTrigger\n");
    for (auto it=std::begin(triggers.buttonTrigger); it!=std::begin(triggers.buttonTrigger)+triggers.buttonTriggerCount; it++) {
        printf(     "      #%ju\n",                                     (uintmax_t)(&*it-triggers.buttonTrigger));
        printf(     "        capture\n");
        printf(     "          delayTicks:          %ju (%.1f)\n",      (uintmax_t)it->capture.delayTicks, _SecondsForTicks(it->capture.delayTicks));
        printf(     "          count:               %ju\n",             (uintmax_t)it->capture.count);
        printf(     "          ledFlash:            %ju\n",             (uintmax_t)it->capture.ledFlash);
    }
    
    printf(         "    source\n");
    for (auto it=std::begin(triggers.source); it!=std::end(triggers.source);) {
        printf(     "      ");
        for (int i=0; i<16 && it!=std::end(triggers.source); i++, it++) {
            printf("%02jx ", (uintmax_t)*it);
        }
        printf("\n");
    }
    printf(         "\n");
    
    printf(         "resets\n");
    size_t i = 0;
    for (const auto& reset : state.resets) {
        if (!reset.count) break;
        printf(     "  #%ju\n",                                         (uintmax_t)i);
        printf(     "    type:                  0x%02jx (%s)\n",        (uintmax_t)reset.type, _StringForResetType(reset.type));
        
        switch (reset.type) {
        case MSP::Reset::Type::Reset:
            printf( "    reason:                0x%04jx (%s)\n",        (uintmax_t)reset.ctx.Reset.reason, _StringForResetReason(reset.ctx.Reset.reason));
            break;
        case MSP::Reset::Type::Abort:
            printf( "    addr:                  0x%04jx [ %s ]\n",      (uintmax_t)reset.ctx.Abort.addr, _MSPLineForAddr(reset.ctx.Abort.addr).c_str());
            break;
        case MSP::Reset::Type::StackOverflow:
            printf( "    taskIdx:               %ju\n",                 (uintmax_t)reset.ctx.StackOverflow.taskIdx);
            break;
        }
        printf(     "    count:                 %ju\n",                 (uintmax_t)reset.count);
        i++;
    }
    printf(         "\n");
}

static void MSPStateWrite(const Args& args, MDCUSBDevice& device) {
    throw Toastbox::RuntimeError("unimplemented");
}

static void MSPTimeGet(const Args& args, MDCUSBDevice& device) {
    using namespace std::chrono;
    using namespace date;
    
    std::cout << "MSPTimeGet:\n";
    const MSP::TimeState state = device.mspTimeGet();
    std::cout << Time::StringForTimeState(state);
}

static void MSPTimeSet(const Args& args, MDCUSBDevice& device) {
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
    
    const Time::Instant now = Time::Clock::TimeInstantFromTimePoint(Time::Clock::now());
    const MSP::TimeState state = {
        .start = now,
        .time = now,
    };
    
    std::cout << "MSPTimeSet: " << Time::StringForTimeInstant(now) << "\n";
    device.mspTimeSet(state);
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
    
    device.mspLock();
    device.mspSBWConnect();
    device.mspSBWHalt();
    
    // Write the data
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("MSPSBWWrite: Writing %22s @ 0x%04jx    size: 0x%04jx    vaddr: 0x%04jx\n",
            name, (uintmax_t)paddr, (uintmax_t)size, (uintmax_t)vaddr);
        
        device.mspSBWWrite(paddr, data, size);
    });
    
    // Read back data and compare with what we expect
    elf.enumerateLoadableSections([&](uint32_t paddr, uint32_t vaddr, const void* data,
    size_t size, const char* name) {
        printf("MSPSBWWrite: Verifying %s @ 0x%jx [size: 0x%jx]\n",
            name, (uintmax_t)paddr, (uintmax_t)size);
        
        auto buf = std::make_unique<uint8_t[]>(size);
        device.mspSBWRead(paddr, buf.get(), size);
        
        if (memcmp(data, buf.get(), size)) {
            throw Toastbox::RuntimeError("section doesn't match: %s", name);
        }
    });
    
    device.mspSBWReset();
    device.mspSBWDisconnect();
    device.mspUnlock();
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
    DebugLogPacket log[Toastbox::USB::Endpoint::MaxPacketSizeBulk / sizeof(DebugLogPacket)];
    
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
    static_assert(!(SD::BlockLen % Toastbox::USB::Endpoint::MaxPacketSizeBulk));
    const size_t len = (size_t)args.SDRead.count * (size_t)SD::BlockLen;
    
    printf("Sending SDInit command...\n");
    device.sdInit();
    printf("-> OK\n\n");
    
    printf("Sending SDRead command...\n");
    device.sdRead(args.SDRead.addr);
    printf("-> OK\n\n");
    
    printf("Reading data...\n");
    auto buf = std::make_unique<uint8_t[]>(len);
    device.readout(buf.get(), len);
    printf("-> OK\n\n");
    
    // Write data
    printf("Writing data...\n");
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

static Toastbox::USBDevicePtr GetDevice() {
    auto usbDevs = Toastbox::USBDevice::GetDevices();
    for (Toastbox::USBDevicePtr& usbDev : usbDevs) {
        if (MDCUSBDevice::USBDeviceMatches(*usbDev)) {
            return std::move(usbDev);
        }
    }
    return nullptr;
}

int main(int argc, const char* argv[]) {
    
    Toastbox::USBDevicePtr dev = GetDevice();
    if (!dev) {
        printf("No device\n");
        return 0;
    }
    
    try {
        printf("[MDCUSBDevice] status START\n");
        dev->status();
        printf("[MDCUSBDevice] status END\n");
    
    } catch (const std::exception& e) {
        printf("Error: %s\n", e.what());
    }
    
    return 0;
}

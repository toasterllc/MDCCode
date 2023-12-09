#include <cstdint>
#include "Code/Lib/Toastbox/Scheduler.h"
#include "System.h"
#include "USB.h"
#include "USBConfig.h"
using namespace STM;

static void _Reset();
static void _CmdHandle(const STM::Cmd& cmd);

using _System = System<
    STM::Status::Mode::STMApp,  // T_Mode
    true,                       // T_USBDMAEn
    _CmdHandle,                 // T_CmdHandle
    _Reset,                     // T_Reset
    
    // T_Pins
    std::tuple<>,
    
    // T_Tasks
    std::tuple<>
>;

using _Scheduler = _System::Scheduler;
using _USB = _System::USB;

static void _Reset() {
}

static void _CmdHandle(const STM::Cmd& cmd) {
}

// MARK: - ISRs

extern "C" [[gnu::section(".isr")]] void ISR_SysTick() {
    _Scheduler::Tick();
    HAL_IncTick();
}

extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS() {
    _USB::ISR();
}

extern "C" [[gnu::section(".isr")]] void ISR_I2C1_EV() {
    _System::ISR_I2CEvent();
}

extern "C" [[gnu::section(".isr")]] void ISR_I2C1_ER() {
    _System::ISR_I2CError();
}

// MARK: - Abort

extern "C"
[[noreturn]]
void Abort(uintptr_t addr) {
    _System::Abort();
}

// MARK: - Main
int main() {
    _Scheduler::Run();
    return 0;
}

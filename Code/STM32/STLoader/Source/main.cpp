#include <string.h>
#include <algorithm>
#define TaskARM32
#include "Toastbox/Task.h"
#include "Assert.h"
#include "Toastbox/IntState.h"
#include "STM.h"
#include "USB.h"
#include "BufQueue.h"
#include "System.h"
using namespace STM;

static void _CmdHandle(const STM::Cmd& cmd);
static void _Reset();

using _System = System<
    STM::Status::Modes::STMLoader,  // T_Mode
    false,                          // T_USBDMAEn
    _CmdHandle,                     // T_CmdHandle
    _Reset                          // T_Reset
>;

using _Scheduler = _System::Scheduler;
using _USB = _System::USB;

using _BufQueue = BufQueue<uint8_t,1024,2>;
static _BufQueue _Bufs;

// The Startup class needs to exist in the `uninit` section,
// so that its _appEntryPointAddr member doesn't get clobbered
// on startup.
using _VoidFn = void(*)();
static volatile _VoidFn _AppEntryPoint [[noreturn, gnu::section(".uninit")]] = 0;

// MARK: - Commands

static size_t _STMRegionCapacity(void* addr) {
    // Verify that `addr` is in one of the allowed RAM regions
    extern uint8_t _sitcm_ram[], _eitcm_ram[];
    extern uint8_t _sdtcm_ram[], _edtcm_ram[];
    extern uint8_t _ssram1[], _esram1[];
    size_t cap = 0;
    if (addr>=_sitcm_ram && addr<_eitcm_ram) {
        cap = (uintptr_t)_eitcm_ram-(uintptr_t)addr;
    } else if (addr>=_sdtcm_ram && addr<_edtcm_ram) {
        cap = (uintptr_t)_edtcm_ram-(uintptr_t)addr;
    } else if (addr>=_ssram1 && addr<_esram1) {
        cap = (uintptr_t)_esram1-(uintptr_t)addr;
    }
    return cap;
}

static void _STMWrite(const STM::Cmd& cmd) {
    const auto& arg = cmd.arg.STMWrite;
    
    // Bail if the region capacity is too small to hold the
    // incoming data length (ceiled to the packet length)
    const size_t len = _USB::CeilToMaxPacketSize(_USB::MaxPacketSizeOut(), arg.len);
    if (len > _STMRegionCapacity((void*)arg.addr)) {
        // Reject command
        _System::USBAcceptCommand(false);
        return;
    }
    
    // Accept command
    _System::USBAcceptCommand(true);
    
    // Receive USB data
    _USB::Recv(Endpoints::DataOut, (void*)arg.addr, len);
}

static void _STMReset(const STM::Cmd& cmd) {
    // Accept command
    _System::USBAcceptCommand(true);
    
    _AppEntryPoint = (_VoidFn)cmd.arg.STMReset.entryPointAddr;
    
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

static void _CmdHandle(const STM::Cmd& cmd) {
    switch (cmd.op) {
    // STM32 Bootloader
    case Op::STMWrite:  _STMWrite(cmd);                     break;
    case Op::STMReset:  _STMReset(cmd);                     break;
    // Bad command
    default:            _System::USBAcceptCommand(false);   break;
    }
}

static void _Reset() {}

// MARK: - ISRs

extern "C" [[gnu::section(".isr")]] void ISR_NMI()          {}
extern "C" [[gnu::section(".isr")]] void ISR_HardFault()    { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_MemManage()    { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_BusFault()     { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_UsageFault()   { abort(); }
extern "C" [[gnu::section(".isr")]] void ISR_SVC()          {}
extern "C" [[gnu::section(".isr")]] void ISR_DebugMon()     {}
extern "C" [[gnu::section(".isr")]] void ISR_PendSV()       {}

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

extern "C" [[gnu::section(".isr")]] void ISR_EXTI15_10() {
    _System::ISR_ExtInt_15_10();
}

// MARK: - Main

static void _JumpToAppIfNeeded() {
    // Stash and reset `_AppEntryPoint` so that we only attempt to start the app once
    // after each software reset.
	const _VoidFn appEntryPoint = _AppEntryPoint;
    _AppEntryPoint = nullptr;
    
    // Cache RCC_CSR since we're about to clear it
    auto csr = READ_REG(RCC->CSR);
    // Clear RCC_CSR by setting the RMVF bit
    SET_BIT(RCC->CSR, RCC_CSR_RMVF);
    // Check if we reset due to a software reset (SFTRSTF), and
    // we have the app's vector table.
    if (READ_BIT(csr, RCC_CSR_SFTRSTF) && appEntryPoint) {
//        volatile bool a = false;
//        while (!a);
        
        // Start the application
        appEntryPoint();
        for (;;); // Loop forever if the app returns
    }
}

// MARK: - Abort

extern "C" [[noreturn]]
void abort() {
    _System::Abort();
}

int main() {
    _JumpToAppIfNeeded();
    _System::Init();
    _Scheduler::Run();
    return 0;
}

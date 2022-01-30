#include <string.h>
#include <algorithm>
#define TaskARM32
#include "Toastbox/Task.h"
#include "Assert.h"
#include "Toastbox/IntState.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"
#include "System.h"
#include "USBConfigDesc.h"

using namespace STM;

// MARK: - Peripherals & Types
static const void* _USBConfigDesc(size_t& len);

using _USBType = USBType<
    false,                      // T_DMAEn: disabled because we want USB to be able to write to
                                // ITCM RAM (because we write to that region as a part of
                                // bootloading), but DMA masters can't access it.
    _USBConfigDesc,             // T_ConfigDesc
    STM::Endpoints::DataOut,    // T_Endpoints
    STM::Endpoints::DataIn
>;

static const void* _USBConfigDesc(size_t& len) {
    return USBConfigDesc<_USBType>(len);
}

using _QSPIType = QSPIType<
    QSPIMode::Single,           // T_Mode
    5,                          // T_ClkDivider (5 -> QSPI clock = 21.3 MHz)
    QSPIAlign::Byte,            // T_Align
    QSPIChipSelect::Controlled  // T_ChipSelect
>;

struct _TaskUSBDataIn;

static void _CmdHandle(const STM::Cmd& cmd);
using _System = System<
    _USBType,
    _QSPIType,
    STM::Status::Modes::STMLoader,
    _CmdHandle,
    // Additional Tasks
    _TaskUSBDataIn
>;

constexpr auto& _USB = _System::USB;
constexpr auto& _QSPI = _System::QSPI;
using _Scheduler = _System::Scheduler;

using _BufQueue = BufQueue<uint8_t,1024,2>;
static _BufQueue _Bufs;

// The Startup class needs to exist in the `uninit` section,
// so that its _appEntryPointAddr member doesn't get clobbered
// on startup.
using _VoidFn = void(*)();
static volatile _VoidFn _AppEntryPoint [[noreturn, gnu::section(".uninit")]] = 0;

// _TaskUSBDataIn: writes buffers from _Bufs to the DataIn endpoint, and pops them from _Bufs
struct _TaskUSBDataIn {
    static void Start();
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._TaskUSBDataIn")]]
    static inline uint8_t Stack[256];
};

// MARK: - Tasks

void _TaskUSBDataIn::Start() {
    _Scheduler::Start<_TaskUSBDataIn>([] {
        for (;;) {
            _Scheduler::Wait([] { return !_Bufs.empty(); });
            
            // Send the data and wait until the transfer is complete
            auto& buf = _Bufs.front();
            _USB.send(Endpoints::DataIn, buf.data, buf.len);
            _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
            
            buf.len = 0;
            _Bufs.pop();
        }
    });
}

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
    const size_t len = _USB.CeilToMaxPacketSize(_USB.MaxPacketSizeOut(), arg.len);
    if (len > _STMRegionCapacity((void*)arg.addr)) {
        // Send preliminary status: error
        _System::USBSendStatus(false);
        return;
    }
    
    // Send preliminary status: OK
    _System::USBSendStatus(true);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Receive USB data
    _USB.recv(Endpoints::DataOut, (void*)arg.addr, len);
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataOut); });
    
    // Send final status
    _System::USBSendStatus(true);
}

static void _STMReset(const STM::Cmd& cmd) {
    _AppEntryPoint = (_VoidFn)cmd.arg.STMReset.entryPointAddr;
    
    // Send status
    _System::USBSendStatus(true);
    // Wait for host to receive status before resetting
    _Scheduler::Wait([] { return _USB.endpointReady(Endpoints::DataIn); });
    
    // Perform software reset
    HAL_NVIC_SystemReset();
    // Unreachable
    abort();
}

static void _CmdHandle(const STM::Cmd& cmd) {
    switch (cmd.op) {
    // STM32 Bootloader
    case Op::STMWrite:              _STMWrite(cmd);                 break;
    case Op::STMReset:              _STMReset(cmd);                 break;
    // Bad command
    default:                        _System::USBSendStatus(false);  break;
    }
}

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
    _USB.isr();
}

extern "C" [[gnu::section(".isr")]] void ISR_QUADSPI() {
    _QSPI.isrQSPI();
}

extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream7() {
    _QSPI.isrDMA();
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
    
    _USB.init();
    _QSPI.init();
    
    _Scheduler::Run();
    return 0;
}




#warning TODO: remove these debug symbols
#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section
constexpr auto& _Debug_Tasks              = _Scheduler::_Tasks;
constexpr auto& _Debug_DidWork            = _Scheduler::_DidWork;
constexpr auto& _Debug_CurrentTask        = _Scheduler::_CurrentTask;
constexpr auto& _Debug_CurrentTime        = _Scheduler::_ISR.CurrentTime;
constexpr auto& _Debug_Wake               = _Scheduler::_ISR.Wake;
constexpr auto& _Debug_WakeTime           = _Scheduler::_ISR.WakeTime;

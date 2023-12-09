#include <cstdint>
#include <cstring>
#include <tuple>
#include <ratio>
#include "Code/Lib/Toastbox/Scheduler.h"
#include "Code/Lib/Toastbox/Scheduler.h"
#include "Code/Lib/Toastbox/Util.h"
#include "Code/Shared/STM.h"
#include "Code/Shared/Assert.h"
#include "GPIO.h"
#include "USB.h"
#include "USBConfig.h"
using namespace STM;

#define _StackInterruptSize 2048

[[gnu::section(".stack.interrupt")]]
alignas(void*)
uint8_t _StackInterrupt[_StackInterruptSize];

asm(".global _StartupStackInterrupt");
asm(".equ _StartupStackInterrupt, _StackInterrupt+" Stringify(_StackInterruptSize));

#define _TaskCmdRecvStackSize 2048

[[gnu::section(".stack._TaskCmdRecv")]]
alignas(void*)
uint8_t _TaskCmdRecvStack[_TaskCmdRecvStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskCmdRecvStack+" Stringify(_TaskCmdRecvStackSize));

// MARK: - System

// This crazniness is necessary to allow System to accept 2 parameter packs (T_Pins and T_Tasks).
// We do that by way of template class specialization, hence the two `class System` occurences.
template<
STM::Status::Mode T_Mode,
bool T_USBDMAEn,
typename...
>
class System;

template<
STM::Status::Mode T_Mode,
bool T_USBDMAEn,
typename... T_Pins,
typename... T_Tasks
>
class System<T_Mode, T_USBDMAEn, std::tuple<T_Pins...>, std::tuple<T_Tasks...>> {
public:
    static constexpr uint8_t CPUFreqMHz = 128;
    using SysTickPeriod = std::ratio<1,1000>;
    
private:
    #warning TODO: remove stack guards for production
    static constexpr size_t _StackGuardCount = 4;
    
    using _USB_DM   = GPIO::PortB::Pin<14, GPIO::Option::Speed3, GPIO::Option::AltFn12>;
    using _USB_DP   = GPIO::PortB::Pin<15, GPIO::Option::Speed3, GPIO::Option::AltFn12>;
    
    // _OSC_IN / _OSC_OUT: used for providing external clock
    // There's no alt function to configure here; we just need these to exist so that GPIO
    // enables the clock for the relevent port (PortH)
    using _OSC_IN   = GPIO::PortH::Pin<0>;
    using _OSC_OUT  = GPIO::PortH::Pin<1>;
    
    [[noreturn]]
    static void _SchedulerStackOverflow(size_t taskIdx) {
        Assert(false);
    }
    
    static void _Sleep() {
        __WFI();
    }
    
    struct _TaskCmdRecv;
    struct _TaskCmdHandle;
    
public:
    // LEDs
    using LED0 = GPIO::PortB::Pin<11, GPIO::Option::Output0>;
    using LED1 = GPIO::PortB::Pin<13, GPIO::Option::Output0>;
    
    using Scheduler = Toastbox::Scheduler<
        SysTickPeriod,                              // T_TicksPeriod: period between ticks, in seconds
        
        _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                    //          invoked when no tasks have work to do
        
        _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
        _SchedulerStackOverflow,                    // T_StackOverflow: function to handle stack overflow
        _StackInterrupt,                            // T_StackInterrupt: stack used for handling interrupts;
                                                    //                   Scheduler only uses this to detect stack overflow
        
        _TaskCmdRecv,                               // T_Tasks: list of tasks
        _TaskCmdHandle,
        T_Tasks...
    >;
    
    using USB = T_USB<
        Scheduler,  // T_Scheduler
        T_USBDMAEn, // T_DMAEn
        USBConfig   // T_Config
    >;
    
    static void USBSendStatus(bool s) {
        alignas(void*) // Aligned to send via USB
        bool status = s;
        
        USB::Send(STM::Endpoint::DataIn, &status, sizeof(status));
    }
    
    static void USBAcceptCommand(bool s) {
        USBSendStatus(s);
    }
    
    [[noreturn]]
    static void Abort() {
        Toastbox::IntState ints(false);
        
        for (bool x=true;; x=!x) {
            LED0::Write(x);
            LED1::Write(x);
            for (volatile uint32_t i=0; i<(uint32_t)500000; i++);
        }
    }
    
private:
    struct _TaskCmdRecv {
        static void Run() {
            // Init system
            // We have to call _Init from within a task, instead of before running the scheduler,
            // because _Init requires interrupts to be enabled, and interrupts are disabled until
            // the first task (this task) executes. See Startup.cpp for why we disable interrupts
            // until our first task executes.
            // (At least one reason -- and there are likely several reasons -- that interrupts
            // need to be enabled for _Init is because the USB init code has some sleeps that
            // require HAL_Delay to work, which requires the SysTick interrupt to fire.)
            _Init();
            
            for (;;) {
                STM::Cmd cmd;
                USB::CmdRecv(cmd);
                
                // Dispatch the command to our handler task
                const bool accepted = _TaskCmdHandle::Handle(cmd);
                // Tell the host whether we accepted the command
                USB::CmdAccept(accepted);
            }
        }
        
        // Task stack
        static constexpr auto& Stack = _TaskCmdRecvStack;
    };
    
    struct _TaskCmdHandle {
        static bool Handle(const STM::Cmd& c) {
            using namespace STM;
            // Short-circuit if we already have a command, and the new command isn't a Reset command.
            // We specifically allow Reset commands to interrupt whatever command is currently
            // underway, since Reset commands are meant to recover from a broken state and
            // _TaskCmdHandle might be hung.
            if (_Cmd && c.op!=Op::Reset) return false;
            _Cmd = c;
            Scheduler::template Start<_TaskCmdHandle>(Run);
            return true;
        }
        
        static void Run() {
            using namespace STM;
            
            switch (_Cmd->op) {
            case Op::Reset:             _Reset(*_Cmd);              break;
            case Op::StatusGet:         _StatusGet(*_Cmd);          break;
            case Op::BootloaderInvoke:  _BootloaderInvoke(*_Cmd);   break;
            case Op::LEDSet:            _LEDSet(*_Cmd);             break;
            default:                    USBAcceptCommand(false);    break;
            }
            
            _Cmd = std::nullopt;
        }
        
        static inline std::optional<STM::Cmd> _Cmd;
        
        // Task stack
        [[gnu::section(".stack._TaskCmdHandle")]]
        alignas(void*)
        static inline uint8_t Stack[1024];
    };
    
    static void _Init() {
        GPIO::Init<
            LED0,
            LED1,
            
            _USB_DM,
            _USB_DP,
            
            _OSC_IN,
            _OSC_OUT,
            
            T_Pins...
        >();
        
        // Reset peripherals, initialize flash interface, initialize SysTick
        HAL_Init();
        
        // Configure the system clock
        _ClockInit();
        
        // Allow debugging while we're asleep
        HAL_DBGMCU_EnableDBGSleepMode();
        HAL_DBGMCU_EnableDBGStopMode();
        HAL_DBGMCU_EnableDBGStandbyMode();
        
        // Configure USB
        USB::Init();
    }
    
    static void _ClockInit() {
        // Configure the main internal regulator output voltage
        {
            __HAL_RCC_PWR_CLK_ENABLE();
            __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE3);
        }
        
        // Initialize RCC oscillators
        {
            RCC_OscInitTypeDef cfg = {};
            cfg.OscillatorType = RCC_OSCILLATORTYPE_HSE;
            cfg.HSEState = RCC_HSE_BYPASS;
            cfg.PLL.PLLState = RCC_PLL_ON;
            cfg.PLL.PLLSource = RCC_PLLSOURCE_HSE;
            cfg.PLL.PLLM = 8;
            cfg.PLL.PLLN = 128;
            cfg.PLL.PLLP = RCC_PLLP_DIV2;
            cfg.PLL.PLLQ = 2;
            
            HAL_StatusTypeDef hr = HAL_RCC_OscConfig(&cfg);
            Assert(hr == HAL_OK);
        }
        
        // Initialize bus clocks for CPU, AHB, APB
        {
            RCC_ClkInitTypeDef cfg = {};
            cfg.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK|RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
            cfg.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
            cfg.AHBCLKDivider = RCC_SYSCLK_DIV1;
            cfg.APB1CLKDivider = RCC_HCLK_DIV4;
            cfg.APB2CLKDivider = RCC_HCLK_DIV2;
            
            HAL_StatusTypeDef hr = HAL_RCC_ClockConfig(&cfg, FLASH_LATENCY_6);
            Assert(hr == HAL_OK);
        }
    }
    
    static void _Reset(const STM::Cmd& cmd) {
        // Reset USB endpoints
        USB::EndpointsReset();
        // Send status
        USBSendStatus(true);
    }
    
    static void _StatusGet(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        
        // Send status struct
        alignas(void*) // Aligned to send via USB
        const STM::Status status = {
            .header     = STM::StatusHeader,
            .mspVersion = 0,
            .mode       = T_Mode,
        };
        
        USB::Send(STM::Endpoint::DataIn, &status, sizeof(status));
    }
    
    static void _BootloaderInvoke(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        // Perform software reset
        HAL_NVIC_SystemReset();
        // Unreachable
        Assert(false);
    }
    
    static void _LEDSet(const STM::Cmd& cmd) {
        switch (cmd.arg.LEDSet.idx) {
        case 0:  USBAcceptCommand(true); LED0::Write(cmd.arg.LEDSet.on); break;
        case 1:  USBAcceptCommand(true); LED1::Write(cmd.arg.LEDSet.on); break;
        default: USBAcceptCommand(false); return;
        }
    }
};

// MARK: - IntState

bool Toastbox::IntState::Get() {
    return !__get_PRIMASK();
}

void Toastbox::IntState::Set(bool en) {
    if (en) __enable_irq();
    else __disable_irq();
}

using _System = System<
    STM::Status::Mode::STMApp,  // T_Mode
    true,                       // T_USBDMAEn
    
    // T_Pins
    std::tuple<>,
    
    // T_Tasks
    std::tuple<>
>;

using _Scheduler = _System::Scheduler;
using _USB = _System::USB;

// MARK: - ISRs

extern "C" [[gnu::section(".isr")]] void ISR_SysTick() {
    _Scheduler::Tick();
    HAL_IncTick();
}

extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS() {
    _USB::ISR();
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

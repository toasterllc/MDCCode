#pragma once
#include <cstring>
#include "GPIO.h"
#include "Util.h"
#include "STM.h"
#include "USB.h"
#include "I2C.h"
#include "MSP.h"
#include "BoolLock.h"
#include "USBConfig.h"
#include "Assert.h"
#include "MSP430JTAG.h"
#include "Toastbox/Scheduler.h"

// MARK: - Interrupt Stack
// This is the stack that's used to handle interrupts.
// It's large because STM's USB code is large and executes in the interrupt context.

#define _StackInterruptSize 1024

[[gnu::section(".stack.interrupt")]]
alignas(sizeof(void*))
uint8_t _StackInterrupt[_StackInterruptSize];

asm(".global _StackInterruptEnd");
asm(".equ _StackInterruptEnd, _StackInterrupt+" Stringify(_StackInterruptSize));

// MARK: - System

template <
STM::Status::Mode T_Mode,
bool T_USBDMAEn,
auto T_CmdHandle,
auto T_Reset,
typename... T_Tasks
>
class System {
public:
    static constexpr uint8_t CPUFreqMHz = 128;
    static constexpr uint32_t SysTickPeriodUs = 1000;
    
private:
    #warning TODO: remove stack guards for production
    static constexpr size_t _StackGuardCount = 4;
    
    using _I2C_SCL  = GPIO::PortB::Pin<8>;
    using _I2C_SDA  = GPIO::PortB::Pin<9>;
    
    using _MSP_TEST = GPIO::PortG::Pin<11>;
    using _MSP_RST_ = GPIO::PortG::Pin<12>;
    
    using _USB_DM   = GPIO::PortB::Pin<14, GPIO::Option::Speed3, GPIO::Option::AltFn12>;
    using _USB_DP   = GPIO::PortB::Pin<15, GPIO::Option::Speed3, GPIO::Option::AltFn12>;
    
    // _OSC_IN / _OSC_OUT: used for providing external clock
    // There's no alt function to configure here; we just need these to exist so that GPIO
    // enables the clock for the relevent port (PortH)
    using _OSC_IN   = GPIO::PortH::Pin<0>;
    using _OSC_OUT  = GPIO::PortH::Pin<1>;
    
    using _BAT_CHRG_STAT          = GPIO::PortE::Pin<15, GPIO::Option::Input, GPIO::Option::Resistor1, GPIO::Option::IntRiseFall>;
    using _BAT_CHRG_STAT_PULLDOWN = GPIO::PortE::Pin<15, GPIO::Option::Input, GPIO::Option::Resistor0, GPIO::Option::IntRiseFall>;
    using _BAT_CHRG_STAT_INT      = GPIO::PortE::Pin<15, GPIO::Option::Input, GPIO::Option::Resistor1, GPIO::Option::IntRiseFall, GPIO::Option::IntEn>;
    
    [[noreturn]]
    static void _SchedulerStackOverflow() {
        Abort();
    }
    
    static void _Sleep() {
        __WFI();
    }
    
    struct _TaskCmdRecv;
    struct _TaskCmdHandle;
    struct _TaskMSPComms;
    
public:
    template <typename... T_Pins>
    [[noreturn]]
    static void Run() {
        GPIO::Init<
            LED0,
            LED1,
            LED2,
            LED3,
            
            MSPJTAG::Pin::Test,
            MSPJTAG::Pin::Rst_,
            
            _USB_DM,
            _USB_DP,
            
            _OSC_IN,
            _OSC_OUT,
            
            _BAT_CHRG_STAT,
            
            typename _I2C::Pin::SCL,
            typename _I2C::Pin::SDA,
            
            T_Pins...
        >();
        
        // Start our default tasks running
        Scheduler::template Start<_TaskCmdRecv, _TaskMSPComms>();
        Scheduler::Run();
    }
    
    // LEDs
    using LED0 = GPIO::PortB::Pin<10, GPIO::Option::Output0>;
    using LED1 = GPIO::PortB::Pin<12, GPIO::Option::Output0>;
    using LED2 = GPIO::PortB::Pin<11, GPIO::Option::Output0>;
    using LED3 = GPIO::PortB::Pin<13, GPIO::Option::Output0>;
    
    using Scheduler = Toastbox::Scheduler<
        SysTickPeriodUs,                            // T_UsPerTick: microseconds per tick
        
        _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                    //          invoked when no tasks have work to do
        
        _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
        _SchedulerStackOverflow,                    // T_StackOverflow: function to handle stack overflow
        _StackInterrupt,                            // T_StackInterrupt: stack used for handling interrupts;
                                                    //                   Scheduler only uses this to detect stack overflow
        
        _TaskCmdRecv,                               // T_Tasks: list of tasks
        _TaskCmdHandle,
        _TaskMSPComms,
        T_Tasks...
    >;
    
    // MSP Spy-bi-wire
    using MSPJTAG = MSP430JTAG<_MSP_TEST, _MSP_RST_, CPUFreqMHz>;
    using MSPLock = BoolLock<Scheduler, _TaskMSPComms::Lock>;
    
    using USB = USBType<
        Scheduler,  // T_Scheduler
        T_USBDMAEn, // T_DMAEn
        USBConfig   // T_Config
    >;
    
    static void USBSendStatus(bool s) {
        alignas(4) bool status = s; // Aligned to send via USB
        USB::Send(STM::Endpoint::DataIn, &status, sizeof(status));
    }
    
    static void USBAcceptCommand(bool s) {
        USBSendStatus(s);
    }
    
    static std::optional<MSP::Resp> MSPSend(const MSP::Cmd& cmd) {
        return _TaskMSPComms::Send(cmd);
    }
    
    #warning TODO: update Abort to accept a domain / line, like we do with MSPApp?
    [[noreturn]]
    static void Abort() {
        Toastbox::IntState ints(false);
        
        for (bool x=true;; x=!x) {
            LED0::Write(x);
            LED1::Write(x);
            LED2::Write(x);
            LED3::Write(x);
            for (volatile uint32_t i=0; i<(uint32_t)500000; i++);
        }
    }
    
    static void ISR_I2CEvent() {
        _I2C::ISR_Event();
    }
    
    static void ISR_I2CError() {
        _I2C::ISR_Error();
    }
    
    static void ISR_ExtInt_15_10() {
        if (_BAT_CHRG_STAT::State::IntClear()) {
            _TaskMSPComms::_BatteryChargeStatusChanged();
        }
    }
    
private:
    static constexpr uint32_t _I2CTimeoutMs = 5000;
    using _I2C = I2CType<Scheduler, _I2C_SCL, _I2C_SDA, MSP::I2CAddr, _I2CTimeoutMs>;
    
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
        [[gnu::section(".stack._TaskCmdRecv")]]
        alignas(sizeof(void*))
        static inline uint8_t Stack[512];
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
            case Op::BatteryStatusGet:  _BatteryStatusGet(*_Cmd);   break;
            case Op::BootloaderInvoke:  _BootloaderInvoke(*_Cmd);   break;
            case Op::LEDSet:            _LEDSet(*_Cmd);             break;
            default:                    T_CmdHandle(*_Cmd);         break;
            }
            
            _Cmd = std::nullopt;
        }
        
        static inline std::optional<STM::Cmd> _Cmd;
        
        // Task stack
        [[gnu::section(".stack._TaskCmdHandle")]]
        alignas(sizeof(void*))
        static inline uint8_t Stack[1024];
    };
    
    struct _TaskMSPComms {
        static inline bool Lock = false;
        
        static void Run() {
            using Deadline = typename Scheduler::Deadline;
            constexpr uint16_t BatteryStatusUpdateIntervalMs = 2000;
            
            Deadline batteryStatusUpdateDeadline = Scheduler::CurrentTime();
            for (;;) {
                // Wait until we get a command or for the deadline to pass
                bool ok = Scheduler::WaitDeadline(batteryStatusUpdateDeadline, [] { return _Cmd.state==_State::Cmd; });
                if (!ok) {
                    // Deadline passed; update battery status
                    _BatteryStatusUpdate();
                    // Update our deadline for the next battery status update
                    batteryStatusUpdateDeadline = Scheduler::CurrentTime() + Scheduler::Ms(BatteryStatusUpdateIntervalMs);
                    continue;
                }
                
                // Send command and return response to the caller
                _Cmd.resp = _Send(_Cmd.cmd);
                // Update our state
                _Cmd.state = _State::Resp;
            }
        }
        
        static void Reset() {
            _Cmd.state = _State::Idle;
        }
        
        static std::optional<MSP::Resp> Send(const MSP::Cmd& cmd) {
            // Wait until we're idle
            Scheduler::Wait([] { return _Cmd.state==_State::Idle; });
            // Supply the I2C command to be sent
            _Cmd.cmd = cmd;
            _Cmd.state = _State::Cmd;
            // Wait until we get a response
            Scheduler::Wait([] { return _Cmd.state==_State::Resp; });
            // Reset our state
            _Cmd.state = _State::Idle;
            return _Cmd.resp;
        }
        
        static const STM::BatteryStatus& BatteryStatus() {
            return _BatteryStatus;
        }
        
//        // Lock(): returns a bool that can be used to ensure only one entity is trying to talk
//        // to the MSP430 at a time.
//        // Currently this is used by the MSP Spy-bi-wire (SBW) facilities to prevent I2C comms
//        // while SBW IO is taking place.
//        static bool& Lock() {
//            return _Lock;
//        }
        
        static std::optional<MSP::Resp> _Send(const MSP::Cmd& cmd) {
            // Acquire mutex while we talk to MSP via I2C, to prevent MSPJTAG from
            // being used until we're done
            MSPLock lock(MSPLock::Lock);
            
            constexpr int AttemptCount = 5;
            constexpr int ErrorDelayMs = 10;
            
            MSP::Resp resp;
            for (int i=0; i<AttemptCount; i++) {
                const auto status = _I2C::Send(cmd, resp);
                switch (status) {
                case _I2C::Status::OK:
                    return resp;
                case _I2C::Status::NAK:
                    // Allow a single NAK before we reset MSP, in case we initiated comms
                    // before MSP was fully booted.
                    if (i) _MSPReset();
                    break;
                case _I2C::Status::Error:
                    // Comms failure; try resetting MSP
                    _MSPReset();
                    break;
                }
                
                Scheduler::Sleep(Scheduler::Ms(ErrorDelayMs));
            }
            
            return std::nullopt;
        }
        
        static void _MSPReset() {
            #warning TODO: remove this assert in the future. we're just using it for debugging so that we know if this occurs
            Assert(false);
            _MSP_RST_::Write(0);
            Scheduler::Sleep(Scheduler::Ms(1));
            _MSP_RST_::Write(1);
            Scheduler::Sleep(Scheduler::Ms(1));
        }
        
        static void _BatteryStatusUpdate() {
            _BatteryStatus = _BatteryStatusGet();
            
            // Update LEDs
            const bool red = (_BatteryStatus.chargeStatus == STM::BatteryStatus::ChargeStatus::Underway);
            const bool green = (_BatteryStatus.chargeStatus == STM::BatteryStatus::ChargeStatus::Complete);
            const MSP::Cmd cmd = {
                .op = MSP::Cmd::Op::LEDSet,
                .arg = { .LEDSet = { .red = red, .green = green }, },
            };
            _Send(cmd);
        }
        
        static STM::BatteryStatus _BatteryStatusGet() {
            STM::BatteryStatus status = {
                .chargeStatus = _ChargeStatusGet(),
                .level = 0,
            };
            
            // Only sample the battery voltage if charging is underway
            // The reason for this is that asserting BAT_CHRG_LVL_EN causes a current draw which
            // fools the battery charger IC's (MCP73831T) battery-detection circuit into thinking
            // a battery is present even if one isn't. So we only want to sample the battery
            // voltage if we know a battery is being charged (and therefore a battery is present),
            // to ensure that we can detect the 'Shutdown' battery state.
            #warning TODO: uncomment `status.chargeStatus` check below
//            if (status.chargeStatus == STM::BatteryStatus::ChargeStatus::Underway) {
                const auto resp = _Send({ .op = MSP::Cmd::Op::BatteryChargeLevelGet });
                if (resp && resp->ok) {
                    status.level = resp->arg.BatteryChargeLevelGet.level;
                }
//            }
            
            return status;
        }
        
        static bool _ChargeStatusOscillating() {
            constexpr uint32_t OscillationThreshold = 2; // Number of transitions to consider the signal to be oscillating
            
            // Start counting _BAT_CHRG_STAT transitions
            {
                Toastbox::IntState ints(false);
                _BAT_CHRG_STAT_INT::Init();
                _BatteryChargeStatusTransitionCount = 0;
            }
            
            // Wait 10ms while we count _BAT_CHRG_STAT transitions
            Scheduler::Sleep(Scheduler::Ms(10));
            
            // Stop counting _BAT_CHRG_STAT transitions
            {
                Toastbox::IntState ints(false);
                _BAT_CHRG_STAT::Init<_BAT_CHRG_STAT_INT>();
            }
            
            return _BatteryChargeStatusTransitionCount > OscillationThreshold;
        }
        
        static STM::BatteryStatus::ChargeStatus _ChargeStatusGet() {
            const bool oscillating = _ChargeStatusOscillating();
            if (oscillating) return STM::BatteryStatus::ChargeStatus::Shutdown;
            
            _BAT_CHRG_STAT_PULLDOWN::Init();
            Scheduler::Sleep(Scheduler::Ms(1));
            const bool a = _BAT_CHRG_STAT::Read();
            
            _BAT_CHRG_STAT::Init<_BAT_CHRG_STAT_PULLDOWN>();
            Scheduler::Sleep(Scheduler::Ms(1));
            const bool b = _BAT_CHRG_STAT::Read();
            
            if (a != b) {
                // _BAT_CHRG_STAT == high-z
                return STM::BatteryStatus::ChargeStatus::Shutdown;
            } else {
                if (!a) {
                    // _BAT_CHRG_STAT == low
                    return STM::BatteryStatus::ChargeStatus::Underway;
                } else {
                    // _BAT_CHRG_STAT == high
                    return STM::BatteryStatus::ChargeStatus::Complete;
                }
            }
        }
        
        static void _BatteryChargeStatusChanged() {
            _BatteryChargeStatusTransitionCount++;
        }
        
        enum class _State {
            Idle,
            Cmd,
            Resp,
        };
        
        static inline struct {
            _State state = _State::Idle;
            MSP::Cmd cmd;
            std::optional<MSP::Resp> resp;
        } _Cmd;
        
        static inline STM::BatteryStatus _BatteryStatus = {};
        
        static inline std::atomic<uint32_t> _BatteryChargeStatusTransitionCount;
        
        // Task stack
        [[gnu::section(".stack._TaskMSPComms")]]
        alignas(sizeof(void*))
        static inline uint8_t Stack[512];
    };
    
    static void _Init() {
        // Reset peripherals, initialize flash interface, initialize SysTick
        HAL_Init();
        
        // Configure the system clock
        _ClockInit();
        
        // Allow debugging while we're asleep
        HAL_DBGMCU_EnableDBGSleepMode();
        HAL_DBGMCU_EnableDBGStopMode();
        HAL_DBGMCU_EnableDBGStandbyMode();
        
        // Configure MSP
        MSPJTAG::Init();
        
        // Configure I2C
        _I2C::Init();
        
        // Configure USB
        USB::Init();
        
        // Enable interrupts for BAT_CHRG_STAT
        constexpr uint32_t InterruptPriority = 2; // Should be >0 so that SysTick can still preempt
        HAL_NVIC_SetPriority(EXTI15_10_IRQn, InterruptPriority, 0);
        HAL_NVIC_EnableIRQ(EXTI15_10_IRQn);
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
        
        {
            RCC_PeriphCLKInitTypeDef cfg = {};
            cfg.PeriphClockSelection = RCC_PERIPHCLK_I2C1|RCC_PERIPHCLK_CLK48;
            cfg.PLLSAI.PLLSAIN = 96;
            cfg.PLLSAI.PLLSAIQ = 2;
            cfg.PLLSAI.PLLSAIP = RCC_PLLSAIP_DIV4;
            cfg.PLLSAIDivQ = 1;
            cfg.I2c1ClockSelection = RCC_I2C1CLKSOURCE_PCLK1;
            cfg.Clk48ClockSelection = RCC_CLK48SOURCE_PLLSAIP;
            
            HAL_StatusTypeDef hr = HAL_RCCEx_PeriphCLKConfig(&cfg);
            Assert(hr == HAL_OK);
        }
    }
    
    static void _Reset(const STM::Cmd& cmd) {
        // Reset tasks
        _TaskMSPComms::Reset();
        // Reset USB endpoints
        USB::EndpointsReset();
        // Call supplied T_Reset function
        T_Reset();
        // Send status
        USBSendStatus(true);
    }
    
    static void _StatusGet(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        
        // Send status struct
        alignas(4) const STM::Status status = { // Aligned to send via USB
            .magic      = STM::Status::MagicNumber,
            .version    = STM::Version,
            .mode       = T_Mode,
        };
        
        USB::Send(STM::Endpoint::DataIn, &status, sizeof(status));
    }
    
    static void _BatteryStatusGet(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        
        alignas(4) // Aligned to send via USB
        const STM::BatteryStatus status = _TaskMSPComms::BatteryStatus();
        USB::Send(STM::Endpoint::DataIn, &status, sizeof(status));
    }
    
    static void _BootloaderInvoke(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        // Perform software reset
        HAL_NVIC_SystemReset();
        // Unreachable
        abort();
    }
    
    static void _LEDSet(const STM::Cmd& cmd) {
        switch (cmd.arg.LEDSet.idx) {
        case 0:  USBAcceptCommand(true); LED0::Write(cmd.arg.LEDSet.on); break;
        case 1:  USBAcceptCommand(true); LED1::Write(cmd.arg.LEDSet.on); break;
        case 2:  USBAcceptCommand(true); LED2::Write(cmd.arg.LEDSet.on); break;
        case 3:  USBAcceptCommand(true); LED3::Write(cmd.arg.LEDSet.on); break;
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

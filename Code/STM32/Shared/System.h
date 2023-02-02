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

// MARK: - Main Thread Stack

#define _StackMainSize 1024

[[gnu::section(".stack.main")]]
alignas(sizeof(void*))
uint8_t _StackMain[_StackMainSize];

asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+" Stringify(_StackMainSize));

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
    static void Init() {
        // Reset peripherals, initialize flash interface, initialize SysTick
        HAL_Init();
        
        // Configure the system clock
        _ClockInit();
        
        // Allow debugging while we're asleep
        HAL_DBGMCU_EnableDBGSleepMode();
        HAL_DBGMCU_EnableDBGStopMode();
        HAL_DBGMCU_EnableDBGStandbyMode();
        
        // Configure LEDs
        _LEDInit();
        
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
    
    // LEDs
    using LED0 = GPIO<GPIOPortB, 10>;
    using LED1 = GPIO<GPIOPortB, 12>;
    using LED2 = GPIO<GPIOPortB, 11>;
    using LED3 = GPIO<GPIOPortB, 13>;
    
    using Scheduler = Toastbox::Scheduler<
        SysTickPeriodUs,                            // T_UsPerTick: microseconds per tick
        
        _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                    //          invoked when no tasks have work to do
        
        _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
        _SchedulerStackOverflow,                    // T_Error: function to handle unrecoverable error
        nullptr,                                    // T_StackInterrupt: unused
        
        _MainTask,                                  // T_Tasks: list of tasks
        _SDTask,
        _ImgTask,
        _I2CTask,
        _ButtonTask
    >;
    
    
    
    
    
    
    
    
    
    using _Scheduler = Toastbox::Scheduler<
        SysTickPeriodUs,                            // T_UsPerTick: microseconds per tick
        
        _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                    //          invoked when no tasks have work to do
        
        _SchedulerStackOverflow,                    // T_StackOverflow: function to call upon an stack overflow
        _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
        ,                    // T_Error: function to handle unrecoverable error
        nullptr,                                    // T_StackInterrupt: unused
        
        _MainTask,                                  // T_Tasks: list of tasks
        _SDTask,
        _ImgTask,
        _I2CTask,
        _ButtonTask
    >;
    
    
    
    
    using Scheduler = Toastbox::Scheduler<
        SysTickPeriodUs,                            // T_UsPerTick: microseconds per tick
        _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                    //          invoked when no tasks have work to do
        _SchedulerError,                            // T_Error: function to call upon an unrecoverable error (eg stack overflow)
        _StackMain,                                 // T_MainStack: main stack pointer (only used to monitor
                                                    //              main stack for overflow; unused if T_StackGuardCount==0)
        4,                                          // T_StackGuardCount: number of pointer-sized stack guard elements to use
        _TaskCmdRecv,                               // T_Tasks: list of tasks
        _TaskCmdHandle,
        _TaskMSPComms,
        T_Tasks...
    >;
    
    // MSP Spy-bi-wire
    using MSP_TEST  = GPIO<GPIOPortG, 11>;
    using MSP_RST_  = GPIO<GPIOPortG, 12>;
    using MSPJTAG = MSP430JTAG<MSP_TEST, MSP_RST_, CPUFreqMHz>;
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
        
        _LEDInit();
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
        if (_BAT_CHRG_STAT::InterruptClear()) {
            _TaskMSPComms::_BatteryChargeStatusChanged();
        }
    }
    
private:
    static constexpr uint32_t _I2CTimeoutMs = 5000;
    using _I2C = I2CType<Scheduler, MSP::I2CAddr, _I2CTimeoutMs>;
    using _BAT_CHRG_STAT = GPIO<GPIOPortE, 15>;
    
    struct _TaskCmdRecv {
        static void Run() {
            for (;;) {
                STM::Cmd cmd;
                USB::CmdRecv(cmd);
                
                // Dispatch the command to our handler task
                const bool accepted = _TaskCmdHandle::Handle(cmd);
                // Tell the host whether we accepted the command
                USB::CmdAccept(accepted);
            }
        }
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{
            .AutoStart = Run, // Task should start running
        };
        
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
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{};
        
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
                bool ok = Scheduler::WaitUntil(batteryStatusUpdateDeadline, [&] { return _Cmd.state==_State::Cmd; });
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
            Scheduler::Wait([&] { return _Cmd.state==_State::Idle; });
            // Supply the I2C command to be sent
            _Cmd.cmd = cmd;
            _Cmd.state = _State::Cmd;
            // Wait until we get a response
            Scheduler::Wait([&] { return _Cmd.state==_State::Resp; });
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
            MSP_RST_::Write(0);
            Scheduler::Sleep(Scheduler::Ms(1));
            MSP_RST_::Write(1);
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
                _BAT_CHRG_STAT::Config(GPIO_MODE_IT_RISING_FALLING, GPIO_PULLUP, GPIO_SPEED_FREQ_LOW, 0);
                _BatteryChargeStatusTransitionCount = 0;
            }
            
            // Wait 10ms while we count _BAT_CHRG_STAT transitions
            Scheduler::Sleep(Scheduler::Ms(10));
            
            // Stop counting _BAT_CHRG_STAT transitions
            {
                Toastbox::IntState ints(false);
                _BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLUP, GPIO_SPEED_FREQ_LOW, 0);
            }
            
            return _BatteryChargeStatusTransitionCount > OscillationThreshold;
        }
        
        static STM::BatteryStatus::ChargeStatus _ChargeStatusGet() {
            const bool oscillating = _ChargeStatusOscillating();
            if (oscillating) return STM::BatteryStatus::ChargeStatus::Shutdown;
            
            _BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLDOWN, GPIO_SPEED_FREQ_LOW, 0);
            Scheduler::Sleep(Scheduler::Ms(1));
            const bool a = _BAT_CHRG_STAT::Read();
            
            _BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLUP, GPIO_SPEED_FREQ_LOW, 0);
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
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{
            .AutoStart = Run, // Task should start running
        };
        
        // Task stack
        [[gnu::section(".stack._TaskMSPComms")]]
        alignas(sizeof(void*))
        static inline uint8_t Stack[512];
    };
    
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
        
        // Enable GPIO clocks
        {
            __HAL_RCC_GPIOB_CLK_ENABLE(); // LED[3:0]
            __HAL_RCC_GPIOE_CLK_ENABLE(); // _BAT_CHRG_STAT
            __HAL_RCC_GPIOG_CLK_ENABLE(); // MSP_TEST / MSP_RST_
            __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
        }
    }
    
    static void _LEDInit() {
        LED0::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED1::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED2::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED3::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
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

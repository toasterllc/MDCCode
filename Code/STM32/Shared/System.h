#pragma once
#include <cstring>
#include <tuple>
#include <ratio>
#include "GPIO.h"
#include "STM.h"
#include "USB.h"
#include "I2C.h"
#include "MSP.h"
#include "BoolLock.h"
#include "USBConfig.h"
#include "Assert.h"
#include "MSP430JTAG.h"
#include "Toastbox/Scheduler.h"
#include "Toastbox/Util.h"

// MARK: - Interrupt Stack
// This is the stack that's used to handle interrupts.
// It's large because STM's USB code is large and executes in the interrupt context.

#define _StackInterruptSize 1024

[[gnu::section(".stack.interrupt")]]
alignas(void*)
uint8_t _StackInterrupt[_StackInterruptSize];

asm(".global _StartupStackInterrupt");
asm(".equ _StartupStackInterrupt, _StackInterrupt+" Stringify(_StackInterruptSize));

#define _TaskCmdRecvStackSize 512

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
auto T_CmdHandle,
auto T_Reset,
typename...
>
class System;

template<
STM::Status::Mode T_Mode,
bool T_USBDMAEn,
auto T_CmdHandle,
auto T_Reset,
typename... T_Pins,
typename... T_Tasks
>
class System<T_Mode, T_USBDMAEn, T_CmdHandle, T_Reset, std::tuple<T_Pins...>, std::tuple<T_Tasks...>> {
public:
    static constexpr uint8_t CPUFreqMHz = 128;
    using SysTickPeriod = std::ratio<1,1000>;
    
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
    
    using _BAT_CHRG_EN_  = GPIO::PortE::Pin<15, GPIO::Option::OpenDrain, GPIO::Option::Output1>;
    using _BAT_CHRG_STAT = GPIO::PortB::Pin<10, GPIO::Option::Input, GPIO::Option::Resistor0>;
    
    [[noreturn]]
    static void _SchedulerStackOverflow() {
//        Toastbox::IntState ints(false);
//        
//        for (bool x=true;; x=!x) {
//            LED0::Write(x);
//            LED1::Write(x);
//            for (volatile uint32_t i=0; i<(uint32_t)2000000; i++);
//        }
        
        Assert(false);
    }
    
    static void _Sleep() {
        __WFI();
    }
    
    struct _TaskCmdRecv;
    struct _TaskCmdHandle;
    struct _TaskMSPComms;
    struct _TaskBatteryStatus;
    
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
        _TaskMSPComms,
        _TaskBatteryStatus,
        T_Tasks...
    >;
    
    // MSP Spy-bi-wire
    using MSPJTAG = MSP430JTAG<_MSP_TEST, _MSP_RST_, CPUFreqMHz>;
    using MSPLock = BoolLock<Scheduler, _TaskMSPComms::Lock>;
    
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
    
    static void BatteryStatusPause(bool x) {
        _TaskBatteryStatus::BatteryStatusPause(x);
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
            for (volatile uint32_t i=0; i<(uint32_t)500000; i++);
        }
    }
    
    static void ISR_I2CEvent() {
        _I2C::ISR_Event();
    }
    
    static void ISR_I2CError() {
        _I2C::ISR_Error();
    }
    
private:
    static constexpr uint32_t _I2CTimeoutMs = 2000;
    using _I2C = T_I2C<Scheduler, _I2C_SCL, _I2C_SDA, MSP::I2CAddr, _I2CTimeoutMs>;
    
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
        alignas(void*)
        static inline uint8_t Stack[1024];
    };
    
    struct _TaskMSPComms {
        static inline bool Lock = false;
        
        static void Run() {
            for (;;) {
                // Wait until we get a command or for the deadline to pass
                Scheduler::Wait([] { return _Cmd.state==_State::Cmd; });
                // Send command and return response to the caller
                _Cmd.resp = _Send(_Cmd.cmd);
                // Update our state
                _Cmd.state = _State::Resp;
                // Give Send() an oppurtunity to consume the response.
                // We reset our state to Idle, instead to have the task calling Send() do it after it
                // consumes the response, so that we can recover if the task calling Send() is stopped
                // and therefore will never consume the response.
                Scheduler::Yield();
                // Reset our state
                _Cmd.state = _State::Idle;
            }
        }
        
        static std::optional<MSP::Resp> Send(const MSP::Cmd& cmd) {
            // Wait until we're idle
            Scheduler::Wait([] { return _Cmd.state==_State::Idle; });
            // Supply the I2C command to be sent
            _Cmd.cmd = cmd;
            _Cmd.state = _State::Cmd;
            // Wait until we get a response
            Scheduler::Wait([] { return _Cmd.state==_State::Resp; });
            return _Cmd.resp;
        }
        
        static std::optional<MSP::Resp> _Send(const MSP::Cmd& cmd) {
            // Acquire mutex while we talk to MSP via I2C, to prevent MSPJTAG from
            // being used until we're done
            MSPLock lock(MSPLock::Lock);
            
            MSP::Resp resp;
            const auto status = _I2C::Send(cmd, resp);
            switch (status) {
            case _I2C::Status::OK:      return resp;
            case _I2C::Status::NAK:     return std::nullopt;
            case _I2C::Status::Error:   return std::nullopt;
            }
            Assert(false);
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
        
        // Task stack
        [[gnu::section(".stack._TaskMSPComms")]]
        alignas(void*)
        static inline uint8_t Stack[512];
    };
    
    struct _TaskBatteryStatus {
        static void Run() {
            constexpr uint32_t UpdateIntervalMs = 2000;
            constexpr uint32_t ResampleBatteryIntervalMs = 150000;
            constexpr uint32_t ResampleBatteryIntervalCount = ResampleBatteryIntervalMs / UpdateIntervalMs;
            constexpr auto UpdateInterval = Scheduler::template Ms<UpdateIntervalMs>;
            
            // Wait until we detect a battery
            for (;;) {
                _BatteryStatus = _BatteryStatusGet();
                if (_BatteryStatus.level != MSP::BatteryLevelMvInvalid) break;
                Scheduler::Sleep(UpdateInterval);
            }
            
            // Turn on battery charger
            _BAT_CHRG_EN_::Write(0);
            Scheduler::Sleep(Scheduler::template Ms<10>);
            
            // If we're already displaying a charge status, wait a bit for battery
            // charging to stabilize.
            //
            // This delay is necessary to workaround the fact that our _BAT_CHRG_EN_
            // net glitches when loading STMApp (because the STM32 GPIO configuration
            // gets reset when the chip resets), causing charging to be momentarily
            // interrupted, which would cause the LED to transition from
            // green->red->green, if not for this workaround.
            if (_BatteryStatus.chargeStatus != MSP::ChargeStatus::Invalid) {
                Scheduler::Sleep(Scheduler::template Ms<10000>);
            }
            
            uint32_t chargeUnderwayCount = 0;
            MSP::BatteryLevelMv batteryLevel = _BatteryStatus.level;
            for (;;) {
                if (!_BatteryStatusPause) {
                    const MSP::ChargeStatus chargeStatus = _ChargeStatusRead();
                    if (chargeStatus == MSP::ChargeStatus::Underway) {
                        chargeUnderwayCount++;
                        if (chargeUnderwayCount >= ResampleBatteryIntervalCount) {
                            chargeUnderwayCount = 0;
                            
                            // Temporarily disable the battery chager while we sample the battery
                            _BAT_CHRG_EN_::Write(1);
                            Scheduler::Sleep(Scheduler::template Ms<1000>);
                            // Sample battery
                            batteryLevel = _BatteryStatusGet().level;
                            // Re-enable the battery charger
                            _BAT_CHRG_EN_::Write(0);
                        }
                    } else {
                        batteryLevel = _BatteryStatusGet().level;
                        chargeUnderwayCount = 0;
                    }
                    
                    _BatteryStatus = {
                        .chargeStatus = chargeStatus,
                        .level = batteryLevel,
                    };
                    
                    // Set the charge status LED
                    _ChargeStatusSet(_BatteryStatus.chargeStatus);
                }
                Scheduler::Sleep(UpdateInterval);
            }
        }
        
        static const STM::BatteryStatus& BatteryStatus() {
            return _BatteryStatus;
        }
        
        static void BatteryStatusPause(bool x) {
            _BatteryStatusPause = x;
        }
        
        static void _ChargeStatusSet(MSP::ChargeStatus status) {
            const MSP::Cmd cmd = {
                .op = MSP::Cmd::Op::ChargeStatusSet,
                .arg = { .ChargeStatusSet = { .status = status }, },
            };
            MSPSend(cmd);
        }
        
        static MSP::ChargeStatus _ChargeStatusRead() {
            return (_BAT_CHRG_STAT::Read() ? MSP::ChargeStatus::Complete : MSP::ChargeStatus::Underway);
        }
        
        static STM::BatteryStatus _BatteryStatusGet() {
            const auto resp = MSPSend({ .op = MSP::Cmd::Op::BatteryStatusGet });
            if (!resp->ok) return {};
            return {
                .chargeStatus = resp->arg.BatteryStatusGet.chargeStatus,
                .level = resp->arg.BatteryStatusGet.level,
            };
        }
        
        static inline STM::BatteryStatus _BatteryStatus = {};
        static inline bool _BatteryStatusPause = false;
        
        // Task stack
        [[gnu::section(".stack._TaskBatteryStatus")]]
        alignas(void*)
        static inline uint8_t Stack[512];
    };
    
    static void _Init() {
        GPIO::Init<
            LED0,
            LED1,
            
            MSPJTAG::Pin::Test,
            MSPJTAG::Pin::Rst_,
            
            _USB_DM,
            _USB_DP,
            
            _OSC_IN,
            _OSC_OUT,
            
            _BAT_CHRG_EN_,
            _BAT_CHRG_STAT,
            
            typename _I2C::Pin::SCL,
            typename _I2C::Pin::SDA,
            
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
        
        // Configure MSP
        MSPJTAG::Init();
        
        // Configure I2C
        _I2C::Init();
        
        // Configure USB
        USB::Init();
        
        // Start _TaskMSPComms task
        Scheduler::template Start<_TaskMSPComms, _TaskBatteryStatus>();
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
        alignas(void*) // Aligned to send via USB
        const STM::Status status = {
            .magic      = STM::Status::MagicNumber,
            .version    = STM::Version,
            .mode       = T_Mode,
        };
        
        USB::Send(STM::Endpoint::DataIn, &status, sizeof(status));
    }
    
    static void _BatteryStatusGet(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        
        alignas(void*) // Aligned to send via USB
        const STM::BatteryStatus status = _TaskBatteryStatus::BatteryStatus();
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

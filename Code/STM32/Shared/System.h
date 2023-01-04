#pragma once
#include <cstring>
#include "GPIO.h"
#include "Util.h"
#include "STM.h"
#include "USB.h"
#include "I2C.h"
#include "MSP.h"
#include "USBConfig.h"
#include "Toastbox/Task.h"

// MARK: - Main Thread Stack

#define _StackMainSize 1024

[[gnu::section(".stack.main")]]
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
    static constexpr uint32_t UsPerSysTick = 1000;
    
private:
    [[noreturn]]
    static void _SchedulerError(uint16_t line) {
        Abort();
    }
    
    static void _Sleep() {
        __WFI();
    }
    
    struct _TaskCmdRecv;
    struct _TaskCmdHandle;
    struct _TaskMSPComms;
    
public:
    static void LEDInit() {
        // Enable GPIO clocks
        __HAL_RCC_GPIOB_CLK_ENABLE();
        
        LED0::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED1::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED2::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED3::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
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
        LEDInit();
        
        // Configure I2C
        _I2C::Init();
        
        // Configure USB
        USB::Init();
    }
    
    // LEDs
    using LED0 = GPIO<GPIOPortB, 10>;
    using LED1 = GPIO<GPIOPortB, 12>;
    using LED2 = GPIO<GPIOPortB, 11>;
    using LED3 = GPIO<GPIOPortB, 13>;
    
    #warning TODO: remove stack guards for production
    using Scheduler = Toastbox::Scheduler<
        UsPerSysTick,                               // T_UsPerTick: microseconds per tick
        Toastbox::IntState::SetInterruptsEnabled,   // T_SetInterruptsEnabled: function to change interrupt state
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
    
    using USB = USBType<
        Scheduler,  // T_Scheduler
        T_USBDMAEn, // T_DMAEn
        USBConfig   // T_Config
    >;
    
    static void USBSendStatus(bool s) {
        alignas(4) bool status = s; // Aligned to send via USB
        USB::Send(STM::Endpoints::DataIn, &status, sizeof(status));
    }
    
    static void USBAcceptCommand(bool s) {
        USBSendStatus(s);
    }
    
    static void Reset(const STM::Cmd& cmd) {
        // Reset endpoints
        USB::EndpointsReset();
        // Call supplied T_Reset function
        T_Reset();
        // Send status
        USBSendStatus(true);
    }
    
    static void StatusGet(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        
        // Send status struct
        alignas(4) const STM::Status status = { // Aligned to send via USB
            .magic      = STM::Status::MagicNumber,
            .version    = STM::Version,
            .mode       = T_Mode,
        };
        
        USB::Send(STM::Endpoints::DataIn, &status, sizeof(status));
    }
    
    static void BatteryStatusGet(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        
        alignas(4) // Aligned to send via USB
        const STM::BatteryStatus status = _TaskMSPComms::BatteryStatus();
        USB::Send(STM::Endpoints::DataIn, &status, sizeof(status));
    }
    
    static void BootloaderInvoke(const STM::Cmd& cmd) {
        // Accept command
        USBAcceptCommand(true);
        // Perform software reset
        HAL_NVIC_SystemReset();
        // Unreachable
        abort();
    }
    
    static void LEDSet(const STM::Cmd& cmd) {
        switch (cmd.arg.LEDSet.idx) {
        case 0:  USBAcceptCommand(true); LED0::Write(cmd.arg.LEDSet.on); break;
        case 1:  USBAcceptCommand(true); LED1::Write(cmd.arg.LEDSet.on); break;
        case 2:  USBAcceptCommand(true); LED2::Write(cmd.arg.LEDSet.on); break;
        case 3:  USBAcceptCommand(true); LED3::Write(cmd.arg.LEDSet.on); break;
        default: USBAcceptCommand(false); return;
        }
    }
    
    static MSP::Resp MSPSend(const MSP::Cmd& cmd) {
        return _TaskMSPComms::Send(cmd);
    }
    
    #warning TODO: update Abort to accept a domain / line, like we do with MSPApp?
    [[noreturn]]
    static void Abort() {
        Toastbox::IntState ints(false);
        
        LEDInit();
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
    
private:
    using _I2C = I2CType<Scheduler, MSP::I2CAddr>;
    using _BAT_CHRG_STAT = GPIO<GPIOPortE, 15>;
    
    struct _TaskCmdRecv {
        static void Run() {
            for (;;) {
                STM::Cmd cmd;
                USB::CmdRecv(cmd);
                
                // Dispatch the command to our handler task
                _TaskCmdHandle::Handle(cmd);
            }
        }
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{
            .AutoStart = Run, // Task should start running
        };
        
        // Task stack
        [[gnu::section(".stack._TaskCmdRecv")]]
        static inline uint8_t Stack[512];
    };
    
    struct _TaskCmdHandle {
        static void Handle(const STM::Cmd& c) {
            // We intentionally don't check for _Cmd==nullopt because we need the Reset
            // command to work even if _TaskCmdHandle is hung from the previous command.
            _Cmd = c;
            Scheduler::template Start<_TaskCmdHandle>(Run);
        }
        
        static void Run() {
            using namespace STM;
            
            switch (_Cmd->op) {
            case Op::Reset:             Reset(*_Cmd);               break;
            case Op::StatusGet:         StatusGet(*_Cmd);           break;
            case Op::BatteryStatusGet:  BatteryStatusGet(*_Cmd);    break;
            case Op::BootloaderInvoke:  BootloaderInvoke(*_Cmd);    break;
            case Op::LEDSet:            LEDSet(*_Cmd);              break;
            default:                    T_CmdHandle(*_Cmd);         break;
            }
            
            _Cmd = std::nullopt;
        }
        
        static inline std::optional<STM::Cmd> _Cmd;
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{};
        
        // Task stack
        [[gnu::section(".stack._TaskCmdHandle")]]
        static inline uint8_t Stack[1024];
    };
    
    struct _TaskMSPComms {
        static void Run() {
            using Deadline = typename Scheduler::Deadline;
            constexpr uint16_t BatteryStatusUpdateIntervalMs = 10000;
            
            Deadline batteryStatusUpdateDeadline = Scheduler::CurrentTime();
            for (;;) {
                // Wait until we get a command or for the deadline to pass
                bool ok = Scheduler::WaitUntil(batteryStatusUpdateDeadline, [&] { return (bool)_Cmd; });
                if (!ok) {
                    // Deadline passed; update battery status
                    _BatteryStatusUpdate();
                    // Update our deadline for the next battery status update
                    batteryStatusUpdateDeadline = Scheduler::CurrentTime() + Scheduler::Ms(BatteryStatusUpdateIntervalMs);
                    continue;
                }
                
                MSP::Resp resp;
                ok = _I2C::Send(_Cmd, resp);
                #warning TODO: handle errors properly
                Assert(ok);
                // Return the response to the caller
                _Resp = resp;
            }
        }
        
        static MSP::Resp Send(const MSP::Cmd& cmd) {
            // Wait until _Cmd is empty
            Scheduler::Wait([&] { return !_Cmd; });
            // Supply the I2C command to be sent
            _Cmd = cmd;
            // Wait until we get a response
            Scheduler::Wait([&] { return _Resp; });
            const MSP::Resp resp = *_Resp;
            // Reset our state
            _Cmd = std::nullopt;
            _Resp = std::nullopt;
            return resp;
        }
        
        static const STM::BatteryStatus& BatteryStatus() {
            return _BatteryStatus;
        }
        
        static void _BatteryStatusUpdate() {
            _BatteryStatus = _BatteryStatusGet();
            
            // Update LEDs
            bool red = false;
            bool green = false;
            switch (_BatteryStatus.chargeStatus) {
            case STM::BatteryStatus::ChargeStatus::Underway: red = true; break;
            case STM::BatteryStatus::ChargeStatus::Complete: green = true; break;
            }
            
            const MSP::Cmd cmd = {
                .op = MSP::Cmd::Op::LEDSet,
                .arg = { .LEDSet = { .red = red, .green = green }, },
            };
            
            MSP::Resp resp;
            const bool ok = _I2C::Send(cmd, resp);
            #warning TODO: handle errors properly
            Assert(ok);
            Assert(resp.ok);
        }
        
        static STM::BatteryStatus _BatteryStatusGet() {
            STM::BatteryStatus status = {
                .chargeStatus = _ChargeStatusGet(),
                .voltage = 0,
            };
            
            // Only sample the battery voltage if charging is underway
            if (status.chargeStatus == STM::BatteryStatus::ChargeStatus::Underway) {
                const MSP::Cmd mspCmd = { .op = MSP::Cmd::Op::BatterySample };
                const MSP::Resp mspResp = MSPSend(mspCmd);
                if (mspResp.ok) {
                    status.voltage = mspResp.arg.BatterySample.sample;
                }
            }
            
            return status;
        }
        
        static STM::BatteryStatus::ChargeStatus _ChargeStatusGet() {
            using namespace STM;
            
            // The battery charger IC (MCP73831T-2ACI/OT) has tristate output, where:
            //   high-z: shutdown / no battery
            //   low: charging underway
            //   high: charging complete
            // To sense these 3 different states, we configure our GPIO with a pullup
            // and read the value of the pin, repeat with a pulldown, and compare the
            // read values.
            _BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLUP, GPIO_SPEED_FREQ_LOW, 0);
            Scheduler::Sleep(Scheduler::Ms(10));
            const bool a = _BAT_CHRG_STAT::Read();
            
            _BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLDOWN, GPIO_SPEED_FREQ_LOW, 0);
            Scheduler::Sleep(Scheduler::Ms(10));
            const bool b = _BAT_CHRG_STAT::Read();
            
            if (a != b) {
                // _BAT_CHRG_STAT == high-z
                return BatteryStatus::ChargeStatus::Shutdown;
            } else {
                if (!a) {
                    // _BAT_CHRG_STAT == low
                    return BatteryStatus::ChargeStatus::Underway;
                } else {
                    // _BAT_CHRG_STAT == high
                    return BatteryStatus::ChargeStatus::Complete;
                }
            }
        }
        
        static inline std::optional<MSP::Cmd> _Cmd;
        static inline std::optional<MSP::Resp> _Resp;
        static inline STM::BatteryStatus _BatteryStatus = {};
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{
            .AutoStart = Run, // Task should start running
        };
        
        // Task stack
        [[gnu::section(".stack._TaskMSPComms")]]
        static inline uint8_t Stack[256];
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
            __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
        }
    }
};

// MARK: - IntState

bool Toastbox::IntState::InterruptsEnabled() {
    return !__get_PRIMASK();
}

void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __enable_irq();
    else __disable_irq();
}

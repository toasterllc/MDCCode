#pragma once
#include "GPIO.h"
#include "MSP430JTAG.h"
#include "Util.h"
#include "STM.h"
#include "USB.h"
#include "QSPI.h"
#include "ICE.h"
#include "Toastbox/Task.h"

// MARK: - Main Thread Stack

#define _StackMainSize 1024

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+" Stringify(_StackMainSize));

// MARK: - System

template <
    typename T_USB,
    typename T_QSPI,
    STM::Status::Mode T_Mode,
    void T_CmdHandle(const STM::Cmd&),
    typename... T_Tasks
>
class System {
private:
    class _TaskCmdRecv;
    class _TaskCmdHandle;
    
    [[noreturn]]
    static void _SchedulerError(uint16_t line) {
        Abort();
    }
    
    [[noreturn]]
    static void _ICEError(uint16_t line) {
        Abort();
    }
    
    static void _Sleep() {
        // Sleep and then enable interrupts.
        // It's important not to enable interrupts before we go to sleep. If
        // we did that, there's a race window where an interrupt could fire
        // and signal that work needs to be done by a task, but then we go
        // to sleep instead of invoking the scheduler to run the tasks.
        __WFI();
        Toastbox::IntState::SetInterruptsEnabled(true);
    }
    
public:
    static constexpr uint8_t CPUFreqMHz = 128;
    static constexpr uint32_t UsPerSysTick = 1000;
    
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
        T_Tasks...
    >;
    
private:
    // _TaskCmdRecv: receive commands over USB initiate handling them
    struct _TaskCmdRecv {
        static void Run() {
            for (;;) {
                // Wait for USB to be re-connected (`Connecting` state) so we can call USB.connect(),
                // or for a new command to arrive so we can handle it.
                Scheduler::Wait([] { return USB.state()==T_USB::State::Connecting || USB.cmdRecv(); });
                
                // Disable interrupts so we can inspect+modify `USB` atomically
                Toastbox::IntState ints(false);
                
                // Reset all tasks
                // This needs to happen before we call `USB.connect()` so that any tasks that
                // were running in the previous USB session are stopped before we enable
                // USB again by calling USB.connect().
                _TasksReset();
                
                switch (USB.state()) {
                case T_USB::State::Connecting:
                    USB.connect();
                    continue;
                case T_USB::State::Connected:
                    if (!USB.cmdRecv()) continue;
                    break;
                default:
                    continue;
                }
                
                auto usbCmd = *USB.cmdRecv();
                
                // Re-enable interrupts while we handle the command
                ints.restore();
                
                // Reject command if the length isn't valid
                STM::Cmd cmd;
                if (usbCmd.len != sizeof(cmd)) {
                    USB.cmdAccept(false);
                    continue;
                }
                
                memcpy(&cmd, usbCmd.data, usbCmd.len);
                
                // Only accept command if it's a flush command (in which case the endpoints
                // don't need to be ready), or it's not a flush command, but all endpoints
                // are ready. Otherwise, reject the command.
                if (cmd.op!=STM::Op::EndpointsFlush && !USB.endpointsReady()) {
                    USB.cmdAccept(false);
                    continue;
                }
                
                USB.cmdAccept(true);
                _TaskCmdHandle::Start(cmd);
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
    
    // _TaskCmdHandle: handle command
    struct _TaskCmdHandle {
        static void Start(const STM::Cmd& c) {
            using namespace STM;
            static STM::Cmd cmd = {};
            cmd = c;
            
            Scheduler::template Start<_TaskCmdHandle>([] {
                switch (cmd.op) {
                case Op::EndpointsFlush:    _EndpointsFlush(cmd);       break;
                case Op::StatusGet:         _StatusGet(cmd);            break;
                case Op::BootloaderInvoke:  _BootloaderInvoke(cmd);     break;
                case Op::LEDSet:            _LEDSet(cmd);               break;
                // Bad command
                default:                    T_CmdHandle(cmd);           break;
                }
            });
        }
        
        // Task options
        static constexpr Toastbox::TaskOptions Options{};
        
        // Task stack
        [[gnu::section(".stack._TaskCmdHandle")]]
        static inline uint8_t Stack[1024];
    };

public:
    
    static void InitLED() {
        // Enable GPIO clocks
        __HAL_RCC_GPIOB_CLK_ENABLE();
        __HAL_RCC_GPIOE_CLK_ENABLE();
        
//        LED0::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
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
        
        // Configure our LEDs
        InitLED();
        
        // Init MSP
        MSP.init();
    }
    
    using MSPTest = GPIO<GPIOPortB, GPIO_PIN_1>;
    using MSPRst_ = GPIO<GPIOPortB, GPIO_PIN_0>;
    static inline MSP430JTAG<MSPTest, MSPRst_, CPUFreqMHz> MSP;
    
    using ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    
    using ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
    using ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    // LEDs
//    using LED0 = GPIO<GPIOPortF, GPIO_PIN_14>;
    using LED1 = GPIO<GPIOPortE, GPIO_PIN_7>;
    using LED2 = GPIO<GPIOPortE, GPIO_PIN_10>;
    using LED3 = GPIO<GPIOPortE, GPIO_PIN_12>;
    
    static inline T_USB USB;
    static inline T_QSPI QSPI;

    using ICE = ::ICE<Scheduler, _ICEError>;
    
    static void USBSendStatus(bool s) {
        alignas(4) static bool status = false; // Aligned to send via USB
        status = s;
        USB.send(STM::Endpoints::DataIn, &status, sizeof(status));
    }
    
    #warning TODO: update Abort to accept a domain / line, like we do with MSPApp?
    [[noreturn]]
    static void Abort() {
        Toastbox::IntState ints(false);
        
        InitLED();
        for (bool x=true;; x=!x) {
            LED1::Write(x);
            LED2::Write(x);
            LED3::Write(x);
            for (volatile uint32_t i=0; i<(uint32_t)500000; i++);
        }
    }
    
private:
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
            cfg.PeriphClockSelection = RCC_PERIPHCLK_CLK48;
            cfg.PLLSAI.PLLSAIN = 96;
            cfg.PLLSAI.PLLSAIQ = 2;
            cfg.PLLSAI.PLLSAIP = RCC_PLLSAIP_DIV4;
            cfg.PLLSAIDivQ = 1;
            cfg.Clk48ClockSelection = RCC_CLK48SOURCE_PLLSAIP;
            
            HAL_StatusTypeDef hr = HAL_RCCEx_PeriphCLKConfig(&cfg);
            Assert(hr == HAL_OK);
        }
        
        // Enable GPIO clocks
        {
            __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
        }
    }
    
    static void _TasksReset() {
        Scheduler::template Stop<_TaskCmdHandle>();
        (Scheduler::template Stop<T_Tasks>(), ...);
    }
    
    static void _EndpointsFlush(const STM::Cmd& cmd) {
        // Reset endpoints
        USB.endpointsReset();
        // Wait until endpoints are ready
        Scheduler::Wait([] { return USB.endpointsReady(); });
        // Send status
        USBSendStatus(true);
    }
    
    static void _StatusGet(const STM::Cmd& cmd) {
        // Send status
        USBSendStatus(true);
        // Wait for host to receive status
        Scheduler::Wait([] { return USB.endpointReady(STM::Endpoints::DataIn); });
        
        // Send status struct
        alignas(4) static const STM::Status status = { // Aligned to send via USB
            .magic      = STM::Status::MagicNumber,
            .version    = STM::Version,
            .mode       = T_Mode,
        };
        
        USB.send(STM::Endpoints::DataIn, &status, sizeof(status));
    }
    
    static void _BootloaderInvoke(const STM::Cmd& cmd) {
        // Send status
        USBSendStatus(true);
        // Wait for host to receive status before resetting
        Scheduler::Wait([] { return USB.endpointReady(STM::Endpoints::DataIn); });
        
        // Perform software reset
        HAL_NVIC_SystemReset();
        // Unreachable
        abort();
    }
    
    static void _LEDSet(const STM::Cmd& cmd) {
        switch (cmd.arg.LEDSet.idx) {
        case 0: USBSendStatus(false); return;
        case 1: LED1::Write(cmd.arg.LEDSet.on); break;
        case 2: LED2::Write(cmd.arg.LEDSet.on); break;
        case 3: LED3::Write(cmd.arg.LEDSet.on); break;
        }
        
        // Send status
        USBSendStatus(true);
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

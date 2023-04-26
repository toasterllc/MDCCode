#include <msp430.h>
#include "Toastbox/Scheduler.h"

class _TaskButton;

static constexpr uint64_t _MCLKFreqHz = 16000000;
static constexpr uint32_t _SysTickPeriodUs  = 512;

static void _Sleep();

[[noreturn]]
static void _SchedulerStackOverflow() {
    for (;;);
}

#warning TODO: disable stack guard for production
static constexpr size_t _StackGuardCount = 16;

using _Scheduler = Toastbox::Scheduler<
    _SysTickPeriodUs,                           // T_UsPerTick: microseconds per tick
    
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    
    _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
    _SchedulerStackOverflow,                    // T_StackOverflow: function to handle stack overflow
    nullptr,                                    // T_StackInterrupt: unused
    
    // T_Tasks: list of tasks
    _TaskButton
>;

static void _MCLK16MHz() {
    const uint16_t* CSCTL0Cal16MHz = (uint16_t*)0x1A22;
    
    // Configure one FRAM wait state if MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set REFO as FLL reference source
        CSCTL3 |= SELREF__REFOCLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        
        // Select 16 MHz
        CSCTL1 |= DCORSEL_5;
        
        // Set DCOCLKDIV based on T_MCLKFreqHz and REFOCLKFreqHz
        CSCTL2 = FLLD_0 | (((uint32_t)16000000/(uint32_t)32768)-1);
        
        // Special case: use the factory-calibrated values for CSCTL0 if one is available for the target frequency
        // This significantly speeds up the FLL lock time; without this technique, it takes ~200ms to get an FLL
        // lock (datasheet specifies 280ms as typical). Using the factory-calibrated value, an FLL lock takes 800us.
        CSCTL0 = *CSCTL0Cal16MHz;
        
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Special case: if we're using one of the factory-calibrated values for CSCTL0 (see above),
    // we need to delay 10 REFOCLK cycles. We do this by temporarily switching MCLK to be sourced
    // by REFOCLK, and waiting 10 cycles.
    // This technique is prescribed by "MSP430FR2xx/FR4xx DCO+FLL Applications Guide", and shown
    // by the "MSP430FR2x5x_FLL_FastLock_24MHz-16MHz.c" example code.
    CSCTL4 |= SELMS__REFOCLK;
    __delay_cycles(10);
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
}

using _SysTick = T_SysTick<_MCLKFreqHz, _SysTickPeriodUs>;

// MARK: - _TaskButton

#define _TaskButtonStackSize 128

SchedulerStack(".stack._TaskButton")
uint8_t _TaskButtonStack[_TaskButtonStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskButtonStack+" Stringify(_TaskButtonStackSize));

struct _TaskButton {
    static void _Init() {
        // Stop watchdog timer
        WDTCTL = WDTPW | WDTHOLD;
        
        // Init clock
        _MCLK16MHz();
        
        // Init SysTick
        _SysTick::Init();
        
        // Init RTC
        // We need RTC to be unconditionally enabled for 2 reasons:
        //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
        //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
        //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
        _RTC::Init();
        
        // Restore our saved power state
        // _OnSaved stores our power state across crashes/LPM3.5, so we need to
        // restore our _On assertion based on it.
        if (_OnSaved) {
            _On = true;
        }
    }
    
    static void Run() {
        _Init();
        
        for (;;) {
            const _Button::Event ev = _Button::WaitForEvent();
            // Ignore all interaction in host mode
            if (_HostMode::Asserted()) continue;
            
            // Keep the lights on until we're done handling the event
            _Caffeine::Assertion caffeine(true);
            
            switch (ev) {
            case _Button::Event::Press: {
                // Ignore button presses if we're off
                if (!_On) break;
                
                for (auto it=_Triggers::ButtonTriggerBegin(); it!=_Triggers::ButtonTriggerEnd(); it++) {
                    _TaskEvent::CaptureStart(*it, _RTC::Now());
                }
                break;
            }
            
            case _Button::Event::Hold:
                _On = !_On;
                _OnSaved = _On;
                _LEDFlash(_On ? _LEDGreen_ : _LEDRed_);
                _Button::WaitForDeassert();
                break;
            }
        }
    }
    
    static void _LEDFlash(OutputPriority& led) {
        // Flash red LED to signal that we're turning off
        for (int i=0; i<5; i++) {
            led.set(_LEDPriority::Power, 0);
            _Scheduler::Delay(_Scheduler::Ms(50));
            led.set(_LEDPriority::Power, 1);
            _Scheduler::Delay(_Scheduler::Ms(50));
        }
        led.set(_LEDPriority::Power, std::nullopt);
    }
    
    // _On: controls user-visible on/off behavior
    static inline _Powered::Assertion _On;
    
    // _OnSaved: remembers our power state across crashes and LPM3.5.
    // This is needed because we don't want the device to return to the
    // powered-off state after a crash.
    // Stored in BAKMEM so it's kept alive through low-power modes <= LPM4.
    // gnu::used is apparently necessary for the gnu::section attribute to
    // work when link-time optimization is enabled.
    [[gnu::section(".ram_backup._TaskButton"), gnu::used]]
    static inline bool _OnSaved = false;
    
    // Task stack
    static constexpr auto& Stack = _TaskButtonStack;
};

// MARK: - Main

//extern "C" void Blink() {
//    for (;;) {
//        _Pin::LED_GREEN_::Write(0);
//        for (volatile uint16_t i=0; i<50000; i++);
//        _Pin::LED_GREEN_::Write(1);
//        for (volatile uint16_t i=0; i<50000; i++);
//    }
//}

int main() {
    // Invokes the first task's Run() function (_TaskButton::Run)
    _Scheduler::Run();
}

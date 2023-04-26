#include <msp430.h>
#include <ratio>
#include "Toastbox/Scheduler.h"
#include "Toastbox/Util.h"
#include "SysTick.h"
#include "Time.h"
#include "Assert.h"
#include "GPIO.h"
#include "Timer.h"
using namespace GPIO;

class _TaskMain;

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _SysTickPeriodUs  = 512;
static constexpr uint32_t _VLOFreqHz        = 10240;
static constexpr uint32_t _ACLKFreqHz       = 32768;

struct _Pin {
    // Port A
    using LEDRed   = PortA::Pin<0x0, Option::Output0>;
    using LEDGreen = PortA::Pin<0x1, Option::Output0>;
};

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
    _TaskMain
>;

// _RTCTime: the current time (either absolute or relative, depending on the
// value supplied to Init()).
//
// _RTCTime is volatile because it's updated from the interrupt context.
//
// _RTCTime is stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep.
//
// _RTCTime needs to live in the _noinit variant of BAKMEM so that RTC
// memory is never automatically initialized, because we don't want it
// to be reset when we abort.
//
// _RTCTime is declared outside of RTCType because apparently with GCC, the
// gnu::section() attribute doesn't work for static member variables within
// templated classes.

[[gnu::section(".ram_backup_noinit.rtc")]]
static volatile Time::Instant _RTCTime;

template<typename T>
static constexpr Time::Ticks _RTCTicksForTocks(uint32_t tocks) {
    return (((Time::Ticks)tocks*T::num)/T::den);
}

class _RTC {
public:
    static constexpr uint32_t Predivider = 1024;
    
    using TocksFreqHzRatio = std::ratio<_VLOFreqHz, Predivider>;
    static_assert(TocksFreqHzRatio::num == 10);
    static_assert(TocksFreqHzRatio::den == 1); // Verify TocksFreqHzRatio division is exact
    static constexpr uint16_t TocksFreqHz = TocksFreqHzRatio::num;
    static_assert(TocksFreqHz == 10); // Debug
    
    using TicksPerTockRatio = std::ratio<Time::TicksFreqHz, TocksFreqHz>;
    static_assert(TicksPerTockRatio::num == 8); // Debug
    static_assert(TicksPerTockRatio::den == 5); // Debug
    
    static constexpr Time::Ticks _TicksForTocks(uint32_t tocks) {
        return _RTCTicksForTocks<TicksPerTockRatio>(tocks);
    }
    
//    static constexpr Time::Ticks _TicksForTocks(uint32_t tocks) {
//        return 0;
//    }
    
    
    static constexpr uint32_t InterruptIntervalTocks = 0x100;
    static constexpr uint32_t InterruptIntervalSec = (InterruptIntervalTocks*TocksFreqHzRatio::den)/TocksFreqHzRatio::num;
    static_assert(InterruptIntervalSec == 25); // Debug
    static constexpr Time::Ticks InterruptIntervalTicks = _RTCTicksForTocks<TicksPerTockRatio>(InterruptIntervalTocks);
    static_assert(InterruptIntervalTicks == 409); // Debug
    
    
    
//    static constexpr uint32_t InterruptIntervalTocks = 0x10000;
//    static constexpr uint32_t InterruptIntervalSec = (InterruptIntervalTocks*TocksFreqHzRatio::den)/TocksFreqHzRatio::num;
//    static_assert(InterruptIntervalSec == 6553); // Debug
//    static constexpr Time::Ticks InterruptIntervalTicks = _RTCTicksForTocks<TicksPerTockRatio>(InterruptIntervalTocks);
//    static_assert(InterruptIntervalTicks == 104857); // Debug
    
    using MsPerTockRatio = std::ratio<1000, TocksFreqHz>;
    static_assert(MsPerTockRatio::den == 1); // Verify MsPerTockRatio division is exact
    static constexpr uint32_t MsPerTock = MsPerTockRatio::num;
    static_assert(MsPerTock == 100); // Debug
    
    static constexpr uint16_t TocksMax = 0xFFFF;
    
    static constexpr uint16_t _RTCMODForTocks(uint32_t tocks) {
        return tocks-1;
    }
    
//    static constexpr uint16_t InterruptCount = (InterruptIntervalSec*TocksFreqHz)-1;
//    static_assert(InterruptCount == 20479); // Debug
    
    static bool Enabled() {
        return RTCCTL != 0;
    }
    
    static void Init(Time::Instant time=0) {
        // Prevent interrupts from firing while we update our time / reset the RTC
        Toastbox::IntState ints(false);
        
        // Decrease the XT1 drive strength to save a little current
        // We're not using this for now because supporting it with LPM3.5 is gross.
        // That's because on a cold start, CSCTL6.XT1DRIVE needs to be set after we
        // clear LOCKLPM5 (to reduce the drive strength after XT1 is running),
        // but on a warm start, CSCTL6.XT1DRIVE needs to be set before we clear
        // LOCKLPM5 (to return the register to its previous state before unlocking).
//        CSCTL6 = (CSCTL6 & ~XT1DRIVE) | XT1DRIVE_0;
        
        // Start RTC if it's not yet running, or restart it if we were given a new time
        if (!Enabled() || time) {
            _RTCTime = time;
            
            RTCMOD = _RTCMODForTocks(InterruptIntervalTocks);
            RTCCTL = RTCSS__VLOCLK | _RTCPSForPredivider<Predivider>() | RTCSR;
            // "TI recommends clearing the RTCIFG bit by reading the RTCIV register
            // before enabling the RTC counter interrupt."
            RTCIV;
            
            // Enable RTC interrupts
            RTCCTL |= RTCIE;
            
            // Wait until RTC is initialized. This is necessary because before the RTC peripheral is initialized,
            // it's possible to read an old value of RTCCNT, which would temporarily reflect the wrong time.
            // Empirically the RTC peripheral is reset and initialized synchronously from its clock (XT1CLK
            // divided by Predivider), so we wait 1.5 cycles of that clock to ensure RTC is finished resetting.
            _Scheduler::Delay(_Scheduler::Ms((3*MsPerTock)/2));
        }
    }
    
    // Tocks(): returns the current tocks offset from _RTCTime, as tracked by the hardware
    // register RTCCNT.
    //
    // Guarantee0: Tocks() will never return 0.
    //
    // Guarantee1: if interrupts are disabled before being called, the Tocks() return value
    // can be safely added to _RTCTime to determine the current time.
    // 
    // Guarantee2: if interrupts are disabled before being called, the Tocks() return value
    // can be safely subtracted from TocksMax+1 to determine the number of tocks until the
    // next overflow occurs / ISR() is called.
    //
    // There are 2 special cases that the Tocks() implementation needs handle:
    //
    //   1. RTCCNT=0
    //      If RTCCNT=0, the RTC overflow interrupt has either occurred or hasn't occurred
    //      (empircally [see Tools/MSP430FR2433-RTCTest] it's possible to observe RTCCNT=0
    //      _before_ the RTCIFG interrupt flag is set / before the ISR occurs). So when
    //      RTCCNT=0, we don't know whether ISR() has been called due to the overflow yet,
    //      and therefore we can't provide either Guarantee1 nor Guarantee2. So to handle
    //      this RTCCNT=0 situation we simply wait 1 RTC clock cycle (with interrupts enabled,
    //      which _Scheduler::Delay() guarantees) to allow RTCCNT to escape 0, therefore
    //      allowing us to provide each Guarantee.
    //
    //   2. RTCIFG=1
    //      It could be the case that RTCIFG=1 upon entry to Tocks() from a previous overflow,
    //      which needs to be explicitly handled to provide Guarantee1 and Guarantee2. We
    //      handle RTCIFG=1 in the same way as the RTCCNT=0: wait 1 RTC clock cycle with
    //      interrupts enabled.
    //
    //      The rationale for why RTCIFG=1 must be explicitly handled to provide the Guarantees
    //      is explained by the following situation: interrupts are disabled, RTCCNT counts
    //      from 0xFFFF -> 0x0 -> 0x1, and then Tocks() is called. In this situation RTCCNT!=0
    //      (because RTCCNT=1) and RTCIFG=1 due to the overflow, and therefore whatever value
    //      RTCCNT contains doesn't reflect the value that should be added to _RTCTime to
    //      get the current time (Guarantee1), because _RTCTime needs to be updated by ISR().
    //      Nor does RTCCNT reflect the number of tocks until the next time ISR() is called
    //      (Guarantee2), because ISR() will be called as soon as interrupts are enabled,
    //      because RTCIFG=1.
    //
    static uint16_t Tocks() {
        for (;;) {
            const uint16_t tocks = RTCCNT;
            if (tocks==0 || _OverflowPending()) {
                _Scheduler::Delay(_Scheduler::Ms(MsPerTock));
                continue;
            }
            return tocks;
        }
    }
    
    static Time::Instant Now() {
        // Disable interrupts so that reading _RTCTime and adding RTCCNT to it is atomic
        // (with respect to overflow causing _RTCTime to be updated)
        Toastbox::IntState ints(false);
        // Make sure to read Tocks() before _RTCTime, to ensure that _RTCTime reflects the
        // value read by Tocks(), since Tocks() enables interrupts in some cases, allowing
        // _RTCTime to be updated.
        const uint16_t tocks = Tocks();
        return _RTCTime + _TicksForTocks(tocks);
    }
    
    // TimeUntilOverflow(): must be called with interrupts disabled to ensure that the overflow
    // interrupt doesn't occur before the caller finishes using the returned value.
    static Time::Ticks TimeUntilOverflow() {
        // Note that the below calculation `(TocksMax-Tocks())+1` will never overflow a uint16_t,
        // because Tocks() never returns 0.
        return _TicksForTocks((TocksMax-Tocks())+1);
    }
    
    static void ISR(uint16_t iv) {
        switch (__even_in_range(iv, RTCIV_RTCIF)) {
        case RTCIV_RTCIF:
            // Update our time
            _RTCTime += InterruptIntervalTicks;
            return;
        default:
            Assert(false);
        }
    }
    
private:
    template <class...>
    static constexpr std::false_type _AlwaysFalse = {};
    
    template <uint16_t T_Predivider>
    static constexpr uint16_t _RTCPSForPredivider() {
             if constexpr (T_Predivider == 1)       return RTCPS__1;
        else if constexpr (T_Predivider == 10)      return RTCPS__10;
        else if constexpr (T_Predivider == 100)     return RTCPS__100;
        else if constexpr (T_Predivider == 1000)    return RTCPS__1000;
        else if constexpr (T_Predivider == 16)      return RTCPS__16;
        else if constexpr (T_Predivider == 64)      return RTCPS__64;
        else if constexpr (T_Predivider == 256)     return RTCPS__256;
        else if constexpr (T_Predivider == 1024)    return RTCPS__1024;
        else static_assert(_AlwaysFalse<T_Predivider>);
    }
    
    static bool _OverflowPending() {
        return RTCCTL & RTCIF;
    }
};

using _SysTick = T_SysTick<_MCLKFreqHz, _SysTickPeriodUs>;

// _EventTimer: timer that triggers us to wake when the next event is ready to be handled
using _EventTimer = T_Timer<_RTC, _ACLKFreqHz>;

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
    
    // MCLK / SMCLK source = DCOCLKDIV
    //         ACLK source = REFOCLK
    CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
}

// MARK: - _TaskMain

#define _TaskMainStackSize 512

SchedulerStack(".stack._TaskMain")
uint8_t _TaskMainStack[_TaskMainStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskMainStack+" Stringify(_TaskMainStackSize));

struct _TaskMain {
    static void _Init() {
        // Stop watchdog timer
        WDTCTL = WDTPW | WDTHOLD;
        
        // Init GPIOs
        GPIO::Init<
            _Pin::LEDRed,
            _Pin::LEDGreen
        >();
        
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
    }
    
    static void Run() {
        _Init();
        
        for (;;) {
            const auto nextTime = _RTC::Now() - 10*Time::TicksFreqHz;
            _EventTimer::Schedule(nextTime);
            _Scheduler::Wait([] { return _EventTimer::Fired(); });
            _Pin::LEDRed::Write(!_Pin::LEDRed::Read());
            
            
            
//            _Scheduler::Sleep(_Scheduler::Ms(1000));
//            _Pin::LEDRed::Write(0);
//            _Scheduler::Sleep(_Scheduler::Ms(1000));
        }
    }
    
    // Task stack
    static constexpr auto& Stack = _TaskMainStack;
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

// MARK: - IntState

inline bool Toastbox::IntState::Get() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::Set(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

// MARK: - Sleep

static void _Sleep() {
    // Remember our current interrupt state, which IntState will restore upon return
    Toastbox::IntState ints;
    // Atomically enable interrupts and go to sleep
    __bis_SR_register(GIE | LPM3_bits);
}

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    _RTC::ISR(RTCIV);
    if (_EventTimer::ISRRTCInterested()) {
        _EventTimer::ISRRTC();
        // Wake if the timer fired
        if (_EventTimer::Fired()) {
            __bic_SR_register_on_exit(LPM3_bits);
        }
    }
}

[[gnu::interrupt(TIMER0_A1_VECTOR)]]
static void _ISR_Timer0() {
    _EventTimer::ISRTimer0(TA0IV);
    // Wake if the timer fired
    if (_EventTimer::Fired()) {
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_SysTick() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

// Abort(): called various Assert's throughout our program
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr) {
    for (;;);
}

int main() {
    // Invokes the first task's Run() function (_TaskMain::Run)
    _Scheduler::Run();
}

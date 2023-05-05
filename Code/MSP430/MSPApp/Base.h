#pragma once
#include <ratio>
#include "Assert.h"
#include "Debug.h"

class _TaskMain;
class _TaskEvent;
class _TaskSD;
class _TaskImg;
class _TaskI2C;
class _TaskMotion;

static constexpr uint32_t _XT1FreqHz        = 32768;        // 32.768 kHz
static constexpr uint32_t _ACLKFreqHz       = _XT1FreqHz;   // 32.768 kHz
static constexpr uint32_t _MCLKFreqHz       = 16000000;     // 16 MHz
static constexpr uint32_t _SysTickFreqHz    = 2048;         // 2.048 kHz

static void _Sleep();

[[noreturn]]
static void _SchedulerStackOverflow() {
    Assert(false);
}

#warning TODO: disable stack guard for production
static constexpr size_t _StackGuardCount = 16;

using _Scheduler = Toastbox::Scheduler<
    std::ratio<1, _SysTickFreqHz>,              // T_TickPeriod: time period between ticks
    
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    
    _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
    _SchedulerStackOverflow,                    // T_StackOverflow: function to handle stack overflow
    nullptr,                                    // T_StackInterrupt: unused
    
    // T_Tasks: list of tasks
    _TaskMain,
    _TaskEvent,
    _TaskSD,
    _TaskImg,
    _TaskI2C,
    _TaskMotion
>;

using _Debug = T_Debug<_Scheduler>;

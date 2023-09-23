#include <msp430.h>
#include <cstdint>
#include <cstdbool>
#include <cstddef>
#include <atomic>
#include <ratio>
#include "Toastbox/Scheduler.h"
#include "Toastbox/Util.h"
#include "SDCard.h"
#include "ICE.h"
#include "ImgSensor.h"
#include "ImgAutoExposure.h"
#include "Startup.h"
#include "GPIO.h"
#include "Clock.h"
#include "RTC.h"
#include "SPI.h"
#include "Watchdog.h"
#include "SysTick.h"
#include "RegLocker.h"
#include "MSP.h"
#include "GetBits.h"
#include "ImgSD.h"
#include "I2C.h"
#include "OutputPriority.h"
#include "BatterySampler.h"
#include "Button.h"
#include "AssertionCounter.h"
#include "Triggers.h"
#include "Motion.h"
#include "Assert.h"
#include "Timer.h"
#include "Debug.h"
#include "WiredMonitor.h"
#include "System.h"
#include "Property.h"
#include "Time.h"
#include "TimeConstants.h"
#include "LED.h"
using namespace GPIO;

using _Clock = T_Clock<_Scheduler, _MCLKFreqHz, _Pin::MSP_XIN, _Pin::MSP_XOUT>;
using _SysTick = T_SysTick<_Scheduler, _ACLKFreqHz>;
using _SPI = T_SPI<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;
using _ICE = T_ICE<_Scheduler>;

using _I2C = T_I2C<_Scheduler, _Pin::MSP_STM_I2C_SCL, _Pin::MSP_STM_I2C_SDA, MSP::I2CAddr>;
using _Motion = T_Motion<_Scheduler, _Pin::MOTION_EN_, _Pin::MOTION_SIGNAL>;

using _BatterySampler = T_BatterySampler<_Scheduler, _Pin::BAT_CHRG_LVL, _Pin::BAT_CHRG_LVL_EN>;

using _Button = T_Button<_Scheduler, _Pin::BUTTON_SIGNAL_>;

using _WiredMonitor = T_WiredMonitor<_Pin::VDD_B_3V3_STM>;

static constexpr uint32_t _FlickerPeriodMs      = 5000;
static constexpr uint32_t _FlickerOnDurationMs  = 20;
using _LED = T_LED<_Scheduler, _Pin::LED_SEL, _Pin::LED_SIGNAL, _ACLKFreqHz, _FlickerPeriodMs, _FlickerOnDurationMs>;

//static OutputPriority _LEDGreen_(_Pin::LED_GREEN_{});
//static OutputPriority _LEDRed_(_Pin::LED_RED_{});

// _ImgSensor: image sensor object
using _ImgSensor = Img::Sensor<
    _Scheduler,             // T_Scheduler
    _ICE                    // T_ICE
>;

// _SDCard: SD card object
using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    6                   // T_ClkDelayFast (odd values invert the clock)
>;

// _RTC: real time clock
using _RTC = T_RTC<_Scheduler, _XT1FreqHz>;
using _Watchdog = T_Watchdog<_ACLKFreqHz, (Time::Ticks64)_RTC::InterruptIntervalTicks*2>;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in FRAM because it needs to persist indefinitely.
[[gnu::section(".persistent")]]
static MSP::State _State = {
    .header = MSP::StateHeader,
};

static void _EventsEnabledUpdate();
static void _EventsEnabledChanged();

static void _MotionPoweredUpdate();

static void _VDDIMGSDEnabledChanged();

// _TaskPowerStateSaved: remembers our power state across crashes and LPM3.5.
//
// This needs to be a global for the gnu::section attribute to work.
[[gnu::section(".ram_backup_bss._TaskPowerStateSaved")]]
static inline uint8_t _TaskPowerStateSaved = 0;

// _EventsEnabled: whether _TaskEvent should be running and handling events
static T_Property<bool,_EventsEnabledChanged,_MotionPoweredUpdate> _EventsEnabled;

using _MotionPowered = T_AssertionCounter<_MotionPoweredUpdate>;

// VDDIMGSD enable/disable
using _VDDIMGSDEnabled = T_AssertionCounter<_VDDIMGSDEnabledChanged>;

// _Triggers: stores our current event state
using _Triggers = T_Triggers<_State, _MotionPowered::Assertion>;

static Time::Ticks32 _RepeatAdvance(MSP::Repeat& x) {
    static constexpr Time::Ticks32 YearPlusDay = Time::Year+Time::Day;
    
    switch (x.type) {
    case MSP::Repeat::Type::Never:
        return 0;
    
    case MSP::Repeat::Type::Daily:
        Assert(x.Daily.interval);
        return Time::Day*x.Daily.interval;
    
    case MSP::Repeat::Type::Weekly: {
        #warning TODO: verify this works properly
        // Determine the next trigger day, calculating the duration of time until then
        Assert(x.Weekly.days & 1); // Weekly.days must always rest on an active day
        x.Weekly.days |= 0x80;
        uint8_t count = 0;
        do {
            x.Weekly.days >>= 1;
            count++;
        } while (!(x.Weekly.days & 1));
        return count*Time::Day;
    }
    
    case MSP::Repeat::Type::Yearly:
        #warning TODO: verify this works properly
        // Return 1 year (either 365 or 366 days) in microseconds
        // We appropriately handle leap years by referencing `leapPhase`
        if (x.Yearly.leapPhase) {
            x.Yearly.leapPhase--;
            return Time::Year;
        } else {
            x.Yearly.leapPhase = 3;
            return YearPlusDay;
        }
    }
    Assert(false);
}

[[gnu::noinline]]
static constexpr Time::Instant _TimeInstantAdd(const Time::Instant& time, Time::Ticks32 deltaTicks) {
    return time + deltaTicks;
}

[[gnu::noinline]]
static constexpr Time::Instant _TimeInstantSubtract(const Time::Instant& time, Time::Ticks32 deltaTicks) {
    if (time < deltaTicks) return 0;
    return time - deltaTicks;
}

static constexpr Time::Ticks32 _TicksForMs(uint64_t ms) {
    return ((ms * Time::TicksPeriod::den) / (1000 * Time::TicksPeriod::num));
}

template<typename T_Dst, typename T_Src>
static T_Dst& _Cast(T_Src& x) {
    return static_cast<T_Dst&>(x);
}

// MARK: - Abort

static void _ResetRecord(MSP::Reset::Type type, uint16_t ctx) {
    using namespace MSP;
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    Reset* hist = nullptr;
    for (Reset& h : _State.resets) {
        if (!h.count || (h.type==type && h.ctx.u16==ctx)) {
            hist = &h;
            break;
        }
    }
    
    // If we don't have a place to record the abort, bail
    if (!hist) return;
    
    // If this is the first occurrence of this kind of reset, fill out its fields.
    if (hist->count == 0) {
        hist->type = type;
        hist->ctx.u16 = ctx;
    }
    
    // Increment the count, but don't allow it to overflow
    if (hist->count < std::numeric_limits<decltype(hist->count)>::max()) {
        hist->count++;
    }
}

[[noreturn]]
static void _BOR() {
    PMMCTL0 = PMMPW | PMMSWBOR;
    // Wait for reset
    for (;;);
}

// Abort(): called by Assert() with the address that aborted
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr) {
    // Disable interrupts
    Toastbox::IntState::Set(false);
    // Record the abort
    _ResetRecord(MSP::Reset::Type::Abort, addr);
    // Wait until all prints have been drained, so we don't drop important
    // info by aborting before it's been read.
    while (!Debug::Empty());
    _BOR();
}

extern "C"
[[noreturn]]
void abort() {
    Assert(false);
}

extern "C"
int atexit(void (*)(void)) {
    return 0;
}

// MARK: - Power

static void _VDDIMGSDEnabledChanged() {
    if (_VDDIMGSDEnabled::Asserted()) {
        _Pin::VDD_B_2V8_IMG_SD_EN::Write(1);
        _Scheduler::Sleep(_Scheduler::Us<100>); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V8)
        _Pin::VDD_B_1V8_IMG_SD_EN::Write(1);
        
        // Rails take ~1ms to turn on, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms<2>);
    
    } else {
        // No delay between 2V8/1V8 needed for power down (per AR0330CS datasheet)
        _Pin::VDD_B_2V8_IMG_SD_EN::Write(0);
        _Pin::VDD_B_1V8_IMG_SD_EN::Write(0);
        
        // Rails take ~1.5ms to turn off, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms<2>);
    }
}

// MARK: - ICE40

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    _SPI::WriteRead(msg, resp);
}

static void _ICEInit() {
    bool ok = false;
    for (int i=0; i<100 && !ok; i++) {
        _Scheduler::Sleep(_Scheduler::Ms<1>);
        // Reset ICE comms (by asserting SPI CLK for some length of time)
        _SPI::ICEReset();
        // Init ICE comms
        ok = _ICE::Init();
    }
    Assert(ok);
}





// MARK: - _TaskLED

struct _TaskLED {
    using Priority = uint8_t;
    static constexpr Priority PriorityButton        = 0;
    static constexpr Priority PriorityBatteryTrap   = 1;
    static constexpr Priority PriorityChargeState   = 2;
    static constexpr Priority _PriorityCount        = 3;
    
    static void Run() {
        for (;;) {
            // Wait until we're signalled
            _Scheduler::Wait([] { return (bool)_State || _Flash; });
            
            // Consume new state
            const std::optional<_LED::State> state = _State;
            const bool flash = _Flash;
            _State = std::nullopt;
            _Flash = false;
            
            // Handle state/flash
            if (state) _LED::StateSet(*state);
            if (flash) _LED::Flash();
        }
    }
    
    static void Set(Priority pri, std::optional<_LED::State> state) {
        _States[pri] = state;
        
        // Update _State
        // By default, turn the LEDs off, unless there's an alternative state requested
        _State = 0;
        for (std::optional<_LED::State> s : _States) {
            if (s) {
                _State = s;
                break;
            }
        }
    }
    
    static void Flash() {
        _Flash = true;
    }
    
    static inline std::optional<_LED::State> _States[_PriorityCount];
    static inline std::optional<_LED::State> _State;
    static inline bool _Flash = false;
    
    // Task stack
    SchedulerStack(".stack._TaskLED")
    static inline uint8_t Stack[128];
};








// MARK: - _TaskPower

#define _TaskPowerStackSize 128

SchedulerStack(".stack._TaskPower")
uint8_t _TaskPowerStack[_TaskPowerStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskPowerStack+" Stringify(_TaskPowerStackSize));

struct _TaskPower {
    static void Run() {
        // Disable interrupts because _Init() and _Wired require it
        Toastbox::IntState ints(false);
        
        _Init();
        
        for (;;) {
            // Wait until something triggers us to update
            _Scheduler::Wait([] { return _Wired()!=_WiredMonitor::Wired() || _BatteryLevelUpdate; });
            
            // Update our wired state
            _Wired(_WiredMonitor::Wired());
            
            if (_BatteryLevelUpdate) {
                // Update our battery level
                _BatteryLevelSet(_BatterySampler::Sample());
                
                // Update our state
                _RTCCounter = _BatterySampleIntervalRTC;
                _CaptureCounter = _BatterySampleIntervalCapture;
                _BatteryLevelUpdate = false;
            }
        }
    }
    
    static MSP::BatteryLevelMv BatteryLevelGet() {
        return _BatteryLevel;
    }
    
    static void BatteryLevelUpdate() {
        _BatteryLevelUpdate = true;
    }
    
    static void BatteryLevelWait() {
        _Scheduler::Wait([] { return !_BatteryLevelUpdate; });
    }
    
    static bool On() { return _On(); }
    static void On(bool x) { _On(x); }
    static bool Wired() { return _Wired(); }
    static bool BatteryTrap() { return _BatteryTrap(); }
    
    static void CaptureNotify() {
        // Short-circuit if we're in battery trap
        // We don't want to monitor the battery while we're in battery trap, to minimize battery use
        if (_BatteryTrap()) return;
        
        _CaptureCounter--; // Rollover OK since we reset _CaptureCounter in Run()
        if (!_CaptureCounter) {
            BatteryLevelUpdate();
            BatteryLevelWait();
        }
    }
    
    static bool ISRRTC() {
        // Short-circuit if we're in battery trap
        // We don't want to monitor the battery while we're in battery trap, to minimize battery use
        if (_BatteryTrap()) return false;
        
        _RTCCounter--; // Rollover OK since we reset _RTCCounter in Run()
        if (!_RTCCounter) {
            BatteryLevelUpdate();
            return true;
        }
        return false;
    }
    
    // _Init(): initialize system
    //
    // Ints: disabled
    //   Rationale: GPIO::Init() and _RTC::Init() require it, and in general we don't want
    //   interrupts to fire while we configure our other subsystems
    static void _Init() {
        // Init watchdog first
        _Watchdog::Init();
        
        // Init GPIOs
        GPIO::Init<
            // Power control
            _Pin::VDD_B_EN,
            _Pin::VDD_B_1V8_IMG_SD_EN,
            _Pin::VDD_B_2V8_IMG_SD_EN,
            
            // Clock (config chosen by _Clock)
            _Clock::Pin::XIN,
            _Clock::Pin::XOUT,
            
            // SPI (config chosen by _SPI)
            _SPI::Pin::Clk,
            _SPI::Pin::DataOut,
            _SPI::Pin::DataIn,
            
            // I2C (config chosen by _I2C)
            _I2C::Pin::SCL,
            _I2C::Pin::SDA,
            
            // Motion (config chosen by _Motion)
            _Motion::Pin::Power,
            _Motion::Pin::Signal,
            
            // Battery (config chosen by _BatterySampler)
            _BatterySampler::Pin::BatChrgLvl,
            _BatterySampler::Pin::BatChrgLvlEn,
            
            // Button (config chosen by _Button)
            _Button::Pin,
            
            // Wired
            _WiredMonitor::Pin,
            
            // LEDs
            _LED::Pin::Select,
            _LED::Pin::Signal
        
        >(Startup::ColdStart());
        
        // Init clock
        _Clock::Init();
        
//        _Pin::LED_RED_::Write(1);
//        for (;;) {
//            _Pin::LED_RED_::Write(1);
//            __delay_cycles(1000000);
//            _Pin::LED_RED_::Write(0);
//            __delay_cycles(1000000);
//        }
        
//        _Pin::LED_RED_::Write(1);
//        _Pin::LED_GREEN_::Write(1);
//        for (;;) {
//            _Pin::LED_RED_::Write(0);
//            __delay_cycles(1000000);
//            _Pin::LED_RED_::Write(1);
//            __delay_cycles(1000000);
//        }
        
//        _Pin::LED_RED_::Write(1);
//        _Pin::LED_GREEN_::Write(1);
//        for (;;) {
//            _Pin::LED_RED_::Write(0);
////            __delay_cycles(1000000);
//            _Scheduler::Delay(_Scheduler::Ms<100>);
//            _Pin::LED_RED_::Write(1);
////            __delay_cycles(1000000);
//            _Scheduler::Delay(_Scheduler::Ms<100>);
//        }
        
        // Init RTC
        // We need RTC to be unconditionally enabled for 2 reasons:
        //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
        //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
        //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
        _RTC::Init();
        
        // Init BatterySampler
        _BatterySampler::Init();
        
        // Start tasks
        _Scheduler::Start<_TaskI2C, _TaskMotion, _TaskButton, _TaskLED>();
        
        // Restore our saved power state
        // This is necessary so that we return to our previous state after an abort.
        _State = _TaskPowerStateSaved;
        
        // Trigger a battery level update when first starting
        BatteryLevelUpdate();
    }
    
    static void _StateChanged() {
        _TaskPowerStateSaved = _State;
    }
    
    static bool _On() {
        return _State & _StateOn;
    }
    
    static void _On(bool x) {
        // Short-circuit if our state didn't change
        if (x == _On()) return;
        if (x) _State = _State |  _StateOn;
        else   _State = _State & ~_StateOn;
    }
    
    static bool _Wired() {
        return _State & _StateWired;
    }
    
    static void _Wired(bool x) {
        // Short-circuit if our state didn't change
        if (x == _Wired()) return;
        
        uint8_t s = _State;
        if (x) {
            // Entering the Wired state
            // Turn ourself on
            s |= _StateOn | _StateWired;
        } else {
            // Exiting the Wired state
            // Exit the On state if we're in BatteryTrap
            if (_BatteryTrap()) s &= ~_StateOn;
            s &= ~_StateWired;
        }
        _State = s;
    }
    
    static void _BatteryLevelSet(MSP::BatteryLevelMv x) {
        // No short-circuit logic here because we need our first _BatteryLevel assignment
        // to cause us to enter battery trap via our logic below, if the battery level is
        // low enough.
        _BatteryLevel = x;
        
        // If our battery level drops below the Enter threshold, enter battery trap
        if (_BatteryLevel <= _BatteryTrapLevelEnter) {
            _BatteryTrap(true);
        
        // If our battery level raises above the Exit threshold, exit battery trap
        } else if (_BatteryLevel >= _BatteryTrapLevelExit) {
            _BatteryTrap(false);
        }
    }
    
    static bool _BatteryTrap() {
        return _State & _StateBatteryTrap;
    }
    
    static void _BatteryTrap(bool x) {
        // Short-circuit if our state didn't change
        if (x == _BatteryTrap()) return;
        
        uint8_t s = _State;
        if (x) {
            // Entering BatteryTrap
            // Turn ourself off if we're not wired
            if (!_Wired()) s &= ~_StateOn;
            s |= _StateBatteryTrap;
        } else {
            s &= ~_StateBatteryTrap;
        }
        _State = s;
    }
    
    static void _LEDFlickerEnabledUpdate() {
        _LEDFlickerEnabled = _BatteryTrap() && !_Wired();
    }
    
    static void _LEDFlickerEnabledChanged() {
        if (_LEDFlickerEnabled) {
            _TaskLED::Set(_TaskLED::PriorityBatteryTrap, _LED::StateRed | _LED::StateFlicker);
        } else {
            _TaskLED::Set(_TaskLED::PriorityBatteryTrap, std::nullopt);
        }
    }
    
    static constexpr uint8_t _StateOff          = 0;
    static constexpr uint8_t _StateOn           = 1<<0;
    static constexpr uint8_t _StateBatteryTrap  = 1<<1;
    static constexpr uint8_t _StateWired        = 1<<2;
    
    static constexpr uint16_t _BatterySampleIntervalRTCDays = 4;
    static constexpr uint16_t _BatterySampleIntervalRTC     = (_BatterySampleIntervalRTCDays * Time::Day) / _RTC::InterruptIntervalTicks;
    static constexpr uint16_t _BatterySampleIntervalCapture = 512;
    static_assert(_BatterySampleIntervalRTC == 168);  // Debug
    
    // _BatteryTrapLevelEnter/_BatteryTrapLevelExit: these are the millivolt values corresponding
    // to the indicated battery percentages. These were calculated by linearizing the battery
    // discharge plot. (See battery discharge table in MDCStudio.)
    static constexpr MSP::BatteryLevelMv _BatteryTrapLevelEnter = 3321; // 2% battery
    static constexpr MSP::BatteryLevelMv _BatteryTrapLevelExit  = 3681; // 10% battery
    
    static inline uint16_t _RTCCounter = 0;
    static inline uint16_t _CaptureCounter = 0;
    
    static inline MSP::BatteryLevelMv _BatteryLevel = MSP::BatteryLevelMvInvalid;
    static inline bool _BatteryLevelUpdate = false;
    
    // _State: our current power state
    // Left uninitialized because we always initialize it with _TaskPowerStateSaved
    static inline T_Property<uint8_t,_StateChanged,_EventsEnabledUpdate,_LEDFlickerEnabledUpdate,_MotionPoweredUpdate> _State;
    
    // _LEDFlickerEnabled: whether the LED should flicker periodically (due to battery trap)
    static inline T_Property<bool,_LEDFlickerEnabledChanged> _LEDFlickerEnabled;
    
    // Task stack
    static constexpr auto& Stack = _TaskPowerStack;
};

// MARK: - _TaskI2C

struct _TaskI2C {
    static void Run() {
        for (;;) {
            // Wait until STM is up (ie we're plugged in)
            _Scheduler::Wait([] { return _WiredMonitor::Wired(); });
            
            _I2C::Init();
            
            for (;;) {
                // Wait for a command
                MSP::Cmd cmd;
                bool ok = _I2C::Recv(cmd);
                if (!ok) break;
                
                // Handle command
                const MSP::Resp resp = _CmdHandle(cmd);
                
                // Send response
                ok = _I2C::Send(resp);
                if (!ok) break;
            }
            
            // Cleanup
            // Relinquish LEDs, which may have been set by _CmdHandle()
            _TaskLED::Set(_TaskLED::PriorityChargeState, std::nullopt);
            
            // Reset state
            _HostModeState = {};
        }
    }
    
    static void WiredChanged() {
        // If we became unwired, restart our I2C state machine
        if (!_WiredMonitor::Wired()) _I2C::Abort();
    }
    
    static MSP::Resp _CmdHandle(const MSP::Cmd& cmd) {
        using namespace MSP;
        switch (cmd.op) {
        case Cmd::Op::None:
            return MSP::Resp{ .ok = false };
        
        case Cmd::Op::StateRead: {
            const size_t off = cmd.arg.StateRead.off;
            if (off > sizeof(::_State)) return MSP::Resp{ .ok = false };
            const size_t rem = sizeof(::_State)-off;
            const size_t len = std::min(rem, sizeof(MSP::Resp::arg.StateRead.data));
            MSP::Resp resp = { .ok = true };
            memcpy(resp.arg.StateRead.data, (uint8_t*)&::_State+off, len);
            return resp;
        }
        
        case Cmd::Op::StateWrite: {
            const size_t off = cmd.arg.StateWrite.off;
            if (off > sizeof(::_State)) return MSP::Resp{ .ok = false };
            FRAMWriteEn writeEn; // Enable FRAM writing
            const size_t rem = sizeof(::_State)-off;
            const size_t len = std::min(rem, sizeof(MSP::Cmd::arg.StateWrite.data));
            memcpy((uint8_t*)&::_State+off, cmd.arg.StateWrite.data, len);
            return MSP::Resp{ .ok = true };
        }
        
        case Cmd::Op::ChargeStatusGet: {
            return MSP::Resp{
                .ok = true,
                .arg = { .ChargeStatusGet = { .status = _HostModeState.chargeStatus } },
            };
        }
        
        case Cmd::Op::ChargeStatusSet: {
            _HostModeState.chargeStatus = cmd.arg.ChargeStatusSet.status;
            return MSP::Resp{ .ok = true };
        }
        
        case Cmd::Op::TimeGet:
            return MSP::Resp{
                .ok = true,
                .arg = { .TimeGet = { .state = _RTC::TimeState() } },
            };
        
        case Cmd::Op::TimeSet:
            // Only allow setting the time while we're in host mode
            // and therefore _TaskEvent isn't running
            if (!_HostModeState.en) return MSP::Resp{ .ok = false };
            _RTC::Init(&cmd.arg.TimeSet.state);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::TimeAdjust:
            // Only allow setting the time while we're in host mode
            // and therefore _TaskEvent isn't running
            if (!_HostModeState.en) return MSP::Resp{ .ok = false };
            _RTC::Adjust(cmd.arg.TimeAdjust.adjustment);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::HostModeSet:
            if (cmd.arg.HostModeSet.en) {
                _HostModeState.en = true;
            } else {
                // Clear entire _HostModeState when exiting host mode
                _HostModeState = {};
            }
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::VDDIMGSDSet:
            if (!_HostModeState.en) return MSP::Resp{ .ok = false };
            _HostModeState.vddImgSd = cmd.arg.VDDIMGSDSet.en;
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::BatteryLevelGet: {
            _TaskPower::BatteryLevelUpdate();
            _TaskPower::BatteryLevelWait();
            return MSP::Resp{
                .ok = true,
                .arg = { .BatteryLevelGet = { .level = _TaskPower::BatteryLevelGet() } },
            };
        }}
        
        return MSP::Resp{ .ok = false };
    }
    
    static bool HostModeEnabled() {
        return _HostModeState.en;
    }
    
    static std::optional<_LED::State> _LEDStateForChargeStatus(MSP::ChargeStatus x) {
        switch (x) {
        case MSP::ChargeStatus::Underway: return _LED::StateRed;
        case MSP::ChargeStatus::Complete: return _LED::StateGreen;
        default: return std::nullopt;
        }
    }
    
    static void _ChargeStatusChanged() {
        _TaskLED::Set(_TaskLED::PriorityChargeState, _LEDStateForChargeStatus(_HostModeState.chargeStatus));
    }
    
    static inline struct {
        T_Property<bool,_EventsEnabledUpdate> en;
        T_Property<MSP::ChargeStatus,_ChargeStatusChanged> chargeStatus;
        _VDDIMGSDEnabled::Assertion vddImgSd;
    } _HostModeState;
    
    // Task stack
    SchedulerStack(".stack._TaskI2C")
    static inline uint8_t Stack[256];
};

// MARK: - _TaskSD

//static void debugSignal() {
//    _Pin::DEBUG_OUT::Init();
//    for (;;) {
////    for (int i=0; i<10; i++) {
//        _Pin::DEBUG_OUT::Write(0);
//        for (volatile int i=0; i<10000; i++);
//        _Pin::DEBUG_OUT::Write(1);
//        for (volatile int i=0; i<10000; i++);
//    }
//}

struct _TaskSD {
    static void Reset() {
        // Reset our state
        _State = {};
    }
    
    static void CardReset() {
        Wait();
        _Scheduler::Start<_TaskSD>([] { _CardReset(); });
    }
    
    static void CardInit() {
        Wait();
        _Scheduler::Start<_TaskSD>([] { _CardInit(); });
    }
    
    static void Write(uint8_t srcRAMBlock) {
        Wait();
        _State.writing = true;
        
        static struct { uint8_t srcRAMBlock; } Args;
        Args = { srcRAMBlock };
        _Scheduler::Start<_TaskSD>([] { _Write(Args.srcRAMBlock); });
    }
    
    static void Wait() {
        _Scheduler::Wait<_TaskSD>();
    }
    
    // SDStateReady(): returns whether we're done initializing _State.sd
    static bool SDStateReady() {
        return (bool)_State.rca;
    }
    
    static bool Writing() {
        return _State.writing;
    }
    
//    static void WaitForInit() {
//        _Scheduler::Wait([&] { return _RCA.has_value(); });
//    }
    
    static void _CardReset() {
        _SDCard::Reset();
    }
    
    static void _CardInit() {
        if (!_State.rca) {
            // We haven't successfully enabled the SD card since _TaskSD::Reset();
            // enable the SD card and get the card id / card data.
            SD::CardId cardId;
            SD::CardData cardData;
            _State.rca = _SDCard::Init(&cardId, &cardData);
            
            // If SD state isn't valid, or the existing SD card id doesn't match the current
            // card id, reset the SD state.
            if (!::_State.sd.valid || memcmp(&::_State.sd.cardId, &cardId, sizeof(cardId))) {
                _SDStateInit(cardId, cardData);
            
            // Otherwise the SD state is valid and the SD card id matches, so init the ring buffers.
            } else {
                _ImgRingBufInit();
            }
        
        } else {
            // We've previously enabled the SD card successfully since _TaskSD::Reset();
            // enable it again
            _SDCard::Init();
        }
    }
    
    static void _Write(uint8_t srcRAMBlock) {
        const MSP::ImgRingBuf& imgRingBuf = ::_State.sd.imgRingBufs[0];
        
        // Copy full-size image from RAM -> SD card
        {
            const SD::Block block = MSP::SDBlockFull(::_State.sd.baseFull, imgRingBuf.buf.idx);
            _SDCard::WriteImage(*_State.rca, srcRAMBlock, block, Img::Size::Full);
        }
        
        // Copy thumbnail from RAM -> SD card
        {
            const SD::Block block = MSP::SDBlockThumb(::_State.sd.baseThumb, imgRingBuf.buf.idx);
            _SDCard::WriteImage(*_State.rca, srcRAMBlock, block, Img::Size::Thumb);
        }
        
        _ImgRingBufIncrement();
        _State.writing = false;
    }
    
    // _SDStateInit(): resets the _State.sd struct
    static void _SDStateInit(const SD::CardId& cardId, const SD::CardData& cardData) {
        using namespace MSP;
        // CombinedBlockCount: thumbnail block count + full-size block count
        constexpr uint32_t CombinedBlockCount = ImgSD::Thumb::ImageBlockCount + ImgSD::Full::ImageBlockCount;
        // blockCap: the capacity of the SD card in SD blocks (1 block == 512 bytes)
        const uint32_t blockCap = ((uint32_t)GetBits<69,48>(cardData)+1) * (uint32_t)1024;
        // imgCap: the capacity of the SD card in number of images
        const uint32_t imgCap = blockCap / CombinedBlockCount;
        
        FRAMWriteEn writeEn; // Enable FRAM writing
        
        // Mark the _State as invalid in case we lose power in the middle of modifying it
        ::_State.sd.valid = false;
        std::atomic_signal_fence(std::memory_order_seq_cst);
        
        // Set .cardId
        {
            ::_State.sd.cardId = cardId;
        }
        
        // Set .imgCap
        {
            ::_State.sd.imgCap = imgCap;
        }
        
        // Set .baseFull / .baseThumb
        {
            ::_State.sd.baseFull = imgCap * ImgSD::Full::ImageBlockCount;
            ::_State.sd.baseThumb = ::_State.sd.baseFull + imgCap * ImgSD::Thumb::ImageBlockCount;
        }
        
        // Set .imgRingBufs
        {
            ImgRingBuf::Set(::_State.sd.imgRingBufs[0], {});
            ImgRingBuf::Set(::_State.sd.imgRingBufs[1], {});
        }
        
        std::atomic_signal_fence(std::memory_order_seq_cst);
        ::_State.sd.valid = true;
    }
    
    // _ImgRingBufInit(): find the correct image ring buffer (the one with the greatest id that's valid)
    // and copy it into the other slot so that there are two copies. If neither slot contains a valid ring
    // buffer, reset them both so that they're both empty (and valid).
    static void _ImgRingBufInit() {
        using namespace MSP;
        FRAMWriteEn writeEn; // Enable FRAM writing
        
        ImgRingBuf& a = ::_State.sd.imgRingBufs[0];
        ImgRingBuf& b = ::_State.sd.imgRingBufs[1];
        const std::optional<int> comp = ImgRingBuf::Compare(a, b);
        if (comp && *comp>0) {
            // a>b (a is newer), so set b=a
            ImgRingBuf::Set(b, a);
        
        } else if (comp && *comp<0) {
            // b>a (b is newer), so set a=b
            ImgRingBuf::Set(a, b);
        
        } else if (!comp) {
            // Both a and b are invalid; reset them both
            ImgRingBuf::Set(a, {});
            ImgRingBuf::Set(b, {});
        }
    }
    
    static void _ImgRingBufIncrement() {
        using namespace MSP;
        const uint32_t imgCap = ::_State.sd.imgCap;
        
        MSP::ImgRingBuf x = ::_State.sd.imgRingBufs[0];
        x.buf.id++;
        x.buf.idx = (x.buf.idx<imgCap-1 ? x.buf.idx+1 : 0);
        
        {
            FRAMWriteEn writeEn; // Enable FRAM writing
            ImgRingBuf::Set(::_State.sd.imgRingBufs[0], x);
            ImgRingBuf::Set(::_State.sd.imgRingBufs[1], x);
        }
    }
    
    static inline struct __State {
        __State() {} // Compiler bug workaround
        // rca: SD card 'relative card address'; needed for SD comms after initialization.
        // As an optional, `rca` also signifies whether we've successfully initiated comms
        // with the SD card since _TaskSD's last Init().
        std::optional<uint16_t> rca;
        // writing: whether writing is currently underway
        bool writing = false;
    } _State;
    
    // Task stack
    SchedulerStack(".stack._TaskSD")
    static inline uint8_t Stack[256];
};

// MARK: - _TaskImg

struct _TaskImg {
    static void Reset() {
        _State = {};
    }
    
    static void SensorInit() {
        Wait();
        _Scheduler::Start<_TaskImg>([] { _SensorInit(); });
    }
    
    static void Capture(const Img::Id& id) {
        Wait();
        
        static struct { Img::Id id; } Args;
        Args = { id };
        _Scheduler::Start<_TaskImg>([] { _Capture(Args.id); });
    }
    
    static uint8_t CaptureBlock() {
        Wait();
        return _State.captureBlock;
    }
    
    static void Wait() {
        _Scheduler::Wait<_TaskImg>();
    }
    
    static void _SensorInit() {
        // Initialize image sensor
        _ImgSensor::Init();
        // Set the initial exposure _before_ we enable streaming, so that the very first frame
        // has the correct exposure, so we don't have to skip any frames on the first capture.
        _ImgSensor::SetCoarseIntTime(_State.autoExp.integrationTime());
        // Enable image streaming
        _ImgSensor::SetStreamEnabled(true);
    }
    
    static void _Capture(const Img::Id& id) {
        // Try up to `CaptureAttemptCount` times to capture a properly-exposed image
        constexpr uint8_t CaptureAttemptCount = 3;
        uint8_t bestExpBlock = 0;
        uint8_t bestExpScore = 0;
        for (uint8_t i=0; i<CaptureAttemptCount; i++) {
            // skipCount:
            // On the initial capture, we didn't set the exposure, so we don't need to skip any images.
            // On subsequent captures, we did set the exposure before the capture, so we need to skip a single
            // image since the first image after setting the exposure is invalid.
            const uint8_t skipCount = (!i ? 0 : 1);
            
            // expBlock: Store images in the block belonging to the worst-exposed image captured so far
            const uint8_t expBlock = !bestExpBlock;
            
            // Populate the header
            static Img::Header header = {
                .magic          = Img::Header::MagicNumber,
                .version        = Img::Header::Version,
                .imageWidth     = Img::Full::PixelWidth,
                .imageHeight    = Img::Full::PixelHeight,
                .coarseIntTime  = 0,
                .analogGain     = 0,
                .id             = 0,
                .timestamp      = 0,
                .batteryLevel   = _TaskPower::BatteryLevelGet(),
            };
            
            header.coarseIntTime = _State.autoExp.integrationTime();
            header.id = id;
            header.timestamp = _RTC::Now();
            
            // Capture an image to RAM
            #warning TODO: optimize the header logic so that we don't set the magic/version/imageWidth/imageHeight every time, since it only needs to be set once per ice40 power-on
            const _ICE::ImgCaptureStatusResp resp = _ICE::ImgCapture(header, expBlock, skipCount);
            const uint8_t expScore = _State.autoExp.update(resp.highlightCount(), resp.shadowCount());
            if (!bestExpScore || (expScore > bestExpScore)) {
                bestExpBlock = expBlock;
                bestExpScore = expScore;
            }
            
            // We're done if we don't have any exposure changes
            if (!_State.autoExp.changed()) break;
            
            // Update the exposure
            _ImgSensor::SetCoarseIntTime(_State.autoExp.integrationTime());
        }
        
        _State.captureBlock = bestExpBlock;
    }
    
    static inline struct __State {
        __State() {} // Compiler bug workaround
        uint8_t captureBlock = 0;
        // _AutoExp: auto exposure algorithm object
        Img::AutoExposure autoExp;
    } _State;
    
    // Task stack
    SchedulerStack(".stack._TaskImg")
    static inline uint8_t Stack[256];
};

// MARK: - _TaskEvent

struct _TaskEvent {
    static void Start() {
        _Scheduler::Start<_TaskEvent>();
    }
    
    static void Reset() {
        // Reset our timer
        _EventTimer::Schedule(std::nullopt);
        // Reset other tasks' state
        // This is necessary because we're stopping them at an arbitrary point
        _TaskSD::Reset();
        _TaskImg::Reset();
        // Stop tasks
        _Scheduler::Stop<_TaskSD, _TaskImg, _TaskEvent>();
        // Reset our state
        // We do this last so that our power assertions are reset last
        _State = {};
    }
    
    static bool ISRRTC() {
        return _EventTimer::ISRRTC();
    }
    
    static bool ISRTimer(uint16_t iv) {
        return _EventTimer::ISRTimer(iv);
    }
    
    static void _TimeTrigger(_Triggers::TimeTriggerEvent& ev) {
        _Triggers::TimeTrigger& trigger = ev.trigger();
        // Schedule the CaptureImageEvent, but only if we're not in fast-forward mode
        if (_State.live) CaptureStart(trigger, ev.time);
        // Reschedule TimeTriggerEvent for its next trigger time
        EventInsert(ev, ev.repeat);
    }
    
    static void _MotionEnablePower(_Triggers::MotionEnablePowerEvent& ev) {
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        // Power on motion sensor
        trigger.stateUpdate(_Triggers::MotionTrigger::StatePowerEnable);
    }
    
    static void _MotionEnable(_Triggers::MotionEnableEvent& ev) {
        _Triggers::MotionTrigger& trigger = ev.trigger();
        
        // Power on the motion sensor, because it may not be powered already, because the very
        // first MotionEnableEvent doesn't have a corresponding MotionEnablePowerEvent, because we
        // schedule the MotionEnablePowerEvent as a result of the MotionEnableEvent, below.
        trigger.stateUpdate(
            _Triggers::MotionTrigger::StatePowerEnable|_Triggers::MotionTrigger::StateMotionEnable,
            _Triggers::MotionTrigger::StateMaxImageCount
        );
        trigger.countRem = trigger.base().count;
        
        // Schedule the MotionDisableEvent, if applicable.
        // This needs to happen before we reschedule `ev` because we need its .time to
        // properly schedule the MotionDisableEvent!
        const uint32_t durationTicks = trigger.base().durationTicks;
        if (durationTicks) {
            EventInsert(_Cast<_Triggers::MotionDisableEvent&>(trigger), _TimeInstantAdd(ev.time, durationTicks));
        }
        
        // Reschedule MotionEnableEvent for its next trigger time
        const bool repeat = EventInsert(ev, ev.repeat);
        
        // Schedule MotionEnablePowerEvent event `PowerOnDelayMs` before the MotionEnableEvent.
        if (repeat) {
            EventInsert(_Cast<_Triggers::MotionEnablePowerEvent>(trigger),
                _TimeInstantSubtract(ev.time, _TicksForMs(_Motion::PowerOnDelayMs)));
        }
    }
    
    static void _MotionDisable(_Triggers::MotionDisableEvent& ev) {
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        // Disable power / motion
        trigger.stateUpdate(
            0,
            _Triggers::MotionTrigger::StatePowerEnable|_Triggers::MotionTrigger::StateMotionEnable
        );
    }
    
    static void _MotionUnsuppressPower(_Triggers::MotionUnsuppressPowerEvent& ev) {
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        // Unsuppress motion power
        trigger.stateUpdate(
            0,
            _Triggers::MotionTrigger::StatePowerSuppress
        );
    }
    
    static void _MotionUnsuppress(_Triggers::MotionUnsuppressEvent& ev) {
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        // Unsuppress motion
        trigger.stateUpdate(
            0,
            _Triggers::MotionTrigger::StateMotionSuppress
        );
    }
    
    static void _CaptureImage(_Triggers::CaptureImageEvent& ev) {
        // We should never get a CaptureImageEvent event while in fast-forward mode
        Assert(_State.live);
        
        constexpr MSP::ImgRingBuf& imgRingBuf = ::_State.sd.imgRingBufs[0];
        
        // Notify _TaskPower that we're performing a capture, and wait for it to sample the battery if it decided to.
        // We do this here because we want the battery sampling to complete before we turn on VDDB / VDDIMGSD and start
        // capturing an image, so that we sample the voltage while the system is quiet, instead of when the system is
        // bursting with activity, which causes lots of noise on the battery line.
        _TaskPower::CaptureNotify();
        
        if (ev.capture->ledFlash) {
            _TaskLED::Flash();
        }
        
        // Turn on VDD_B power (turns on ICE40)
        _State.vddb = true;
        
        // Wait for ICE40 to start
        // We specify (within the bitstream itself, via icepack) that ICE40 should load
        // the bitstream at high-frequency (40 MHz).
        // According to the datasheet, this takes 70ms.
        _Scheduler::Sleep(_Scheduler::Ms<30>);
        _ICEInit();
        
        // Reset SD nets before we turn on SD power
        _TaskSD::CardReset();
        _TaskSD::Wait();
        
        // Turn on IMG/SD power
        _State.vddImgSd = true;
        
        // Init image sensor / SD card
        _TaskImg::SensorInit();
        _TaskSD::CardInit();
        
        // Capture an image
        {
            // Wait until _TaskSD has initialized _State.sd (since we're about to refer to
            // _State.sd.imgRingBufs), and for any previous writing to be complete (because
            // the SDRAM is single-port, so we can't write an image to RAM until we're done
            // copying an image from RAM -> SD card).
            _Scheduler::Wait([] { return _TaskSD::SDStateReady() && !_TaskSD::Writing(); });
            
            // Capture image to RAM
            _TaskImg::Capture(imgRingBuf.buf.id);
            const uint8_t srcRAMBlock = _TaskImg::CaptureBlock();
            
            // Copy image from RAM -> SD card
            _TaskSD::Write(srcRAMBlock);
            _TaskSD::Wait();
        }
        
        _State.vddImgSd = false;
        _State.vddb = false;
        
        ev.countRem--;
        if (ev.countRem) {
            EventInsert(ev, _TimeInstantAdd(ev.time, ev.capture->delayTicks));
        }
    }
    
    static void EventInsert(_Triggers::Event& ev, const Time::Instant& time) {
        _Triggers::EventInsert(ev, time);
        // If this event is now the front of the list, reschedule _EventTimer
        if (_Triggers::EventFront() == &ev) {
            _EventTimerSchedule();
        }
    }
    
    static bool EventInsert(_Triggers::Event& ev, MSP::Repeat& repeat) {
        const Time::Ticks32 delta = _RepeatAdvance(repeat);
        // delta=0 means Repeat=never, in which case we don't reschedule the event
        if (delta) {
            EventInsert(ev, _TimeInstantAdd(ev.time, delta));
            return true;
        }
        return false;
    }
    
//    static void EventInsert(_Triggers::Event& ev, const Time::Instant& time, Time::Ticks32 deltaTicks) {
//        EventInsert(ev, time + deltaTicks);
//    }
    
    static bool CaptureStart(_Triggers::CaptureImageEvent& ev, const Time::Instant& time) {
        // Bail if the CaptureImageEvent is already underway
        if (ev.countRem) return false;
        
        // Reset capture count
        ev.countRem = ev.capture->count;
        if (ev.countRem) {
            EventInsert(ev, time);
        }
        return true;
    }
    
    static void _EventTimerSchedule() {
        // Short-circuit if we're fast-forwarding through events
        if (!_State.live) return;
        _Triggers::Event* ev = _Triggers::EventFront();
        std::optional<Time::Instant> time;
        if (ev) time = ev->time;
        _EventTimer::Schedule(time);
    }
    
    // _EventPop(): pops an event from the front of the list if it's ready to be handled
    // Interrupts must be disabled
    static _Triggers::Event& _EventPop() {
        _Triggers::Event* ev = _Triggers::EventFront();
        Assert(ev); // We must have an event at this point, or else we have a logic error
        _Triggers::EventPop();
        // Schedule _EventTimer for the next event
        _EventTimerSchedule();
        return *ev;
    }
    
    static void _EventHandle(_Triggers::Event& ev) {
        // Handle the event
        using T = _Triggers::Event::Type;
        switch (ev.type) {
        case T::TimeTrigger:
            _TimeTrigger(           _Cast<_Triggers::TimeTriggerEvent&>(ev)             ); break;
        case T::MotionEnablePower:
            _MotionEnablePower(     _Cast<_Triggers::MotionEnablePowerEvent&>(ev)       ); break;
        case T::MotionEnable:
            _MotionEnable(          _Cast<_Triggers::MotionEnableEvent&>(ev)            ); break;
        case T::MotionDisable:
            _MotionDisable(         _Cast<_Triggers::MotionDisableEvent&>(ev)           ); break;
        case T::MotionUnsuppressPower:
            _MotionUnsuppressPower( _Cast<_Triggers::MotionUnsuppressPowerEvent&>(ev)   ); break;
        case T::MotionUnsuppress:
            _MotionUnsuppress(      _Cast<_Triggers::MotionUnsuppressEvent&>(ev)        ); break;
        case T::CaptureImage:
            _CaptureImage(          _Cast<_Triggers::CaptureImageEvent&>(ev)            ); break;
        }
    }
    
    static void Run() {
        // Reset our state
        Reset();
        
        // Init SPI peripheral
        _SPI::Init();
        
        // Init Triggers
        const Time::Instant startTime = _RTC::Now();
        _Triggers::Init(startTime);
        
        // Fast-forward through events
        for (;;) {
            _Triggers::Event* ev = _Triggers::EventFront();
            if (!ev || (ev->time > startTime)) break;
            _EventHandle(_EventPop());
        }
        
        _State.live = true;
        
        // Schedule _EventTimer for the first event
        _EventTimerSchedule();
        
        for (;;) {
            // Wait for _EventTimer to fire
            _EventTimer::Wait();
            _EventHandle(_EventPop());
        }
    }
    
    static void _VDDBEnabledChanged() {
        _Pin::VDD_B_EN::Write(_State.vddb);
        // Rails take ~1.5ms to turn on/off, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms<2>);
    }
    
    // _EventTimer: timer that triggers us to wake when the next event is ready to be handled
    using _EventTimer = T_Timer<_Scheduler, _RTC, _ACLKFreqHz>;
    
    static inline struct __State {
        __State() {} // Compiler bug workaround
        // live=false while initializing, where we execute events in 'fast-forward' mode,
        // solely to arrive at the correct state for the current time.
        // live=true once we're done initializing and executing events normally.
        bool live = false;
        // power / vddb / vddImgSd: our power assertions
        // These need to be ivars because _TaskEvent can be reset at any time via
        // our Reset() function, so if the power assertion lived on the stack and
        // _TaskEvent is reset, its destructor would never be called and our state
        // would be corrupted.
        T_Property<bool,_VDDBEnabledChanged> vddb;
        _VDDIMGSDEnabled::Assertion vddImgSd;
    } _State;
    
    // Task stack
    SchedulerStack(".stack._TaskEvent")
    static inline uint8_t Stack[256];
};

// MARK: - _TaskButton

struct _TaskButton {
    static bool _ButtonInteractionAllowed() {
        // Allow button interaction if we're not in battery trap, or we're wired
        return !_TaskPower::BatteryTrap() || _TaskPower::Wired();
    }
    
    static void _ButtonHoldPrepare() {
        _TaskLED::Set(_TaskLED::PriorityButton, _LED::StateOff);
    }
    
    static void _ButtonHold() {
        _TaskPower::On(!_TaskPower::On());
        _TaskLED::Set(_TaskLED::PriorityButton, _TaskPower::On() ? _LED::StateGreen : _LED::StateRed);
    }
    
    static void _ButtonHoldCleanup() {
        _TaskLED::Set(_TaskLED::PriorityButton, _LED::StateOff);
        _Scheduler::Sleep(_Scheduler::Ms<1000>);
        _TaskLED::Set(_TaskLED::PriorityButton, std::nullopt);
    }
    
    static void _ButtonPress() {
        // Ignore button presses if events are disabled
        if (!_EventsEnabled) return;
        
        for (auto it=_Triggers::ButtonTriggerBegin(); it!=_Triggers::ButtonTriggerEnd(); it++) {
            _TaskEvent::CaptureStart(*it, _RTC::Now());
        }
    }
    
    static void Run() {
        // Disable interrupts because _Button requires it
        Toastbox::IntState ints(false);
        
        // Wait until button is released
        {
            _Button::ConfigUp();
            _Button::Wait();
        }
        
        for (;;) {
            // Wait until button is pressed
            {
                _Button::ConfigDown();
                _Button::Wait();
            }
            
            // Ignore button interaction if necessary
            if (!_ButtonInteractionAllowed()) continue;
            
            // Wait until button is released
            {
                _Button::ConfigUp();
                const bool up = _Button::Wait(_HoldShortDuration);
                if (up) {
                    _ButtonPress();
                    continue;
                }
            }
            
            // Wait until button is released
            {
                _ButtonHoldPrepare();
                const bool up = _Button::Wait(_HoldLongDuration);
                if (up) {
                    _ButtonPress();
                } else {
                    _ButtonHold();
                    // Wait until button is actually released
                    _Button::Wait();
                }
                _ButtonHoldCleanup();
            }
        }
    }
    
    static constexpr auto _HoldShortDuration = _Scheduler::Ms<300>;
    static constexpr auto _HoldLongDuration = _Scheduler::Ms<1100>;
    
    // Task stack
    SchedulerStack(".stack._TaskButton")
    static inline uint8_t Stack[128];
};

// MARK: - _TaskMotion

struct _TaskMotion {
    static void Run() {
        // Disable interrupts because _Motion requires it
        Toastbox::IntState ints(false);
        
        for (;;) {
            // Wait for motion to be powered
            _Scheduler::Wait([] { return _Power; });
            
            // Power on motion sensor and wait for it to start up
            _Motion::Power(true);
            
            for (;;) {
                // Wait for motion, or for motion to be disabled
                _Motion::SignalReset();
                _Scheduler::Wait([] { return !_Power || _Motion::Signal(); });
                
                // When potentially disabling the motion sensor, institute a debounce to filter 1->0->1 glitches.
                // This is so we don't have to pay for the full motion-sensor power-on time (30s) for a momentary
                // glitch.
                // Such glitches can occur when we go from wired->unwired, since we power on the motion sensor
                // when we're wired. (We do this in case the device is reconfigured to enable the motion sensor,
                // so it's ready to go as soon as we're unwired, and we don't have to pay the 30s penalty.)
                if (!_Power) {
                    _Scheduler::Wait(_PowerOffDebounceDuration, [] { return _Power; });
                    if (_Power) continue;
                    else        break;
                }
                
                _HandleMotion();
            }
            
            // Turn off motion sensor
            _Motion::Power(false);
        }
    }
    
    static void Power(bool x) {
        _Power = x;
    }
    
    static void _HandleMotion() {
        // Ignore motion if events are disabled
        // This can happen if we're wired (and therefore motion is enabled),
        // but we're powered off.
        if (!_EventsEnabled) return;
        
        // When motion occurs, start captures for each enabled motion trigger
        for (auto it=_Triggers::MotionTriggerBegin(); it!=_Triggers::MotionTriggerEnd(); it++) {
            _Triggers::MotionTrigger& trigger = *it;
            
            // Check if we should ignore this trigger
            if (!trigger.enabled()) continue;
            
            // Start capture
            const Time::Instant time = _RTC::Now();
            const bool captureStarted = _TaskEvent::CaptureStart(trigger, time);
            // CaptureStart() returns false if a capture is already in progress for this trigger.
            // Short-circuit if that's the case.
            if (!captureStarted) continue;
            
            // Update the number of motion triggers remaining.
            // If this was the last trigger that we're allowed, set the `StateMaxImageCount` bit,
            // which will .
            if (trigger.countRem) {
                trigger.countRem--;
                if (!trigger.countRem) {
                    trigger.stateUpdate(_Triggers::MotionTrigger::StateMaxImageCount);
                }
            }
            
            // Suppress motion for the specified duration, if suppression is enabled
            const Time::Ticks32 suppressTicks = trigger.base().suppressTicks;
            if (suppressTicks) {
                // Suppress power/motion immediately
                trigger.stateUpdate(
                    _Triggers::MotionTrigger::StatePowerSuppress|_Triggers::MotionTrigger::StateMotionSuppress);
                
                // Schedule MotionUnsuppressEvent
                const Time::Instant unsuppressTime = _TimeInstantAdd(time, suppressTicks);
                _TaskEvent::EventInsert(_Cast<_Triggers::MotionUnsuppressEvent>(trigger), unsuppressTime);
                
                // Schedule MotionUnsuppressPowerEvent event `PowerOnDelayMs` before the MotionUnsuppressEvent.
                const Time::Instant prepareTime = _TimeInstantSubtract(unsuppressTime, _TicksForMs(_Motion::PowerOnDelayMs));
                _TaskEvent::EventInsert(_Cast<_Triggers::MotionUnsuppressPowerEvent>(trigger), prepareTime);
            }
        }
    }
    
    static constexpr auto _PowerOffDebounceDuration = _Scheduler::Ms<1000>;
    static inline bool _Power = false;
    
    // Task stack
    SchedulerStack(".stack._TaskMotion")
    static inline uint8_t Stack[128];
};





















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
    // Put ourself to sleep until an interrupt occurs
    
    // Enable/disable SysTick depending on whether we have tasks that are waiting for a deadline to pass.
    // We do this to prevent ourself from waking up unnecessarily, saving power.
    const bool systickEnabled = _Scheduler::TickRequired();
    _SysTick::Enabled(systickEnabled);
    
    // We consider the sleep 'extended' if SysTick isn't needed during the sleep
    const bool extendedSleep = !systickEnabled;
    _Clock::Sleep(extendedSleep);
    
    // Unconditionally enable SysTick while we're awake
    _SysTick::Enabled(true);
}

// MARK: - Properties

static void _EventsEnabledUpdate() {
    _EventsEnabled = _TaskPower::On() && !_TaskI2C::HostModeEnabled();
}

static void _EventsEnabledChanged() {
    if (_EventsEnabled) _TaskEvent::Start();
    else                _TaskEvent::Reset();
}

static void _MotionPoweredUpdate() {
    _TaskMotion::Power(_TaskPower::Wired() || (_EventsEnabled && _MotionPowered::Asserted()));
}

// MARK: - Interrupts

[[gnu::interrupt]]
void _ISR_RTC() {
    // Let _EventTimer know we got an RTC interrupt
    bool wake = false;
    
    // Pet the watchdog first
    _Watchdog::Init();
    
    // Let _RTC know that we got an RTC interrupt
    _RTC::ISR(RTCIV);
    
    wake |= _TaskEvent::ISRRTC();
    wake |= _TaskPower::ISRRTC();
    
    // Wake if directed
    if (wake) _Clock::Wake();
}

[[gnu::interrupt]]
void _ISR_TIMER1_A1() {
//    _Pin::LED_GREEN_::Write(!_Pin::LED_GREEN_::Read());
    const bool wake = _SysTick::ISR(TA1IV);
    // Wake if directed
    if (wake) _Clock::Wake();
}

[[gnu::interrupt]]
void _ISR_TIMER2_A1() {
    const bool wake = _TaskEvent::ISRTimer(TA2IV);
    
//    _Pin::LED_RED_::Write(1);
//    for (;;) {
//        _Pin::LED_RED_::Write(1);
//        __delay_cycles(1000000);
//        _Pin::LED_RED_::Write(0);
//        __delay_cycles(1000000);
//    }
    
    // Wake if directed
    if (wake) _Clock::Wake();
}

[[gnu::interrupt]]
void _ISR_PORT2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    const uint16_t iv = P2IV;
    switch (iv) {
    
    // Motion
    case _Pin::MOTION_SIGNAL::IVPort2():
        _Motion::ISR();
        // Wake ourself
        _Clock::Wake();
        break;
    
    // Wired (ie VDD_B_3V3_STM)
    case _WiredMonitor::Pin::IVPort2():
        _WiredMonitor::ISR(iv);
        // Notify _TaskI2C that our wired state changed
        _TaskI2C::WiredChanged();
        // Wake ourself
        _Clock::Wake();
        break;
    
    // Button
    case _Button::Pin::IVPort2():
        _Button::ISR();
        // Wake ourself
        _Clock::Wake();
        break;
    
    default:
        break;
    }
}

[[gnu::interrupt]]
void _ISR_USCI_B0() {
    // Accessing `UCB0IV` automatically clears the highest-priority interrupt
    const uint16_t iv = UCB0IV;
    _I2C::ISR_I2C(iv);
    // Wake ourself
    _Clock::Wake();
}

[[gnu::interrupt]]
void _ISR_ADC() {
    const bool wake = _BatterySampler::ISR(ADCIV);
    // Wake if directed
    if (wake) _Clock::Wake();
}

[[noreturn]]
[[gnu::naked]] // No function preamble because we always abort, so we don't need to preserve any registers
[[gnu::interrupt]]
void _ISR_UNMI() {
    switch (SYSUNIV) {
    case SYSUNIV_NMIIFG:    Assert(false);
    case SYSUNIV_OFIFG:     Assert(false);
    default:                Assert(false);
    }
}

[[gnu::interrupt]]
void _ISR_SYSNMI() {
    switch (SYSSNIV) {
    case SYSSNIV_VMAIFG:
        Assert(false);
    
#if DebugEnable
    // We can get spurious interrupts when reading the debug log via SBW
    // This is likely because Debug.h disables/enables JMBOUTIE to disable/enable the JMBOUTIFG interrupt.
    // Presumably there's a race between the JMBOUTIFG interrupt being scheduled and us actually reading
    // SYSSNIV, between which JMBOUTIE can be cleared, which causes SYSSNIV==0.
    case SYSSNIV_NONE:
        break;
    case SYSSNIV_JMBOUTIFG:
        if (Debug::ISR()) {
            // Wake ourself if directed
            _Clock::Wake();
        }
        break;
#endif // DebugEnable
    
    default:
        Assert(false);
    }
}

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
    // If our previous reset wasn't because we explicitly reset ourself (a 'software BOR'),
    // reset ourself now.
    //
    // This ensures that any unexpected reset (such as a watchdog timer timeout) triggers
    // a full BOR, and not a PUC or a POR. We want a full BOR because it resets all our
    // peripherals, unlike a PUC/POR, which don't reset all peripherals (like timers).
    // This will cause us to reset ourself twice upon initial startup, but that's OK.
    //
    // We want to do this here before interrupts are first enabled, and not within
    // _TaskPower, to ensure that we don't have pending resets after a reset (since some
    // IFG flags persist across PUC/POR). We especially don't want our peripherals to
    // receive ISRs before they're initialized.
    //
    // We also want to do this here to prevent a potential crash loop: if an interrupt
    // handler crashed before it clears its IFG flag, and that IFG flag persists across
    // PUC/POR, if we enabled interrupts before checking if this reset was a BOR, then
    // the interrupt would immediately fire again and a crash loop would ensue. (We may
    // have encountered this issue when we had missing entries in our vector table.)
    if (Startup::ResetReason() != SYSRSTIV_DOBOR) {
        _ResetRecord(MSP::Reset::Type::Reset, Startup::ResetReason());
        _BOR();
    }
    
    // Invokes the first task's Run() function (_TaskPower::Run)
    _Scheduler::Run();
}

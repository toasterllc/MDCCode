#include <msp430.h>
#include <cstdint>
#include <cstdbool>
#include <cstddef>
#include <atomic>
#include <ratio>
#include "Toastbox/Scheduler.h"
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
#include "SuppressibleAssertion.h"
#include "Assert.h"
#include "Timer.h"
#include "Debug.h"
#include "Charging.h"
#include "System.h"
#include "Property.h"
#include "Time.h"
#include "TimeConstants.h"
#include "LEDFlicker.h"
using namespace GPIO;

using _Clock = T_Clock<_Scheduler, _MCLKFreqHz, _Pin::MSP_XIN, _Pin::MSP_XOUT>;
using _SysTick = T_SysTick<_Scheduler, _ACLKFreqHz>;
using _SPI = T_SPI<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;
using _ICE = T_ICE<_Scheduler>;

using _I2C = T_I2C<_Scheduler, _Pin::MSP_STM_I2C_SCL, _Pin::MSP_STM_I2C_SDA, MSP::I2CAddr>;
using _Motion = T_Motion<_Scheduler, _Pin::MOTION_EN_, _Pin::MOTION_SIGNAL>;

using _BatterySampler = T_BatterySampler<_Scheduler, _Pin::BAT_CHRG_LVL, _Pin::BAT_CHRG_LVL_EN_>;

using _Button = T_Button<_Scheduler, _Pin::BUTTON_SIGNAL_>;

using _Charging = T_Charging<_Pin::VDD_B_3V3_STM>;

static OutputPriority _LEDGreen_(_Pin::LED_GREEN_{});
static OutputPriority _LEDRed_(_Pin::LED_RED_{});

struct _LEDPriority {
    static constexpr uint8_t Power   = 0;
    static constexpr uint8_t Capture = 1;
    static constexpr uint8_t I2C     = 2;
    static constexpr uint8_t Default = 3;
};

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

static void _MotionEnabledUpdate();

static void _VDDIMGSDEnabledChanged();

// _BatteryTrapSaved: remembers our battery-trap state across crashes and LPM3.5.
[[gnu::section(".ram_backup_bss._BatteryTrapSaved")]]
static inline bool _BatteryTrapSaved = false;

// _OnSaved: remembers our power state across crashes and LPM3.5.
// This is needed because we don't want the device to return to the
// powered-off state after a crash.
//
// Stored in BAKMEM so it's kept alive through low-power modes <= LPM4.
//
// Apparently it has to be stored outside of _TaskMain for the gnu::section
// attribute to work.
[[gnu::section(".ram_backup_bss._OnSaved")]]
static inline bool _OnSaved = false;

// _EventsEnabled: whether _TaskEvent should be running and handling events
static T_Property<bool,_EventsEnabledChanged,_MotionEnabledUpdate> _EventsEnabled;

using _MotionRequested = T_AssertionCounter<_MotionEnabledUpdate>;
using _MotionRequestedAssertion = T_SuppressibleAssertion<_MotionRequested>;

// VDDIMGSD enable/disable
using _VDDIMGSDEnabled = T_AssertionCounter<_VDDIMGSDEnabledChanged>;

// _Triggers: stores our current event state
using _Triggers = T_Triggers<_State, _MotionRequestedAssertion>;

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

// MARK: - _TaskPower

struct _TaskPower {
    static void Run() {
        // Init BatterySampler
        _BatterySampler::Init();
        
        // Restore our battery trap state
        _BatteryTrap = _BatteryTrapSaved;
        
        // Restore our saved power state
        _On = _OnSaved;
        
        static bool charging = false;
        for (;;) {
            // Wait until something triggers us to update
            _Scheduler::Wait([] { return _BatteryLevelUpdate || charging!=_Charging::Charging(); });
            
            if (_BatteryLevelUpdate) {
                // Disable interrupts so that ISRRTC() can't interrupt us setting our state
                Toastbox::IntState ints(false);
                // Update our battery level
                _BatteryLevel = _BatterySampler::Sample();
                // Reset our counters
                _RTCCounter = _SampleIntervalRTC;
                _CaptureCounter = _SampleIntervalCapture;
                _BatteryLevelUpdate = false;
            }
            
            if (charging != _Charging::Charging()) {
                charging = _Charging::Charging();
                // Turn ourself on when we're plugged in
                if (charging) _On = true;
            }
        }
    }
    
    static bool On() {
        return _On;
    }
    
    static void On(bool x) {
        _On = x;
    }
    
    static MSP::BatteryLevel BatteryLevel() {
        return _BatteryLevel;
    }
    
    static void BatteryLevelUpdate() {
        // When in battery trap mode, never sample the battery voltage unless we're charging.
        if (_BatteryTrap && !_Charging::Charging()) return;
        _BatteryLevelUpdate = true;
    }
    
    static void BatteryLevelWait() {
        _Scheduler::Wait([] { return !_BatteryLevelUpdate; });
    }
    
    static bool BatteryTrap() {
        return _BatteryTrap;
    }
    
    static void CaptureNotify() {
        // Short-circuit if we're in battery trap
        // We don't want to monitor the battery while we're in battery trap, to minimize battery use
        if (_BatteryTrap) return;
        
        _CaptureCounter--; // Rollover OK since we reset _CaptureCounter in Run()
        if (!_CaptureCounter) {
            _BatteryLevelUpdate = true;
        }
    }
    
    static bool ISRRTC() {
        // Short-circuit if we're in battery trap
        // We don't want to monitor the battery while we're in battery trap, to minimize battery use
        if (_BatteryTrap) return false;
        
        _RTCCounter--; // Rollover OK since we reset _RTCCounter in Run()
        if (!_RTCCounter) {
            _BatteryLevelUpdate = true;
            return true;
        }
        return false;
    }
    
    static void _OnChanged() {
        _OnSaved = _On;
        _LEDFlash(_On ? _LEDGreen_ : _LEDRed_);
    }
    
    static void _BatteryLevelChanged() {
        // If our battery level drops below the Enter threshold, enter battery trap
        if (_BatteryLevel <= _BatteryTrapLevelEnter) {
            _BatteryTrap = true;
        
        // If our battery level raises above the Exit threshold, exit battery trap
        // Only allow this to occur if we're charging though. This check is needed because we update the battery
        } else if (_BatteryLevel >= _BatteryTrapLevelExit) {
            _BatteryTrap = false;
        }
    }
    
    static void _BatteryTrapChanged() {
        _BatteryTrapSaved = _BatteryTrap;
        // Turn ourself on when exiting battery trap
        if (!_BatteryTrap) _On = true;
        _LEDFlicker::Enabled(_BatteryTrap);
    }
    
    static void _LEDFlash(OutputPriority& led) {
        // Flash red LED to signal that we're turning off
        for (int i=0; i<5; i++) {
            led.set(_LEDPriority::Power, 0);
            _Scheduler::Delay(_Scheduler::Ms<50>);
            led.set(_LEDPriority::Power, 1);
            _Scheduler::Delay(_Scheduler::Ms<50>);
        }
        led.set(_LEDPriority::Power, std::nullopt);
    }
    
    static constexpr uint16_t _SampleIntervalRTCDays = 4;
    static constexpr uint16_t _SampleIntervalRTC     = (_SampleIntervalRTCDays * Time::Day) / _RTC::InterruptIntervalTicks;
    static constexpr uint16_t _SampleIntervalCapture = 512;
    
    static constexpr uint8_t _BatteryTrapPercentEnter = 2;
    static constexpr uint8_t _BatteryTrapPercentExit  = 10;
    
    static constexpr MSP::BatteryLevel _BatteryTrapLevelEnter
        = MSP::BatteryLevelMin + ((((uint32_t)MSP::BatteryLevelMax-MSP::BatteryLevelMin)*_BatteryTrapPercentEnter)/100);
    static constexpr MSP::BatteryLevel _BatteryTrapLevelExit
        = MSP::BatteryLevelMin + ((((uint32_t)MSP::BatteryLevelMax-MSP::BatteryLevelMin)*_BatteryTrapPercentExit)/100);
    
    static_assert(_SampleIntervalRTC     == 168);  // Debug
    static_assert(_BatteryTrapLevelEnter == 1311); // Debug
    static_assert(_BatteryTrapLevelExit  == 6554); // Debug
    
    static inline uint16_t _RTCCounter = 0;
    static inline uint16_t _CaptureCounter = 0;
    
    // _On: user-controlled power state
    static inline T_Property<bool,_OnChanged,_EventsEnabledUpdate> _On;
    
    // _BatteryLevel: the cached battery charge level
    static inline T_Property<MSP::BatteryLevel,_BatteryLevelChanged> _BatteryLevel = MSP::BatteryLevelInvalid;
    
    // _BatteryTrap: mode that disables all functionality except time-tracking
    static inline T_Property<bool,_BatteryTrapChanged,_EventsEnabledUpdate> _BatteryTrap;
    
    static inline bool _BatteryLevelUpdate = false;
    
    static constexpr uint32_t _FlickerPeriodMs      = 5000;
    static constexpr uint32_t _FlickerOnDurationMs  = 20;
    using _LEDFlicker = T_LEDFlicker<_Pin::LED_GREEN_, _ACLKFreqHz, _FlickerPeriodMs, _FlickerOnDurationMs>;
    
    // Task stack
    SchedulerStack(".stack._TaskPower")
    static inline uint8_t Stack[128];
};

// MARK: - _TaskI2C

struct _TaskI2C {
    static void Run() {
        for (;;) {
            // Wait until STM is up (ie we're plugged in and charging)
            _Scheduler::Wait([] { return _Charging::Charging(); });
            
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
            _LEDRed_.set(_LEDPriority::I2C, std::nullopt);
            _LEDGreen_.set(_LEDPriority::I2C, std::nullopt);
            
            // Reset state
            _HostModeState = {};
        }
    }
    
    static void Abort() {
        _I2C::Abort();
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
        
        case Cmd::Op::LEDSet:
            _LEDRed_.set(_LEDPriority::I2C, !cmd.arg.LEDSet.red);
            _LEDGreen_.set(_LEDPriority::I2C, !cmd.arg.LEDSet.green);
            return MSP::Resp{ .ok = true };
        
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
                .arg = { .BatteryLevelGet = { .level = _TaskPower::BatteryLevel() } },
            };
        }}
        
        return MSP::Resp{ .ok = false };
    }
    
    static bool HostModeEnabled() {
        return _HostModeState.en;
    }
    
    static inline struct {
        T_Property<bool,_EventsEnabledUpdate> en;
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
                .batteryLevel   = _TaskPower::BatteryLevel(),
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
    
    static void _MotionEnable(_Triggers::MotionEnableEvent& ev) {
        _Triggers::MotionTrigger& trigger = ev.trigger();
        
        // Enable motion
        trigger.enabled.set(true);
        
        // Schedule the MotionDisable event, if applicable
        // This needs to happen before we reschedule `ev` because we need its .time to
        // properly schedule the MotionDisableEvent!
        const uint32_t durationTicks = trigger.base().durationTicks;
        if (durationTicks) {
            EventInsert((_Triggers::MotionDisableEvent&)trigger, ev.time, durationTicks);
        }
        
        // Reschedule MotionEnableEvent for its next trigger time
        EventInsert(ev, ev.repeat);
    }
    
    static void _MotionDisable(_Triggers::MotionDisableEvent& ev) {
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        trigger.enabled.set(false);
    }
    
    static void _MotionUnsuppress(_Triggers::MotionUnsuppressEvent& ev) {
        // We should never get a MotionUnsuppressEvent event while in fast-forward mode
        Assert(_State.live);
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        trigger.enabled.suppress(false);
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
        _TaskPower::BatteryLevelWait();
        
        const bool green = ev.capture->leds & MSP::LEDs_::Green;
        const bool red = ev.capture->leds & MSP::LEDs_::Red;
        _LEDGreen_.set(_LEDPriority::Capture, !green);
        _LEDRed_.set(_LEDPriority::Capture, !red);
        
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
        
        _LEDGreen_.set(_LEDPriority::Capture, std::nullopt);
        _LEDRed_.set(_LEDPriority::Capture, std::nullopt);
        
        _State.vddImgSd = false;
        _State.vddb = false;
        
        ev.countRem--;
        if (ev.countRem) {
            EventInsert(ev, ev.time, ev.capture->delayTicks);
        }
    }
    
    static void EventInsert(_Triggers::Event& ev, const Time::Instant& time) {
        _Triggers::EventInsert(ev, time);
        // If this event is now the front of the list, reschedule _EventTimer
        if (_Triggers::EventFront() == &ev) {
            _EventTimerSchedule();
        }
    }

    static void EventInsert(_Triggers::Event& ev, MSP::Repeat& repeat) {
        const Time::Ticks32 delta = _RepeatAdvance(repeat);
        // delta=0 means Repeat=never, in which case we don't reschedule the event
        if (delta) {
            EventInsert(ev, ev.time+delta);
        }
    }

    static void EventInsert(_Triggers::Event& ev, const Time::Instant& time, Time::Ticks32 deltaTicks) {
        EventInsert(ev, time + deltaTicks);
    }

    static void CaptureStart(_Triggers::CaptureImageEvent& ev, const Time::Instant& time) {
        // Reset capture count
        ev.countRem = ev.capture->count;
        if (ev.countRem) {
            EventInsert(ev, time);
        }
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
        case T::TimeTrigger:      _TimeTrigger(      (_Triggers::TimeTriggerEvent&)ev      ); break;
        case T::MotionEnable:     _MotionEnable(     (_Triggers::MotionEnableEvent&)ev     ); break;
        case T::MotionDisable:    _MotionDisable(    (_Triggers::MotionDisableEvent&)ev    ); break;
        case T::MotionUnsuppress: _MotionUnsuppress( (_Triggers::MotionUnsuppressEvent&)ev ); break;
        case T::CaptureImage:     _CaptureImage(     (_Triggers::CaptureImageEvent&)ev     ); break;
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
        if (Time::Absolute(startTime)) {
            for (;;) {
                _Triggers::Event* ev = _Triggers::EventFront();
                if (!ev || (ev->time > startTime)) break;
                _EventHandle(_EventPop());
            }
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

// MARK: - _TaskMotion

struct _TaskMotion {
    static void Run() {
        // Disable interrupts because _Motion requires it
        Toastbox::IntState ints(false);
        
        for (;;) {
            // Wait for motion to be enabled
            _Scheduler::Wait([] { return _Enabled; });
            
            // Power on motion sensor and wait for it to start up
            _Motion::Power(true);
            
            for (;;) {
                // Wait for motion, or for motion to be disabled
                _Motion::SignalReset();
                _Scheduler::Wait([] { return !_Enabled || _Motion::Signal(); });
                if (!_Enabled) break;
                
                _HandleMotion();
            }
            
            // Turn off motion sensor
            _Motion::Power(false);
        }
    }
    
    static void Enable(bool x) {
        _Enabled = x;
    }
    
    static void _HandleMotion() {
        // When motion occurs, start captures for each enabled motion trigger
        for (auto it=_Triggers::MotionTriggerBegin(); it!=_Triggers::MotionTriggerEnd(); it++) {
            _Triggers::MotionTrigger& trigger = *it;
            // If this trigger is enabled...
            if (trigger.enabled.get()) {
                const Time::Instant time = _RTC::Now();
                // Start capture
                _TaskEvent::CaptureStart(trigger, time);
                // Suppress motion for the specified duration, if suppression is enabled
                const uint32_t suppressTicks = trigger.base().suppressTicks;
                if (suppressTicks) {
                    trigger.enabled.suppress(true);
                    _TaskEvent::EventInsert((_Triggers::MotionUnsuppressEvent&)trigger, time, suppressTicks);
                }
            }
        }
    }
    
    static inline bool _Enabled = false;
    
    // Task stack
    SchedulerStack(".stack._TaskMotion")
    static inline uint8_t Stack[128];
};

// MARK: - _TaskMain

#define _TaskMainStackSize 128

SchedulerStack(".stack._TaskMain")
uint8_t _TaskMainStack[_TaskMainStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskMainStack+" Stringify(_TaskMainStackSize));

struct _TaskMain {
    static void _Init() {
        // Disable interrupts while we init our subsystems
        Toastbox::IntState ints(false);
        
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
            _BatterySampler::Pin::BatChrgLvlPin,
            _BatterySampler::Pin::BatChrgLvlEn_Pin,
            
            // Button (config chosen by _Button)
            _Button::Pin,
            
            // Charging
            _Charging::Pin,
            
            // LEDs
            _Pin::LED_GREEN_,
            _Pin::LED_RED_
        
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
        
        // Init LEDs by setting their default-priority / 'backstop' values to off.
        // This is necessary so that relinquishing the LEDs from I2C task causes
        // them to turn off. If we didn't have a backstop value, the LEDs would
        // remain in whatever state the I2C task set them to before relinquishing.
        _LEDGreen_.set(_LEDPriority::Default, 1);
        _LEDRed_.set(_LEDPriority::Default, 1);
        
        // Start tasks
        _Scheduler::Start<_TaskI2C, _TaskPower, _TaskMotion>();
    }
    
    static void Run() {
        _Init();
        
//        for (;;) {
//            _Pin::LED_RED_::Write(1);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//            _Pin::LED_RED_::Write(0);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//        }
        
//        _Pin::LED_RED_::Write(1);
//        for (;;) {
//            _Pin::LED_RED_::Write(1);
//            __delay_cycles(1000000);
//            _Pin::LED_RED_::Write(0);
//            __delay_cycles(1000000);
//        }
        
//        for (bool on_=0;; on_=!on_) {
////            _Scheduler::Sleep(_Scheduler::Ms<100>);
//        }
        
//        _On = true;
//        for (bool on_=false;; on_=!on_) {
////            __delay_cycles(1000000);
////            _Pin::LED_GREEN_::Write(on_);
////            _EventTimer::Schedule(_RTC::Now() + 5*Time::TicksFreq::num);
////            _Scheduler::Wait([] { return _EventTimer::Fired(); });
//            
//            const auto nextTime = _Triggers::EventFront()->time;
//            const auto currTime = _RTC::Now();
//            
//            _Scheduler::Sleep(_Scheduler::Ms<1000>);
//        }
        
        
        
//        _On = true;
//        for (bool on_=false;; on_=!on_) {
////            __delay_cycles(1000000);
////            _Pin::LED_GREEN_::Write(on_);
//            _EventTimer::Schedule(_RTC::Now() + 5*Time::TicksFreq::num);
//            _Scheduler::Wait([] { return _EventTimer::Fired(); });
//        }
        
//        for (bool on_=false;; on_=!on_) {
//            _Pin::LED_GREEN_::Write(on_);
//            _Scheduler::Sleep(_Scheduler::Ms<1000>);
//        }
        
//        for (;;) {
//            _Pin::LED_RED_::Write(1);
//            _Pin::LED_GREEN_::Write(1);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//            
//            if (_Clock::_ClockFaults()) {
//                _Pin::LED_RED_::Write(0);
//            } else {
//                _Pin::LED_GREEN_::Write(0);
//            }
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//        }
        
//        for (;;) {
////            _LEDRed_.set(_LEDPriority::Power, !_LEDRed_.get());
//            _Pin::LED_RED_::Write(0);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//            
//            _Pin::LED_RED_::Write(1);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//        }
        
//        for (;;) {
////            _LEDRed_.set(_LEDPriority::Power, !_LEDRed_.get());
//            _Pin::LED_RED_::Write(0);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//            
//            _Pin::LED_RED_::Write(1);
//            _Scheduler::Sleep(_Scheduler::Ms<100>);
//        }
        
        for (;;) {
            // Button needs interrupts to be disabled
            Toastbox::IntState ints(false);
            
            // Wait for a button press
            _Button::Reset();
            _Scheduler::Wait([] { return _Button::EventPending(); });
            
            switch (_Button::EventRead()) {
            case _Button::Event::Press: {
                // Ignore button presses if we're off or in host mode
                if (!_TaskPower::On() || _TaskI2C::HostModeEnabled()) break;
                
                for (auto it=_Triggers::ButtonTriggerBegin(); it!=_Triggers::ButtonTriggerEnd(); it++) {
                    _TaskEvent::CaptureStart(*it, _RTC::Now());
                }
                break;
            }
            
            case _Button::Event::Hold:
                // Toggle our user-visible power state
                _TaskPower::On(!_TaskPower::On());
                break;
            }
        }
    }
    
    static void Sleep() {
        // Put ourself to sleep until an interrupt occurs
        
        // Enable/disable SysTick depending on whether we have tasks that are waiting for a deadline to pass.
        // We do this to prevent ourself from waking up unnecessarily, saving power.
        _SysTickEnabled = _Scheduler::TickRequired();
        
        // We consider the sleep 'extended' if SysTick isn't needed during the sleep
//        const bool extendedSleep = false;
//        const bool extendedSleep = true;
        const bool extendedSleep = !_SysTickEnabled;
        _Clock::Sleep(extendedSleep);
        
        // Unconditionally enable SysTick while we're awake
        _SysTickEnabled = true;
    }
    
    static void _SysTickEnabledChanged() {
        _SysTick::Enabled(_SysTickEnabled);
    }
    
    static inline T_Property<bool,_SysTickEnabledChanged> _SysTickEnabled;
    
    // Task stack
    static constexpr auto& Stack = _TaskMainStack;
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
    _TaskMain::Sleep();
}

// MARK: - Properties

static void _EventsEnabledUpdate() {
    _EventsEnabled = _TaskPower::On() && !_TaskPower::BatteryTrap() && !_TaskI2C::HostModeEnabled();
}

static void _EventsEnabledChanged() {
    if (_EventsEnabled) _TaskEvent::Start();
    else                _TaskEvent::Reset();
}

static void _MotionEnabledUpdate() {
    _TaskMotion::Enable(_EventsEnabled && _MotionRequested::Asserted());
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
    
    // Charging (ie VDD_B_3V3_STM)
    case _Charging::Pin::IVPort2():
        _Charging::ISR(iv);
        // If the I2C master went away, abort whatever I2C was doing
        if (!_Charging::Charging()) _TaskI2C::Abort();
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
    // _TaskMain, to ensure that we don't have pending resets after a reset (since some
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
    
    // Invokes the first task's Run() function (_TaskMain::Run)
    _Scheduler::Run();
}

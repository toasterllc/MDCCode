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
using namespace GPIO;

static constexpr uint32_t _XT1FreqHz        = 32768;        // 32.768 kHz
static constexpr uint32_t _ACLKFreqHz       = _XT1FreqHz;   // 32.768 kHz
static constexpr uint32_t _MCLKFreqHz       = 16000000;     // 16 MHz
static constexpr uint32_t _SysTickFreqHz    = 2048;         // 2.048 kHz

struct _Pin {
    // Port A
    using VDD_B_1V8_IMG_SD_EN       = PortA::Pin<0x0, Option::Output0>;
    using LED_GREEN_                = PortA::Pin<0x1, Option::Output1>;
    using MSP_STM_I2C_SDA           = PortA::Pin<0x2>;
    using MSP_STM_I2C_SCL           = PortA::Pin<0x3>;
    using ICE_MSP_SPI_DATA_OUT      = PortA::Pin<0x4>;
    using ICE_MSP_SPI_DATA_IN       = PortA::Pin<0x5>;
    using ICE_MSP_SPI_CLK           = PortA::Pin<0x6>;
    using BAT_CHRG_LVL              = PortA::Pin<0x7, Option::Input>; // No pullup/pulldown because this is an analog input (and the voltage divider provides a physical pulldown)
    using MSP_XOUT                  = PortA::Pin<0x8>;
    using MSP_XIN                   = PortA::Pin<0x9>;
    using LED_RED_                  = PortA::Pin<0xA, Option::Output1>;
    using VDD_B_2V8_IMG_SD_EN       = PortA::Pin<0xB, Option::Output0>;
    using MOTION_SIGNAL             = PortA::Pin<0xC>;
    using BUTTON_SIGNAL_            = PortA::Pin<0xD>;
    using BAT_CHRG_LVL_EN_          = PortA::Pin<0xE, Option::Output1>;
    using VDD_B_3V3_STM             = PortA::Pin<0xF, Option::Input, Option::Resistor0>;
    
    // Port B
    using MOTION_EN_                = PortB::Pin<0x0>;
    using VDD_B_EN                  = PortB::Pin<0x1, Option::Output0>;
    using _UNUSED0                  = PortB::Pin<0x2>;
};

class _TaskMain;
class _TaskEvent;
class _TaskSD;
class _TaskImg;
class _TaskI2C;
class _TaskMotion;

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

using _Clock = T_Clock<_Scheduler, _MCLKFreqHz, _Pin::MSP_XIN, _Pin::MSP_XOUT>;
using _SysTick = T_SysTick<_Scheduler, _ACLKFreqHz>;
using _SPI = T_SPI<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;
using _ICE = T_ICE<_Scheduler>;

using _I2C = T_I2C<_Scheduler, _Pin::MSP_STM_I2C_SCL, _Pin::MSP_STM_I2C_SDA, _Pin::VDD_B_3V3_STM, MSP::I2CAddr>;
using _Motion = T_Motion<_Scheduler, _Pin::MOTION_EN_, _Pin::MOTION_SIGNAL>;

using _BatterySampler = T_BatterySampler<_Scheduler, _Pin::BAT_CHRG_LVL, _Pin::BAT_CHRG_LVL_EN_>;

constexpr uint16_t _ButtonHoldDurationMs = 1500;
using _Button = T_Button<_Scheduler, _Pin::BUTTON_SIGNAL_, _ButtonHoldDurationMs>;

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

static void _TaskEventRunningUpdate();
static void _HostModeUpdate() { _TaskEventRunningUpdate(); }
static void _PoweredUpdate() { _TaskEventRunningUpdate(); }
static void _CaffeineUpdate() {}
static void _MotionEnabledUpdate();
static void _VDDBEnabledUpdate();
static void _VDDIMGSDEnabledUpdate();
static void _SysTickEnabledUpdate();

// _HostMode: events pause/resume (for host mode)
using _HostMode = T_AssertionCounter<_HostModeUpdate>;

// _Powered: power state assertion (the user-facing power state)
using _Powered = T_AssertionCounter<_PoweredUpdate>;

// _Caffeine: prevents sleep
using _Caffeine = T_AssertionCounter<_CaffeineUpdate>;

// Motion enable/disable
using _MotionEnabled = T_AssertionCounter<_MotionEnabledUpdate>;
using _MotionEnabledAssertion = T_SuppressibleAssertion<_MotionEnabled>;

// VDDB enable/disable
using _VDDBEnabled = T_AssertionCounter<_VDDBEnabledUpdate>;

// VDDIMGSD enable/disable
using _VDDIMGSDEnabled = T_AssertionCounter<_VDDIMGSDEnabledUpdate>;

// VDDIMGSD enable/disable
using _SysTickEnabled = T_AssertionCounter<_SysTickEnabledUpdate>;

// _Triggers: stores our current event state
using _Triggers = T_Triggers<_State, _MotionEnabledAssertion>;

// _EventTimer: timer that triggers us to wake when the next event is ready to be handled
using _EventTimer = T_Timer<_RTC, _ACLKFreqHz>;

static Time::Ticks32 _RepeatAdvance(MSP::Repeat& x) {
    static_assert(Time::TicksFreq::den == 1); // Check assumption that TicksFreq is an integer
    
    static constexpr Time::Ticks32 Day         = (Time::Ticks32)     24*60*60*Time::TicksFreq::num;
    static constexpr Time::Ticks32 Year        = (Time::Ticks32) 365*24*60*60*Time::TicksFreq::num;
    static constexpr Time::Ticks32 YearPlusDay = (Time::Ticks32) 366*24*60*60*Time::TicksFreq::num;
    switch (x.type) {
    case MSP::Repeat::Type::Never:
        return 0;
    
    case MSP::Repeat::Type::Daily:
        Assert(x.Daily.interval);
        return Day*x.Daily.interval;
    
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
        return count*Day;
    }
    
    case MSP::Repeat::Type::Yearly:
        #warning TODO: verify this works properly
        // Return 1 year (either 365 or 366 days) in microseconds
        // We appropriately handle leap years by referencing `leapPhase`
        if (x.Yearly.leapPhase) {
            x.Yearly.leapPhase--;
            return Year;
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
    
    hist->ctx.u16 = ctx;
    
    // Increment the count, but don't allow it to overflow
    if (hist->count < std::numeric_limits<decltype(hist->count)>::max()) {
        hist->count++;
    }
}

[[noreturn]]
static void _BOR() {
    PMMUnlock pmm; // Unlock PMM registers
    PMMCTL0_L |= PMMSWBOR_L;
    // Wait for reset
    for (;;);
}

// Abort(): called by Assert() with the address that aborted
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr) {
    // Record the abort
    _ResetRecord(MSP::Reset::Type::Abort, addr);
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

static void _VDDBEnabledUpdate() {
    _Pin::VDD_B_EN::Write(_VDDBEnabled::Asserted());
    // Rails take ~1.5ms to turn on/off, so wait 2ms to be sure
    _Scheduler::Sleep(_Scheduler::Ms<2>);
}

static void _VDDIMGSDEnabledUpdate() {
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

static void _SysTickEnabledUpdate() {
    _SysTick::Enabled(_SysTickEnabled::Asserted());
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
        // Reset other tasks' state
        // This is necessary because we're stopping them at an arbitrary point
        _TaskSD::Reset();
        _TaskImg::Reset();
        // Stop tasks
        _Scheduler::Stop<_TaskSD>();
        _Scheduler::Stop<_TaskImg>();
        _Scheduler::Stop<_TaskEvent>();
        // Reset our state
        // We do this last so that our power assertions are reset last
        _State = {};
    }
    
    static void _TimeTrigger(_Triggers::TimeTriggerEvent& ev) {
        _Triggers::TimeTrigger& trigger = ev.trigger();
        // Schedule the CaptureImageEvent, but only if we're not in fast-forward mode
        if (!_State.fastForward) {
            CaptureStart(trigger, ev.time);
        }
        // Reschedule TimeTriggerEvent for its next trigger time
        EventInsert(ev, ev.repeat);
    }
    
    static void _MotionEnable(_Triggers::MotionEnableEvent& ev) {
        _Triggers::MotionTrigger& trigger = ev.trigger();
        
        // Enable motion
        trigger.enabled.set(true);
        
        // Schedule the MotionDisable event, if applicable
        // This needs to happen before we reschedule `motionEnableEvent` because we need its .time to
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
        Assert(!_State.fastForward);
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        trigger.enabled.suppress(false);
    }
    
    static void _CaptureImage(_Triggers::CaptureImageEvent& ev) {
        // We should never get a CaptureImageEvent event while in fast-forward mode
        Assert(!_State.fastForward);
        
        constexpr MSP::ImgRingBuf& imgRingBuf = ::_State.sd.imgRingBufs[0];
        
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
        _Triggers::Event* ev = _Triggers::EventFront();
        if (ev) {
            _EventTimer::Schedule(ev->time);
        } else {
            _EventTimer::Reset();
        }
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
    
    static bool _EventTimerFired() {
        const bool fired = _EventTimer::Fired();
        // Exit fast-forward mode the first time we have an event that's in the future
        if (!fired) _State.fastForward = false;
        return fired;
    }
    
    static void Run() {
        // Reset our state
        Reset();
        
        // Init SPI peripheral
        _SPI::Init();
        
        // Init Triggers
        _Triggers::Init(_RTC::Now());
        
        // Schedule _EventTimer for the first event
        _EventTimerSchedule();
        
        // Enter fast-forward mode while we pop every event that occurs in the past
        // (_EventTimerFired() will exit from fast-forward mode)
        #warning TODO: don't enter fast-forward mode if the first event is a relative time, otherwise we'll arbitrarily skip the first event in FF mode since it's in the past
        #warning TODO: OR: don't enter FF mode if our time is a relative time
        _State.fastForward = true;
        for (;;) {
            // Wait for _EventTimer to fire
            _Scheduler::Wait([] { return _EventTimerFired(); });
            _Triggers::Event& ev = _EventPop();
            
            // Don't go to sleep until we handle the event
            _State.caffeine = true;
            
            // Handle the event
            using T = _Triggers::Event::Type;
            switch (ev.type) {
            case T::TimeTrigger:      _TimeTrigger((_Triggers::TimeTriggerEvent&)ev);           break;
            case T::MotionEnable:     _MotionEnable((_Triggers::MotionEnableEvent&)ev);         break;
            case T::MotionDisable:    _MotionDisable((_Triggers::MotionDisableEvent&)ev);       break;
            case T::MotionUnsuppress: _MotionUnsuppress((_Triggers::MotionUnsuppressEvent&)ev); break;
            case T::CaptureImage:     _CaptureImage((_Triggers::CaptureImageEvent&)ev);         break;
            }
            
            // Allow sleep
            _State.caffeine = false;
        }
    }
    
    static inline struct __State {
        __State() {} // Compiler bug workaround
        // fastForward=true while initializing, where we execute events in 'fast-forward' mode,
        // solely to arrive at the correct state for the current time.
        // fastForward=false once we're done initializing and executing events normally.
        bool fastForward = false;
        // power / vddb / vddImgSd: our power assertions
        // These need to be ivars because _TaskEvent can be reset at any time via
        // our Reset() function, so if the power assertion lived on the stack and
        // _TaskEvent is reset, its destructor would never be called and our state
        // would be corrupted.
        _Caffeine::Assertion caffeine;
        _VDDBEnabled::Assertion vddb;
        _VDDIMGSDEnabled::Assertion vddImgSd;
    } _State;
    
    // Task stack
    SchedulerStack(".stack._TaskEvent")
    static inline uint8_t Stack[256];
};

static void _TaskEventRunningUpdate() {
    if (_Powered::Asserted() && !_HostMode::Asserted()) {
        _TaskEvent::Start();
    } else {
        _TaskEvent::Reset();
    }
}

// MARK: - _TaskI2C

struct _TaskI2C {
    static void Run() {
        for (;;) {
            // Wait until the I2C lines are activated (ie VDD_B_3V3_STM becomes powered)
            _I2C::WaitUntilActive();
            
            // Maintain power while I2C is active
            _Caffeine::Assertion caffeine(true);
            
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
            
//            // Relinquish LEDs, which may have been set by _CmdHandle()
            _LEDRed_.set(_LEDPriority::I2C, std::nullopt);
            _LEDGreen_.set(_LEDPriority::I2C, std::nullopt);
            
            // Reset state
            _State = {};
        }
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
                .arg = { .TimeGet = { .time = _RTC::Now() } },
            };
        
        case Cmd::Op::TimeSet:
            // Only allow setting the time while we're in host mode
            // and therefore _TaskEvent isn't running
            if (!_State.hostMode) return MSP::Resp{ .ok = false };
            _RTC::Init(cmd.arg.TimeSet.time);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::HostModeSet:
            _State.hostMode = cmd.arg.HostModeSet.en;
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::VDDIMGSDSet:
            _State.vddImgSd = cmd.arg.VDDIMGSDSet.en;
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::BatteryChargeLevelGet: {
            return MSP::Resp{
                .ok = true,
                .arg = { .BatteryChargeLevelGet = { .level = _BatterySampler::Sample() } },
            };
        }}
        
        return MSP::Resp{ .ok = false };
    }
    
    static inline struct {
        _HostMode::Assertion hostMode;
        _VDDIMGSDEnabled::Assertion vddImgSd;
    } _State;
    
    // Task stack
    SchedulerStack(".stack._TaskI2C")
    static inline uint8_t Stack[256];
};

// MARK: - _TaskMotion

struct _TaskMotion {
    static void Run() {
        for (;;) {
            _Motion::WaitForMotion();
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
    }
    
    // Task stack
    SchedulerStack(".stack._TaskMotion")
    static inline uint8_t Stack[128];
};

static void _MotionEnabledUpdate() {
    _Motion::Enabled(_MotionEnabled::Asserted());
}

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
        
        WDTCTL = WDTPW | WDTHOLD;
        
        // Init watchdog first
//        _Watchdog::Init();
        
        // If our previous reset wasn't because we explicitly reset ourself (a 'software BOR'), reset
        // ourself now.
        // This ensures that any unexpected reset (such as a watchdog timer timeout) triggers a full BOR,
        // and not a PUC or a POR. We want a full BOR because it resets all our peripherals, unlike a
        // PUC/POR, which don't reset all peripherals (like timers).
        // This will cause us to reset ourself twice upon initial startup, but that's OK.
        if (Startup::ResetReason() != SYSRSTIV_DOBOR) {
            _ResetRecord(MSP::Reset::Type::Reset, Startup::ResetReason());
            _BOR();
        }
        
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
            _I2C::Pin::Active,
            
            // Motion (config chosen by _Motion)
            _Motion::Pin::Power,
            _Motion::Pin::Signal,
            
            // Battery (config chosen by _BatterySampler)
            _BatterySampler::Pin::BatChrgLvlPin,
            _BatterySampler::Pin::BatChrgLvlEn_Pin,
            
            // Button (config chosen by _Button)
            _Button::Pin,
            
            // LEDs
            _Pin::LED_GREEN_,
            _Pin::LED_RED_
        >();
        
//        _Pin::LED_RED_::Write(1);
//        _Pin::LED_GREEN_::Write(1);
        
        // Init clock
        _Clock::Init();
        
//        _Pin::LED_RED_::Write(1);
//        _Pin::LED_GREEN_::Write(1);
//        for (;;) {
//            _Pin::LED_RED_::Write(0);
//            __delay_cycles(1000000);
//            _Pin::LED_RED_::Write(1);
//            __delay_cycles(1000000);
//        }
        
        // Init RTC
        // We need RTC to be unconditionally enabled for 2 reasons:
        //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
        //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
        //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
        _RTC::Init();
        
        // Init BatterySampler
        _BatterySampler::Init();
        
        // Init LEDs by setting their default-priority / 'backstop' values to off.
        // This is necessary so that relinquishing the LEDs from I2C task causes
        // them to turn off. If we didn't have a backstop value, the LEDs would
        // remain in whatever state the I2C task set them to before relinquishing.
        _LEDGreen_.set(_LEDPriority::Default, 1);
        _LEDRed_.set(_LEDPriority::Default, 1);
        
        // Start tasks
        _Scheduler::Start<_TaskI2C, _TaskMotion>();
        
        // Restore our saved power state
        // _OnSaved stores our power state across crashes/LPM3.5, so we need to
        // restore our _On assertion based on it.
        if (_OnSaved) {
            _On = true;
        }
    }
    
    static void Run() {
        _Init();
        
//        for (bool on_=false;; on_=!on_) {
//            _EventTimer::Schedule(_RTC::Now() + 1*Time::TicksFreq::num);
//            _LEDGreen_.set(_LEDPriority::Power, on_);
////            _EventTimer::Schedule(_RTC::Now() + 37*60*Time::TicksFreq::num);
//            _Scheduler::Wait([] { return _EventTimer::Fired(); });
//        }
        
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
    
    static void Sleep() {
        // Put ourself to sleep until an interrupt occurs. This function may or may not return:
        // 
        // - This function returns if an interrupt was already pending and the ISR
        //   wakes us (via `__bic_SR_register_on_exit`). In this case we never enter LPM3.5.
        // 
        // - This function doesn't return if an interrupt wasn't pending and
        //   therefore we enter LPM3.5. The next time we wake will be due to a
        //   reset and execution will start from main().
        
        // Enable/disable SysTick depending on whether we have tasks that are waiting for a deadline to pass.
        // We do this to prevent ourself from waking up unnecessarily, saving power.
        _SysTick = _Scheduler::TickRequired();
        
        // Remember our current interrupt state, which IntState will restore upon return
        Toastbox::IntState ints;
        // Atomically enable interrupts and go to sleep
        __bis_SR_register(GIE | LPM3_bits);
        
        // Unconditionally enable SysTick while we're awake
        _SysTick = true;
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
    
    // _On: controls user-visible on/off behavior
    static inline _Powered::Assertion _On;
    
    // _OnSaved: remembers our power state across crashes and LPM3.5.
    // This is needed because we don't want the device to return to the
    // powered-off state after a crash.
    // Stored in BAKMEM so it's kept alive through low-power modes <= LPM4.
    // gnu::used is apparently necessary for the gnu::section attribute to
    // work when link-time optimization is enabled.
    [[gnu::section(".ram_backup._TaskMain"), gnu::used]]
    static inline bool _OnSaved = false;
    
    // _SysTickEnabled: controls whether the SysTick timer is enabled
    // We disable SysTick when going to sleep if no tasks are waiting for a certain amount of time to pass
    static inline _SysTickEnabled::Assertion _SysTick;
    
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

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    // Pet the watchdog first
    _Watchdog::Pet();
    
    // Let _RTC know that we got an RTC interrupt
    _RTC::ISR(RTCIV);
    
    // Let _EventTimer know we got an RTC interrupt
    if (_EventTimer::ISRRTCInterested()) {
        const bool wake = _EventTimer::ISRRTC();
        // Wake if the timer fired
        if (wake) {
            __bic_SR_register_on_exit(LPM3_bits);
        }
    }
}

[[gnu::interrupt(TIMER0_A1_VECTOR)]]
static void _ISR_Timer0() {
    const bool wake = _EventTimer::ISRTimer(TA0IV);
    // Wake if the timer fired
    if (wake) {
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

[[gnu::interrupt(TIMER1_A1_VECTOR)]]
static void _ISR_Timer1() {
    const bool wake = _SysTick::ISR(TA1IV);
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

[[gnu::interrupt(PORT2_VECTOR)]]
static void _ISR_Port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    const uint16_t iv = P2IV;
    switch (__even_in_range(iv, 0x10)) {
    
    // Motion
    case _Pin::MOTION_SIGNAL::IVPort2():
        _Motion::ISR();
        __bic_SR_register_on_exit(LPM3_bits); // Wake ourself
        break;
    
    // I2C (ie VDD_B_3V3_STM)
    case _I2C::Pin::Active::IVPort2():
        _I2C::ISR_Active(iv);
        __bic_SR_register_on_exit(LPM3_bits); // Wake ourself
        break;
    
    // Button
    case _Button::Pin::IVPort2():
        _Button::ISR();
        __bic_SR_register_on_exit(LPM3_bits); // Wake ourself
        break;
    
    default:
        break;
    }
}

[[gnu::interrupt(USCI_B0_VECTOR)]]
static void _ISR_USCI_B0() {
    // Accessing `UCB0IV` automatically clears the highest-priority interrupt
    const uint16_t iv = UCB0IV;
    _I2C::ISR_I2C(iv);
    // Wake ourself
    __bic_SR_register_on_exit(LPM0_bits);
}

[[gnu::interrupt(ADC_VECTOR)]]
static void _ISR_ADC() {
    _BatterySampler::ISR(ADCIV);
    // Wake ourself
    __bic_SR_register_on_exit(LPM3_bits);
}

[[gnu::interrupt(UNMI_VECTOR)]]
static void _ISR_UNMI() {
    const uint16_t iv = SYSUNIV;
    
    switch (__even_in_range(iv, SYSUNIV_OFIFG)) {
    
    // This should never happen because we don't configure the reset pin to trigger an NMI
    case SYSUNIV_NMIIFG:
        Assert(false);
        break;
    
    // Oscillator fault
    case SYSUNIV_OFIFG:
        Assert(false);
        break;
    
    default:
        Assert(false);
        break;
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
    // Invokes the first task's Run() function (_TaskMain::Run)
    _Scheduler::Run();
}

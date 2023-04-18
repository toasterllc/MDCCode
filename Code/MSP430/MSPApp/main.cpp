#include <msp430.h>
#include <cstdint>
#include <cstdbool>
#include <cstddef>
#include <atomic>
#define SchedulerMSP430
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
#include "WDT.h"
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
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

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

class _TaskButton;
class _TaskEvent;
class _TaskSD;
class _TaskImg;
class _TaskI2C;
class _TaskMotion;

static void _Sleep();
static void _SchedulerStackOverflow();

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
    _TaskButton,
    _TaskEvent,
    _TaskSD,
    _TaskImg,
    _TaskI2C,
    _TaskMotion
>;

using _Clock = ClockType<_MCLKFreqHz>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;
using _ICE = ICE<_Scheduler>;

using _I2C = I2CType<_Scheduler, _Pin::MSP_STM_I2C_SCL, _Pin::MSP_STM_I2C_SDA, _Pin::VDD_B_3V3_STM, MSP::I2CAddr>;
using _Motion = T_Motion<_Scheduler, _Pin::MOTION_EN_, _Pin::MOTION_SIGNAL>;

using _BatterySampler = BatterySamplerType<_Scheduler, _Pin::BAT_CHRG_LVL, _Pin::BAT_CHRG_LVL_EN_>;

constexpr uint16_t _ButtonHoldDurationMs = 1500;
using _Button = ButtonType<_Scheduler, _Pin::BUTTON_SIGNAL_, _ButtonHoldDurationMs>;

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
using _RTC = RTCType<_XT1FreqHz, _Pin::MSP_XOUT, _Pin::MSP_XIN>;

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

// _Triggers: stores our current event state
using _Triggers = T_Triggers<_State, _MotionEnabledAssertion>;

static Time::Us _RepeatAdvance(MSP::Repeat& x) {
    static constexpr Time::Us Day         = (Time::Us)     24*60*60*1000000;
    static constexpr Time::Us Year        = (Time::Us) 365*24*60*60*1000000;
    static constexpr Time::Us YearPlusDay = (Time::Us) 366*24*60*60*1000000;
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

//static void _EventInsert(_Triggers::Event& ev, const Time::Instant& t) {
//    _Triggers::EventInsert(ev, t);
//}

static void _EventInsert(_Triggers::Event& ev, MSP::Repeat& repeat) {
    const Time::Us delta = _RepeatAdvance(repeat);
    // delta=0 means Repeat=never, in which case we don't reschedule the event
    if (delta) {
        _Triggers::EventInsert(ev, ev.time+delta);
    }
}

static void _EventInsert(_Triggers::Event& ev, Time::Instant time, uint32_t deltaMs) {
    _Triggers::EventInsert(ev, time + ((Time::Us)deltaMs)*1000);
}

static void _CaptureStart(_Triggers::CaptureImageEvent& ev, Time::Instant time) {
    // Reset capture count
    ev.countRem = ev.capture->count;
    if (ev.countRem) {
        _Triggers::EventInsert(ev, time);
    }
}










// MARK: - Power

static void _VDDBEnabledUpdate() {
    _Pin::VDD_B_EN::Write(_VDDBEnabled::Asserted());
    // Rails take ~1.5ms to turn on/off, so wait 2ms to be sure
    _Scheduler::Sleep(_Scheduler::Ms(2));
}

static void _VDDIMGSDEnabledUpdate() {
    if (_VDDIMGSDEnabled::Asserted()) {
        _Pin::VDD_B_2V8_IMG_SD_EN::Write(1);
        _Scheduler::Sleep(_Scheduler::Us(100)); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V8)
        _Pin::VDD_B_1V8_IMG_SD_EN::Write(1);
        
        // Rails take ~1ms to turn on, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms(2));
    
    } else {
        // No delay between 2V8/1V8 needed for power down (per AR0330CS datasheet)
        _Pin::VDD_B_2V8_IMG_SD_EN::Write(0);
        _Pin::VDD_B_1V8_IMG_SD_EN::Write(0);
        
        // Rails take ~1.5ms to turn off, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms(2));
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
        _Scheduler::Sleep(_Scheduler::Ms(1));
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
            header.timestamp = _RTC::TimeRead();
            
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
            _CaptureStart(trigger, ev.time);
        }
        // Reschedule TimeTriggerEvent for its next trigger time
        _EventInsert(ev, ev.repeat);
    }
    
    static void _MotionEnable(_Triggers::MotionEnableEvent& ev) {
        _Triggers::MotionTrigger& trigger = ev.trigger();
        
        // Enable motion
        trigger.enabled.set(true);
        
        // Schedule the MotionDisable event, if applicable
        // This needs to happen before we reschedule `motionEnableEvent` because we need its .time to
        // properly schedule the MotionDisableEvent!
        const uint32_t durationMs = trigger.base().durationMs;
        if (durationMs) {
            _EventInsert((_Triggers::MotionDisableEvent&)trigger, ev.time, durationMs);
        }
        
        // Reschedule MotionEnableEvent for its next trigger time
        _EventInsert(ev, ev.repeat);
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
        _Scheduler::Sleep(_Scheduler::Ms(30));
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
            _EventInsert(ev, ev.time, ev.capture->delayMs);
        }
    }
    
    static _Triggers::Event* _EventPop() {
        _Triggers::Event* ev = _Triggers::EventPop(_RTC::TimeRead());
        // Exit fast-forward mode when we no longer have any events in the past
        if (!ev) {
            _State.fastForward = false;
        }
        return ev;
    }
    
    static void Run() {
        // Reset our state
        Reset();
        
        // Init SPI peripheral
        _SPI::Init();
        
        // Init Triggers
        _Triggers::Init(_RTC::TimeRead());
        
        // Enter fast-forward mode while we pop every event that occurs in the past
        // (_EventPop() will exit from fast-forward mode)
        _State.fastForward = true;
        for (;;) {
            // Wait for an event
            static _Triggers::Event* ev = nullptr;
            _Scheduler::Wait([] { return (bool)(ev = _EventPop()); });
            
            // Don't go to sleep until we handle the event
            _State.caffeine = true;
            
            using T = _Triggers::Event::Type;
            switch (ev->type) {
            case T::TimeTrigger:      _TimeTrigger((_Triggers::TimeTriggerEvent&)*ev);           break;
            case T::MotionEnable:     _MotionEnable((_Triggers::MotionEnableEvent&)*ev);         break;
            case T::MotionDisable:    _MotionDisable((_Triggers::MotionDisableEvent&)*ev);       break;
            case T::MotionUnsuppress: _MotionUnsuppress((_Triggers::MotionUnsuppressEvent&)*ev); break;
            case T::CaptureImage:     _CaptureImage((_Triggers::CaptureImageEvent&)*ev);         break;
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
        // These need to be an ivar because TaskMain can be reset at any time via
        // our Reset() function, so if the power assertion lived on the stack and
        // TaskMain is reset, its destructor would never be called and our state
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
                .arg = { .TimeGet = { .time = _RTC::TimeRead() } },
            };
        
        case Cmd::Op::TimeSet:
            // Only allow setting the time while we're in host mode
            // and therefore TaskMain isn't running
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
                    const Time::Instant time = _RTC::TimeRead();
                    // Start capture
                    _CaptureStart(trigger, time);
                    // Suppress motion for the specified duration, if suppression is enabled
                    const uint32_t suppressMs = trigger.base().suppressMs;
                    if (suppressMs) {
                        trigger.enabled.suppress(true);
                        _EventInsert((_Triggers::MotionUnsuppressEvent&)trigger, time, suppressMs);
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
        
        // Init GPIOs
        GPIO::Init<
            // Power control
            _Pin::VDD_B_EN,
            _Pin::VDD_B_1V8_IMG_SD_EN,
            _Pin::VDD_B_2V8_IMG_SD_EN,
            
            // Clock (config chosen by _RTC)
            _RTC::Pin::XOUT,
            _RTC::Pin::XIN,
            
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
        
        // Init clock
        _Clock::Init();
        
        // Init RTC
        // We need RTC to be unconditionally enabled for 2 reasons:
        //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
        //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
        //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
        _RTC::Init();
        
        // Init SysTick
        _SysTick::Init();
        
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
                    _CaptureStart(*it, _RTC::TimeRead());
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
    // Put ourself to sleep until an interrupt occurs. This function may or may not return:
    // 
    // - This function returns if an interrupt was already pending and the ISR
    //   wakes us (via `__bic_SR_register_on_exit`). In this case we never enter LPM3.5.
    // 
    // - This function doesn't return if an interrupt wasn't pending and
    //   therefore we enter LPM3.5. The next time we wake will be due to a
    //   reset and execution will start from main().
    
    // If deep sleep is OK, enter LPM3.5 sleep, where RAM content is lost.
    // Otherwise, enter LPM1 sleep, because something is running.
    
//    const uint16_t mode = (_PowerAssertion::Asserted() ? LPM1_bits : LPM3_bits);
    
//    // If nothing asserts that we remained powered, enter LPM3.5
//    if (!_PowerAssertion::Asserted()) {
//        PMMUnlock pmm; // Unlock PMM registers
//        PMMCTL0_L |= PMMREGOFF_L;
//    }
    
    // Remember our current interrupt state, which IntState will restore upon return
    Toastbox::IntState ints;
    // Atomically enable interrupts and go to sleep
    __bis_SR_register(GIE | LPM3_bits);
}

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    _RTC::ISR();
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

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_SysTick() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

[[gnu::interrupt(ADC_VECTOR)]]
static void _ISR_ADC() {
    _BatterySampler::ISR(ADCIV);
    // Wake ourself
    __bic_SR_register_on_exit(LPM3_bits);
}

// MARK: - Abort

[[noreturn]]
static void _SchedulerStackOverflow() {
    Assert(false);
}

static void _AbortRecord(const Time::Instant& timestamp, uintptr_t addr) {
    using namespace MSP;
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    AbortHistory* hist = nullptr;
    for (AbortHistory& h : _State.aborts) {
        if (!h.count || h.addr==addr) {
            hist = &h;
            break;
        }
    }
    
    // If we don't have a place to record the abort, bail
    if (!hist) return;
    
    // Prep the element if this is the first instance
    if (!hist->count) {
        hist->addr = addr;
        hist->earliest = timestamp;
    }
    
    hist->latest = timestamp;
    hist->count++;
}

[[noreturn]]
static void _BOR() {
    PMMUnlock pmm; // Unlock PMM registers
    PMMCTL0_L |= PMMSWBOR_L;
    // Wait for reset
    for (;;);
}

// Abort(): called various Assert's throughout our program
[[noreturn]]
void Abort(uintptr_t addr) {
    const Time::Instant timestamp = _RTC::TimeRead();
    // Record the abort
    _AbortRecord(timestamp, addr);
    _BOR();
}

extern "C" [[noreturn]]
void abort() {
    Assert(false);
}

extern "C"
int atexit(void (*)(void)) {
    return 0;
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
    // Invokes the first task's Run() function (_TaskButton::Run)
    _Scheduler::Run();
}

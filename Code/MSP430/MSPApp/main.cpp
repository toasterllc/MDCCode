#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include <atomic>
#define TaskMSP430
#include "Toastbox/Task.h"
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
#include "FRAMWriteEn.h"
#include "Util.h"
#include "MSP.h"
#include "GetBits.h"
#include "Toastbox/IntState.h"
#include "ImgSD.h"
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line);

struct _Pin {
    // Default GPIOs
    using UNUSED0                           = PortA::Pin<0x0>;
    using DEBUG_OUT                         = PortA::Pin<0x1, Option::Output0>;
    using VDD_B_EN                          = PortA::Pin<0x2, Option::Output0>;
    using MOTION_SIGNAL                     = PortA::Pin<0x3, Option::Resistor0>; // Motion sensor can only pull up, so it requires a pulldown resistor
//    using MOTION_SIGNAL                     = PortA::Pin<0x3, Option::Interrupt01, Option::Resistor0>; // Motion sensor can only pull up, so it requires a pulldown resistor
    using UNUSED4                           = PortA::Pin<0x4>;
    using UNUSED5                           = PortA::Pin<0x5>;
    using VDD_B_2V8_IMG_SD_EN               = PortA::Pin<0x6, Option::Input, Option::Resistor0>; // Weakly controlled to allow STM to override
    using UNUSED7                           = PortA::Pin<0x7>;
    using XOUT                              = PortA::Pin<0x8>;
    using XIN                               = PortA::Pin<0x9>;
    using HOST_MODE_                        = PortA::Pin<0xA, Option::Input, Option::Resistor0>;
    using VDD_B_1V8_IMG_SD_EN               = PortA::Pin<0xB, Option::Input, Option::Resistor0>; // Weakly controlled to allow STM to override
    using ICE_MSP_SPI_CLK                   = PortA::Pin<0xC>;
    using ICE_MSP_SPI_DATA_OUT              = PortA::Pin<0xD>;
    using ICE_MSP_SPI_DATA_IN               = PortA::Pin<0xE>;
};

// _MotionSignalIV: motion interrupt vector; keep in sync with the pin chosen for MOTION_SIGNAL
constexpr uint16_t _MotionSignalIV = P1IV__P1IFG3;

using _Clock = ClockType<_MCLKFreqHz>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;

class _MainTask;
class _SDTask;
class _ImgTask;

static void _Sleep();

static void _SchedulerError(uint16_t line);
static void _ICEError(uint16_t line);
static void _SDError(uint16_t line);
static void _ImgError(uint16_t line);

extern uint8_t _StackMain[];

#warning disable stack guard for production
static constexpr size_t _StackGuardCount = 16;
using _Scheduler = Toastbox::Scheduler<
    _SysTickPeriodUs,                           // T_UsPerTick: microseconds per tick
    Toastbox::IntState::SetInterruptsEnabled,   // T_SetInterruptsEnabled: function to change interrupt state
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    _SchedulerError,                            // T_Error: function to handle unrecoverable error
    _StackMain,                                 // T_MainStack: main stack pointer (only used to monitor
                                                //              main stack for overflow; unused if T_StackGuardCount==0)
    _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
    _MainTask,                                  // T_Tasks: list of tasks
    _SDTask,
    _ImgTask
>;

using _ICE = ICE<
    _Scheduler,
    _ICEError
>;

// _ImgSensor: image sensor object
using _ImgSensor = Img::Sensor<
    _Scheduler,             // T_Scheduler
    _ICE,                   // T_ICE
    _ImgError               // T_Error
>;

// _SDCard: SD card object
using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    _SDError,           // T_Error
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    6                   // T_ClkDelayFast (odd values invert the clock)
>;

using _RTCType = RTC::Type<_XT1FreqHz, _Pin::XOUT, _Pin::XIN>;

// _RTC: real time clock
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
// 
// _RTC needs to live in the _noinit variant, so that RTC memory
// is never automatically initialized, because we don't want it
// to be reset when we abort.
[[gnu::section(".ram_backup_noinit.main")]]
static _RTCType _RTC;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely
[[gnu::section(".fram_info.main")]]
static MSP::State _State;

// MARK: - Power

static void _VDDBSetEnabled(bool en) {
    _Pin::VDD_B_EN::Write(en);
}

static void _VDDIMGSDSetEnabled(bool en) {
    // Short-circuit if the pin state hasn't changed, to save us the Sleep()
    if (_Pin::VDD_B_2V8_IMG_SD_EN::Read() == en) return;
    
    if (en) {
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

// MARK: - Tasks

static void debugSignal() {
    _Pin::DEBUG_OUT::Init();
    for (;;) {
//    for (int i=0; i<10; i++) {
        _Pin::DEBUG_OUT::Write(0);
        for (volatile int i=0; i<10000; i++);
        _Pin::DEBUG_OUT::Write(1);
        for (volatile int i=0; i<10000; i++);
    }
}

struct _SDTask {
    static void Reset() {
        Wait();
        _Scheduler::Start<_SDTask>([] { _Reset(); });
    }
    
    static void Init() {
        Wait();
        _Scheduler::Start<_SDTask>([] { _Init(); });
    }
    
    static void Write(uint8_t srcRAMBlock) {
        Wait();
        
        _Writing = true;
        
        static struct { uint8_t srcRAMBlock; } Args;
        Args = { srcRAMBlock };
        _Scheduler::Start<_SDTask>([] { _Write(Args.srcRAMBlock); });
    }
    
    static void Wait() {
        _Scheduler::Wait<_SDTask>();
    }
    
    // WaitForInitAndWrite: wait for both initialization and writing to complete
    static void WaitForInitAndWrite() {
        _Scheduler::Wait([&] { return _RCA.has_value() && !_Writing; });
    }
    
//    static void WaitForInit() {
//        _Scheduler::Wait([&] { return _RCA.has_value(); });
//    }
    
    static void _Reset() {
        _SDCard::Reset();
    }
    
    static void _Init() {
        if (!_RCA) {
            // We haven't successfully enabled the SD card since the battery was connected;
            // enable the SD card and get the card id / card data.
            SD::CardId cardId;
            SD::CardData cardData;
            _RCA = _SDCard::Init(&cardId, &cardData);
            
            // If SD state isn't valid, or the existing SD card id doesn't match the current
            // card id, reset the SD state.
            if (!_State.sd.valid || memcmp(&_State.sd.cardId, &cardId, sizeof(cardId))) {
                _StateInit(cardId, cardData);
            
            // Otherwise the SD state is valid and the SD card id matches, so init the ring buffers.
            } else {
                _ImgRingBufInit();
            }
        
        } else {
            // We've previously enabled the SD card successfully since the battery was connected;
            // enable it again
            _SDCard::Init();
        }
    }
    
    static void _Write(uint8_t srcRAMBlock) {
        const uint32_t widx = _State.sd.imgRingBufs[0].buf.widx;
        
        // Copy full-size image from RAM -> SD card
        {
            const SD::Block dstSDBlock = widx * ImgSD::Full::ImageBlockCount;
            _SDCard::WriteImage(*_RCA, srcRAMBlock, dstSDBlock, Img::Size::Full);
        }
        
        // Copy thumbnail from RAM -> SD card
        {
            const SD::Block dstSDBlock = _State.sd.thumbBlockStart + (widx * ImgSD::Thumb::ImageBlockCount);
            _SDCard::WriteImage(*_RCA, srcRAMBlock, dstSDBlock, Img::Size::Thumb);
        }
        
        _ImgRingBufIncrement();
        _Writing = false;
    }
    
    // _StateInit(): resets the _State.sd struct
    static void _StateInit(const SD::CardId& cardId, const SD::CardData& cardData) {
        // CombinedBlockCount: thumbnail block count + full-size block count
        constexpr uint32_t CombinedBlockCount = ImgSD::Thumb::ImageBlockCount + ImgSD::Full::ImageBlockCount;
        // cardBlockCap: the capacity of the SD card in SD blocks (1 block == 512 bytes)
        const uint32_t cardBlockCap = ((uint32_t)GetBits<69,48>(cardData)+1) * (uint32_t)1024;
        // cardImgCap: the capacity of the SD card in number of images
        const uint32_t cardImgCap = cardBlockCap / CombinedBlockCount;
        
        FRAMWriteEn writeEn; // Enable FRAM writing
        
        // Mark the _State as invalid in case we lose power in the middle of modifying it
        _State.sd.valid = false;
        std::atomic_signal_fence(std::memory_order_seq_cst);
        
        // Set .cardId
        {
            _State.sd.cardId = cardId;
        }
        
        // Set .imgCap
        {
            _State.sd.imgCap = cardImgCap;
        }
        
        // Set .thumbBlockStart
        {
            _State.sd.thumbBlockStart = cardImgCap * ImgSD::Full::ImageBlockCount;
        }
        
        // Set .imgRingBufs
        {
            _State.sd.imgRingBufs[0] = {};
            _State.sd.imgRingBufs[1] = {};
        }
        
        std::atomic_signal_fence(std::memory_order_seq_cst);
        _State.sd.valid = true;
    }
    
    // _ImgRingBufInit(): find the correct image ring buffer (the one with the greatest id that's valid)
    // and copy it into the other slot so that there are two copies. If neither slot contains a valid ring
    // buffer, reset them both so that they're both empty (and valid).
    static void _ImgRingBufInit() {
        using namespace MSP;
        FRAMWriteEn writeEn; // Enable FRAM writing
        
        MSP::ImgRingBuf& a = _State.sd.imgRingBufs[0];
        MSP::ImgRingBuf& b = _State.sd.imgRingBufs[1];
        const std::optional<int> comp = ImgRingBuf::Compare(a, b);
        if (comp && *comp>0) {
            // a>b (a is newer), so set b=a
            b = a;
        
        } else if (comp && *comp<0) {
            // b>a (b is newer), so set a=b
            a = b;
        
        } else if (!comp) {
            // Both a and b are invalid; reset them both
            a = {};
            b = {};
        }
    }
    
    static void _ImgRingBufIncrement() {
        FRAMWriteEn writeEn; // Enable FRAM writing
        MSP::ImgRingBuf ringBufCopy = _State.sd.imgRingBufs[0];
        
        // Update write index
        ringBufCopy.buf.widx++;
        // Wrap widx
        if (ringBufCopy.buf.widx >= _State.sd.imgCap) ringBufCopy.buf.widx = 0;
        
        // Update read index (if we're currently full)
        if (ringBufCopy.buf.full) {
            ringBufCopy.buf.ridx++;
            // Wrap ridx
            if (ringBufCopy.buf.ridx >= _State.sd.imgCap) ringBufCopy.buf.ridx = 0;
            
            // Update the beginning image id (which only gets incremented if we're full)
            ringBufCopy.buf.idBegin++;
        }
        
        // Update the end image id (the next image id that'll be used)
        ringBufCopy.buf.idEnd++;
        
        if (ringBufCopy.buf.widx == ringBufCopy.buf.ridx) ringBufCopy.buf.full = true;
        
        _State.sd.imgRingBufs[0] = ringBufCopy;
        _State.sd.imgRingBufs[1] = ringBufCopy;
    }
    
    // _RCA: SD card 'relative card address'; needed for SD comms after initialization.
    // As an optional, _RCA also signifies whether we've successfully initiated comms
    // with the SD card since the battery was plugged in.
    // Stored in BAKMEM (RAM that's retained in LPM3.5) so that it's maintained during
    // sleep, but reset upon a cold start.
    [[gnu::section(".ram_backup.main")]]
    static inline std::optional<uint16_t> _RCA;
    
    static inline bool _Writing = false;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._SDTask")]]
    static inline uint8_t Stack[256];
};

struct _ImgTask {
    static void Init() {
        Wait();
        _Scheduler::Start<_ImgTask>([] { _Init(); });
    }
    
    static void Capture(const Img::Id& id) {
        Wait();
        
        static struct { Img::Id id; } Args;
        Args = { id };
        _Scheduler::Start<_ImgTask>([] { _Capture(Args.id); });
    }
    
    static uint8_t CaptureBlock() {
        Wait();
        return _CaptureBlock;
    }
    
    static void Wait() {
        _Scheduler::Wait<_ImgTask>();
    }
    
    static void _Init() {
        // Initialize image sensor
        _ImgSensor::Init();
        // Set the initial exposure _before_ we enable streaming, so that the very first frame
        // has the correct exposure, so we don't have to skip any frames on the first capture.
        _ImgSensor::SetCoarseIntTime(_AutoExp.integrationTime());
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
            
            header.coarseIntTime = _AutoExp.integrationTime();
            header.id = id;
            header.timestamp = _RTC.time();
            
            // Capture an image to RAM
            const _ICE::ImgCaptureStatusResp resp = _ICE::ImgCapture(header, expBlock, skipCount);
            const uint8_t expScore = _AutoExp.update(resp.highlightCount(), resp.shadowCount());
            if (!bestExpScore || (expScore > bestExpScore)) {
                bestExpBlock = expBlock;
                bestExpScore = expScore;
            }
            
            // We're done if we don't have any exposure changes
            if (!_AutoExp.changed()) break;
            
            // Update the exposure
            _ImgSensor::SetCoarseIntTime(_AutoExp.integrationTime());
        }
        
        _CaptureBlock = bestExpBlock;
    }
    
    static inline uint8_t _CaptureBlock = 0;
    
    // _AutoExp: auto exposure algorithm object
    // Stored in BAKMEM (RAM that's retained in LPM3.5) so that
    // it's maintained during sleep, but reset upon a cold start.
    // This is so we don't forget exposure levels between captures,
    // since the exposure doesn't change often.
    [[gnu::section(".ram_backup.main")]]
    static inline Img::AutoExposure _AutoExp;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._ImgTask")]]
    static inline uint8_t Stack[256];
};

// CCIFG0 interrupt
[[gnu::interrupt(TIMER0_A0_VECTOR)]]
static void _ISR_TIMER0_A0() {
    __bic_SR_register_on_exit(LPM3_bits);
}

struct _MainTask {
    static void Run() {
        const MSP::ImgRingBuf& imgRingBuf = _State.sd.imgRingBufs[0];
        
        // Configure Timer_A
        TA0CCTL0 = CM__NONE | CAP__COMPARE | CCIE_1; // No capture (CM__NONE), compare mode (CAP__COMPARE), enable CCIFG0 interrupt
//        TA0CCR0 = 40960-1; // 5 seconds: 5 s / (1 / (32768 Hz / 4))
//        TA0CCR0 = 8192-1; // // 1 second: 1 s / (1 / (32768 Hz / 4))
        TA0CCR0 = 16384-1; // // 2 seconds: 2 s / (1 / (32768 Hz / 4))
        // Source=ACLK, Continuous mode, clear TAR
        TA0CTL = TASSEL__ACLK | ID__4 | MC__UP | TACLR;
        
        // Init SPI peripheral
        _SPI::Init();
        
        for (;;) {
            // Turn on VDD_B power (turns on ICE40)
            _VDDBSetEnabled(true);
            
            // Wait for ICE40 to start
            // We specify (within the bitstream itself, via icepack) that ICE40 should load
            // the bitstream at high-frequency (40 MHz).
            // According to the datasheet, this takes 70ms.
            _Scheduler::Sleep(_Scheduler::Ms(75));
            
            // Reset ICE comms (by asserting SPI CLK for some length of time)
            _SPI::ICEReset();
            
            // Init ICE comms
            _ICE::Init();
            
            // Reset SD nets before we turn on SD power
            _SDTask::Reset();
            _SDTask::Wait();
            
            // Turn on IMG/SD power
            _VDDIMGSDSetEnabled(true);
            
            // Init image sensor / SD card
            _ImgTask::Init();
            _SDTask::Init();
            
            // Capture an image
            {
                _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
                
                // Wait for _SDTask to be initialized and done with writing, which is necessary
                // for 2 reasons:
                //   1. we have to wait for _SDTask to initialize _State.sd.imgRingBufs before we
                //      access it,
                //   2. we can't initiate a new capture until writing to the SD card (from a
                //      previous capture) is complete (because the SDRAM is single-port, so
                //      we can only read or write at one time)
                _SDTask::WaitForInitAndWrite();
                
                // Capture image to RAM
                _ImgTask::Capture(imgRingBuf.buf.idEnd);
                const uint8_t srcRAMBlock = _ImgTask::CaptureBlock();
                
                // Copy image from RAM -> SD card
                _SDTask::Write(srcRAMBlock);
                _SDTask::Wait();
                
                _ICE::Transfer(_ICE::LEDSetMsg(0x00));
            }
            
            // Turn off power
            _VDDIMGSDSetEnabled(false);
            _VDDBSetEnabled(false);
            
            // Go to sleep and wait for timer to fire
            // We pause SysTick while we sleep so we don't wake at all until the timer fires
            WDTCTL = ((uint16_t)WDTCTL_L | WDTPW) | WDTHOLD;
//            // Enter LPM3.5
//            {
//                PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
//                PMMCTL0_L |= PMMREGOFF_1_L;
//            }
            __bis_SR_register(LPM3_bits);
            WDTCTL = ((uint16_t)WDTCTL_L | WDTPW | WDTCNTCL) & ~WDTHOLD;
        }
    }
    
    static bool DeepSleepOK() {
        // Permit LPM3.5 if we're waiting for motion, and neither of our tasks are doing anything.
        // This logic works because if _WaitingForMotion==true, then we've disabled both _SDTask
        // and _ImgTask, so if the tasks are idle, then everything's idle so we can enter deep
        // sleep. (The case that we need to be careful of is going to sleep when either _SDTask
        // or _ImgTask is idle but still powered on, which the _WaitingForMotion check takes
        // care of.)
        return _WaitingForMotion                &&
               !_Scheduler::Running<_SDTask>()  &&
               !_Scheduler::Running<_ImgTask>() ;
    }
    
    static void MotionSignal() {
        _Motion = true;
    }
    
    // _Motion: announces that motion occurred
    // atomic because _Motion is modified from the interrupt context
    static inline std::atomic<bool> _Motion = false;
    static inline bool _WaitingForMotion = false;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._MainTask")]]
    static inline uint8_t Stack[256];
};

// MARK: - IntState

inline bool Toastbox::IntState::InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

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
    const uint16_t LPMBits = (_MainTask::DeepSleepOK() ? LPM3_bits : LPM1_bits);
    
    // If we're entering LPM3, disable regulator so we enter LPM3.5 (instead of just LPM3)
    if (LPMBits == LPM3_bits) {
        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
        PMMCTL0_L |= PMMREGOFF_1_L;
    }
    
    // Atomically enable interrupts and go to sleep
    const bool prevEn = Toastbox::IntState::InterruptsEnabled();
    __bis_SR_register(GIE | LPMBits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    _RTC.isr();
}

[[gnu::interrupt(PORT1_VECTOR)]]
static void _ISR_Port1() {
    // Accessing `P1IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P1IV, _MotionSignalIV)) {
    case _MotionSignalIV:
        _MainTask::MotionSignal();
        // Wake ourself
        __bic_SR_register_on_exit(LPM3_bits);
        break;
    
    default:
        break;
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

// MARK: - Abort

namespace AbortDomain {
    static constexpr uint16_t Invalid       = 0;
    static constexpr uint16_t General       = 1;
    static constexpr uint16_t Scheduler     = 2;
    static constexpr uint16_t ICE           = 3;
    static constexpr uint16_t SD            = 4;
    static constexpr uint16_t Img           = 5;
}

[[noreturn]]
static void _SchedulerError(uint16_t line) {
    _Abort(AbortDomain::Scheduler, line);
}

[[noreturn]]
static void _ICEError(uint16_t line) {
    _Abort(AbortDomain::ICE, line);
}

[[noreturn]]
static void _SDError(uint16_t line) {
    _Abort(AbortDomain::SD, line);
}

[[noreturn]]
static void _ImgError(uint16_t line) {
    _Abort(AbortDomain::Img, line);
}

static void _AbortRecord(const MSP::Time& timestamp, uint16_t domain, uint16_t line) {
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    auto& abort = _State.abort;
    if (abort.eventsCount >= std::size(abort.events)) return;
    
    abort.events[abort.eventsCount] = MSP::AbortEvent{
        .timestamp = timestamp,
        .domain = domain,
        .line = line,
    };
    
    abort.eventsCount++;
}

[[noreturn]]
static void _BOR() {
    PMMCTL0 = PMMPW | PMMSWBOR;
    for (;;);
}

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line) {
    const MSP::Time timestamp = _RTC.time();
    // Record the abort
    _AbortRecord(timestamp, domain, line);
    _BOR();
}

extern "C" [[noreturn]]
void abort() {
    _Abort(AbortDomain::General, 0);
}

// MARK: - Main

#warning verify that _StackMainSize is large enough
#define _StackMainSize 128

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm(".equ __stack, _StackMain+" Stringify(_StackMainSize));

static void _HostMode() {
    // Let power rails fully discharge before turning them on
    _Scheduler::Delay(_Scheduler::Ms(10));
    
    while (!_Pin::HOST_MODE_::Read()) {
        _Scheduler::Delay(_Scheduler::Ms(100));
    }
}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIO::Init<
        // General IO
        _Pin::DEBUG_OUT,
        _Pin::MOTION_SIGNAL,
        _Pin::HOST_MODE_,
        
        // Power control
        _Pin::VDD_B_EN,
        _Pin::VDD_B_1V8_IMG_SD_EN,
        _Pin::VDD_B_2V8_IMG_SD_EN,
        
        // Clock (config chosen by _RTCType)
        _RTCType::Pin::XOUT,
        _RTCType::Pin::XIN,
        
        // SPI (config chosen by _SPI)
        _SPI::Pin::Clk,
        _SPI::Pin::DataOut,
        _SPI::Pin::DataIn
    >();
    
    // We're using the 'remapped' pin assignments for the eUSCI_B0 pins, which requires setting SYSCFG2.USCIBRMP.
    // See "Table 9-11. eUSCI Pin Configurations" in the datasheet.
    SYSCFG2 |= USCIBRMP;
    
    // Init clock
    _Clock::Init();
    
    // Init RTC
    // We need RTC to be unconditionally enabled for 2 reasons:
    //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
    //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
    //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
    MSP::Time startTime = 0;
    if (_State.startTime.valid) {
        startTime = _State.startTime.time;
        
        // If `time` is valid, consume it before handing it off to _RTC.
        FRAMWriteEn writeEn; // Enable FRAM writing
        // Reset `valid` before consuming the start time, so that if we lose power,
        // the time won't be reused again
        _State.startTime.valid = false;
        std::atomic_signal_fence(std::memory_order_seq_cst);
    }
    _RTC.init(startTime);
    
    // Init SysTick
    _SysTick::Init();
    
//    {
//        _Pin::VDD_B_EN::Write(1);
//        _Scheduler::Delay(_Scheduler::Ms(1000));
//        
////        debugSignal();
//        
//        for (;;) {
//            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//            _Scheduler::Delay(_Scheduler::Ms(250));
//            
//            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            _Scheduler::Delay(_Scheduler::Ms(250));
//        }
//    }
    
    // Handle cold starts
    if (Startup::ColdStart()) {
        // Temporarily enable a pullup on HOST_MODE_ so that we can determine whether STM is driving it low.
        // We don't want the pullup to be permanent to prevent leakage current (~80nA) through STM32's GPIO
        // that controls HOST_MODE_.
        _Pin::HOST_MODE_::Write(1);
        
        // Wait for the pullup to pull the rail up
        _Scheduler::Delay(_Scheduler::Ms(1));
        
        // Enter host mode if HOST_MODE_ is asserted
        if (!_Pin::HOST_MODE_::Read()) {
            _HostMode();
        }
        
        // Return to default HOST_MODE_ config
        // Not using GPIO::Init() here because it costs a lot more instructions.
        _Pin::HOST_MODE_::Write(0);
        
        // Since this is a cold start, delay 3s before beginning.
        // This delay is meant for the case where we restarted due to an abort, and
        // serves 2 purposes:
        //   1. it rate-limits aborts, in case there's a persistent issue
        //   2. it allows GPIO outputs to settle, so that peripherals fully turn off
        _Scheduler::Delay(_Scheduler::Ms(3000));
    }
    
    _Scheduler::Run();
}




//#warning TODO: remove these debug symbols
//#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section
//constexpr auto& _Debug_Tasks              = _Scheduler::_Tasks;
//constexpr auto& _Debug_DidWork            = _Scheduler::_DidWork;
//constexpr auto& _Debug_CurrentTask        = _Scheduler::_CurrentTask;
//constexpr auto& _Debug_CurrentTime        = _Scheduler::_ISR.CurrentTime;
//constexpr auto& _Debug_Wake               = _Scheduler::_ISR.Wake;
//constexpr auto& _Debug_WakeTime           = _Scheduler::_ISR.WakeTime;
//
//struct _DebugStack {
//    uint16_t stack[_StackGuardCount];
//};
//
//const _DebugStack& _Debug_MainStack               = *(_DebugStack*)_StackMain;
//const _DebugStack& _Debug_MainTaskStack         = *(_DebugStack*)_MainTask::Stack;
//const _DebugStack& _Debug_SDTaskStack             = *(_DebugStack*)_SDTask::Stack;
//const _DebugStack& _Debug_ImgTaskStack            = *(_DebugStack*)_ImgTask::Stack;

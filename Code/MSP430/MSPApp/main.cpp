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
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line);

struct _Pin {
    // Default GPIOs
    using VDD_1V9_IMG_EN                    = PortA::Pin<0x0, Option::Output0>;
    using VDD_2V8_IMG_EN                    = PortA::Pin<0x2, Option::Output0>;
    using ICE_MSP_SPI_DATA_DIR              = PortA::Pin<0x3>;
    using ICE_MSP_SPI_DATA_OUT              = PortA::Pin<0x4>;
    using ICE_MSP_SPI_DATA_IN               = PortA::Pin<0x5>;
    using ICE_MSP_SPI_CLK                   = PortA::Pin<0x6>;
    using ICE_MSP_SPI_AUX                   = PortA::Pin<0x7, Option::Output0>;
    using XOUT                              = PortA::Pin<0x8>;
    using XIN                               = PortA::Pin<0x9>;
    using ICE_MSP_SPI_AUX_DIR               = PortA::Pin<0xA, Option::Output1>;
    using VDD_SD_EN                         = PortA::Pin<0xB, Option::Output0>;
    using VDD_B_EN_                         = PortA::Pin<0xC, Option::Output1>;
    using MOTION_SIGNAL                     = PortA::Pin<0xD, Option::Resistor0, Option::Interrupt01>; // Motion sensor can only pull up, so it requires a pulldown resistor
    
    using DEBUG_OUT                         = PortA::Pin<0xE, Option::Output0>;
};

using _Clock = ClockType<_XT1FreqHz, _MCLKFreqHz, _Pin::XOUT, _Pin::XIN>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN, _Pin::ICE_MSP_SPI_DATA_DIR>;

class _MotionTask;
class _SDTask;
class _ImgTask;
class _BusyTimeoutTask;

static void _Sleep();

static void _SchedulerError(uint16_t line);
static void _ICEError(uint16_t line);
static void _SDError(uint16_t line);
static void _ImgError(uint16_t line);

static void _SDSetPowerEnabled(bool en);
static void _ImgSetPowerEnabled(bool en);

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
    _MotionTask,                                // T_Tasks: list of tasks
    _SDTask,
    _ImgTask,
    _BusyTimeoutTask
>;

using _ICE = ICE<
    _Scheduler,
    _ICEError
>;

// _ImgSensor: image sensor object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
using _ImgSensor = Img::Sensor<
    _Scheduler,             // T_Scheduler
    _ICE,                   // T_ICE
    _ImgSetPowerEnabled,    // T_SetPowerEnabled
    _ImgError               // T_Error
>;

// _SDCard: SD card object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    _SDSetPowerEnabled, // T_SetPowerEnabled
    _SDError,           // T_Error
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    0                   // T_ClkDelayFast (odd values invert the clock)
>;

// _RTC: real time clock
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
// 
// _RTC needs to live in the _noinit variant, so that RTC memory
// is never automatically initialized, because we don't want it
// to be reset when we abort.
[[gnu::section(".ram_backup_noinit.main")]]
static RTC::Type<_XT1FreqHz> _RTC;

// _ImgAutoExp: auto exposure algorithm object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
[[gnu::section(".ram_backup.main")]]
static Img::AutoExposure _ImgAutoExp;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely
[[gnu::section(".fram_info.main")]]
static MSP::State _State;

struct _SDTask {
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._SDTask")]]
    static inline uint8_t Stack[256];
};

struct _ImgTask {
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._ImgTask")]]
    static inline uint8_t Stack[128];
};

class _SD {
public:
    static void EnableAsync() {
        Wait();
        if (_Enabled) return; // Short-circuit
        _Enabled = true;
        
        // If the SD state is valid, and this is a warm start (therefore we've already
        // verified the SD card ID), then enable the SD card asynchronously.
        if (_State.sd.valid && !Startup::ColdStart()) {
            _Scheduler::Start<_SDTask>([] { _RCA = _SDCard::Enable(); });
            return;
        }
        
        // Otherwise, enable the SD card synchronously because we need the card id / card data
        SD::CardId cardId;
        SD::CardData cardData;
        _RCA = _SDCard::Enable(&cardId, &cardData);
        
        // If the SD state is valid and the SD card id matches, just init the ring buffers
        if (_State.sd.valid && !memcmp(&_State.sd.cardId, &cardId, sizeof(cardId))) {
            _ImgRingBufInit();
        
        // Otherwise, either the SD state isn't valid, or the existing SD card id doesn't
        // match the current card id. Either way, we need to reset the SD state.
        } else {
            _ResetState(cardId, cardData);
        }
    }
    
    static void DisableAsync() {
        Wait();
        if (!_Enabled) return; // Short-circuit
        _Enabled = false;
        
        _Scheduler::Start<_SDTask>([] { _SDCard::Disable(); });
    }
    
    static void Wait() {
        _Scheduler::Wait<_SDTask>();
    }
    
    static void WriteImage(uint8_t srcBlock, uint16_t dstIdx) {
        _SDCard::WriteImage(_RCA, srcBlock, dstIdx);
    }
    
private:
    static inline bool _Enabled = false;
    static inline uint16_t _RCA = 0;
    
    // _ResetState(): resets the _State.sd struct
    static void _ResetState(const SD::CardId& cardId, const SD::CardData& cardData) {
        FRAMWriteEn writeEn; // Enable FRAM writing
        
        // Mark the _State as invalid in case we lose power in the middle of modifying it
        _State.sd.valid = false;
        
        // Set .cardId
        {
            _State.sd.cardId = cardId;
        }
        
        // Set .imgCap
        {
            // ImgBlockLen: the length of an image in SD blocks
            constexpr uint32_t ImgBlockLen = Img::PaddedLen / SD::BlockLen;
            // cardBlockCap: the capacity of the SD card in SD blocks (1 block == 512 bytes)
            const uint32_t cardBlockCap = ((uint32_t)GetBits<69,48>(cardData)+1) * (uint32_t)1024;
            // cardImgCap: the capacity of the SD card in number of images
            const uint32_t cardImgCap = cardBlockCap / ImgBlockLen;
            
            _State.sd.imgCap = cardImgCap;
        }
        
        // Set .imgRingBufs
        {
            _State.sd.imgRingBufs[0] = {};
            _State.sd.imgRingBufs[1] = {};
        }
        
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
};

class _Img {
public:
    static void EnableAsync() {
        Wait();
        if (_Enabled) return; // Short-circuit
        _Enabled = true;
        
        _Scheduler::Start<_ImgTask>([] {
            // Initialize image sensor
            _ImgSensor::Enable();
            // Set the initial exposure _before_ we enable streaming, so that the very first frame
            // has the correct exposure, so we don't have to skip any frames on the first capture.
            _ImgSensor::SetCoarseIntTime(_ImgAutoExp.integrationTime());
            // Enable image streaming
            _ImgSensor::SetStreamEnabled(true);
        });
    }
    
    static void DisableAsync() {
        Wait();
        if (!_Enabled) return; // Short-circuit
        _Enabled = false;
        
        _Scheduler::Start<_ImgTask>([] { _ImgSensor::Disable(); });
    }
    
    static void Wait() {
        _Scheduler::Wait<_ImgTask>();
    }
    
private:
    static inline bool _Enabled = false;
};

// MARK: - Motion

static volatile bool _Motion = false;
static volatile bool _Busy = false;

static void _SDImgRingBufIncrement() {
    using namespace MSP;
    FRAMWriteEn writeEn; // Enable FRAM writing
    ImgRingBuf ringBufCopy = _State.sd.imgRingBufs[0];
    
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

static void _ImgCapture() {
    const auto& ringBuf = _State.sd.imgRingBufs[0].buf;
    
    // Asynchronously turn on the image sensor
    _Img::EnableAsync();
    
    // Init SD card
    // This should come after we kick off Img initialization, because sometimes (after a cold start)
    // _SD::EnableAsync needs to synchronously wait for the SD card (to verify the SD card id, and
    // get its capacity if we haven't seen the SD card before). So while that's happening, we want
    // the image sensor to be initializing in parallel.
    _SD::EnableAsync();
    
    // Wait until the image sensor is ready
    _Img::Wait();
    
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
            .imageWidth     = Img::PixelWidth,
            .imageHeight    = Img::PixelHeight,
            .coarseIntTime  = 0,
            .analogGain     = 0,
            .id             = 0,
            .timeStart      = 0,
            .timeDelta      = 0,
        };
        
        header.coarseIntTime = _ImgAutoExp.integrationTime();
        header.id = ringBuf.idEnd;
        
        const MSP::Time t = _RTC.time();
        header.timeStart = t.start;
        header.timeDelta = t.delta;
        
        // Capture an image to RAM
        const _ICE::ImgCaptureStatusResp resp = _ICE::ImgCapture(header, expBlock, skipCount);
        const uint8_t expScore = _ImgAutoExp.update(resp.highlightCount(), resp.shadowCount());
        if (!bestExpScore || (expScore > bestExpScore)) {
            bestExpBlock = expBlock;
            bestExpScore = expScore;
        }
        
        // We're done if we don't have any exposure changes
        if (!_ImgAutoExp.changed()) break;
        
        // Update the exposure
        _ImgSensor::SetCoarseIntTime(_ImgAutoExp.integrationTime());
    }
    
    // Wait until the SD card is ready
    _SD::Wait();
    
    // Write the best-exposed image to the SD card
    _SD::WriteImage(bestExpBlock, ringBuf.widx);
    
    // Update _State.img
    _SDImgRingBufIncrement();
}

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    _RTC.isr();
}

[[gnu::interrupt(PORT2_VECTOR)]]
static void _ISR_Port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV__P2IFG5)) {
    case P2IV__P2IFG5:
        _Motion = true;
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

// MARK: - ICE40

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    // Init SPI peripheral
    static bool spiInit = false;
    if (!spiInit) {
        spiInit = true;
        _SPI::Init();
    }
    
    // iceInit: Stored in BAKMEM (RAM that's retained in LPM3.5) so that
    // it's maintained during sleep, but reset upon a cold start.
    [[gnu::section(".ram_backup.main")]]
    static bool iceInit = false;
    
    // Init ICE comms
    if (!iceInit) {
        iceInit = true;
        // Reset ICE comms (by asserting SPI CLK for some length of time)
        _SPI::ICEReset();
        // Init ICE comms
        _ICE::Init();
    }
    
//    // Init ICE40 if we haven't done so yet
//    static bool iceInit = false;
//    if (!iceInit) {
//        // Init SPI/ICE40
//        if (Startup::ColdStart()) {
//            constexpr bool iceReset = true; // Cold start -> reset ICE40 SPI state machine
//            _SPI::Init(iceReset);
//            _ICE::Init(); // Cold start -> init ICE40 to verify that comms are working
//        
//        } else {
//            constexpr bool iceReset = false; // Warm start -> no need to reset ICE40 SPI state machine
//            _SPI::Init(iceReset);
//        }
//    }
    
    _SPI::WriteRead(msg, resp);
}

// MARK: - Power

static void _SDSetPowerEnabled(bool en) {
    _Pin::VDD_SD_EN::Write(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _Scheduler::SleepMs<2>();
}

static void _ImgSetPowerEnabled(bool en) {
    if (en) {
        _Pin::VDD_2V8_IMG_EN::Write(1);
        _Scheduler::SleepUs<100>(); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        _Pin::VDD_1V9_IMG_EN::Write(1);
        
        #warning measure actual delay that we need for the rails to rise
    
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        _Pin::VDD_1V9_IMG_EN::Write(0);
        _Pin::VDD_2V8_IMG_EN::Write(0);
        
        #warning measure actual delay that we need for the rails to fall
    }
}

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
    
    #warning can we just inspect the state of the tasks to determine what kind of sleep to enter?
    
    // If we're currently handling motion (_Busy), enter LPM1 sleep because a task is just delaying itself.
    // If we're not handling motion (!_Busy), enter the deep LPM3.5 sleep, where RAM content is lost.
//    const uint16_t LPMBits = (_Busy ? LPM1_bits : LPM3_bits);
    const uint16_t LPMBits = LPM1_bits;
    
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

// MARK: - Tasks

//static void debugSignal() {
//    _Pin::DEBUG_OUT::Init();
//    for (int i=0; i<10; i++) {
//        _Pin::DEBUG_OUT::Write(0);
//        for (volatile int i=0; i<10000; i++);
//        _Pin::DEBUG_OUT::Write(1);
//        for (volatile int i=0; i<10000; i++);
//    }
//}

struct _BusyTimeoutTask {
    static void Run() {
        // Stay on for 1 second waiting for motion
        _Scheduler::SleepMs<1000>();
        
        // Asynchronously turn off the image sensor / SD card
        _Img::DisableAsync();
        _SD::DisableAsync();
        
        // Wait until the image sensor / SD card are off
        _Img::Wait();
        _SD::Wait();
        
        // Update our state
        _Busy = false;
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._BusyTimeoutTask")]]
    static inline uint8_t Stack[128];
};

struct _MotionTask {
    static void Run() {
        for (;;) {
            // Wait for motion
            _Scheduler::Wait([&] { return _Motion; });
            _Motion = false;
            _Busy = true;
            
            // Stop the timeout task while we capture a new image
            _Scheduler::Stop<_BusyTimeoutTask>();
            
            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
            
            // Capture an image
            _ImgCapture();
            
            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
            
            // Restart the timeout task, so that we turn off automatically if
            // we're idle for a bit
            _Scheduler::Start<_BusyTimeoutTask>(_BusyTimeoutTask::Run);
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._MotionTask")]]
    static inline uint8_t Stack[256];
};

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

static void _AbortRecord(const MSP::Time& time, uint16_t domain, uint16_t line) {
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    auto& abort = _State.abort;
    if (abort.eventsCount >= std::size(abort.events)) return;
    
    abort.events[abort.eventsCount] = MSP::AbortEvent{
        .time = time,
        .domain = domain,
        .line = line,
    };
    
    abort.eventsCount++;
}

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line) {
    const MSP::Time time = _RTC.time();
    // Record the abort
    _AbortRecord(time, domain, line);
    // Trigger a BOR
    PMMCTL0 = PMMPW | PMMSWBOR;
    
//    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
//    PMMCTL0_L |= PMMSWBOR_1_L;
    
    for (;;);
    
//    _Pin::DEBUG_OUT::Init();
//    
//    for (;;) {
//        for (uint16_t i=0; i<(uint16_t)domain; i++) {
//            _Pin::DEBUG_OUT::Write(1);
//            _Pin::DEBUG_OUT::Write(0);
//        }
//        
//        for (volatile int i=0; i<100; i++) {}
//        
//        for (uint16_t i=0; i<(uint16_t)line; i++) {
//            _Pin::DEBUG_OUT::Write(1);
//            _Pin::DEBUG_OUT::Write(0);
//        }
//        
//        for (volatile int i=0; i<1000; i++) {}
//    }
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

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
//    volatile bool a = false;
//    while (!a);
    
    // Init GPIOs
    GPIO::Init<
        // Power control
        _Pin::VDD_1V9_IMG_EN,
        _Pin::VDD_2V8_IMG_EN,
        _Pin::VDD_SD_EN,
        _Pin::VDD_B_EN_,
        
        // SPI peripheral determines initial state of SPI GPIOs
        _SPI::Pin::Clk,
        _SPI::Pin::DataOut,
        _SPI::Pin::DataIn,
        _SPI::Pin::DataDir,
        
        // Clock peripheral determines initial state of clock GPIOs
        _Clock::Pin::XOUT,
        _Clock::Pin::XIN,
        
        // Motion
        _Pin::MOTION_SIGNAL,
        
        // Other
        _Pin::ICE_MSP_SPI_AUX,
        _Pin::ICE_MSP_SPI_AUX_DIR
    >();
    
    // Init clock
    _Clock::Init();
    
//    _Pin::DEBUG_OUT::Init();
//    for (uint32_t i=0; i<1000000; i++) {
//        _Pin::DEBUG_OUT::Write(1);
//        _Pin::DEBUG_OUT::Write(0);
//    }
    
    #warning if this is a cold start:
    #warning   wait a few milliseconds to allow our outputs to settle so that our peripherals
    #warning   (SD card, image sensor) fully turn off, because we may have restarted because
    #warning   of an error
    
    #warning we're currently sleeping before we abort -- move that sleep here instead.
    
    #warning how do we handle turning off SD clock after an error occurs?
    #warning   ? dont worry about that because in the final design,
    #warning   well be powering off ICE40 anyway?
    
    // Start RTC if it's not currently enabled.
    // We need RTC to be unconditionally enabled for 2 reasons:
    //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
    //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
    //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
    if (_State.startTime.valid) {
        // If _StartTime is valid, consume it and hand it off to _RTC.
        FRAMWriteEn writeEn; // Enable FRAM writing
        // Mark the time as invalid before consuming it, so that if we lose power,
        // the time won't be reused again
        _State.startTime.valid = false;
        // Init real-time clock
        _RTC.init(_State.startTime.time);
    
    // Otherwise, we don't have a valid _State.startTime, so if _RTC isn't currently
    // enabled, init _RTC with 0.
    } else if (!_RTC.enabled()) {
        _RTC.init(0);
    }
    
    // Init SysTick
    _SysTick::Init();
    
    if (Startup::ColdStart()) {
        _Scheduler::DelayMs<3000>();
    }
    
    // Rate-limit aborting by simply sleeping for 3s
    #warning TODO: move this delay to main() so that this delay not only rate-limits, but gives the outputs a chance to settle in the off position.
    #warning TODO: wrap the delay with _Busy=true so we don't enter LPM3.5
    _Scheduler::DelayMs<3000>();
    
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
//const _DebugStack& _Debug_MotionTaskStack         = *(_DebugStack*)_MotionTask::Stack;
//const _DebugStack& _Debug_SDTaskStack             = *(_DebugStack*)_SDTask::Stack;
//const _DebugStack& _Debug_ImgTaskStack            = *(_DebugStack*)_ImgTask::Stack;
//const _DebugStack& _Debug_BusyTimeoutTaskStack    = *(_DebugStack*)_BusyTimeoutTask::Stack;

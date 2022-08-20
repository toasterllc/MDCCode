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
#include "BusyAssertion.h"
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
    using VDD_B_1V8_IMG_EN                  = PortA::Pin<0x0, Option::Output0>;
    using VDD_B_EN                          = PortA::Pin<0x1, Option::Output0>;
    using VDD_B_2V8_IMG_EN                  = PortA::Pin<0x2, Option::Output0>;
    using MOTION_SIGNAL                     = PortA::Pin<0x3, Option::Interrupt01, Option::Resistor0>; // Motion sensor can only pull up, so it requires a pulldown resistor
    using ICE_MSP_SPI_DATA_OUT              = PortA::Pin<0x4>;
    using ICE_MSP_SPI_DATA_IN               = PortA::Pin<0x5>;
    using ICE_MSP_SPI_CLK                   = PortA::Pin<0x6>;
    using XOUT                              = PortA::Pin<0x8>;
    using XIN                               = PortA::Pin<0x9>;
    using VDD_B_SD_EN                       = PortA::Pin<0xB, Option::Output0>;
    using DEBUG_OUT                         = PortA::Pin<0xD, Option::Output0>;
    using MSP_RUN                           = PortA::Pin<0xE, Option::Input, Option::Resistor1>;
};

// _MotionSignalIV: motion interrupt vector; keep in sync with the pin chosen for MOTION_SIGNAL
constexpr uint16_t _MotionSignalIV = P1IV__P1IFG3;

using _Clock = ClockType<_MCLKFreqHz>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;

class _MotionTask;
class _SDTask;
class _ImgTask;

static void _Sleep();

static void _SchedulerError(uint16_t line);
static void _ICEError(uint16_t line);
static void _SDError(uint16_t line);
static void _ImgError(uint16_t line);

static bool _SDSetPowerEnabled(bool en);
static bool _ImgSetPowerEnabled(bool en);

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
    _ImgTask
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

// _ImgAutoExp: auto exposure algorithm object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
[[gnu::section(".ram_backup.main")]]
static Img::AutoExposure _ImgAutoExp;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely
[[gnu::section(".fram_info.main")]]
static MSP::State _State;

// _Motion: announces that motion occurred
// atomic because _Motion is modified from the interrupt context
static std::atomic<bool> _Motion = false;

// _BusyCount: counts the number of entities preventing LPM3.5 sleep
static uint8_t _BusyCount = 0;
using _BusyAssertion = BusyAssertionType<_BusyCount>;

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
    
    static void DisableAsync(bool force=false) {
        Wait();
        if (!_Enabled && !force) return; // Short-circuit
        _Enabled = false;
        
        _Scheduler::Start<_SDTask>([] { _SDCard::Disable(); });
    }
    
    static void Wait() {
        _Scheduler::Wait<_SDTask>();
    }
    
    static void WriteImage(uint8_t srcBlock, uint32_t dstBlockIdx) {
        _SDCard::WriteImage(_RCA, srcBlock, dstBlockIdx);
    }
    
private:
    static inline bool _Enabled = false;
    static inline uint16_t _RCA = 0;
    
    // _ResetState(): resets the _State.sd struct
    static void _ResetState(const SD::CardId& cardId, const SD::CardData& cardData) {
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
            // cardBlockCap: the capacity of the SD card in SD blocks (1 block == 512 bytes)
            const uint32_t cardBlockCap = ((uint32_t)GetBits<69,48>(cardData)+1) * (uint32_t)1024;
            // cardImgCap: the capacity of the SD card in number of images
            const uint32_t cardImgCap = cardBlockCap / ImgSD::ImgBlockCount;
            
            _State.sd.imgCap = cardImgCap;
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
    
    static void DisableAsync(bool force=false) {
        Wait();
        if (!_Enabled && !force) return; // Short-circuit
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
    
//    #warning TODO: remove this cold-start disabling once MSP controls ICE40, since ICE40 will be in a known state when MSP applies power
//    // If this is a cold start, ensure SD/Img are disabled
//    // This is necessary because ICE40 can be in an unknown state when MSP
//    // restarts, because MSP may have aborted, or restarted due to STM
//    // Spy-Bi-Wire debug access
//    if (Startup::ColdStart()) {
//        static bool disabled = false;
//        if (!disabled) {
//            _Img::DisableAsync(true);
//            _SD::DisableAsync(true);
//            _Scheduler::Wait<_ImgTask, _SDTask>();
//            disabled = true;
//        }
//    }
    
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
            .timestamp      = 0,
        };
        
        header.coarseIntTime = _ImgAutoExp.integrationTime();
        header.id = ringBuf.idEnd;
        header.timestamp = _RTC.time();
        
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
    const uint32_t dstBlockIdx = ringBuf.widx * ImgSD::ImgBlockCount;
    _SD::WriteImage(bestExpBlock, dstBlockIdx);
    
    // Update _State.img
    _SDImgRingBufIncrement();
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

static bool _SDSetPowerEnabled(bool en) {
    #warning TODO: short-circuit if the pin state isn't changing, to save time
    
    _Pin::VDD_B_SD_EN::Write(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _Scheduler::Sleep(_Scheduler::Ms(2));
    return true;
}

static bool _ImgSetPowerEnabled(bool en) {
    #warning TODO: short-circuit if the pin state isn't changing, to save time
    
    if (en) {
        _Pin::VDD_B_2V8_IMG_EN::Write(1);
        _Scheduler::Sleep(_Scheduler::Us(100)); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V8)
        _Pin::VDD_B_1V8_IMG_EN::Write(1);
        
        #warning measure actual delay that we need for the rails to rise
    
    } else {
        // No delay between 2V8/1V8 needed for power down (per AR0330CS datasheet)
        _Pin::VDD_B_1V8_IMG_EN::Write(0);
        _Pin::VDD_B_2V8_IMG_EN::Write(0);
        
        #warning measure actual delay that we need for the rails to fall
    }
    return true;
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
    
    #warning TODO: re-enable LPM3.5 sleep below
    // If we're currently busy (_BusyCount > 0), enter LPM1 sleep because some tasks are running.
    // If we're not busy (!_BusyCount), enter the deep LPM3.5 sleep, where RAM content is lost.
//    const uint16_t LPMBits = (_BusyCount ? LPM1_bits : LPM3_bits);
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

//class _BusyTimeoutTask {
//public:
//    static void Run() {
//        for (;;) {
////            _Scheduler::Wait<_BusyTimeoutTask>([] { return _Busy.has_value(); });
//            
//            while (_Scheduler::Wait<_BusyTimeoutTask,1000>([] { return (bool)_Busy; })) {
//                _Busy = std::nullopt;
//            }
//            
//            // Asynchronously turn off the image sensor / SD card
//            _Img::DisableAsync();
//            _SD::DisableAsync();
//            
//            // Wait until the image sensor / SD card are off
//            _Img::Wait();
//            _SD::Wait();
//            
////            // Wait to be tickled
////            _Scheduler::Wait<_BusyTimeoutTask>([] { return _Tickled; });
////
////            // Assert that we're busy until we stop getting tickled + 1s
////            _BusyAssertion busy;
////            do {
////                _Tickled = false;
////            } while ();
////
////            // Asynchronously turn off the image sensor / SD card
////            _Img::DisableAsync();
////            _SD::DisableAsync();
////
////            // Wait until the image sensor / SD card are off
////            _Img::Wait();
////            _SD::Wait();
//        }
//        
//        _Scheduler::Yield();
//    }
//    
//    
////    static void Run() {
////        for (;;) {
////            _BusyAssertion busy;
////            while (_Scheduler::Wait<_BusyTimeoutTask,1000>([] { return _Tickled; })) {
////                _Tickled = false;
////            }
////            
////            // Asynchronously turn off the image sensor / SD card
////            _Img::DisableAsync();
////            _SD::DisableAsync();
////            
////            // Wait until the image sensor / SD card are off
////            _Img::Wait();
////            _SD::Wait();
////            
//////            // Wait to be tickled
//////            _Scheduler::Wait<_BusyTimeoutTask>([] { return _Tickled; });
//////
//////            // Assert that we're busy until we stop getting tickled + 1s
//////            _BusyAssertion busy;
//////            do {
//////                _Tickled = false;
//////            } while ();
//////
//////            // Asynchronously turn off the image sensor / SD card
//////            _Img::DisableAsync();
//////            _SD::DisableAsync();
//////
//////            // Wait until the image sensor / SD card are off
//////            _Img::Wait();
//////            _SD::Wait();
////        }
////        
////        _Scheduler::Yield();
////    }
//    
////    static void Stop() {
////        _Scheduler::Stop<_BusyTimeoutTask>();
////    }
//    
//    static void Tickle() {
//        _Busy.emplace();
//    }
//    
//    // Task options
//    static constexpr Toastbox::TaskOptions Options{};
//    
//    // Task stack
//    [[gnu::section(".stack._BusyTimeoutTask")]]
//    static inline uint8_t Stack[128];
//    
//private:
//    static inline std::optional<_BusyAssertion> _Busy;
//};

struct _MotionTask {
    static void Run() {
//        for (;;) {
//            _Pin::VDD_B_EN::Write(1);
//            _Scheduler::Sleep(_Scheduler::Ms(500));
//            
//            _Pin::VDD_B_EN::Write(0);
//            _Scheduler::Sleep(_Scheduler::Ms(500));
//        }
//        
//        _Pin::VDD_B_EN::Write(1);
//        _Scheduler::Sleep(_Scheduler::Ms(500));
//        
//        for (;;) {
//            _Pin::DEBUG_OUT::Write(1);
//            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//            _Scheduler::Sleep(_Scheduler::Ms(500));
//            
//            _Pin::DEBUG_OUT::Write(0);
//            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            _Scheduler::Sleep(_Scheduler::Ms(500));
//        }
        
        for (;;) {
//            _Scheduler::Sleep(_Scheduler::Ms(2000));
            
            _Scheduler::Wait([&] { return (bool)_Motion; });
            _Motion = false;
            
            _Pin::VDD_B_EN::Write(1);
            _Scheduler::Sleep(_Scheduler::Ms(250));
            
            for (;;) {
                _BusyAssertion busy;
                
                // Capture an image
                _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
                _ImgCapture();
                _ICE::Transfer(_ICE::LEDSetMsg(0x00));
                
                // Wait up to 1s for further motion
                const auto motion = _Scheduler::Wait(_Scheduler::Ms(1000), [] { return (bool)_Motion; });
                if (!motion) {
                    // We timed-out
                    // Asynchronously disable Img / SD
                    _Img::DisableAsync();
                    _SD::DisableAsync();
                    
                    // Wait until both Img and SD are disabled
                    _Scheduler::Wait<_ImgTask, _SDTask>();
                    // Relinquish our busy assertion by breaking out of scope,
                    // allowing us to enter LPM3.5 sleep
                    break;
                }
                
                // Only reset _Motion if we've observed motion; otherwise, if we always reset
                // _Motion, there'd be a race window where we could first observe
                // _Motion==false, but then the ISR sets _Motion=true, but then we clobber
                // the true value by resetting it to false.
                _Motion = false;
            }
            
            _Pin::VDD_B_EN::Write(0);
            
//            // Asynchronously turn off the image sensor / SD card
//            _Img::DisableAsync();
//            _SD::DisableAsync();
//            
//            _Scheduler::Wait([&] { return (_Img && _SD) || _Motion; });
//            
//            // Wait until the image sensor / SD card are off
//            _Img::Wait();
//            _SD::Wait();
//            
//            // Wait for motion
//            const bool motion = _Scheduler::WaitTimeout<1000>([&] { return _Motion; });
//            
//            if (motion) {
//                _Motion = false;
//                
//                // Capture an image
//                _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//                _ImgCapture();
//                _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            
//            } else {
//                // Asynchronously turn off the image sensor / SD card
//                _Img::DisableAsync();
//                _SD::DisableAsync();
//                
//                // Wait until the image sensor / SD card are off
//                _Img::Wait();
//                _SD::Wait();
//                
//                break;
//            }
//            
//            
//            
////            // Stop the timeout task while we capture a new image
////            _Scheduler::Stop<_BusyTimeoutTask>();
//            
//            
//            // Wait for motion
//            _Scheduler::Wait([&] { return _Motion; });
//            _Motion = false;
//            
//            _BusyAssertion busy;
//            
////            // Stop the timeout task while we capture a new image
////            _Scheduler::Stop<_BusyTimeoutTask>();
//            
//            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//            
//            // Capture an image
//            _ImgCapture();
//            
//            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            
//            // wait for motion or 1s to elapse
//            // if motion:
//            //   capture another image
//            // if 1s elapses:
//            //   disable SD/Img
//            //   wait for: [1] _Motion or [2] (SD && Img)
//            //   if [1]: capture another image
//            //   if [2]: drop busy assertion and yield
//            
//            
//            // Tickle the busy task
//            _BusyTimeoutTask::Tickle();
//            
////            // Restart the timeout task, so that we turn off automatically if
////            // we're idle for a bit
////            _Scheduler::Start<_BusyTimeoutTask>(_BusyTimeoutTask::Run);
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
static void _Abort(uint16_t domain, uint16_t line) {
    const MSP::Time timestamp = _RTC.time();
    // Record the abort
    _AbortRecord(timestamp, domain, line);
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
        // Main Pins
        _Pin::VDD_B_1V8_IMG_EN,
        _Pin::VDD_B_2V8_IMG_EN,
        _Pin::VDD_B_SD_EN,
        _Pin::VDD_B_EN,
        _Pin::MSP_RUN,
        _Pin::MOTION_SIGNAL,
        
        // SPI peripheral determines initial state of SPI GPIOs
        _SPI::Pin::Clk,
        _SPI::Pin::DataOut,
        _SPI::Pin::DataIn,
        
        // Clock peripheral determines initial state of clock GPIOs
        _RTCType::Pin::XOUT,
        _RTCType::Pin::XIN
    >();
    
//    debugSignal();
    
    // Init clock
    _Pin::DEBUG_OUT::Init();
    _Pin::DEBUG_OUT::Write(1);
    _Clock::Init();
    _Pin::DEBUG_OUT::Write(0);
    
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
//    const MSP::Time time = _State.time;
//    if (time) {
//        {
//            // If `time` is valid, consume it and hand it off to _RTC.
//            FRAMWriteEn writeEn; // Enable FRAM writing
//            
//            // Reset `_State.time` before consuming it, so that if we lose power,
//            // the time won't be reused again
//            _State.time = 0;
//            std::atomic_signal_fence(std::memory_order_seq_cst);
//        }
//        
//        // Init real-time clock
//        _RTC.init(time);
//    
//    // Otherwise, we don't have a valid time, so if _RTC isn't currently
//    // enabled, init _RTC with 0.
//    } else if (!_RTC.enabled()) {
//        _RTC.init(0);
//    }
    
    // Init RTC
    // We need RTC to be unconditionally enabled for 2 reasons:
    //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
    //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
    //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
    const MSP::Time time = _State.time;
    if (time) {
        // If `time` is valid, consume it before handing it off to _RTC.
        FRAMWriteEn writeEn; // Enable FRAM writing
        // Reset `_State.time` before consuming it, so that if we lose power,
        // the time won't be reused again
        _State.time = 0;
        std::atomic_signal_fence(std::memory_order_seq_cst);
    }
    _RTC.init(time);
    
    // Init SysTick
    _SysTick::Init();
    
    // If this is a cold start, delay 3s before beginning.
    // This delay is meant for the case where we restarted due to an abort, and
    // serves 2 purposes:
    //   1. it rate-limits aborts, in case there's a persistent issue
    //   2. it allows GPIO outputs to settle, so that peripherals fully turn off
    if (Startup::ColdStart()) {
//        #warning TODO: VDD_B_EN needs to be controlled elsewhere when we implement proper power rail control
//        // Turn on VDD_B
//        _Pin::VDD_B_EN::Write(1);
        
        _BusyAssertion busy; // Prevent LPM3.5 sleep during the delay
        _Scheduler::Delay(_Scheduler::Ms(3000));
    }
    
    // If this is a cold start, wait until MSP_RUN is high.
    // STM32 controls MSP_RUN to control when we start executing, in order to implement mutual
    // exclusion on controlling the power rails and talking to ICE40.
    if (Startup::ColdStart()) {
        _BusyAssertion busy; // Prevent LPM3.5 sleep during the delay
        while (!_Pin::MSP_RUN::Read()) _Scheduler::Delay(_Scheduler::Ms(100));
        
//        _Pin::DEBUG_OUT::Init();
//        while (!_Pin::MSP_RUN::Read()) {
//            _Pin::DEBUG_OUT::Write(1);
//            _Scheduler::Delay(_Scheduler::Ms(50));
//            _Pin::DEBUG_OUT::Write(0);
//            _Scheduler::Delay(_Scheduler::Ms(50));
//        }
        
        // Once we're allowed to run, disable the pullup on MSP_RUN to prevent the leakage current (~80nA)
        // through STM32's GPIO that controls MSP_RUN.
        using MSP_RUN_PULLDOWN = _Pin::MSP_RUN::Opts<Option::Input, Option::Resistor0>;
        MSP_RUN_PULLDOWN::Init();
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
//const _DebugStack& _Debug_MotionTaskStack         = *(_DebugStack*)_MotionTask::Stack;
//const _DebugStack& _Debug_SDTaskStack             = *(_DebugStack*)_SDTask::Stack;
//const _DebugStack& _Debug_ImgTaskStack            = *(_DebugStack*)_ImgTask::Stack;

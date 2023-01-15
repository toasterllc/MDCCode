#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include <atomic>
#define TaskMSP430
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
#include "Util.h"
#include "MSP.h"
#include "GetBits.h"
#include "ImgSD.h"
#include "I2C.h"
#include "OutputPriority.h"
#include "BatterySampler.h"
#include "Button.h"
using namespace GPIO;

#define Assert(x) if (!(x)) _MainError(__LINE__)
#define AssertArg(x) if (!(x)) _MainError(__LINE__)

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line);

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
    using MOTION_SIGNAL             = PortA::Pin<0xC, Option::Input, Option::Interrupt01, Option::Resistor0>; // Motion sensor can only drive 1, so we have a pulldown
    using BUTTON_SIGNAL_            = PortA::Pin<0xD>;
    using BAT_CHRG_LVL_EN_          = PortA::Pin<0xE, Option::Output1>;
    using VDD_B_3V3_STM             = PortA::Pin<0xF, Option::Input, Option::Resistor0>;
    // Port B
    using MOTION_EN_                = PortB::Pin<0x0, Option::Output1>;
    using VDD_B_EN                  = PortB::Pin<0x1, Option::Output0>;
    using _UNUSED0                  = PortB::Pin<0x2>;
};

class _MainTask;
class _SDTask;
class _ImgTask;
class _I2CTask;
class _ButtonTask;

static void _Sleep();

static void _MainError(uint16_t line);
static void _SchedulerError(uint16_t line);
static void _ICEError(uint16_t line);
static void _SDError(uint16_t line);
static void _ImgError(uint16_t line);
static void _I2CError(uint16_t line);
static void _BatterySamplerError(uint16_t line);

extern uint8_t _StackMain[];

#warning disable stack guard for production
static constexpr size_t _StackGuardCount = 16;
using _Scheduler = Toastbox::Scheduler<
    _SysTickPeriodUs,                           // T_UsPerTick: microseconds per tick
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    _SchedulerError,                            // T_Error: function to handle unrecoverable error
    _StackMain,                                 // T_MainStack: main stack pointer (only used to monitor
                                                //              main stack for overflow; unused if T_StackGuardCount==0)
    _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
    _MainTask,                                  // T_Tasks: list of tasks
    _SDTask,
    _ImgTask,
    _I2CTask,
    _ButtonTask
>;

using _Clock = ClockType<_MCLKFreqHz>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;
using _ICE = ICE<_Scheduler, _ICEError>;

using _I2C = I2CType<_Scheduler, _Pin::MSP_STM_I2C_SCL, _Pin::MSP_STM_I2C_SDA, _Pin::VDD_B_3V3_STM, MSP::I2CAddr, _I2CError>;

using _BatterySampler = BatterySamplerType<_Scheduler, _Pin::BAT_CHRG_LVL, _Pin::BAT_CHRG_LVL_EN_, _BatterySamplerError>;

constexpr uint16_t _ButtonHoldDurationMs = 1500;
using _Button = ButtonType<_Scheduler, _Pin::BUTTON_SIGNAL_, _ButtonHoldDurationMs>;

using _LEDGreen_ = OutputPriority<_Pin::LED_GREEN_>;
using _LEDRed_ = OutputPriority<_Pin::LED_RED_>;

// _ImgSensor: image sensor object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
using _ImgSensor = Img::Sensor<
    _Scheduler,             // T_Scheduler
    _ICE,                   // T_ICE
    _ImgError               // T_Error
>;

// _SDCard: SD card object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    _SDError,           // T_Error
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    6                   // T_ClkDelayFast (odd values invert the clock)
>;

// _RTC: real time clock
using _RTC = RTCType<_XT1FreqHz, _Pin::MSP_XOUT, _Pin::MSP_XIN>;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely
[[gnu::section(".fram_info.main")]]
static MSP::State _State = {
    .header = MSP::StateHeader,
};

// MARK: - Power

static void _VDDBSet(bool en) {
    _Pin::VDD_B_EN::Write(en);
    // Rails take ~1.5ms to turn on/off, so wait 2ms to be sure
    _Scheduler::Sleep(_Scheduler::Ms(2));
}

static void _VDDIMGSDSet(bool en) {
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

// MARK: - Tasks

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
        using namespace MSP;
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
            ImgRingBuf::Set(_State.sd.imgRingBufs[0], {});
            ImgRingBuf::Set(_State.sd.imgRingBufs[1], {});
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
        
        ImgRingBuf& a = _State.sd.imgRingBufs[0];
        ImgRingBuf& b = _State.sd.imgRingBufs[1];
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
        
        ImgRingBuf::Set(_State.sd.imgRingBufs[0], ringBufCopy);
        ImgRingBuf::Set(_State.sd.imgRingBufs[1], ringBufCopy);
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
    alignas(sizeof(void*))
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
            header.timestamp = _RTC::TimeRead();
            
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
    alignas(sizeof(void*))
    static inline uint8_t Stack[256];
};

struct _MainTask {
    static void Run() {
        
//        for (bool x=false;; x=!x) {
//            _Pin::LED_RED_::Write(x);
//            _BatterySampler::Sample();
//            _Scheduler::Sleep(_Scheduler::Ms(1000));
//        }
        
        // Handle cold starts
        if (!_Init) {
            _Init = true;
            // Since this is a cold start, delay 3s before beginning.
            // This delay is meant for the case where we restarted due to an abort, and
            // serves 2 purposes:
            //   1. it rate-limits aborts, in case there's a persistent issue
            //   2. it allows GPIO outputs to settle, so that peripherals fully turn off
            _LEDRed_::Set(_LEDRed_::Priority::Low, 0);
            _Scheduler::Sleep(_Scheduler::Ms(3000));
            _LEDRed_::Set(_LEDRed_::Priority::Low, 1);
        }
        
//        _Scheduler::Sleep(_Scheduler::Ms(10000));
//        for (;;) {
//            _Pin::LED_GREEN_::Write(0);
//            for (volatile uint16_t i=0; i<50000; i++);
//            _Pin::LED_GREEN_::Write(1);
//            for (volatile uint16_t i=0; i<50000; i++);
//        }
        
//        _Pin::VDD_B_EN::Write(1);
//        _Scheduler::Sleep(_Scheduler::Ms(250));
//        
//        for (;;) {
//            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//            _Scheduler::Sleep(_Scheduler::Ms(250));
//            
//            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            _Scheduler::Sleep(_Scheduler::Ms(250));
//        }
        
//        for (;;) {
//            _Scheduler::Sleep(_Scheduler::Ms(1000));
//        }
        
        const MSP::ImgRingBuf& imgRingBuf = _State.sd.imgRingBufs[0];
        
        // Init SPI peripheral
        _SPI::Init();
        
        for (;;) {
//            // Wait for motion. During this block we allow LPM3.5 sleep, as long as our other tasks are idle.
//            {
//                _WaitingForMotion = true;
//                _Scheduler::Wait([&] { return (bool)_Motion; });
//                _Motion = false;
//                _WaitingForMotion = false;
//            }
            
//            // Turn on VDD_B power (turns on ICE40)
//            _VDDBSet(true);
//            
//            // Wait for ICE40 to start
//            // We specify (within the bitstream itself, via icepack) that ICE40 should load
//            // the bitstream at high-frequency (40 MHz).
//            // According to the datasheet, this takes 70ms.
//            _Scheduler::Sleep(_Scheduler::Ms(30));
//            _ICEInit();
//            
//            // Reset SD nets before we turn on SD power
//            _SDTask::Reset();
//            _SDTask::Wait();
//            
//            // Turn on IMG/SD power
//            _VDDIMGSDSet(true);
//            
//            // Init image sensor / SD card
//            _ImgTask::Init();
//            _SDTask::Init();
            
            for (;;) {
                // Capture an image
                {
//                    _LEDGreen_::Set(_LEDGreen_::Priority::Low, 0);
                    
                    // Pretend to capture an image
                    _Scheduler::Sleep(_Scheduler::Ms(500));
                    
//                    // Wait for _SDTask to be initialized and done with writing, which is necessary
//                    // for 2 reasons:
//                    //   1. we have to wait for _SDTask to initialize _State.sd.imgRingBufs before we
//                    //      access it,
//                    //   2. we can't initiate a new capture until writing to the SD card (from a
//                    //      previous capture) is complete (because the SDRAM is single-port, so
//                    //      we can only read or write at one time)
//                    _SDTask::WaitForInitAndWrite();
//                    
//                    // Capture image to RAM
//                    _ImgTask::Capture(imgRingBuf.buf.idEnd);
//                    const uint8_t srcRAMBlock = _ImgTask::CaptureBlock();
//                    
//                    // Copy image from RAM -> SD card
//                    _SDTask::Write(srcRAMBlock);
//                    _SDTask::Wait();
                    
//                    _LEDGreen_::Set(_LEDGreen_::Priority::Low, 1);
                }
                
                break;
                
//                // Wait up to 1s for further motion
//                const auto motion = _Scheduler::Wait(_Scheduler::Ms(1000), [] { return (bool)_Motion; });
//                if (!motion) break;
//                
//                // Only reset _Motion if we've observed motion; otherwise, if we always reset
//                // _Motion, there'd be a race window where we could first observe
//                // _Motion==false, but then the ISR sets _Motion=true, but then we clobber
//                // the true value by resetting it to false.
//                _Motion = false;
            }
            
//            _VDDIMGSDSet(false);
//            _VDDBSet(false);
            
            _Scheduler::Sleep(_Scheduler::Ms(3000));
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
    
    static void HostModeSet(bool en) {
        // Short-circuit if the state hasn't changed
        if (_HostMode == en) return;
        _HostMode = en;
        
        if (_HostMode) {
            // Reset state
            _WaitingForMotion = false;
            _LEDRed_::Set(_LEDRed_::Priority::Low, 1);
            _LEDGreen_::Set(_LEDGreen_::Priority::Low, 1);
            // Stop _MainTask
            _Scheduler::Stop<_MainTask>();
            // Turn off power
            _VDDIMGSDSet(false);
            _VDDBSet(false);
        
        } else {
            _Scheduler::Start<_MainTask>(Run);
        }
    }
    
    static void ISR_MotionSignal(uint16_t iv) {
        _Motion = true;
    }
    
    static inline bool _HostMode = false;
    
    // _Init: stores whether this is the first
    [[gnu::section(".ram_backup.main")]]
    static inline bool _Init = false;
    
    // _Motion: announces that motion occurred
    // _Motion: atomic because it's modified from the interrupt context
    static inline std::atomic<bool> _Motion = false;
    static inline bool _WaitingForMotion = false;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._MainTask")]]
    alignas(sizeof(void*))
    static inline uint8_t Stack[256];
};

struct _I2CTask {
    static void Run() {
        for (;;) {
            // Wait until the I2C lines are activated (ie VDD_B_3V3_STM becomes powered)
            _I2C::WaitUntilActive();
            
            for (;;) {
                // Wait for a command
                MSP::Cmd cmd;
                
                bool ok = _I2C::Recv(cmd);
                if (!ok) break;
                
                // Handle command
                const MSP::Resp resp = _CmdHandle(cmd);
                
                ok = _I2C::Send(resp);
                if (!ok) break;
            }
            
            // Cleanup
            
            // Relinquish LEDs
            _LEDRed_::Set(_LEDRed_::Priority::High, std::nullopt);
            _LEDGreen_::Set(_LEDGreen_::Priority::High, std::nullopt);
            
            // Exit host mode
            _MainTask::HostModeSet(false);
        }
    }
    
    static MSP::Resp _CmdHandle(const MSP::Cmd& cmd) {
        using namespace MSP;
        switch (cmd.op) {
        case Cmd::Op::StateRead: {
            const size_t off = cmd.arg.StateRead.chunk * sizeof(MSP::Resp::arg.StateRead.data);
            if (off > sizeof(_State)) return MSP::Resp{ .ok = false };
            const size_t rem = sizeof(_State)-off;
            const size_t len = std::min(rem, sizeof(MSP::Resp::arg.StateRead.data));
            MSP::Resp resp = { .ok = true };
            memcpy(resp.arg.StateRead.data, (uint8_t*)&_State+off, len);
            return resp;
        }
        
        case Cmd::Op::StateWrite: {
            const size_t off = cmd.arg.StateWrite.chunk * sizeof(MSP::Cmd::arg.StateWrite.data);
            if (off > sizeof(_State)) return MSP::Resp{ .ok = false };
            const size_t rem = sizeof(_State)-off;
            const size_t len = std::min(rem, sizeof(MSP::Cmd::arg.StateWrite.data));
            memcpy((uint8_t*)&_State+off, cmd.arg.StateWrite.data, len);
            return MSP::Resp{ .ok = true };
        }
        
        case Cmd::Op::LEDSet:
            _LEDRed_::Set(_LEDRed_::Priority::High, !cmd.arg.LEDSet.red);
            _LEDGreen_::Set(_LEDGreen_::Priority::High, !cmd.arg.LEDSet.green);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::TimeSet:
            _RTC::Init(cmd.arg.TimeSet.time);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::HostModeSet:
            _MainTask::HostModeSet(cmd.arg.HostModeSet.en);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::VDDIMGSDSet:
            _VDDIMGSDSet(cmd.arg.VDDIMGSDSet.en);
            return MSP::Resp{ .ok = true };
        
        case Cmd::Op::BatteryChargeLevelGet: {
            return MSP::Resp{
                .ok = true,
                .arg = { .BatteryChargeLevelGet = { .level = _BatterySampler::Sample() } },
            };
        }
        
        default:
            return MSP::Resp{ .ok = false };
        }
    }
    
    static inline bool _HostMode = false;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._I2CTask")]]
    alignas(sizeof(void*))
    static inline uint8_t Stack[256];
};

struct _ButtonTask {
    static void Run() {
        for (;;) {
            const _Button::Event ev = _Button::WaitForEvent();
            switch (ev) {
            case _Button::Event::Press:
                _LEDRed_::Set(_LEDRed_::Priority::Low, 0);
                _Scheduler::Sleep(_Scheduler::Ms(250));
                _LEDRed_::Set(_LEDRed_::Priority::Low, 1);
                break;
            
            case _Button::Event::Hold:
                _LEDGreen_::Set(_LEDGreen_::Priority::Low, 0);
                _Scheduler::Sleep(_Scheduler::Ms(250));
                _LEDGreen_::Set(_LEDGreen_::Priority::Low, 1);
                break;
            }
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._ButtonTask")]]
    alignas(sizeof(void*))
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
        PMMUnlock pmm; // Unlock PMM registers
        PMMCTL0_L |= PMMREGOFF_L;
    }
    
    // Remember our current interrupt state, which IntState will restore upon return
    Toastbox::IntState ints;
    // Atomically enable interrupts and go to sleep
    __bis_SR_register(GIE | LPMBits);
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
    case _Pin::MOTION_SIGNAL::IVPort2():
        _MainTask::ISR_MotionSignal(iv);
        __bic_SR_register_on_exit(LPM3_bits); // Wake ourself
        break;
    case _I2C::Pin::Active::IVPort2():
        _I2C::ISR_Active(iv);
        __bic_SR_register_on_exit(LPM3_bits); // Wake ourself
        break;
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

namespace AbortDomain {
    static constexpr uint16_t Invalid           = 0;
    static constexpr uint16_t Main              = 1;
    static constexpr uint16_t Scheduler         = 2;
    static constexpr uint16_t ICE               = 3;
    static constexpr uint16_t SD                = 4;
    static constexpr uint16_t Img               = 5;
    static constexpr uint16_t I2C               = 6;
    static constexpr uint16_t BatterySampler    = 7;
}

[[noreturn]]
static void _MainError(uint16_t line) {
    _Abort(AbortDomain::Main, line);
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

[[noreturn]]
static void _I2CError(uint16_t line) {
    _Abort(AbortDomain::I2C, line);
}

[[noreturn]]
static void _BatterySamplerError(uint16_t line) {
    _Abort(AbortDomain::BatterySampler, line);
}

static void _AbortRecord(const MSP::Time& timestamp, uint16_t domain, uint16_t line) {
    using namespace MSP;
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    AbortHistory* hist = nullptr;
    for (AbortHistory& h : _State.aborts) {
        if (!h.count || (h.type.domain == domain && h.type.line == line)) {
            hist = &h;
            break;
        }
    }
    
    // If we don't have a place to record the abort, bail
    if (!hist) return;
    
    // Prep the element if this is the first instance
    if (!hist->count) {
        hist->type = {
            .domain = domain,
            .line = line,
        };
        
        hist->timestampEarliest = timestamp;
    }
    
    hist->timestampLatest = timestamp;
    hist->count++;
}

[[noreturn]]
static void _BOR() {
    PMMUnlock pmm; // Unlock PMM registers
    PMMCTL0_L |= PMMSWBOR_L;
    // Wait for reset
    for (;;);
}

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line) {
    const MSP::Time timestamp = _RTC::TimeRead();
    // Record the abort
    _AbortRecord(timestamp, domain, line);
    _BOR();
}

extern "C" [[noreturn]]
void abort() {
    Assert(false);
}

// MARK: - Main

#warning verify that _StackMainSize is large enough
#define _StackMainSize 128

[[gnu::section(".stack.main")]]
alignas(sizeof(void*))
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm(".equ __stack, _StackMain+" Stringify(_StackMainSize));

//static void _HostMode() {
//    // Let power rails fully discharge before turning them on
//    _Scheduler::Delay(_Scheduler::Ms(10));
//    
//    while (!_Pin::HOST_MODE_::Read()) {
//        _Scheduler::Delay(_Scheduler::Ms(100));
//    }
//}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIO::Init<
        // General IO
        _Pin::MOTION_SIGNAL,
        _Pin::LED_GREEN_,
        _Pin::LED_RED_,
        _Pin::MOTION_EN_,
        _Pin::VDD_B_EN,
        
        // Power control
        _Pin::VDD_B_1V8_IMG_SD_EN,
        _Pin::VDD_B_2V8_IMG_SD_EN,
        
        // Clock (config chosen by _RTCType)
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
        
        // Battery (config chosen by _BatterySampler)
        _BatterySampler::Pin::BatChrgLvlPin,
        _BatterySampler::Pin::BatChrgLvlEn_Pin,
        
        // Button
        _Button::Pin
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
    
    // Init _BatterySampler
    _BatterySampler::Init();
    
    // Init LEDs by setting their low-priority / 'backstop' values to off.
    // This is necessary so that relinquishing the LEDs from I2C task causes
    // them to turn off. If we didn't have a backstop value, the LEDs would
    // remain in whatever state the I2C task set them to before relinquishing.
    _LEDGreen_::Set(_LEDGreen_::Priority::Low, 1);
    _LEDRed_::Set(_LEDRed_::Priority::Low, 1);
    
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

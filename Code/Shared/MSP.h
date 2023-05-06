#pragma once
#include <optional>
#include <atomic>
#include "Img.h"
#include "SD.h"
#include "ImgSD.h"
#include "Time.h"
#include "Toastbox/Util.h"

namespace MSP {

using BatteryChargeLevel = uint16_t;
constexpr BatteryChargeLevel BatteryChargeLevelInvalid  = 0x0000;
constexpr BatteryChargeLevel BatteryChargeLevelMin      = 0x0001;
constexpr BatteryChargeLevel BatteryChargeLevelMax      = 0xFFFF;

constexpr SD::Block SDBlockFull(SD::Block base, uint32_t idx) {
    return base - ((idx+1) * ImgSD::Full::ImageBlockCount);
}

constexpr SD::Block SDBlockThumb(SD::Block base, uint32_t idx) {
    return base - ((idx+1) * ImgSD::Thumb::ImageBlockCount);
}

// ImgRingBuf: stats to track captured images
struct [[gnu::packed]] ImgRingBuf {
    struct [[gnu::packed]] {
        Img::Id id;   // Next image id
        uint32_t idx; // Next image index
    } buf;
    bool valid;
    
    static void Set(ImgRingBuf& a, const ImgRingBuf& b) {
        a.valid = false;
        // Ensure that `valid` is reset before we modify `buf`
        std::atomic_signal_fence(std::memory_order_seq_cst);
        a.buf = b.buf;
        // Ensure that `buf` is valid before we set `valid`
        std::atomic_signal_fence(std::memory_order_seq_cst);
        a.valid = true;
    }
    
    static std::optional<int> Compare(const ImgRingBuf& a, const ImgRingBuf& b) {
        if (a.valid && b.valid) {
            if (a.buf.id > b.buf.id) return 1;
            else if (a.buf.id < b.buf.id) return -1;
            else return 0;
        
        } else if (a.valid) {
            return 1;
        
        } else if (b.valid) {
            return -1;
        }
        return std::nullopt;
    }
};

// Reset: records history of a type of reset (either abort or an unexpected reset)
struct [[gnu::packed]] Reset {
    enum class Type : uint8_t {
        Reset,
        Abort,
    };
    
    Type type;
    uint8_t count;
    
    union [[gnu::packed]] {
        struct [[gnu::packed]] {
            uint16_t reason;
        } Reset;
        
        struct [[gnu::packed]] {
            uint16_t addr;
        } Abort;
        
        uint16_t u16;
    } ctx;
    
    // We got rid of the time-tracking aspect of Reset for a few reasons:
    //   - it takes up a lot of space
    //   - we abort sometimes from the interrupt context, and we can't safely get the time there,
    //     because RTC::Tocks() calls Scheduler::Delay(), which isn't meant to be called from the
    //     interrupt context
    //   - we abort sometimes before RTC is configured, and we can't safely call RTC::Now() before
    //     it's configured, because it'll hang in Tocks() because RTCCNT never escapes 0
//    Time::Instant earliest = {};
//    Time::Instant latest   = {};
};
static_assert(!(sizeof(Reset) % 2)); // Check alignment
static_assert(sizeof(Reset) == 4); // Debug

struct [[gnu::packed]] Repeat {
    enum class Type : uint8_t {
        Never,
        Daily,
        Weekly,
        Yearly,
    };
    
    Type type;
    union [[gnu::packed]] {
        struct [[gnu::packed]] {
            uint8_t interval;
        } Daily;
        
        struct [[gnu::packed]] {
            uint8_t days;
        } Weekly;
        
        struct [[gnu::packed]] {
            uint8_t leapPhase;
        } Yearly;
    };
};
static_assert(sizeof(Repeat) == 2);

using LEDs = uint8_t;
struct LEDs_ { enum : LEDs {
    None  = 0,
    Green = 1<<0,
    Red   = 1<<1,
}; };

// Capture: describes the capture action when a trigger occurs
struct [[gnu::packed]] Capture {
    uint32_t delayTicks;
    uint16_t count;
    LEDs leds;
    uint8_t _pad;
};
static_assert(!(sizeof(Capture) % 2)); // Check alignment

struct [[gnu::packed]] Triggers {
    struct [[gnu::packed]] Event {
        enum class Type : uint8_t {
            TimeTrigger,
            MotionEnable,
        };
        Time::Instant time;
        Type type;
        Repeat repeat;
        uint8_t idx;
    };
    static_assert(!(sizeof(Event) % 2)); // Check alignment
    
    struct [[gnu::packed]] TimeTrigger {
        Capture capture;
    };
    static_assert(!(sizeof(TimeTrigger) % 2)); // Check alignment
    
    struct [[gnu::packed]] MotionTrigger {
        Capture capture;
        // count: the maximum number of triggers until motion is suppressed (0 == unlimited)
        uint16_t count;
        // durationTicks: duration for which motion should be enabled (0 == forever)
        uint32_t durationTicks;
        // suppressTicks: duration to suppress motion, after motion occurs (0 == no suppression)
        uint32_t suppressTicks;
    };
    static_assert(!(sizeof(MotionTrigger) % 2)); // Check alignment
    
    struct [[gnu::packed]] ButtonTrigger {
        Capture capture;
    };
    static_assert(!(sizeof(ButtonTrigger) % 2)); // Check alignment
    
    Event         event[32];
    TimeTrigger   timeTrigger[8];
    MotionTrigger motionTrigger[8];
    ButtonTrigger buttonTrigger[2];
    
    uint8_t eventCount;
    uint8_t timeTriggerCount;
    uint8_t motionTriggerCount;
    uint8_t buttonTriggerCount;
    
    // source: opaque data used by software to hold its representation of this struct
    uint8_t source[256];
};
//StaticPrint(sizeof(Triggers));


//struct [[gnu::packed]] Triggers {
//    struct [[gnu::packed]] TimeTrigger {
//        Time::Instant time = 0;
//        Repeat repeat;
//        Capture capture;
//    };
//    static_assert(!(sizeof(TimeTrigger) % 2)); // Check alignment
//    
//    struct [[gnu::packed]] MotionTrigger {
//        Time::Instant time = 0;
//        Repeat repeat;
//        Capture capture;
//        // count: the maximum number of triggers until motion is suppressed (0 == unlimited)
//        uint16_t count = 0;
//        // durationTicks: duration for which motion should be enabled (0 == forever)
//        uint32_t durationTicks = 0;
//        // suppressTicks: duration to suppress motion, after motion occurs (0 == no suppression)
//        uint32_t suppressTicks = 0;
//    };
//    static_assert(!(sizeof(MotionTrigger) % 2)); // Check alignment
//    
//    struct [[gnu::packed]] ButtonTrigger {
//        Capture capture;
//    };
//    static_assert(!(sizeof(ButtonTrigger) % 2)); // Check alignment
//    
//    TimeTrigger   timeTrigger[32];
//    MotionTrigger motionTrigger[8];
//    ButtonTrigger buttonTrigger[2];
//    
//    uint8_t timeTriggerCount   = 0;
//    uint8_t motionTriggerCount = 0;
//    uint8_t buttonTriggerCount = 0;
//    uint8_t _pad               = 0;
//    
//    // source: opaque data used by software to hold its representation of this struct
//    uint8_t source[256] = {};
//};
//StaticPrint(sizeof(Triggers));

struct [[gnu::packed]] Settings {
    Triggers triggers;
//    StaticPrint(sizeof(triggers));
    static_assert(sizeof(triggers) == 868); // Debug
};

struct [[gnu::packed]] State {
    struct [[gnu::packed]] Header {
        uint32_t magic;
        uint16_t version;
        uint16_t length;
    };
    
    Header header;
    static_assert(sizeof(header) == 8);
    
    struct [[gnu::packed]] {
        // cardId: the SD card's CID, used to determine when the SD card has been
        // changed, and therefore we need to update `imgCap` and reset `ringBufs`
        SD::CardId cardId;
        // imgCap: image capacity; the number of images that bounds the ring buffer
        uint32_t imgCap;
        // baseFull / baseThumb: the first block of the full-size and thumb image regions.
        // The SD card is broken into 2 regions (fullSize, thumbnails), to allow the host
        // to quickly read the thumbnails.
        SD::Block baseFull;
        SD::Block baseThumb;
        // ringBufs: tracks captured images on the SD card; 2 copies in case there's a
        // power failure while updating one
        ImgRingBuf imgRingBufs[2];
        bool valid;
        uint8_t _pad;
    } sd;
//    StaticPrint(sizeof(sd));
    static_assert(!(sizeof(sd) % 2)); // Check alignment
    static_assert(sizeof(sd) == 56); // Debug
    
    Settings settings;
//    StaticPrint(sizeof(settings));
    static_assert(!(sizeof(settings) % 2)); // Check alignment
    static_assert(sizeof(settings) == 868); // Debug
    
    // resets: records resets that have occurred
    Reset resets[10];
//    StaticPrint(sizeof(aborts));
    static_assert(!(sizeof(resets) % 2)); // Check alignment
    static_assert(sizeof(resets) == 40); // Debug
};
//StaticPrint(sizeof(State));
static_assert(!(sizeof(State) % 2)); // Check alignment
static_assert(sizeof(State) == 972); // Debug

constexpr State::Header StateHeader = {
    .magic   = 0xDECAFBAD,
    .version = 0,
    .length  = sizeof(State),
};

constexpr uint8_t I2CAddr = 0x55;

struct [[gnu::packed]] Cmd {
    enum class Op : uint8_t {
        None,
        StateRead,
        StateWrite,
        LEDSet,
        TimeGet,
        TimeSet,
        HostModeSet,
        VDDIMGSDSet,
        BatteryChargeLevelGet,
    };
    
    Op op;
    union {
        struct [[gnu::packed]] {
            uint16_t off;
        } StateRead;
        
        struct [[gnu::packed]] {
            uint16_t off;
            uint8_t data[8];
        } StateWrite;
        
        struct [[gnu::packed]] {
            uint8_t red;
            uint8_t green;
        } LEDSet;
        
        struct [[gnu::packed]] {
            Time::Instant time;
        } TimeSet;
        
        struct [[gnu::packed]] {
            uint8_t en;
        } HostModeSet;
        
        struct [[gnu::packed]] {
            uint8_t en;
        } VDDIMGSDSet;
    } arg;
};

struct [[gnu::packed]] Resp {
    uint8_t ok;
    union {
        struct [[gnu::packed]] {
            uint8_t data[8];
        } StateRead;
        
        struct [[gnu::packed]] {
            Time::Instant time;
        } TimeGet;
        
        struct [[gnu::packed]] {
            BatteryChargeLevel level;
        } BatteryChargeLevelGet;
    } arg;
};

//struct [[gnu::packed]] Triggers {
//    struct [[gnu::packed]] TimeTrigger {
//        enum class Type : uint8_t {
//            Capture,
//            MotionEnable,
//            MotionDisable,
//        };
//        
//        Type type;
//        Time::Instant time;
//        size_t idx;
//    };
//    
//    struct [[gnu::packed]] Capture {
//        
//    };
//    
//    TimeTrigger time[64];
//    Capture capture[8];
//    Motion motion[8];
//    Button button[2];
//};

struct [[gnu::packed]] DebugLogPacket {
    enum class Type : uint16_t {
        Chars = 0x8000, // High bit must be used to disambiguate against ASCII characters
        Dec16,
        Dec32,
        Dec64,
        Hex16,
        Hex32,
        Hex64,
    };
    
    union [[gnu::packed]] {
        Type type;
        uint8_t u8[2];
        uint16_t u16;
    };
};

} // namespace MSP

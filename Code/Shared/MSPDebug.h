#pragma once
#include <sstream>
#include <format>
#include <cstdio>
#include "MSP.h"
#include "TimeString.h"
#include "Lib/Toastbox/RuntimeError.h"
#include "Lib/Toastbox/Defer.h"

namespace MSP {

inline float _SecondsForTicks(uint32_t ticks) {
    // Check our assumption that Time::TicksFreq is an integer
    static_assert(Time::TicksFreq::den == 1);
    return (float)ticks / Time::TicksFreq::num;
}

inline const char* _StringForRepeatType(MSP::Repeat::Type x) {
    using X = MSP::Repeat::Type;
    switch (x) {
    case X::Never:  return "Never";  break;
    case X::Daily:  return "Daily";  break;
    case X::Weekly: return "Weekly"; break;
    case X::Yearly: return "Yearly"; break;
    }
    return "unknown";
}

inline const char* _StringForTriggerEventType(MSP::Triggers::Event::Type x) {
    using X = MSP::Triggers::Event::Type;
    switch (x) {
    case X::TimeTrigger:  return "TimeTrigger";
    case X::MotionEnable: return "MotionEnable";
    case X::DST:          return "DST";
    }
    return "unknown";
}

inline const char* _StringForResetType(MSP::Reset::Type x) {
    switch (x) {
    case MSP::Reset::Type::Reset:         return "reset";
    case MSP::Reset::Type::Abort:         return "abort";
    case MSP::Reset::Type::StackOverflow: return "stack overflow";
    }
    return "unknown";
}

inline const char* _StringForResetReason(uint16_t x) {
    switch (x) {
    case 0x0000: return "NONE";
    case 0x0002: return "BOR";
    case 0x0004: return "RSTNMI";
    case 0x0006: return "DOBOR";
    case 0x0008: return "LPM5WU";
    case 0x000A: return "SECYV";
    case 0x000C: return "RES12";
    case 0x000E: return "SVSHIFG";
    case 0x0010: return "RES16";
    case 0x0012: return "RES18";
    case 0x0014: return "DOPOR";
    case 0x0016: return "WDTTO";
    case 0x0018: return "WDTKEY";
    case 0x001A: return "FRCTLPW";
    case 0x001C: return "UBDIFG";
    case 0x001E: return "PERF";
    case 0x0020: return "PMMPW";
    case 0x0024: return "FLLUL";
    }
    return "unknown";
}

using MSPLineForAddrFn = std::string (*)(uint16_t addr);
inline std::string StringForState(const MSP::State& x, MSPLineForAddrFn mspLineForAddr=nullptr) {
    char* buf = nullptr;
    size_t bufLen = 0;
    FILE* f = open_memstream(&buf, &bufLen);
    if (!f) throw Toastbox::RuntimeError("open_memstream failed: %s", strerror(errno));
    Defer( fclose(f); free(buf); );
    
    fprintf(f,              "header\n");
    fprintf(f,              "  magic:                   0x%08jx\n",             (uintmax_t)x.header.magic);
    fprintf(f,              "  version:                 0x%04jx\n",             (uintmax_t)x.header.version);
    fprintf(f,              "  length:                  0x%04jx\n",             (uintmax_t)x.header.length);
    fprintf(f,              "\n");
    
    fprintf(f,              "sd\n");
    fprintf(f,              "  cardId\n");
    fprintf(f,              "    manufacturerId:        0x%02jx\n",             (uintmax_t)x.sd.cardId.manufacturerId);
    fprintf(f,              "    oemId:                 0x%02jx\n",             (uintmax_t)x.sd.cardId.oemId);
    fprintf(f,              "    productName:           %c%c%c%c%c\n",          x.sd.cardId.productName[0],
                                                                            x.sd.cardId.productName[1],
                                                                            x.sd.cardId.productName[2],
                                                                            x.sd.cardId.productName[3],
                                                                            x.sd.cardId.productName[4]);
    fprintf(f,              "    productRevision:       0x%02jx\n",             (uintmax_t)x.sd.cardId.productRevision);
    fprintf(f,              "    productSerialNumber:   0x%08jx\n",             (uintmax_t)x.sd.cardId.productSerialNumber);
    fprintf(f,              "    manufactureDate:       0x%04jx\n",             (uintmax_t)x.sd.cardId.manufactureDate);
    fprintf(f,              "    crc:                   0x%02jx\n",             (uintmax_t)x.sd.cardId.crc);
    
    fprintf(f,              "  imgCap:                  %ju\n",                 (uintmax_t)x.sd.imgCap);
    fprintf(f,              "  baseFull:                %ju\n",                 (uintmax_t)x.sd.baseFull);
    fprintf(f,              "  baseThumb:               %ju\n",                 (uintmax_t)x.sd.baseThumb);
    
    fprintf(f,              "  imgRingBufs[0]\n");
    fprintf(f,              "    buf\n");
    fprintf(f,              "      id:                  %ju\n",                 (uintmax_t)x.sd.imgRingBufs[0].buf.id);
    fprintf(f,              "      idx:                 %ju\n",                 (uintmax_t)x.sd.imgRingBufs[0].buf.idx);
    fprintf(f,              "    valid:                 %ju\n",                 (uintmax_t)x.sd.imgRingBufs[0].valid);
    
    fprintf(f,              "  imgRingBufs[1]\n");
    fprintf(f,              "    buf\n");
    fprintf(f,              "      id:                  %ju\n",                 (uintmax_t)x.sd.imgRingBufs[1].buf.id);
    fprintf(f,              "      idx:                 %ju\n",                 (uintmax_t)x.sd.imgRingBufs[1].buf.idx);
    fprintf(f,              "    valid:                 %ju\n",                 (uintmax_t)x.sd.imgRingBufs[1].valid);
    fprintf(f,              "\n");
    
    fprintf(f,              "settings\n");
    fprintf(f,              "  triggers\n");
    
    const auto& triggers = x.settings.triggers;
    
    fprintf(f,              "    repeatEvent\n");
    for (auto it=std::begin(triggers.repeatEvent); it!=std::begin(triggers.repeatEvent)+triggers.repeatEventCount; it++) {
        fprintf(f,          "      #%ju\n",                                     (uintmax_t)(&*it-triggers.repeatEvent));
        fprintf(f,          "        time:              %s\n",              Time::StringForTimeInstant(it->time).c_str());
        fprintf(f,          "        type:              %s\n",              _StringForTriggerEventType(it->type));
        fprintf(f,          "        idx:               %ju\n",             (uintmax_t)it->idx);
        fprintf(f,          "        repeat\n");
        fprintf(f,          "          type:            %s\n",              _StringForRepeatType(it->repeat.type));
        fprintf(f,          "          arg:             0x%jx\n",           (uintmax_t)it->repeat.Daily.interval);
    }
    
    fprintf(f,              "    timeTrigger\n");
    for (auto it=std::begin(triggers.timeTrigger); it!=std::begin(triggers.timeTrigger)+triggers.timeTriggerCount; it++) {
        fprintf(f,          "      #%ju\n",                                     (uintmax_t)(&*it-triggers.timeTrigger));
        fprintf(f,          "        capture\n");
        fprintf(f,          "          delayTicks:      %ju (%.1f)\n",      (uintmax_t)it->capture.delayTicks, _SecondsForTicks(it->capture.delayTicks));
        fprintf(f,          "          count:           %ju\n",             (uintmax_t)it->capture.count);
        fprintf(f,          "          ledFlash:        %ju\n",             (uintmax_t)it->capture.ledFlash);
    }
    
    fprintf(f,              "    motionTrigger\n");
    for (auto it=std::begin(triggers.motionTrigger); it!=std::begin(triggers.motionTrigger)+triggers.motionTriggerCount; it++) {
        fprintf(f,          "      #%ju\n",                                     (uintmax_t)(&*it-triggers.motionTrigger));
        fprintf(f,          "        capture\n");
        fprintf(f,          "          delayTicks:      %ju (%.1f)\n",      (uintmax_t)it->capture.delayTicks, _SecondsForTicks(it->capture.delayTicks));
        fprintf(f,          "          count:           %ju\n",             (uintmax_t)it->capture.count);
        fprintf(f,          "          ledFlash:        %ju\n",             (uintmax_t)it->capture.ledFlash);
        fprintf(f,          "        count:             %ju\n",             (uintmax_t)it->count);
        fprintf(f,          "        durationTicks:     %ju (%.1f)\n",      (uintmax_t)it->durationTicks, _SecondsForTicks(it->durationTicks));
        fprintf(f,          "        suppressTicks:     %ju (%.1f)\n",      (uintmax_t)it->suppressTicks, _SecondsForTicks(it->suppressTicks));
    }
    
    fprintf(f,              "    buttonTrigger\n");
    for (auto it=std::begin(triggers.buttonTrigger); it!=std::begin(triggers.buttonTrigger)+triggers.buttonTriggerCount; it++) {
        fprintf(f,          "      #%ju\n",                                     (uintmax_t)(&*it-triggers.buttonTrigger));
        fprintf(f,          "        capture\n");
        fprintf(f,          "          delayTicks:      %ju (%.1f)\n",      (uintmax_t)it->capture.delayTicks, _SecondsForTicks(it->capture.delayTicks));
        fprintf(f,          "          count:           %ju\n",             (uintmax_t)it->capture.count);
        fprintf(f,          "          ledFlash:        %ju\n",             (uintmax_t)it->capture.ledFlash);
    }
    
    fprintf(f,              "    dstEvent\n");
    for (auto it=std::begin(triggers.dstEvent); it!=std::begin(triggers.dstEvent)+triggers.dstEventCount; it++) {
        fprintf(f,          "      #%ju\n",                                     (uintmax_t)(&*it-triggers.dstEvent));
        fprintf(f,          "        time:              %s\n",              Time::StringForTimeInstant(it->time).c_str());
        fprintf(f,          "        type:              %s\n",              _StringForTriggerEventType(it->type));
        fprintf(f,          "        idx:               %ju\n",             (uintmax_t)it->idx);
        fprintf(f,          "        phase:             0x%016jx\n",        (uintmax_t)it->phase.u64);
        fprintf(f,          "        adjustmentTicks:   %+jd\n",            (intmax_t)it->adjustmentTicks);
    }
    
    fprintf(f,              "    source\n");
    for (auto it=std::begin(triggers.source); it!=std::end(triggers.source);) {
        fprintf(f,          "      ");
        for (int i=0; i<16 && it!=std::end(triggers.source); i++, it++) {
            fprintf(f,      "%02jx ", (uintmax_t)*it);
        }
        fprintf(f,          "\n");
    }
    fprintf(f,              "\n");
    
    fprintf(f,              "resets\n");
    size_t i = 0;
    for (const auto& reset : x.resets) {
        if (!reset.count) break;
        fprintf(f,          "  #%ju\n",                                         (uintmax_t)i);
        fprintf(f,          "    type:                  0x%02jx (%s)\n",        (uintmax_t)reset.type, _StringForResetType(reset.type));
        
        switch (reset.type) {
        case MSP::Reset::Type::Reset:
            fprintf(f,      "    reason:                0x%04jx (%s)\n",        (uintmax_t)reset.ctx.Reset.reason, _StringForResetReason(reset.ctx.Reset.reason));
            break;
        case MSP::Reset::Type::Abort:
            if (mspLineForAddr) {
                std::string addrStr;
                try {
                    addrStr = mspLineForAddr(reset.ctx.Abort.addr);
                } catch (const std::exception& e) {
                    addrStr = std::string("address lookup failed: ") + e.what();
                }
                fprintf(f,  "    addr:                  0x%04jx [ %s ]\n",  (uintmax_t)reset.ctx.Abort.addr, addrStr.c_str());
            } else {
                fprintf(f,  "    addr:                  0x%04jx\n",         (uintmax_t)reset.ctx.Abort.addr);
            }
            
            break;
        case MSP::Reset::Type::StackOverflow:
            fprintf(f,      "    taskIdx:               %ju\n",                 (uintmax_t)reset.ctx.StackOverflow.taskIdx);
            break;
        }
        fprintf(f,          "    count:                 %ju\n",                 (uintmax_t)reset.count);
        i++;
    }
    fprintf(f,              "\n");
    
    // Flush the stream to so that `buf` is assigned to the FILE's internal buffer
    fflush(f);
    return buf;
}

} // namespace MSP

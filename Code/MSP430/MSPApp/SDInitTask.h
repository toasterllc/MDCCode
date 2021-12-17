#pragma once
#include "SDCard.h"
#include "Scheduler.h"

class SDInitTask {
    
    // Task options
    using Options = Scheduler::Options<>;
    
    // Task stack
    __attribute__((section(".stack.SDInitTask")))
    static inline uint8_t Stack[128];
    
    static void Enable() {
        // Wait until we're idle
        Wait();
        // Run the enable function
        Scheduler::Run<SDTask>(_Enable);
    }
    
    static void Disable() {
        // Wait until we're idle
        Wait();
        // Run the enable function
        Scheduler::Run<SDTask>(_Disable);
    }
    
    static bool Wait() {
        Scheduler::Wait([] { return !Running(); });
    }
    
    static bool Running() {
        return !Scheduler<SDTask>::Running();
    }
    
    static void _Enable() {
        _SDCard.enable();
    }
    
    static void _Disable() {
        _SDCard.disable();
    }
    
private:
    static inline T_SDCard _SDCard;
};

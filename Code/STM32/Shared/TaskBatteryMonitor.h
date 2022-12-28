#pragma once
#include "Toastbox/Task.h"

template <typename T_Scheduler>
struct TaskBatteryMonitor {
    static void Run() {
        for (bool green=true;; green=!green) {
            LED0::Write(green);
            
            const MSP::Cmd cmd = {
                .op = MSP::Cmd::Op::LEDSet,
                .arg = { .LEDSet = { .green = green }, },
            };
            
            MSP::Resp resp;
            T_I2C::Send(cmd, resp);
            
            Scheduler::Sleep(Scheduler::Ms(3000));
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack.TaskBatteryMonitor")]]
    static inline uint8_t Stack[256];
};

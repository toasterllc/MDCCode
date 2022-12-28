#pragma once
#include "Toastbox/Task.h"

// TaskCmdHandle: handle command
template <typename T_Scheduler>
struct TaskCmdHandle {
    static void Start(const STM::Cmd& c) {
        using namespace STM;
        static STM::Cmd cmd = {};
        cmd = c;
        
        T_Scheduler::template Start<TaskCmdHandle>([] {
            switch (cmd.op) {
            case Op::EndpointsFlush:    _EndpointsFlush(cmd);       break;
            case Op::StatusGet:         _StatusGet(cmd);            break;
            case Op::BootloaderInvoke:  _BootloaderInvoke(cmd);     break;
            case Op::LEDSet:            _LEDSet(cmd);               break;
            // Unknown command
            default:                    T_CmdHandle(cmd);           break;
            }
        });
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack.TaskCmdHandle")]]
    static inline uint8_t Stack[1024];
};

#pragma once
#include "Toastbox/Task.h"

// TaskCmdHandle: handle command
template <
typename T_Scheduler,
typename T_System,
auto T_CmdHandle
>
struct TaskCmdHandle {
    static void Handle(const STM::Cmd& c) {
        Assert(!_Cmd);
        _Cmd = c;
        T_Scheduler::template Start<TaskCmdHandle>();
    }
    
    static void Run() {
        using namespace STM;
        
        switch (_Cmd->op) {
        case Op::EndpointsFlush:    T_System::EndpointsFlush(*_Cmd);   break;
        case Op::StatusGet:         T_System::StatusGet(*_Cmd);        break;
        case Op::BootloaderInvoke:  T_System::BootloaderInvoke(*_Cmd); break;
        case Op::LEDSet:            T_System::LEDSet(*_Cmd);           break;
        default:                    T_CmdHandle(*_Cmd);                 break;
        }
        
        _Cmd = std::nullopt;
    }
    
    static inline std::optional<STM::Cmd> _Cmd;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack.TaskCmdHandle")]]
    static inline uint8_t Stack[1024];
};

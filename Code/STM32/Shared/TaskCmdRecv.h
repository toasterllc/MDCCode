#pragma once
#include "Toastbox/Task.h"

// _TaskCmdRecv: receive commands over USB, and initiate handling them
template <
typename T_USB,
auto T_CmdHandle,
auto T_TasksReset
>
struct TaskCmdRecv {
    static void Run() {
        for (;;) {
            auto usbCmdOpt = T_USB::CmdRecv();
            // If T_USB returns nullopt, it signifies that USB was disconnected or re-connected,
            // so we need to reset our tasks.
            if (!usbCmdOpt) {
                // Reset all tasks
                // This needs to happen before we call `T_USB::Connect()` so that any tasks that
                // were running in the previous T_USB session are stopped before we enable
                // T_USB again by calling T_USB::Connect().
                T_TasksReset();
                continue;
            }
            
            auto usbCmd = *usbCmdOpt;
            
            // Reject command if the length isn't valid
            STM::Cmd cmd;
            if (usbCmd.len != sizeof(cmd)) {
                T_USB::CmdAccept(false);
                continue;
            }
            
            memcpy(&cmd, usbCmd.data, usbCmd.len);
            
            // Only accept command if it's a flush command (in which case the endpoints
            // don't need to be ready), or it's not a flush command, but all endpoints
            // are ready. Otherwise, reject the command.
            if (cmd.op!=STM::Op::EndpointsFlush && !T_USB::EndpointsReady()) {
                T_USB::CmdAccept(false);
                continue;
            }
            
            T_USB::CmdAccept(true);
            T_CmdHandle(cmd);
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack.TaskCmdRecv")]]
    static inline uint8_t Stack[512];
};

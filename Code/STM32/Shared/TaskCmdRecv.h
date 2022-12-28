#pragma once
#include "Toastbox/Task.h"

// _TaskCmdRecv: receive commands over USB, and initiate handling them
template <typename T_Scheduler>
struct TaskCmdRecv {
    static void Run() {
        for (;;) {
            // Wait for USB to be re-connected (`Connecting` state) so we can call USB::Connect(),
            // or for a new command to arrive so we can handle it.
            Scheduler::Wait([] { return USB::StateGet()==T_USB::State::Connecting || USB::CmdRecv(); });
            
            // Disable interrupts so we can inspect+modify `USB` atomically
            Toastbox::IntState ints(false);
            
            // Reset all tasks
            // This needs to happen before we call `USB::Connect()` so that any tasks that
            // were running in the previous USB session are stopped before we enable
            // USB again by calling USB::Connect().
            _TasksReset();
            
            switch (USB::StateGet()) {
            case T_USB::State::Connecting:
                USB::Connect();
                continue;
            case T_USB::State::Connected:
                if (!USB::CmdRecv()) continue;
                break;
            default:
                continue;
            }
            
            auto usbCmd = *USB::CmdRecv();
            
            // Re-enable interrupts while we handle the command
            ints.restore();
            
            // Reject command if the length isn't valid
            STM::Cmd cmd;
            if (usbCmd.len != sizeof(cmd)) {
                USB::CmdAccept(false);
                continue;
            }
            
            memcpy(&cmd, usbCmd.data, usbCmd.len);
            
            // Only accept command if it's a flush command (in which case the endpoints
            // don't need to be ready), or it's not a flush command, but all endpoints
            // are ready. Otherwise, reject the command.
            if (cmd.op!=STM::Op::EndpointsFlush && !USB::EndpointsReady()) {
                USB::CmdAccept(false);
                continue;
            }
            
            USB::CmdAccept(true);
            _TaskCmdHandle::Start(cmd);
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

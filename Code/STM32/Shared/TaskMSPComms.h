#pragma once
#include "Toastbox/Task.h"
#include "MSP.h"
#include "Assert.h"

template <
typename T_Scheduler,
typename T_I2C
>
struct TaskMSPComms {
    static void Run() {
        using Deadline = typename T_Scheduler::Deadline;
        constexpr uint16_t UpdateChargeStatusIntervalMs = 10000;
        
        Deadline updateChargeStatusDeadline = T_Scheduler::CurrentTime();
        for (;;) {
            // Wait until we get a command or for the deadline to pass
            const auto ok = T_Scheduler::WaitUntil(updateChargeStatusDeadline, [&] { return (bool)_Cmd; });
            if (!ok) {
                // Deadline passed; update charge status
                _UpdateChargeStatus();
                // Update our deadline for the next charge status update
                updateChargeStatusDeadline = T_Scheduler::CurrentTime() + T_Scheduler::Ms(UpdateChargeStatusIntervalMs);
                continue;
            }
            
            MSP::Resp resp;
            const bool ok = T_I2C::Send(_Cmd, resp);
            #warning TODO: handle errors properly
            Assert(ok);
            // Return the response to the caller
            _Resp = resp;
        }
        
        
        //T_Scheduler::CurrentTime() + T_Scheduler::Ms(10000);
        
        
//        WaitUntil();
//        T_Scheduler::Ms()
//        
//        T_Scheduler::Deadline 
//        
//        T_Scheduler::WaitUntil([&] { return _St.load() == _State::Idle; });
//        
//        
//        T_Scheduler::Ticks deadline = T_Scheduler::CurrentTime() + T_Scheduler::Ms(10000);
//        
//        if () 
//        
//        
//        for (bool green=true;; green=!green) {
//            LED0::Write(green);
//            
//            const MSP::Cmd cmd = {
//                .op = MSP::Cmd::Op::LEDSet,
//                .arg = { .LEDSet = { .green = green }, },
//            };
//            
//            MSP::Resp resp;
//            T_I2C::Send(cmd, resp);
//            
//            Scheduler::Sleep(Scheduler::Ms(3000));
//        }
    }
    
//    static bool Send(const T_Send& send, T_Recv& recv) {
//        T_Scheduler::Wait([&] { return _St.load() == _State::Idle; });
//        
//        bool ok = _Send(send);
//        if (!ok) return false;
//        
//        ok = _Recv(recv);
//        if (!ok) return false;
//        
//        return true;
//    }
    
    static MSP::Resp Send(const MSP::Cmd& cmd) {
        // Wait until _Cmd is empty
        T_Scheduler::Wait([&] { return !_Cmd; });
        // Supply the I2C command to be sent
        _Cmd = cmd;
        // Wait until we get a response
        T_Scheduler::Wait([&] { return _Resp; });
        const MSP::Resp resp = *_Resp;
        // Reset our state
        _Cmd = std::nullopt;
        _Resp = std::nullopt;
        return resp;
        
//        if (!ok || !mspResp.ok) {
//            _System::USBSendStatus(false);
//            return;
//        }
//        
//        
    }
    
    static void _UpdateChargeStatus() {
        // Refresh charge status LEDs
        const MSP::Cmd cmd = {
            .op = MSP::Cmd::Op::LEDSet,
            .arg = { .LEDSet = { .green = true }, },
        };
        
        MSP::Resp resp;
        const bool ok = T_I2C::Send(cmd, resp);
        #warning TODO: handle errors properly
        Assert(ok);
        Assert(resp.ok);
    }
    
    static inline std::optional<MSP::Cmd> _Cmd;
    static inline std::optional<MSP::Resp> _Resp;
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack.TaskMSPComms")]]
    static inline uint8_t Stack[256];
};

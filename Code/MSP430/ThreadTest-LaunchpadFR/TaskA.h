#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
#include "Scheduler.h"

class TaskA {
public:
    static void Run() {
        for (;;) {
            PAOUT ^= BIT0;
            
//            Scheduler::Start<TaskA,MyFun>();
//            Scheduler::Start<TaskA>(MyFun);
//            Scheduler::Start<TaskB>(MyFun);
//            Scheduler::Wait<TaskB>();
            
//            puts("TaskA\n");
            Scheduler::Sleep(10000); // 5.12s
        }
    }
    
    __attribute__((section(".stack.TaskA")))
    static inline uint8_t Stack[1024];
    
    using Options = Scheduler::Options<
        Scheduler::Option::AutoStart<Run>
    >;
};

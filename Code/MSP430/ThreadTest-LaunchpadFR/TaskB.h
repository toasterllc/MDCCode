#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
#include "Scheduler.h"

class TaskB {
public:
    using Options = Scheduler::Options<>;
    
    static void Run() {
        for (;;) {
            PAOUT ^= BIT0;
//            puts("TaskB\n");
            Scheduler::Sleep(10000); // 5.12s
        }
    }
    
    __attribute__((section(".stack.TaskB")))
    static inline uint8_t Stack[1024];
};

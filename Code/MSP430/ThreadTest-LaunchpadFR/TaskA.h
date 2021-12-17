#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
#include "Scheduler.h"

class TaskA {
public:
    using Options = typename Scheduler::Options<>;
    
    static void Run() {
        for (;;) {
            PAOUT ^= BIT0;
//            puts("TaskA\n");
            Scheduler::Sleep(10000); // 5.12s
        }
    }
    
    __attribute__((section(".stack.TaskA")))
    static inline uint8_t Stack[1024];
};

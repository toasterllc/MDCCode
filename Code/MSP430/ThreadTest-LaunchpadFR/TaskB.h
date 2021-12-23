#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
#include "Scheduler.h"

class TaskB {
public:
    static void Run() {
        for (;;) {
            PAOUT ^= BIT1;
//            puts("TaskB\n");
            Scheduler::Sleep(40000); // 20.48s
        }
    }
    
    __attribute__((section(".stack.TaskB")))
    static inline uint8_t Stack[1024];
    
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run,
    };
};

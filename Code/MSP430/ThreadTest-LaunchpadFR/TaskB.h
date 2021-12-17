#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
#include "Scheduler.h"
#include <vector>

class TaskB {
public:
    using Options = typename Scheduler::Options<>;
    
    template <typename T>
    using MyVector = std::vector<T>;
    
    MyVector SomeVector;
    
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

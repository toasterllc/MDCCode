#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"

class TaskA;
class TaskB;

using Scheduler = Toastbox::Scheduler<
    // Microseconds per tick
    512,
    // Stack guard
    nullptr,
    0,
    // Tasks
    TaskA,
    TaskB
>;

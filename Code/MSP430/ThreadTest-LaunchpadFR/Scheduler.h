#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"

class TaskA;
class TaskB;

using Scheduler = Toastbox::Scheduler<
    TaskA,
    TaskB
>;

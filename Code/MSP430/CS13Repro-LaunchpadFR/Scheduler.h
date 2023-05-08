#include <msp430.h>
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"

class TaskA;
class TaskB;

void _Sleep();
void _Error(uint16_t);

using Scheduler = Toastbox::Scheduler<
    512,                                        // T_UsPerTick: microseconds per tick
    Toastbox::IntState::SetInterruptsEnabled,   // T_SetInterruptsEnabled: function to change interrupt state
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    _Error,                                     // T_Error: function to call upon an unrecoverable error (eg stack overflow)
    nullptr,                                    // T_MainStack: main stack pointer (only used to monitor
                                                //              main stack for overflow; unused if T_StackGuardCount==0)
    0,                                          // T_StackGuardCount: number of pointer-sized stack guard elements to use
    TaskA,                                      // T_Tasks: list of tasks
    TaskB
>;

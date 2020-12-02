#include "Startup.h"

Startup Start;

// StartupRun needs to be in the .isr section so that it's near ISR_Reset,
// otherwise we can get a linker error.
extern "C" __attribute__((section(".isr"))) void StartupRun() {
    Start.run();
}

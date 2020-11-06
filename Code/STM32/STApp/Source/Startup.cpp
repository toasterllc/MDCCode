#include "Startup.h"

Startup Start;
extern "C" void StartupRun() {
    Start.run();
}

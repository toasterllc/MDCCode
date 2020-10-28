#include "Startup.h"
#include <string.h>
#include "stm32f7xx.h"

void Startup::setAppEntryPointAddr(uintptr_t addr) {
    _appEntryPointAddr = addr;
}

void Startup::run() {
    // Stash and reset `AppEntryPointAddr` so that we only attempt to start the app once
    // after each software reset.
    void (*const appEntryPoint)() = (void (*)())_appEntryPointAddr;
    setAppEntryPointAddr(0);
    
    // Cache RCC_CSR since we're about to clear it
    auto csr = READ_REG(RCC->CSR);
    // Clear RCC_CSR by setting the RMVF bit
    SET_BIT(RCC->CSR, RCC_CSR_RMVF);
    // Check if we reset due to a software reset (SFTRSTF), and
    // we have the app's vector table.
    if (READ_BIT(csr, RCC_CSR_SFTRSTF) && appEntryPoint) {
        // Start the application
        appEntryPoint();
        for (;;); // Loop forever if the app returns
    }
    
    _super::run();
}

// The Startup class needs to exist in the `noinit` section,
// so that its _appEntryPointAddr member doesn't get clobbered
// on startup.
Startup Start __attribute__((section(".noinit")));

extern "C" void StartupRun() {
    Start.run();
}

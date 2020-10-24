#include "stm32f7xx.h"
#include <string.h>

class Startup {
public:
    static void Run();
    static void SetAppEntryPointAddr(uintptr_t addr);
};

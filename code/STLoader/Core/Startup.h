#include <stdint.h>

class Startup {
public:
    static void Run();
    static void SetAppEntryPointAddr(uintptr_t addr);
};

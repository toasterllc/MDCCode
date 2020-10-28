#include <stdint.h>
#include "StartupBase.h"

class Startup : public StartupBase<Startup> {
public:
    void run();
    void setAppEntryPointAddr(uintptr_t addr);
    
private:
    using _super = StartupBase<Startup>;
    volatile uintptr_t _appEntryPointAddr;
    friend class StartupBase<Startup>;
};

extern Startup Start;

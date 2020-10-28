#include <stdint.h>
#include "StartupBase.h"

class Startup : StartupBase {
public:
    void setAppEntryPointAddr(uintptr_t addr);
    
protected:
    void runInit() override;
    
private:
    volatile uintptr_t _appEntryPointAddr;
};

extern Startup Start;

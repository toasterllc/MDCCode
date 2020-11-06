#include "StartupBase.h"

class Startup : public StartupBase<Startup> {};
extern Startup Start;

#pragma once
#include "Enum.h"

namespace STLoader {
    Enum(uint8_t, Endpoint, Endpoints,
        // Control endpoint
        Ctrl        = 0x00,
        
        // OUT endpoints (high bit 0)
        DataOut     = 0x01,
    );
    
    Enum(uint8_t, EndpointIdx, EndpointIdxs,
        DataOut = 1,
    );
}

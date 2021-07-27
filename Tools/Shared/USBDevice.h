#pragma once

#if __APPLE__
#include "USBDeviceMac.h"
#elif __linux__
#include "USBDeviceLinux.h"
#endif

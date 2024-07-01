#pragma once
#include <stdint.h>

#define STORAGE_SECTOR_SIZE     512
#define STORAGE_SECTOR_COUNT    64
extern uint8_t Storage[STORAGE_SECTOR_SIZE*STORAGE_SECTOR_COUNT];

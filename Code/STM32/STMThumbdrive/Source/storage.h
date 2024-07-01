#pragma once
#include <stdint.h>

#define STORAGE_SECTOR_SIZE         512
#define STORAGE_SECTOR_COUNT        256
#define STORAGE_SIZE                (STORAGE_SECTOR_SIZE*STORAGE_SECTOR_COUNT)
extern uint8_t Storage[STORAGE_SIZE];


#define STORAGE_SECTOR_FAKE_COUNT   16384
#define STORAGE_FAKE_SIZE           (STORAGE_SECTOR_SIZE*STORAGE_SECTOR_FAKE_COUNT)
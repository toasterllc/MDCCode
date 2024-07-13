#pragma once
#include <cstdint>
#include "Code/Lib/Toastbox/FAT12.h"

struct Filesystem {
    static constexpr size_t _BytesPerSector = 512;
    //constexpr size_t _BytesPerSector = 1024;
    static_assert(_BytesPerSector <= 32768);
    
    static constexpr size_t _DataSize = 16*1024;
    //constexpr size_t _DataSize = 128*1024;
    
    static constexpr size_t _SectorsPerCluster = _DataSize / _BytesPerSector;
    static_assert(_SectorsPerCluster == 32); // Debug
    
    //constexpr size_t _SectorsPerCluster = 1;
    static_assert(_SectorsPerCluster <= 128);
    
    static constexpr size_t _DataSectorCount = _DataSize / _BytesPerSector;
    static_assert(_DataSectorCount == 32); // Debug
    
    static constexpr size_t _DataClusterCount = _DataSectorCount / _SectorsPerCluster;
    static_assert(_DataClusterCount == 1); // Debug
    
    static constexpr size_t _HeaderSectorCount = 3;
    static constexpr size_t _SectorCount = _HeaderSectorCount + _DataSectorCount;
    
    using BootRecord = Toastbox::FAT12::BootRecord<_BytesPerSector>;
    using FATTable = Toastbox::FAT12::FATTable<_BytesPerSector>;
    using DirTable = Toastbox::FAT12::DirTable<_BytesPerSector>;
    
    alignas(void*)
    static inline struct [[gnu::packed]] {
        BootRecord boot;
        FATTable fat;
        DirTable dir;
        std::uint8_t data[_DataClusterCount][_SectorsPerCluster][_BytesPerSector];
    
    } _Data = {
        .boot = {
            .jump                   = { 0xEB, 0xFE, 0x90, },
            .oem                    = { 'M','S','D','O','S','5','.','0', },
            .sectorSize             = _BytesPerSector,
            .clusterSize            = _SectorsPerCluster,
            .reservedSize           = 1,
            .fatCount               = 1,
            .rootEntryCount         = DirTable::EntryCount,
            .totalSize              = _SectorCount,
            .mediaDescriptor        = 0xF8,
            .fatSize                = 1,
            .trackSize              = 1,
            .headCount              = 0,
            .hiddenSectorCount      = 0,
            .largeSectorCount       = 0,
            .driveNumber            = 0,
            .extendedBootSignature  = 0x29,
            .serialNumber           = 0,
            .volumeLabel            = { 'P','h','o','t','o','n',' ',' ',' ',' ',' ', },
            .filesystemType         = { 'F','A','T',' ',' ',' ',' ',' ', },
            .bootcode               = { },
            .signature              = 0xAA55,
        },
        
        .fat = {
            .entries = {
                { 0xFF8, 0xFFF },   // Root directory entry
                { 0xFFF, 0x000 },
            },
        },
        
        .dir = {
            .entries = {
                {
                    .name       = { 'a',' ',' ',' ',' ',' ',' ',' ', },
                    .ext        = { ' ',' ',' ', },
                    .attr       = 0x00,
                    .fatIndex   = 2,
                    .fileSize   = _DataSize,
                },
            },
        },
        
        .data = {
            'h','e','l','l','o',
        },
    };
};

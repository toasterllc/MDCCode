#pragma once
#include <cstdint>
#include "Code/Lib/Toastbox/FAT12.h"

struct Filesystem {
    static constexpr size_t _BytesPerSector = 512;
    //constexpr size_t _BytesPerSector = 1024;
    static_assert(_BytesPerSector <= 32768);
    
//    static constexpr size_t _DataSize = 128*1024;
//    static constexpr size_t _DataSize = 512*1024;
//    static constexpr size_t _DataSize = 1024*1024;
//    static constexpr size_t _DataSize = 338*128*512;
    static constexpr size_t _DataSize = 16*1024*1024;
    //constexpr size_t _DataSize = 128*1024;
    
    static constexpr size_t _SectorsPerCluster = 128;
//    static constexpr size_t _SectorsPerCluster = _DataSize / _BytesPerSector;
//    static_assert(_SectorsPerCluster == 32); // Debug
    
    //constexpr size_t _SectorsPerCluster = 1;
    static_assert(_SectorsPerCluster <= 128);
    
    static constexpr size_t _DataSectorCount = _DataSize / _BytesPerSector;
//    static_assert(_DataSectorCount == 32); // Debug
    
    static constexpr size_t _DataClusterCount = _DataSectorCount / _SectorsPerCluster;
//    static_assert(_DataClusterCount == 1); // Debug
    
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
        std::uint8_t data[];
//        std::uint8_t data[_DataClusterCount][_SectorsPerCluster][_BytesPerSector];
    
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
//                { 0xFFF, 0x000 },
                
                { 0x003, 0x004 },
                { 0x005, 0x006 },
                { 0x007, 0x008 },
                { 0x009, 0x00A },
                { 0x00B, 0x00C },
                { 0x00D, 0x00E },
                { 0x00F, 0x010 },
                { 0x011, 0x012 },
                { 0x013, 0x014 },
                { 0x015, 0x016 },
                { 0x017, 0x018 },
                { 0x019, 0x01A },
                { 0x01B, 0x01C },
                { 0x01D, 0x01E },
                { 0x01F, 0x020 },
                { 0x021, 0x022 },
                { 0x023, 0x024 },
                { 0x025, 0x026 },
                { 0x027, 0x028 },
                { 0x029, 0x02A },
                { 0x02B, 0x02C },
                { 0x02D, 0x02E },
                { 0x02F, 0x030 },
                { 0x031, 0x032 },
                { 0x033, 0x034 },
                { 0x035, 0x036 },
                { 0x037, 0x038 },
                { 0x039, 0x03A },
                { 0x03B, 0x03C },
                { 0x03D, 0x03E },
                { 0x03F, 0x040 },
                { 0x041, 0x042 },
                { 0x043, 0x044 },
                { 0x045, 0x046 },
                { 0x047, 0x048 },
                { 0x049, 0x04A },
                { 0x04B, 0x04C },
                { 0x04D, 0x04E },
                { 0x04F, 0x050 },
                { 0x051, 0x052 },
                { 0x053, 0x054 },
                { 0x055, 0x056 },
                { 0x057, 0x058 },
                { 0x059, 0x05A },
                { 0x05B, 0x05C },
                { 0x05D, 0x05E },
                { 0x05F, 0x060 },
                { 0x061, 0x062 },
                { 0x063, 0x064 },
                { 0x065, 0x066 },
                { 0x067, 0x068 },
                { 0x069, 0x06A },
                { 0x06B, 0x06C },
                { 0x06D, 0x06E },
                { 0x06F, 0x070 },
                { 0x071, 0x072 },
                { 0x073, 0x074 },
                { 0x075, 0x076 },
                { 0x077, 0x078 },
                { 0x079, 0x07A },
                { 0x07B, 0x07C },
                { 0x07D, 0x07E },
                { 0x07F, 0x080 },
                { 0x081, 0x082 },
                { 0x083, 0x084 },
                { 0x085, 0x086 },
                { 0x087, 0x088 },
                { 0x089, 0x08A },
                { 0x08B, 0x08C },
                { 0x08D, 0x08E },
                { 0x08F, 0x090 },
                { 0x091, 0x092 },
                { 0x093, 0x094 },
                { 0x095, 0x096 },
                { 0x097, 0x098 },
                { 0x099, 0x09A },
                { 0x09B, 0x09C },
                { 0x09D, 0x09E },
                { 0x09F, 0x0A0 },
                { 0x0A1, 0x0A2 },
                { 0x0A3, 0x0A4 },
                { 0x0A5, 0x0A6 },
                { 0x0A7, 0x0A8 },
                { 0x0A9, 0x0AA },
                { 0x0AB, 0x0AC },
                { 0x0AD, 0x0AE },
                { 0x0AF, 0x0B0 },
                { 0x0B1, 0x0B2 },
                { 0x0B3, 0x0B4 },
                { 0x0B5, 0x0B6 },
                { 0x0B7, 0x0B8 },
                { 0x0B9, 0x0BA },
                { 0x0BB, 0x0BC },
                { 0x0BD, 0x0BE },
                { 0x0BF, 0x0C0 },
                { 0x0C1, 0x0C2 },
                { 0x0C3, 0x0C4 },
                { 0x0C5, 0x0C6 },
                { 0x0C7, 0x0C8 },
                { 0x0C9, 0x0CA },
                { 0x0CB, 0x0CC },
                { 0x0CD, 0x0CE },
                { 0x0CF, 0x0D0 },
                { 0x0D1, 0x0D2 },
                { 0x0D3, 0x0D4 },
                { 0x0D5, 0x0D6 },
                { 0x0D7, 0x0D8 },
                { 0x0D9, 0x0DA },
                { 0x0DB, 0x0DC },
                { 0x0DD, 0x0DE },
                { 0x0DF, 0x0E0 },
                { 0x0E1, 0x0E2 },
                { 0x0E3, 0x0E4 },
                { 0x0E5, 0x0E6 },
                { 0x0E7, 0x0E8 },
                { 0x0E9, 0x0EA },
                { 0x0EB, 0x0EC },
                { 0x0ED, 0x0EE },
                { 0x0EF, 0x0F0 },
                { 0x0F1, 0x0F2 },
                { 0x0F3, 0x0F4 },
                { 0x0F5, 0x0F6 },
                { 0x0F7, 0x0F8 },
                { 0x0F9, 0x0FA },
                { 0x0FB, 0x0FC },
                { 0x0FD, 0x0FE },
                { 0x0FF, 0x100 },
                { 0x101, 0xFFF },
                
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
        
//        .data = {
//            'h','e','l','l','o',
//        },
    };
};

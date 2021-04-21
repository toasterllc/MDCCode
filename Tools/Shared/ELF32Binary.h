#pragma once
#include <sys/stat.h>
#include <sys/mman.h>
#include <vector>
#include "Enum.h"
#include "Mmap.h"

class ELF32Binary {
public:
    Enum(uint32_t, SectionType, SectionTypes,
        NUL         = 0x00000000,
        PROGBITS    = 0x00000001,
        SYMTAB	    = 0x00000002,
        STRTAB	    = 0x00000003,
        RELA	    = 0x00000004,
        HASH	    = 0x00000005,
        DYNAMIC	    = 0x00000006,
        NOTE	    = 0x00000007,
        NOBITS	    = 0x00000008,
        REL		    = 0x00000009,
        SHLIB	    = 0x0000000A,
        DYNSYM	    = 0x0000000B,
        LOPROC	    = 0x70000000,
        HIPROC	    = 0x7FFFFFFF,
        LOUSER	    = 0x80000000,
        HIUSER	    = 0xFFFFFFFF,
    );
    
    Enum(uint32_t, SectionFlag, SectionFlags,
        WRITE       = 0x00000001,
        ALLOC       = 0x00000002,
        EXECINSTR   = 0x00000004,
        MASKPROC    = 0xF0000000,
    );
    
    struct Section {
        size_t idx;
        std::string name;
        SectionType type;
        SectionFlag flags;
        uint32_t addr;
        uint32_t off;
        uint32_t size;
        uint32_t align;
    };
    
    // Throws on error
    ELF32Binary(const char* path) :
    _mmap(path) {
        // Validate the magic number
        struct MagicNum { uint8_t b[4]; };
        const MagicNum expected = {0x7F, 'E', 'L', 'F'};
        MagicNum mn = _read<MagicNum>(0);
        if (memcmp(expected.b, mn.b, sizeof(expected.b)))
            throw std::runtime_error("bad magic number");
        
        // Verify that we have an ELF32 binary
        ELF32Header header = _read<ELF32Header>(0);
        if (header.e_ident[ELFIdentIdxs::CLASS] != ELFClasses::CLASS32)
            throw std::runtime_error("not an ELF32 binary");
        
        _entryPointAddr = header.e_entry;
    }
    
    uint32_t entryPointAddr() {
        return _entryPointAddr;
    }
    
    // Throws on error
    std::vector<Section> sections() {
        const ELF32Header ehdr = _read<ELF32Header>(0);
        const ELF32SectionHeader strhdr = _read<ELF32SectionHeader>(ehdr.e_shoff + ehdr.e_shstrndx*sizeof(ELF32SectionHeader));
        const size_t sectionCount = ehdr.e_shnum;
        std::vector<Section> sections;
        for (size_t i=0; i<sectionCount; i++) {
            const ELF32SectionHeader shdr = _read<ELF32SectionHeader>(ehdr.e_shoff + i*sizeof(ELF32SectionHeader));
            Section s;
            s.idx = i;
            s.name = _readString(strhdr.sh_offset + shdr.sh_name);
            s.type = (SectionType)shdr.sh_type;
            s.flags = shdr.sh_flags;
            s.addr = shdr.sh_addr;
            s.off = shdr.sh_offset;
            s.size = shdr.sh_size;
            s.align = shdr.sh_addralign;
            sections.push_back(s);
        }
        return sections;
    }
    
    void* sectionData(const Section& s) {
        _assertCanRead(s.off, s.size);
        return _mmap.data()+s.off;
    }
    
private:
    struct ELF32Header {
        unsigned char e_ident[16];
        uint16_t e_type;
        uint16_t e_machine;
        uint32_t e_version;
        uint32_t e_entry;
        uint32_t e_phoff;
        uint32_t e_shoff;
        uint32_t e_flags;
        uint16_t e_ehsize;
        uint16_t e_phentsize;
        uint16_t e_phnum;
        uint16_t e_shentsize;
        uint16_t e_shnum;
        uint16_t e_shstrndx;
    };
    
    struct ELF32SectionHeader {
        uint32_t sh_name;
        uint32_t sh_type;
        uint32_t sh_flags;
        uint32_t sh_addr;
        uint32_t sh_offset;
        uint32_t sh_size;
        uint32_t sh_link;
        uint32_t sh_info;
        uint32_t sh_addralign;
        uint32_t sh_entsize;
    };
    
    Enum(uint8_t, ELFIdentIdx, ELFIdentIdxs,
        MAG0        = 0,
        MAG1        = 1,
        MAG2        = 2,
        MAG3        = 3,
        CLASS       = 4,
        DATA        = 5,
        VERSION     = 6,
        PAD         = 7,
    );
    
    Enum(uint8_t, ELFClass, ELFClasses,
        CLASSNONE   = 0,
        CLASS32     = 1,
        CLASS64     = 2,
    );
    
    void _assertCanRead(size_t off, size_t len) {
        if (off > _mmap.len()) throw std::runtime_error("attempt to read past data");
        if (_mmap.len()-off < len) throw std::runtime_error("attempt to read past data");
    }
    
    // _read: Verify that we have enough bytes to return a `T` from offset `off`
    //   - Throws on error
    //   - Returns a copy of the data (rather than a direct pointer) so that we don't have to worry about alignment
    template <typename T>
    T _read(size_t off) {
        _assertCanRead(off, sizeof(T));
        T r;
        memcpy(&r, _mmap.data()+off, sizeof(T));
        return r;
    }
    
    std::string _readString(size_t off) {
        std::string str;
        for (;; off++) {
            char c = _read<char>(off);
            if (!c) break;
            str.push_back(c);
        }
        return str;
    }
    
    Mmap<uint8_t> _mmap;
    uint32_t _entryPointAddr = 0;
};

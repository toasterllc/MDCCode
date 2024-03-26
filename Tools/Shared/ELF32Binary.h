#pragma once
#include <sys/stat.h>
#include <sys/mman.h>
#include <vector>
#include "Code/Lib/Toastbox/Mmap.h"
#include "Code/Lib/Toastbox/RuntimeError.h"

class ELF32Binary {
public:
    enum class SectionType : uint32_t {
        SHT_NUL             = 0x00000000,
        SHT_PROGBITS        = 0x00000001,
        SHT_SYMTAB	        = 0x00000002,
        SHT_STRTAB	        = 0x00000003,
        SHT_RELA	        = 0x00000004,
        SHT_HASH	        = 0x00000005,
        SHT_DYNAMIC	        = 0x00000006,
        SHT_NOTE	        = 0x00000007,
        SHT_NOBITS	        = 0x00000008,
        SHT_REL		        = 0x00000009,
        SHT_SHLIB	        = 0x0000000A,
        SHT_DYNSYM	        = 0x0000000B,
        SHT_INIT_ARRAY      = 0x0000000E,
        SHT_FINI_ARRAY      = 0x0000000F,
        SHT_LOPROC	        = 0x70000000,
        SHT_HIPROC	        = 0x7FFFFFFF,
        SHT_LOUSER	        = 0x80000000,
        SHT_HIUSER	        = 0xFFFFFFFF,
    };
    
    enum class SegmentType : uint32_t {
        PT_NULL             = 0x00000000,
        PT_LOAD             = 0x00000001,
        PT_DYNAMIC          = 0x00000002,
        PT_INTERP           = 0x00000003,
        PT_NOTE             = 0x00000004,
        PT_SHLIB            = 0x00000005,
        PT_PHDR             = 0x00000006,
        PT_LOPROC           = 0x70000000,
        PT_HIPROC           = 0x7FFFFFFF,
    };
    
    enum class SectionFlags : uint32_t {
        SHF_WRITE           = 0x00000001,
        SHF_ALLOC           = 0x00000002,
        SHF_EXECINSTR       = 0x00000004,
        SHF_MASKPROC        = 0xF0000000,
    };
    
    struct Section {
        size_t idx          = 0;
        std::string name    = {};
        SectionType type    = (SectionType)0;
        SectionFlags flags  = (SectionFlags)0;
        uint32_t vaddr      = 0;
        uint32_t paddr      = 0;
        uint32_t off        = 0;
        uint32_t size       = 0;
        uint32_t align      = 0;
    };
    
    struct Segment {
        SegmentType type                = (SegmentType)0;
        uint32_t vaddr                  = 0;
        uint32_t paddr                  = 0;
        uint32_t off                    = 0;
        uint32_t filesize               = 0;
        uint32_t memsize                = 0;
        uint32_t align                  = 0;
        std::vector<Section> sections   = {};
    };
    
    // Throws on error
    ELF32Binary(const std::filesystem::path& path) :
    _mmap(path) {
        // Validate the magic number
        struct MagicNum { uint8_t b[4]; };
        const MagicNum expected = {0x7F, 'E', 'L', 'F'};
        MagicNum mn = _read<MagicNum>(0);
        if (memcmp(expected.b, mn.b, sizeof(expected.b)))
            throw std::runtime_error("bad magic number");
        
        // Verify that we have an ELF32 binary
        _Header header = _read<_Header>(0);
        if (header.e_ident[(uint8_t)ELFIdentIdx::EI_CLASS] != (uint8_t)ELFClass::ELFCLASS32)
            throw std::runtime_error("not an ELF32 binary");
        
        _entryPointAddr = header.e_entry;
    }
    
    uint32_t entryPointAddr() const {
        return _entryPointAddr;
    }
    
    // Throws on error
    std::vector<Segment> segments() const {
        const _Header hdr = _read<_Header>(0);
        if (hdr.e_phentsize != sizeof(_SegmentHeader)) {
            throw Toastbox::RuntimeError("invalid e_phentsize (expected: %ju, got %ju)",
                (uintmax_t)sizeof(_SegmentHeader), (uintmax_t)hdr.e_phentsize);
        }
        
        std::vector<Segment> segs;
        const _SectionHeader strhdr = _read<_SectionHeader>(hdr.e_shoff + hdr.e_shstrndx*sizeof(_SectionHeader));
        const size_t segmentCount = hdr.e_phnum;
        const size_t sectionCount = hdr.e_shnum;
        for (size_t i=0; i<segmentCount; i++) {
            const _SegmentHeader seghdr = _read<_SegmentHeader>(hdr.e_phoff + i*sizeof(_SegmentHeader));
            
            if (seghdr.p_filesz > seghdr.p_memsz) {
                throw Toastbox::RuntimeError("segment p_filesz (%ju) > p_memsz (%ju)",
                    (uintmax_t)seghdr.p_filesz, (uintmax_t)seghdr.p_memsz);
            }
            
            Segment seg = {
                .type       = (SegmentType)seghdr.p_type,
                .vaddr      = seghdr.p_vaddr,
                .paddr      = seghdr.p_paddr,
                .off        = seghdr.p_offset,
                .filesize   = seghdr.p_filesz,
                .memsize    = seghdr.p_memsz,
                .align      = seghdr.p_align,
            };
            
            // Find all sections that lie in this segment
            for (size_t i=0; i<sectionCount; i++) {
                const _SectionHeader sechdr = _read<_SectionHeader>(hdr.e_shoff + i*sizeof(_SectionHeader));
                // Ignore sections that aren't within the current segment
                if (!(sechdr.sh_addr>=seg.vaddr && sechdr.sh_addr<(seg.vaddr+seghdr.p_memsz))) continue;
                
                seg.sections.push_back(Section{
                    .idx    = i,
                    .name   = _readString(strhdr.sh_offset + sechdr.sh_name),
                    .type   = (SectionType)sechdr.sh_type,
                    .flags  = (SectionFlags)sechdr.sh_flags,
                    .vaddr  = sechdr.sh_addr,
                    .paddr  = seghdr.p_paddr + (sechdr.sh_offset-seghdr.p_offset),
                    .off    = sechdr.sh_offset,
                    .size   = sechdr.sh_size,
                    .align  = sechdr.sh_addralign,
                });
            }
            
            segs.push_back(seg);
        }
        
        return segs;
    }
    
    template <typename T_Fn>
    void enumerateLoadableSections(T_Fn fn) {
        auto segs = segments();
        for (const auto& seg : segs) {
            for (const auto& sec : seg.sections) {
                // Ignore NOBITS sections (NOBITS = "occupies no space in the file"),
                if (sec.type == SectionType::SHT_NOBITS) continue;
                // Ignore non-ALLOC sections (ALLOC = "occupies memory during process execution")
                if (!((uint32_t)sec.flags & (uint32_t)SectionFlags::SHF_ALLOC)) continue;
                const size_t size = sec.size;
                if (!size) continue; // Ignore sections with zero length
                const uint32_t paddr = sec.paddr;
                const uint32_t vaddr = sec.vaddr;
                const void* data = sectionData(sec);
                
                fn(paddr, vaddr, data, size, sec.name.c_str());
            }
        }
    }
    
//    // Throws on error
//    std::vector<Section> sections() const {
//        const _Header hdr = _read<_Header>(0);
//        if (hdr.e_phentsize != sizeof(_SegmentHeader)) {
//            throw Toastbox::RuntimeError("invalid e_phentsize (expected: %ju, got %ju)",
//                (uintmax_t)sizeof(_SegmentHeader), (uintmax_t)hdr.e_phentsize);
//        }
//        
//        std::vector<Section> secs;
//        const _SectionHeader strhdr = _read<_SectionHeader>(hdr.e_shoff + hdr.e_shstrndx*sizeof(_SectionHeader));
//        const size_t sectionCount = hdr.e_shnum;
//        for (size_t i=0; i<sectionCount; i++) {
//            const _SectionHeader sechdr = _read<_SectionHeader>(hdr.e_shoff + i*sizeof(_SectionHeader));
//            
//            secs.push_back(Section{
//                .idx    = i,
//                .name   = _readString(strhdr.sh_offset + sechdr.sh_name),
//                .type   = (SectionType)sechdr.sh_type,
//                .flags  = (SectionFlags)sechdr.sh_flags,
//                .vaddr  = sechdr.sh_addr,
//                .paddr  = seghdr.p_paddr + (sechdr.sh_offset-seghdr.p_offset),
//                .off    = sechdr.sh_offset,
//                .size   = sechdr.sh_size,
//                .align  = sechdr.sh_addralign,
//            });
//        }
//        
//        return secs;
//        
//        
//        
//        std::vector<Segment> segs;
//        const _SectionHeader strhdr = _read<_SectionHeader>(hdr.e_shoff + hdr.e_shstrndx*sizeof(_SectionHeader));
//        const size_t segmentCount = hdr.e_phnum;
//        const size_t sectionCount = hdr.e_shnum;
//        for (size_t i=0; i<segmentCount; i++) {
//            const _SegmentHeader seghdr = _read<_SegmentHeader>(hdr.e_phoff + i*sizeof(_SegmentHeader));
//            
//            if (seghdr.p_filesz > seghdr.p_memsz) {
//                throw Toastbox::RuntimeError("segment p_filesz (%ju) > p_memsz (%ju)",
//                    (uintmax_t)seghdr.p_filesz, (uintmax_t)seghdr.p_memsz);
//            }
//            
//            Segment seg = {
//                .type       = (SegmentType)seghdr.p_type,
//                .vaddr      = seghdr.p_vaddr,
//                .paddr      = seghdr.p_paddr,
//                .off        = seghdr.p_offset,
//                .filesize   = seghdr.p_filesz,
//                .memsize    = seghdr.p_memsz,
//                .align      = seghdr.p_align,
//            };
//            
//            // Find all sections that lie in this segment
//            for (size_t i=0; i<sectionCount; i++) {
//                const _SectionHeader sechdr = _read<_SectionHeader>(hdr.e_shoff + i*sizeof(_SectionHeader));
//                // Ignore sections that aren't within the current segment
//                if (!(sechdr.sh_addr>=seg.vaddr && sechdr.sh_addr<(seg.vaddr+seghdr.p_memsz))) continue;
//                
//                seg.sections.push_back(Section{
//                    .idx    = i,
//                    .name   = _readString(strhdr.sh_offset + sechdr.sh_name),
//                    .type   = (SectionType)sechdr.sh_type,
//                    .flags  = (SectionFlags)sechdr.sh_flags,
//                    .vaddr  = sechdr.sh_addr,
//                    .paddr  = _physAddrForFileOffset(hdr, sechdr.sh_offset),
//                    .off    = sechdr.sh_offset,
//                    .size   = sechdr.sh_size,
//                    .align  = sechdr.sh_addralign,
//                });
//            }
//            
//            segs.push_back(seg);
//        }
//        
//        return segs;
//    }
    
//    // Throws on error
//    std::vector<Section> sections() {
//        const _Header hdr = _read<_Header>(0);
//        const ELF32SectionHeader strhdr = _read<ELF32SectionHeader>(hdr.e_shoff + hdr.e_shstrndx*sizeof(ELF32SectionHeader));
//        const size_t sectionCount = hdr.e_shnum;
//        std::vector<Section> sections;
//        for (size_t i=0; i<sectionCount; i++) {
//            const ELF32SectionHeader shdr = _read<ELF32SectionHeader>(hdr.e_shoff + i*sizeof(ELF32SectionHeader));
//            Section s;
//            s.idx = i;
//            s.name = _readString(strhdr.sh_offset + shdr.sh_name);
//            s.type = (SectionType)shdr.sh_type;
//            s.flags = shdr.sh_flags;
//            s.addr = shdr.sh_addr;
//            s.off = shdr.sh_offset;
//            s.size = shdr.sh_size;
//            s.align = shdr.sh_addralign;
//            sections.push_back(s);
//        }
//        return sections;
//    }
    
    const void* sectionData(const Section& s) const {
        _assertCanRead(s.off, s.size);
        return _mmap.data()+s.off;
    }
    
//    std::unique_ptr<uint8_t[]> segmentData(const Segment& seg) const {
//        // We can't just return a pointer to the mmap'd data because the ELF32 spec
//        // allows a segment's p_filesz < p_memsz, in which case the 'extra' p_memsz
//        // bytes must be zero.
//        // In this case, we need to read `p_memsz` bytes but only `p_filesz` bytes
//        // are valid in the mmap'd data, so we have to create our own allocation
//        // with the remaining bytes zeroed.
//        _assertCanRead(seg.off, seg.filesize);
//        auto data = std::make_unique<uint8_t[]>(seg.size); // automatically zeroes entire array, which we require!
//        memcpy(data.get(), _mmap.data()+seg.off, seg.filesize);
//        return data;
//    }
    
    
private:
    struct _Header {
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
    
    struct _SegmentHeader {
        uint32_t p_type;
        uint32_t p_offset;
        uint32_t p_vaddr;
        uint32_t p_paddr;
        uint32_t p_filesz;
        uint32_t p_memsz;
        uint32_t p_flags;
        uint32_t p_align;
    };
    
    struct _SectionHeader {
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
    
    enum class ELFIdentIdx : uint8_t {
        EI_MAG0         = 0,
        EI_MAG1         = 1,
        EI_MAG2         = 2,
        EI_MAG3         = 3,
        EI_CLASS        = 4,
        EI_DATA         = 5,
        EI_VERSION      = 6,
        EI_PAD          = 7,
    };
    
    enum class ELFClass : uint8_t {
        ELFCLASSNONE    = 0,
        ELFCLASS32      = 1,
        ELFCLASS64      = 2,
    };
    
    void _assertCanRead(size_t off, size_t len) const {
        if (off > _mmap.len()) throw std::runtime_error("attempt to read past data");
        if (_mmap.len()-off < len) throw std::runtime_error("attempt to read past data");
    }
    
    // _read: Verify that we have enough bytes to return a `T` from offset `off`
    //   - Throws on error
    //   - Returns a copy of the data (rather than a direct pointer) so that we don't have to worry about alignment
    template <typename T>
    T _read(size_t off) const {
        _assertCanRead(off, sizeof(T));
        T r;
        memcpy(&r, _mmap.data()+off, sizeof(T));
        return r;
    }
    
    std::string _readString(size_t off) const {
        std::string str;
        for (;; off++) {
            char c = _read<char>(off);
            if (!c) break;
            str.push_back(c);
        }
        return str;
    }
    
//    // _physAddrForFileOffset: find the segment that contains `off`,
//    // and calculate the physical address
//    uint32_t _physAddrForFileOffset(const _Header& hdr, uint32_t off) const {
//        const size_t segmentCount = hdr.e_phnum;
//        for (size_t i=0; i<segmentCount; i++) {
//            const _SegmentHeader seghdr = _read<_SegmentHeader>(hdr.e_phoff + i*sizeof(_SegmentHeader));
//            if (off>=seghdr.p_offset && off<(seghdr.p_offset+seghdr.p_filesz)) {
//                return p.p_paddr + (off - seghdr.p_offset);
//            }
//        }
//        throw Toastbox::RuntimeError("failed to get physical address for file offset 0x%jx", (uintmax_t)off);
//    }
    
    Toastbox::Mmap _mmap;
    uint32_t _entryPointAddr = 0;
};

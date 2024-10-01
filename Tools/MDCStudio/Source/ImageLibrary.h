#pragma once
#include <forward_list>
#include <set>
#include "Code/Lib/Toastbox/IterAny.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/Img.h"
#include "RecordStore.h"
#include "ImageOptions.h"
#include "ImageThumb.h"
#include "Object.h"

namespace MDCStudio {

struct [[gnu::packed]] ImageInfo {
    Img::Id id = 0;
    uint64_t addrFull = 0;
    uint64_t addrThumb = 0;
    
    Time::Instant timestamp = 0;
    
    uint16_t imageWidth = 0;
    uint16_t imageHeight = 0;
    
    uint16_t coarseIntTime = 0;
    uint16_t analogGain = 0;
    
    uint16_t batteryLevelMv = 0;
    uint16_t _pad[3] = {};
    
    // illumEst: estimated illuminant
    double illumEst[3] = {0,0,0};
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[128];
};

static_assert(!(sizeof(ImageInfo) % 8)); // Ensure that ImageInfo is a multiple of 8 bytes

struct [[gnu::packed]] ImageStatus {
    uint32_t flags = 0;
    // loadCount: indicator for when the thumbnail has been re-rendered
    // Used to determine whether a cache is stale relative to the ImageRecord's thumbnail
    // 0 indicates that the thumbnail hasn't been loaded yet
    uint32_t loadCount = 0;
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[128];
};

static_assert(!(sizeof(ImageStatus) % 8)); // Ensure that ImageStatus is a multiple of 8 bytes

struct [[gnu::packed]] ImageRecord {
    static constexpr uint32_t Version = 0;
    
    ImageInfo info;
    ImageStatus status;
    ImageOptions options;
    
    // _pad: necessary for our thumbnail compression to keep our `thumb` member aligned
    // to a 16-byte boundary.
    uint8_t _pad[8];
    
    ImageThumb thumb;
};

// Ensure that ImageRecord is a multiple of 8 bytes
static_assert(!(sizeof(ImageRecord) % 8));

// Ensure that the thumbnail is aligned to a 4-pixel boundary
static_assert(!(offsetof(ImageRecord, thumb) % 16));

struct ImageLibrary : Object, RecordStore<ImageRecord>, std::mutex {
    using RecordStore::RecordStore;
    using IterAny = Toastbox::IterAny<RecordRefConstIter>;
    
    struct Event : Object::Event {
        enum class Type {
            Add,
            Remove,
            Clear,
            ChangeProperty,
            ChangeThumbnail,
        };
        
        Type type = Type::Add;
        std::set<RecordStrongRef> records;
    };
    
    struct Descriptor {
        const char* name = nullptr;
        size_t thumbWidth = 0;
        size_t thumbHeight = 0;
        size_t chunkRecordCap = 0; // The number of ImageRecords per chunk
    };
    
    struct Descriptors {
        static constexpr const inline Descriptor  Small  = { "Small",  128,  72, 2048 };
        static constexpr const inline Descriptor  Medium = { "Medium", 256, 144,  512 };
        static constexpr const inline Descriptor  Large  = { "Large",  384, 216,  128 };
        static constexpr const inline Descriptor* All[] = {
            &Small,
            &Medium,
            &Large,
        };
    };
    
    static constexpr size_t RecordSizeForDescriptor(const Descriptor& desc) {
        return sizeof(ImageRecord) + desc.thumbWidth*desc.thumbHeight;
    }
    
    static const Descriptor& DescriptorForRecordSize(size_t recordSize) {
        switch (recordSize) {
        case RecordSizeForDescriptor(Descriptors::Small):   return Descriptors::Small;
        case RecordSizeForDescriptor(Descriptors::Medium):  return Descriptors::Medium;
        case RecordSizeForDescriptor(Descriptors::Large):   return Descriptors::Large;
        default: abort();
        }
    }
    
//    static size_t DataLength(const Descriptor& desc) {
//        // Compressed thumbnail data length is one byte per pixel
//        return desc.width * desc.height;
//    }
    
    static IterAny BeginSorted(const ImageLibrary& lib, bool sortNewestFirst) {
        if (sortNewestFirst) return lib.rbegin();
        else                 return lib.begin();
    }
    
    static IterAny EndSorted(const ImageLibrary& lib, bool sortNewestFirst) {
        if (sortNewestFirst) return lib.rend();
        else                 return lib.end();
    }
    
    void read(const RecordStore::Path& dir, const ImageLibrary::Descriptor& desc) {
        try {
            const size_t recordSize = sizeof(ImageRecord) + ImageThumb::DataLength(desc);
            std::ifstream f = RecordStore::read({
                .path = dir,
                .recordSize = recordSize,
                .chunkRecordCap = desc.chunkRecordCap,
            });
            _StateRead(f, _state);
        } catch (const std::exception& e) {
            printf("Recreating ImageLibrary; cause: %s\n", e.what());
        }
    }
    
//    void read(const RecordStore::Config& cfg) {
//        try {
//            std::ifstream f = RecordStore::read(cfg);
//            _StateRead(f, _state);
//        } catch (const std::exception& e) {
//            printf("Recreating ImageLibrary; cause: %s\n", e.what());
//        }
//    }
    
    void write() {
        std::ofstream f = RecordStore::write();
        _StateWrite(f, _state);
    }
    
    void add(size_t count) {
        RecordStore::add(count);
        
        // Notify observers that we changed
        Event ev;
        ev.type = Event::Type::Add;
        for (auto i=end()-count; i!=end(); i++) {
            ev.records.insert(*i);
        }
        Object::observersNotify(ev);
    }
    
    void remove(RecordRefConstIter begin, RecordRefConstIter end) {
        Event ev;
        ev.type = Event::Type::Remove;
        for (auto i=begin; i!=end; i++) {
            ev.records.insert(*i);
        }
        
        RecordStore::remove(begin, end);
        // Notify observers that we changed
        Object::observersNotify(ev);
    }
    
    void remove(const std::set<RecordStrongRef>& recs) {
        RecordStore::remove(recs);
        
        // Notify observers that we changed
        Event ev;
        ev.type = Event::Type::Remove;
        ev.records = recs;
        Object::observersNotify(ev);
    }
    
    void clear() {
        RecordStore::clear();
        _state = {};
        
        // Notify observers that we changed
        Event ev;
        ev.type = Event::Type::Clear;
        Object::observersNotify(ev);
    }
    
    RecordRefConstIter find(const RecordRef& ref) {
        return RecordStore::Find(begin(), end(), ref);
    }
    
    void imageIdEnd(Img::Id x) { _state.imageIdEnd = x; }
    Img::Id imageIdEnd() const { return _state.imageIdEnd; }
    
    static IterAny Find(IterAny begin, IterAny end, const RecordRef& ref) {
        if (begin.fwd()) {
            return RecordStore::Find<true>(begin.fwdGet(), end.fwdGet(), ref);
        } else {
            return RecordStore::Find<false>(begin.revGet(), end.revGet(), ref);
        }
    }
    
    void observersNotify(Event::Type type, std::set<RecordStrongRef> records) {
        Event ev;
        ev.type = type;
        ev.records = std::move(records);
        Object::observersNotify(ev);
    }
    
    static constexpr uint32_t _Version = 0;
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
        uint64_t imageIdEnd = 0;
        
        // Make sure the type of `imageIdEnd` matches Img::Id
        static_assert(std::is_same_v<decltype(imageIdEnd), Img::Id>);
    };
    
    struct _State {
        Img::Id imageIdEnd = 0;
        const ImageLibrary::Descriptor* desc = nullptr;
    };
    
    static void _StateRead(std::ifstream& f, _State& state) {
        try {
            state = {};
            
            _SerializedState serialized;
            f.read((char*)&serialized, sizeof(serialized));
            
            if (serialized.version != _Version) {
                throw Toastbox::RuntimeError("invalid state version (expected: 0x%jx, got: 0x%jx)",
                    (uintmax_t)_Version,
                    (uintmax_t)serialized.version
                );
            }
            
            state.imageIdEnd = serialized.imageIdEnd;
        
        } catch (...) {
            state = {};
            throw;
        }
    }
    
    static void _StateWrite(std::ofstream& f, const _State& state) {
        const _SerializedState serialized = {
            .version = _Version,
            .imageIdEnd = state.imageIdEnd,
        };
        f.write((char*)&serialized, sizeof(serialized));
    }
    
    _State _state;
};
using ImageLibraryPtr = SharedPtr<ImageLibrary>;

using ImageRecordIter = ImageLibrary::RecordRefConstIter;
using ImageRecordIterAny = Toastbox::IterAny<ImageRecordIter>;
using ImageRecordPtr = ImageLibrary::RecordStrongRef;
using ImageSet = std::set<ImageRecordPtr>;

// ImageSetsOverlap: returns whether there's an intersection between a and b.
// This is templated so we can compare between std::set<RecordRef> and std::set<RecordStrongRef>
template<typename T_A, typename T_B>
bool ImageSetsOverlap(const T_A& a, const T_B& b) {
    ImageSet r;
    for (const ImageRecordPtr& x : a) {
        if (b.find(x) != b.end()) {
            return true;
        }
    }
    return false;
}

inline ImageSet ImageSetsUnion(const ImageSet& a, const ImageSet& b) {
    ImageSet r = a;
    r.insert(b.begin(), b.end());
    return r;
}

inline ImageSet ImageSetsSubtract(const ImageSet& a, const ImageSet& b) {
    ImageSet r;
    for (const ImageRecordPtr& x : a) {
        if (b.find(x) == b.end()) {
            r.insert(x);
        }
    }
    return r;
}

inline ImageSet ImageSetsIntersect(const ImageSet& a, const ImageSet& b) {
    ImageSet r;
    for (const ImageRecordPtr& x : a) {
        if (b.find(x) != b.end()) {
            r.insert(x);
        }
    }
    return r;
}

inline ImageSet ImageSetsXOR(const ImageSet& a, const ImageSet& b) {
    ImageSet r;
    for (const ImageRecordPtr& x : a) {
        if (b.find(x) == b.end()) {
            r.insert(x);
        }
    }
    
    for (const ImageRecordPtr& x : b) {
        if (a.find(x) == a.end()) {
            r.insert(x);
        }
    }
    
    return r;
}

} // namespace MDCStudio

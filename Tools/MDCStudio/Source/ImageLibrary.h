#pragma once
#include <forward_list>
#include <set>
#include "Toastbox/IterAny.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/Img.h"
#include "RecordStore.h"
#include "ImageOptions.h"
#include "ImageThumb.h"
#include "ImageUtil.h"

namespace MDCStudio {

struct ImageFlags {
    static constexpr uint64_t Loaded = 1<<0;
};

struct [[gnu::packed]] ImageInfo {
    Img::Id id = 0;
    uint64_t addrFull = 0;
    uint64_t addrThumb = 0;
    uint64_t flags = 0;
    
    Time::Instant timestamp = 0;
    
    uint16_t imageWidth = 0;
    uint16_t imageHeight = 0;
    
    uint16_t coarseIntTime = 0;
    uint16_t analogGain = 0;
    
    // illumEst: estimated illuminant
    double illumEst[3] = {0,0,0};
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[128];
};

static_assert(!(sizeof(ImageInfo) % 8)); // Ensure that ImageInfo is a multiple of 8 bytes

struct [[gnu::packed]] ImageRecord {
    static constexpr uint32_t Version = 0;
    
    ImageInfo info;
    ImageOptions options;
//    // _pad: necessary for our thumbnail compression to keep our `thumb` member aligned
//    // to a 4-pixel boundary. Each row of the thumbnail is ThumbWidth bytes, and info+options consume 1 row  (where each row is 512 bytes)
//    uint8_t _pad[ImageThumb::ThumbWidth*3];
    
    ImageThumb thumb;
};

static_assert(!(sizeof(ImageRecord) % 8)); // Ensure that ImageRecord is a multiple of 8 bytes
//static_assert(!(offsetof(ImageRecord, thumb) % (ImageThumb::ThumbWidth*4)); // Ensure that the thumbnail is aligned to a 4-pixel boundary in the Y dimension

class ImageLibrary : public RecordStore<ImageRecord, 128>, public std::mutex {
public:
    using RecordStore::RecordStore;
    using IterAny = Toastbox::IterAny<RecordRefConstIter>;
    
    struct Event {
        enum class Type {
            Add,
            Remove,
            ChangeProperty,
            ChangeThumbnail,
        };
        
        Type type = Type::Add;
        std::set<RecordStrongRef> records;
    };
    
    using Observer = std::function<bool(const Event& ev)>;
    
    static IterAny BeginSorted(const ImageLibrary& lib, bool sortNewestFirst) {
        if (sortNewestFirst) return lib.rbegin();
        else                 return lib.begin();
    }
    
    static IterAny EndSorted(const ImageLibrary& lib, bool sortNewestFirst) {
        if (sortNewestFirst) return lib.rend();
        else                 return lib.end();
    }
    
    void read() {
        // Reset our state, as RecordStore::read() does
        _state = {};
        
        try {
            std::ifstream f = RecordStore::read();
            
            _SerializedState state;
            f.read((char*)&state, sizeof(state));
            
            if (state.version != _Version) {
                throw Toastbox::RuntimeError("invalid state version (expected: 0x%jx, got: 0x%jx)",
                    (uintmax_t)_Version,
                    (uintmax_t)state.version
                );
            }
            
        } catch (const std::exception& e) {
            printf("Recreating ImageLibrary; cause: %s\n", e.what());
        }
    }
    
    void write() {
        std::ofstream f = RecordStore::write();
        const _SerializedState state {
            .version = _Version,
        };
        f.write((char*)&state, sizeof(state));
    }
    
    void add(size_t count) {
        RecordStore::add(count);
        // Notify observers that we changed
        
        Event ev = { .type = Event::Type::Add };
        for (auto i=end()-count; i!=end(); i++) {
            ev.records.insert(*i);
        }
        notify(ev);
    }
    
    void remove(RecordRefConstIter begin, RecordRefConstIter end) {
        Event ev = { .type = Event::Type::Remove };
        for (auto i=begin; i!=end; i++) {
            ev.records.insert(*i);
        }
        
        RecordStore::remove(begin, end);
        // Notify observers that we changed
        notify(ev);
    }
    
    RecordRefConstIter find(const RecordRef& ref) {
        return RecordStore::Find(begin(), end(), ref);
    }
    
    static IterAny Find(IterAny begin, IterAny end, const RecordRef& ref) {
        if (begin.fwd()) {
            return RecordStore::Find<true>(begin.fwdGet(), end.fwdGet(), ref);
        } else {
            return RecordStore::Find<false>(begin.revGet(), end.revGet(), ref);
        }
    }
    
//    bool sortNewest() const {
//        return _sortNewest;
//    }
//    
//    void sortNewest(bool x) {
//        _sortNewest = x;
//        notifyChange({});
//    }
//    
//    Toastbox::IterAny<RecordRefConstIter> beginSorted() const {
//        if (_sortNewest) return rbegin();
//        else             return begin();
//    }
//    
//    Toastbox::IterAny<RecordRefConstIter> endSorted() const {
//        if (_sortNewest) return rbegin();
//        else             return begin();
//    }
    
//    RecordRefConstIter find(Img::Id id) {
//        RecordRefConstIter iter = std::lower_bound(begin(), end(), 0,
//            [&](const RecordRef& sample, auto) -> bool {
//                return sample->info.id < id;
//            });
//        
//        if (iter == end()) return end();
//        if ((*iter)->info.id != id) return end();
//        return iter;
//    }
//    
//    RecordStrongRef findStrong(Img::Id id) {
//        auto it = find(id);
//        if (it == end()) return {};
//        return *it;
//    }
    
    void observerAdd(Observer&& observer) {
        _state.observers.push_front(std::move(observer));
    }
    
    // notify(): notifies each observer of an event.
    // The notifications are delivered synchronously on the calling thread.
    // The ImageLibrary lock will therefore be held when events are delivered!
    void notify(const Event& ev) {
        auto prev = _state.observers.before_begin();
        for (auto it=_state.observers.begin(); it!=_state.observers.end();) {
            // Notify the observer; it returns whether it's still valid
            // If it's not valid (it returned false), remove it from the list
            if (!(*it)(ev)) {
                it = _state.observers.erase_after(prev);
            } else {
                prev = it;
                it++;
            }
        }
    }
    
    void notify(Event::Type type, std::set<RecordStrongRef> records) {
        Event ev = { .type = type };
        ev.records = std::move(records);
        notify(ev);
    }
    
private:
    static constexpr uint32_t _Version = 0;
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
    };
    
    struct {
        std::forward_list<Observer> observers;
    } _state;
};

using ImageRecordIter = ImageLibrary::RecordRefConstIter;
using ImageRecordIterAny = Toastbox::IterAny<ImageRecordIter>;
using ImageRecordPtr = ImageLibrary::RecordStrongRef;
using ImageSet = std::set<ImageRecordPtr>;

// ImageSetsOverlap: returns whether there's an intersection between a and b.
// This is templated so we can compare between std::set<RecordRef> and std::set<RecordStrongRef>
template <typename T_A, typename T_B>
bool ImageSetsOverlap(const T_A& a, const T_B& b) {
    ImageSet r;
    for (const ImageRecordPtr& x : a) {
        if (b.find(x) != b.end()) {
            return true;
        }
    }
    return false;
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

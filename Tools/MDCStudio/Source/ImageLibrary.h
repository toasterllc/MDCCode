#pragma once
#include <forward_list>
#include <set>
#include "Code/Shared/Time.h"
#include "RecordStore.h"
#include "Code/Shared/Img.h"
#include "Tools/Shared/Lockable.h"

namespace MDCStudio {

struct [[gnu::packed]] ImageInfo {
    Img::Id id = 0;
    
    // addr: address of the full-size image on the device
    uint64_t addr = 0;
    
    Time::Instant timestamp = 0;
    
    uint16_t imageWidth = 0;
    uint16_t imageHeight = 0;
    
    uint16_t coarseIntTime = 0;
    uint16_t analogGain = 0;
    
    // illumEst: estimated illuminant
    double illumEst[3] = {0,0,0};
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[64] = {};
};

static_assert(!(sizeof(ImageInfo) % 8)); // Ensure that ImageInfo is a multiple of 8 bytes

struct [[gnu::packed]] ImageOptions {
    enum class Rotation : uint8_t {
        None,
        Clockwise90,
        Clockwise180,
        Clockwise270,
    };
    
    enum class Corner : uint8_t {
        BottomRight,
        BottomLeft,
        TopLeft,
        TopRight,
    };
    
    Rotation rotation = Rotation::None;
    bool defringe = false;
    bool reconstructHighlights = false;
    struct [[gnu::packed]] {
        bool show = false;
        Corner corner = Corner::BottomRight;
    } timestamp;
    uint8_t _pad[3];
    
    float exposure = 0;
    float saturation = 0;
    float brightness = 0;
    float contrast = 0;
    struct {
        float amount = 0;
        float radius = 0;
    } localContrast;
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[64] = {};
};

static_assert(!(sizeof(ImageOptions) % 8)); // Ensure that ImageOptions is a multiple of 8 bytes

struct [[gnu::packed]] ImageThumb {
//    static constexpr size_t ThumbWidth      = 288;
//    static constexpr size_t ThumbHeight     = 162;

//    static constexpr size_t ThumbWidth      = 400;
//    static constexpr size_t ThumbHeight     = 225;
    
//    static constexpr size_t ThumbWidth      = 432;
//    static constexpr size_t ThumbHeight     = 243;
    
//    static constexpr size_t ThumbWidth      = 480;
//    static constexpr size_t ThumbHeight     = 270;
    
    static constexpr size_t ThumbWidth      = 512;
    static constexpr size_t ThumbHeight     = 288;
    
//    static constexpr size_t ThumbWidth      = 576;
//    static constexpr size_t ThumbHeight     = 324;
    
//    static constexpr size_t ThumbWidth      = 2304;
//    static constexpr size_t ThumbHeight     = 1296;
    
    static constexpr size_t ThumbPixelSize  = 3;
    
    uint8_t data[ThumbWidth*ThumbHeight*ThumbPixelSize];
};

static_assert(!(sizeof(ImageThumb) % 8)); // Ensure that ImageThumb is a multiple of 8 bytes

struct [[gnu::packed]] ImageRecord {
    static constexpr uint32_t Version = 0;
    ImageInfo info;
    ImageOptions options;
    ImageThumb thumb;
};

static_assert(!(sizeof(ImageRecord) % 8)); // Ensure that ImageRecord is a multiple of 8 bytes

class ImageLibrary : public RecordStore<ImageRecord, 512> {
public:
    using RecordStore::RecordStore;
    
    struct Event {
        enum class Type {
            Add,
            Remove,
            Change,
        };
        
        Type type = Type::Add;
        std::set<RecordRef> records;
    };
    
    using Observer = std::function<bool(const Event& ev)>;
    
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
            
            _state.deviceImgIdEnd = state.deviceImgIdEnd;
            
        } catch (const std::exception& e) {
            printf("Recreating ImageLibrary; cause: %s\n", e.what());
        }
    }
    
    void write() {
        std::ofstream f = RecordStore::write();
        const _SerializedState state {
            .version = _Version,
            .deviceImgIdEnd = _state.deviceImgIdEnd,
        };
        f.write((char*)&state, sizeof(state));
    }
    
    void add() {
        Event ev = { .type = Event::Type::Add };
        for (auto i=reservedBegin(); i!=reservedEnd(); i++) {
            ev.records.insert(*i);
        }
        
        RecordStore::add();
        // Notify observers that we changed
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
    
    Img::Id deviceImgIdEnd() const {
        return _state.deviceImgIdEnd;
    }
    
    void setDeviceImgIdEnd(Img::Id id) {
        _state.deviceImgIdEnd = id;
    }
    
    // notify(): notifies each observer of an event.
    // The notifications are delivered synchronously on the calling thread.
    // The ImageLibraryPtr lock will therefore be held when events are delivered!
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
    
    void notifyChange(std::set<RecordRef> records) {
        Event ev = { .type = Event::Type::Change };
        ev.records = std::move(records);
        notify(ev);
    }
    
private:
    static constexpr uint32_t _Version = 0;
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
        Img::Id deviceImgIdEnd = 0;
    };
    
    struct {
        Img::Id deviceImgIdEnd = 0;
        std::forward_list<Observer> observers;
    } _state;
};

using ImageLibraryPtr = std::shared_ptr<MDCTools::Lockable<ImageLibrary>>;
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

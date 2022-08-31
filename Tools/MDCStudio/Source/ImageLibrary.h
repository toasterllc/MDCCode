#pragma once
#include <forward_list>
#include "RecordStore.h"
#include "Code/Shared/Img.h"
#include "Tools/Shared/Lockable.h"

namespace MDCStudio {

using ImageId = uint64_t;

struct [[gnu::packed]] ImageRef {
    static constexpr uint32_t Version = 0;
    
    enum Rotation : uint8_t {
        None,
        Clockwise90,
        Clockwise180,
        Clockwise270
    };
    
    ImageId id = 0;
    
    uint64_t timestamp = 0; // Unix time
    
    uint64_t addr = 0;
    
    uint16_t imageWidth = 0;
    uint16_t imageHeight = 0;
    uint8_t _pad[4] = {};
    
    uint32_t coarseIntTime = 0;
    uint32_t analogGain = 0;
    
    Rotation rotation = Rotation::None;
    uint8_t _pad2[7] = {};
    
    uint8_t _reserved[64] = {}; // So we can add fields without doing a big data migration
};

struct [[gnu::packed]] ImageThumb {
    
//    static constexpr size_t ThumbWidth      = 288;
//    static constexpr size_t ThumbHeight     = 162;

    static constexpr size_t ThumbWidth      = 400;
    static constexpr size_t ThumbHeight     = 225;
    
//    static constexpr size_t ThumbWidth      = 432;
//    static constexpr size_t ThumbHeight     = 243;
    
//    static constexpr size_t ThumbWidth      = 480;
//    static constexpr size_t ThumbHeight     = 270;
    
//    static constexpr size_t ThumbWidth      = 512;
//    static constexpr size_t ThumbHeight     = 288;
    
//    static constexpr size_t ThumbWidth      = 576;
//    static constexpr size_t ThumbHeight     = 324;
    
    static constexpr size_t ThumbPixelSize  = 3;
    
    ImageRef ref;
    uint8_t thumb[ThumbWidth*ThumbHeight*ThumbPixelSize];
};

class ImageLibrary : public RecordStore<ImageRef::Version, ImageThumb, 512> {
public:
    using RecordStore::RecordStore;
    using Observer = std::function<bool()>;
    
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
        RecordStore::add();
        // Notify observers that we changed
        _notifyObservers();
    }
    
    void remove(RecordRefConstIter begin, RecordRefConstIter end) {
        RecordStore::remove(begin, end);
        // Notify observers that we changed
        _notifyObservers();
    }
    
    RecordRefConstIter find(ImageId id) {
        RecordRefConstIter iter = std::lower_bound(begin(), end(), 0,
            [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
                return recordGet(sample)->ref.id < id;
            });
        
        if (iter == end()) return end();
        if (recordGet(iter)->ref.id != id) return end();
        return iter;
    }
    
    void addObserver(Observer&& observer) {
        _state.observers.push_front(std::move(observer));
    }
    
    Img::Id deviceImgIdEnd() const {
        return _state.deviceImgIdEnd;
    }
    
    void setDeviceImgIdEnd(Img::Id id) {
        _state.deviceImgIdEnd = id;
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
    
    void _notifyObservers() {
        auto prev = _state.observers.before_begin();
        for (auto it=_state.observers.begin(); it!=_state.observers.end();) {
            // Notify the observer; it returns whether it's still valid
            // If it's not valid (it returned false), remove it from the list
            if (!(*it)()) {
                it = _state.observers.erase_after(prev);
            } else {
                prev = it;
                it++;
            }
        }
    }
};

using ImageLibraryPtr = std::shared_ptr<MDCTools::Lockable<ImageLibrary>>;

} // namespace MDCStudio

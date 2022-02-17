#import <forward_list>
#import "RecordStore.h"
#import "Code/Shared/Img.h"
#import "Tools/Shared/Vendor.h"

struct [[gnu::packed]] ImageRef {
    static constexpr uint32_t Version       = 0;
    static constexpr size_t ThumbWidth      = Img::PixelWidth/8;
    static constexpr size_t ThumbHeight     = Img::PixelHeight/8;
    static constexpr size_t ThumbPixelSize  = 3;
    
    enum Rotation : uint8_t {
        None,
        Clockwise90,
        Clockwise180,
        Clockwise270
    };
    
    Img::Id id = 0;
    Rotation rotation = Rotation::None;
    uint8_t _pad[3] = {};
    uint8_t _reserved[64] = {}; // For future use, so we can add fields without doing a big data migration
    
    uint8_t thumbData[ThumbWidth*ThumbHeight*ThumbPixelSize];
};

class ImageLibrary : public RecordStore<ImageRef::Version, ImageRef, 512> {
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
            
            _state.imgIdEnd = state.imgIdEnd;
            
        } catch (const std::exception& e) {
            printf("Recreating ImageLibrary; cause: %s\n", e.what());
        }
    }
    
    void write() {
        std::ofstream f = RecordStore::write();
        const _SerializedState state {
            .version = _Version,
            .imgIdEnd = _state.imgIdEnd,
        };
        f.write((char*)&state, sizeof(state));
    }
    
    void add() {
        RecordStore::add();
        // Update imgIdEnd
        _state.imgIdEnd = (!RecordStore::empty() ? RecordStore::recordGet(RecordStore::back())->id+1 : 0);
        // Notify observers that we changed
        _notifyObservers();
    }
    
    void remove(RecordRefConstIter begin, RecordRefConstIter end) {
        RecordStore::remove(begin, end);
        // Notify observers that we changed
        _notifyObservers();
    }
    
    RecordRefConstIter find(Img::Id id) {
        return std::lower_bound(RecordStore::begin(), RecordStore::end(), 0,
        [&](const ImageLibrary::RecordRef& sample, auto) -> bool {
            return RecordStore::recordGet(sample)->id < id;
        });
    }
    
    void addObserver(Observer&& observer) {
        _state.observers.push_front(std::move(observer));
    }
    
    Img::Id imgIdEnd() const { return _state.imgIdEnd; }
    
private:
    static constexpr uint32_t _Version = 0;
    
    struct [[gnu::packed]] _SerializedState {
        uint32_t version = 0;
        Img::Id imgIdEnd = 0;
    };
    
    struct {
        Img::Id imgIdEnd = 0;
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

using ImageLibraryPtr = std::shared_ptr<MDCTools::Vendor<ImageLibrary>>;

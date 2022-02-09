#import "RecordStore.h"
#import "Img.h"
#import "Vendor.h"

struct [[gnu::packed]] ImageRef {
    static constexpr uint32_t Version       = 0;
    static constexpr size_t ThumbWidth      = Img::PixelWidth/8;
    static constexpr size_t ThumbHeight     = Img::PixelHeight/8;
//    static constexpr size_t ThumbWidth      = 288;
//    static constexpr size_t ThumbHeight     = 162;
    static constexpr size_t ThumbPixelSize  = 3;
    
    enum Rotation : uint8_t {
        None,
        Clockwise90,
        Clockwise180,
        Clockwise270
    };
    
    uint32_t id = 0;
    Rotation rotation = Rotation::None;
    uint8_t _pad[3] = {};
    uint8_t _reserved[64] = {}; // For future use, so we can add fields without doing a big data migration
    
    uint8_t thumbData[ThumbWidth*ThumbHeight*ThumbPixelSize];
};

class ImageLibrary : public RecordStore<ImageRef::Version, ImageRef, 512> {
public:
    using RecordStore::RecordStore;
    
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
    } _state;
    
//    ImageLibrary(const Path& path) : RecordStore(path) {
//        
//    }
//    
//private:
//    static constexpr uint32_t _Version = 0;
//    
//    std::mutex _lock; // Protects this object
//    Img::Id _imgIdEnd = 0;
//    
//    struct [[gnu::packed]] _SerializedState {
//        uint32_t version = 0;
//        Img::Id imgIdEnd = 0;
//    };
//    
//    static Path _StatePath(const Path& path) { return Path(path).replace_extension(".state"); }
//    
//    static _SerializedState _SerializedStateRead(const Path& path) {
//        const Mmap mmap(_StatePath(path));
//        
//        const _SerializedState& state = *mmap.data<_SerializedState>(0);
//        
//        if (state.version != _Version) {
//            throw Toastbox::RuntimeError("invalid state version (expected: 0x%jx, got: 0x%jx)",
//                (uintmax_t)_Version,
//                (uintmax_t)state.version
//            );
//        }
//        
//        return state;
//    }
//    
//    static void _SerializedStateWrite(const Path& path, const _SerializedState& state) {
//        std::ofstream f;
//        f.exceptions(std::ofstream::failbit | std::ofstream::badbit);
//        f.open(_StatePath(path));
//        f.write((char*)&state, sizeof(state));
//    }
};

using ImageLibraryPtr = std::shared_ptr<MDCTools::Vendor<ImageLibrary>>;

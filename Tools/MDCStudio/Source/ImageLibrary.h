#import "RecordStore.h"

struct [[gnu::packed]] ImageRef {
    static constexpr uint32_t Version       = 0;
    static constexpr size_t ThumbWidth      = 256;
    static constexpr size_t ThumbHeight     = 256;
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
    uint8_t thumbData[ThumbWidth*ThumbHeight*ThumbPixelSize];
};

class ImageLibrary : public RecordStore<ImageRef::Version, ImageRef, 512> {
public:
    using RecordStore::RecordStore;
    std::mutex lock;
};

using ImageLibraryPtr = std::shared_ptr<ImageLibrary>;

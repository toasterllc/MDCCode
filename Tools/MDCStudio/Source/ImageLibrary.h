#import "RecordStore.h"
#import "Img.h"

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
    std::mutex lock;
};

using ImageLibraryPtr = std::shared_ptr<ImageLibrary>;

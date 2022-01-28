#import "RecordStore.h"

struct [[gnu::packed]] ImgRef {
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

using ImgStore = RecordStore<
    ImgRef::Version,
    ImgRef,
    512
>;

using ImgStorePtr = std::shared_ptr<ImgStore>;

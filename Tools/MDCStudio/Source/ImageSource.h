#pragma once
#include <memory>
#include "ImageLibrary.h"
#include "ImageCache.h"
#include "Toastbox/Signal.h"
#include "Toastbox/Atomic.h"

namespace MDCStudio {

// ImageSource: abstract interface for an entity that contains an ImageLibrary + ImageCache
// Concrete implementations: MDCDevice, and 'LocalImageLibrary' (not implemented yet)
class ImageSource {
public:
    virtual ImageLibrary& imageLibrary() = 0;
    virtual ImageCache& imageCache() = 0;
    
    struct LoadImagesState {
        Toastbox::Signal signal; // Protects this struct
        std::set<ImageRecordPtr> notify;
        Toastbox::Atomic<size_t> underway;
    };
    
    enum class Priority : uint8_t { High, Low, Last=Low };
    virtual void loadImages(LoadImagesState& state, Priority priority, std::set<ImageRecordPtr> recs) = 0;
    
    struct Image {
        size_t width = 0;
        size_t height = 0;
        MDCTools::CFADesc cfaDesc;
        std::unique_ptr<uint8_t[]> data;
    };
    
    virtual Image imageGet(Priority priority, const ImageRecordPtr& rec) = 0;
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

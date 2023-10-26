#pragma once
#include <memory>
#include "ImageLibrary.h"
#include "Toastbox/Signal.h"
#include "Toastbox/Atomic.h"
#include "Object.h"

namespace MDCStudio {

struct Image {
    size_t width = 0;
    size_t height = 0;
    MDCTools::CFADesc cfaDesc;
    std::unique_ptr<uint8_t[]> data;
    operator bool() const { return (bool)data; }
};

// ImageSource: abstract interface for an entity that contains an ImageLibrary + ImageCache
// Concrete implementations: MDCDevice, and 'LocalImageLibrary' (not implemented yet)
struct ImageSource : Object {
    enum class Priority : uint8_t { High, Low, Last=Low };
    
    virtual ImageLibraryPtr imageLibrary() = 0;
    virtual void renderThumbs(Priority priority, ImageSet recs) = 0;
    virtual Image getCachedImage(const ImageRecordPtr& rec) = 0;
    virtual Image loadImage(Priority priority, const ImageRecordPtr& rec) = 0;
    virtual void deleteImages(const ImageSet& images) = 0;
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

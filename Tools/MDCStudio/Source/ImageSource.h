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
    
    // imageLibrary(): returns the image library
    virtual ImageLibraryPtr imageLibrary() = 0;
    
    // renderThumbs(): synchronously renders the thumbnails for `recs`
    virtual void renderThumbs(Priority priority, ImageSet recs) = 0;
    
    // getCachedImage(): returns a cached image for `rec`, if it exists. Otherwise returns Image{}.
    virtual Image getCachedImage(const ImageRecordPtr& rec) = 0;
    
    // loadImage(): synchronously loads the full-size image for `rec`
    virtual Image loadImage(Priority priority, const ImageRecordPtr& rec) = 0;
    
    // deleteImages(): synchronously deletes the images specified by `recs`
    virtual void deleteImages(const ImageSet& recs) {
        ImageLibraryPtr il = imageLibrary();
        auto lock = std::unique_lock(*il);
        il->remove(recs);
        il->write();
    }
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

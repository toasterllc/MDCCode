#pragma once
#include <memory>
#include "ImageLibrary.h"
#include "ImageCache.h"

namespace MDCStudio {

// ImageSource: abstract interface for an entity that contains an ImageLibrary + ImageCache
// Concrete implementations: MDCDevice, and 'LocalImageLibrary' (not implemented yet)
class ImageSource {
public:
    virtual ImageLibraryPtr imageLibrary() = 0;
    virtual ImageCachePtr imageCache() = 0;
    
    // renderThumbs(): within the given range, asynchronously re-render each thumbnail that has the `thumb.render` flag set
    // ImageLibrary must be locked! 
    virtual void renderThumbs(ImageRecordIter begin, ImageRecordIter end) = 0;
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

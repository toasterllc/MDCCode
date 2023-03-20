#pragma once
#include <memory>
#include "ImageLibrary.h"
#include "ImageCache.h"
#include "Toastbox/AnyIter.h"

namespace MDCStudio {

// ImageSource: abstract interface for an entity that contains an ImageLibrary + ImageCache
// Concrete implementations: MDCDevice, and 'LocalImageLibrary' (not implemented yet)
class ImageSource {
public:
    virtual ImageLibrary& imageLibrary() = 0;
    virtual ImageCache& imageCache() = 0;
    
    // visibleThumbs(): notifies the ImageSource which thumbnails are currently visible.
    // Used to asynchronously re-render the thumbnails that have the `thumb.render` flag set.
    // ImageLibrary must be locked!
    virtual void visibleThumbs(ImageRecordAnyIter begin, ImageRecordAnyIter end) = 0;
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

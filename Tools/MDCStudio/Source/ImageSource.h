#pragma once
#include <memory>
#include "ImageLibrary.h"
#include "ImageCache.h"
#include "Prefs.h"

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
    
    static ImageRecordAnyIter BeginSorted(const ImageLibrary& lib) {
        if (Prefs::SortNewestFirst()) return lib.rbegin();
        else                          return lib.begin();
    }
    
    static ImageRecordAnyIter EndSorted(const ImageLibrary& lib) {
        if (Prefs::SortNewestFirst()) return lib.rend();
        else                          return lib.end();
    }
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

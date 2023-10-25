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
    
    // MARK: - Selection
    // Thread-unsafe; main thread only!
    ObjectPropertyReference(ImageSet, _selection);
    
    auto selection() { return _selection(); }
    void selection(ImageSet x) {
        // Remove images that aren't loaded
        // Ie, don't allow placeholder images to be selected
        for (auto it=x.begin(); it!=x.end();) {
            if (!(*it)->status.loadCount) {
                it = x.erase(it);
            } else {
                it++;
            }
        }
        _selection(x);
    }
};

using ImageSourcePtr = std::shared_ptr<ImageSource>;

} // namespace MDCStudio

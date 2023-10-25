#pragma once
#include "ImageLibrary.h"
#include "Object.h"

namespace MDCStudio {

struct ImageSelection : Object {
    // Thread-unsafe; main thread only!
    ObjectProperty(ImageSet, _images);
    const ImageSet& images() { return __images; }
    void images(ImageSet x) {
        // Remove images that aren't loaded
        // Ie, don't allow placeholder images to be selected
        for (auto it=x.begin(); it!=x.end();) {
            if (!(*it)->status.loadCount) {
                it = x.erase(it);
            } else {
                it++;
            }
        }
        _images(x);
    }
};

using ImageSelectionPtr = std::shared_ptr<ImageSelection>;

} // namespace MDCStudio

#pragma once
#include "ImageLibrary.h"
#include "Object.h"

namespace MDCStudio {

struct ImageSelection : Object {
    
    void init(ImageLibraryPtr imageLibrary) {
        printf("MDCDevice::init()\n");
        Object::init(); // Call super
        
        _imageLibrary = imageLibrary;
        _imageLibraryOb = _imageLibrary->observerAdd([&] (auto, const Object::Event& ev) {
            _handleImageLibraryEvent(static_cast<const ImageLibrary::Event&>(ev));
        });
    }
    
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
    
    void _handleImagesRemoved(const ImageSet& images) {
        // Remove images from the selection that were removed from the ImageLibrary
        bool changed = false;
        for (ImageRecordPtr rec : images) {
            changed |= __images.erase(rec);
        }
        if (changed) observersNotify({});
    }
    
    void _handleImageLibraryEvent(const ImageLibrary::Event& ev) {
        // Only pay attention to removals
        if (ev.type != ImageLibrary::Event::Type::Remove) {
            return;
        }
        
        // Trampoline to the main thread
        // We always need to do this, even if we're already on the main thread,
        // because we don't want the ImageLibrary to be locked when we callout.
        const auto imagesCopy = ev.records;
        auto me = self<ImageSelection>();
        dispatch_async(dispatch_get_main_queue(), ^{
            me->_handleImagesRemoved(imagesCopy);
        });
    }
    
    ImageLibraryPtr _imageLibrary;
    Object::ObserverPtr _imageLibraryOb;
};

using ImageSelectionPtr = std::shared_ptr<ImageSelection>;

} // namespace MDCStudio

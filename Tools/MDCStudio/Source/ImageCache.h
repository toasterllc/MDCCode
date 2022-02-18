#pragma once
#include <map>
#include <thread>

namespace MDCStudio {

class ImageCache {
public:
    using AsyncLoadHandler = std::function<void(ImagePtr)>;
    
    ImageCache() {
        _thread = std::thread([=] {
            _threadLoadImages();
        });
    }
    
    ImagePtr imageForImageRef(const ImageRef& imageRef, AsyncLoadHandler handler) {
        auto find = _images.find(imageRef.id);
        if (find != _images.end()) {
            return find->second;
        }
        
        return nullptr;
    }
    
private:
    std::map<ImageId,ImagePtr> _images;
    std::thread _thread;
    
    void _threadLoadImages() {
        
    }
};

class ImageProvider {
public:
    
};

using ImageCachePtr = std::shared_ptr<ImageCache>;

} // namespace MDCStudio

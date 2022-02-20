#pragma once
#include <map>
#include <set>
#include <thread>
#import "Image.h"
#import "ImageLibrary.h"

namespace MDCStudio {

//class ImageProvider {
//public:
//    
//};

class ImageCache {
public:
    using ImageProvider = std::function<ImagePtr(const ImageRef&)>;
    using ImageLoadedHandler = std::function<void(ImagePtr)>;
    
    ImageCache(ImageLibraryPtr imageLibrary, ImageProvider&& imageProvider) : _imageLibrary(imageLibrary), _imageProvider(imageProvider) {
        auto lock = std::unique_lock(_stateLock);
        _state.thread = std::thread([=] { _thread(); });
    }
    
    ~ImageCache() {
        auto lock = std::unique_lock(_stateLock);
        #warning TODO: need to signal thread to exit
        _state.thread.join();
    }
    
    ImagePtr imageForImageRef(const ImageRef& imageRef, ImageLoadedHandler handler) {
        auto lock = std::unique_lock(_stateLock);
        
        // If the image is already in the cache, return it
        ImagePtr image;
        auto find = _state.images.find(imageRef.id);
        if (find != _state.images.end()) {
            image = find->second;
        }
        
        // Schedule the image/neighbors to be loaded asynchronously
        _state.work = _Work{
            .imageRef = imageRef,
            .handler = handler,
            .loadImage = !image,
            .loadNeighbors = true,
        };
        
        _state.workSignal.notify_all();
        return image;
    }
    
private:
    static constexpr size_t _CacheImageCount = 32;
    static constexpr size_t _NeighborImageLoadCount = 8;
    
    struct _Work {
        ImageRef imageRef;
        ImageLoadedHandler handler;
        bool loadImage = false;
        bool loadNeighbors = false;
    };
    
    void _thread() {
        for (;;) {
            std::set<ImageId> inserted;
            
            // Wait for work
            _Work work;
            {
                auto lock = std::unique_lock(_stateLock);
                while (!_state.work) _state.workSignal.wait(lock);
                work = *_state.work;
                _state.work = std::nullopt;
            }
            
            // Load the image itself, if instructed to do so
            if (work.loadImage) {
                // Load the image
                ImagePtr image = _imageProvider(work.imageRef);
                // Put the image in the cache
                _state.images[work.imageRef.id] = image;
                inserted.insert(work.imageRef.id);
                // Notify the handler
                work.handler(image);
            }
            
            // Load the image neighbors, if instructed to do so and there's no further work to do
            if (work.loadNeighbors) {
                std::vector<ImageRef> imageRefs;
                imageRefs.reserve(_NeighborImageLoadCount);
                
                // Collect the neighboring ImageRefs in the order that we want to load them: 3 2 1 0 [img] 0 1 2 3
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    auto find = _imageLibrary->find(work.imageRef.id);
                    auto it = find;
                    auto rit = std::make_reverse_iterator(find); // Points to element before `find`
                    
                    for (size_t i=0; i<_NeighborImageLoadCount/2; i++) {
                        if (it != _imageLibrary->end()) it++;
                        
                        if (it != _imageLibrary->end()) {
                            imageRefs.push_back(_imageLibrary->recordGet(it)->ref);
                        }
                        
                        if (rit != _imageLibrary->rend()) {
                            imageRefs.push_back(_imageLibrary->recordGet(rit)->ref);
                        }
                        
                        // make_reverse_iterator() returns an iterator that points to the element _before_ the
                        // forward iterator (`find`), so we increment `rit` at the end of the loop, instead of
                        // at the beginning (where we increment the forward iterator `it`)
                        if (rit != _imageLibrary->rend()) rit++;
                    }
                }
                
                // Load the neighboring images, bailing if additional work appears
                for (const ImageRef& imageRef : imageRefs) {
                    inserted.insert(imageRef.id);
                    NSLog(@"Loading neighbor %d", (int)imageRef.id);
                    
                    auto lock = std::unique_lock(_stateLock);
                        // Bail if more work appears
                        if (_state.work) break;
                        const auto find = _state.images.find(imageRef.id);
                        // Move on if this image is already loaded
                        if (find != _state.images.end()) continue;
                    lock.unlock();
                    
                    // Load the image without the lock held
                    ImagePtr image = _imageProvider(imageRef);
                    
                    if (image) {
                        lock.lock();
                            // `find` stays valid after relinquishing the lock because this thread
                            // is the only thread that modifies `_state.images`
                            _state.images.insert_or_assign(find, imageRef.id, image);
                        lock.unlock();
                    }
                }
            }
            
            // Prune the cache, ensuring that we don't remove any of the images that we just added (`inserted`)
            {
                auto lock = std::unique_lock(_stateLock);
                for (auto it=_state.images.begin(); it!=_state.images.end() && _state.images.size()>_CacheImageCount;) {
                    const ImageId imageId = it->first;
                    const auto itPrev = it;
                    it++;
                    
                    // Skip removal if this image was just added
                    if (inserted.find(imageId) != inserted.end()) continue;
                    _state.images.erase(itPrev);
                }
            }
        }
    }
    
    std::mutex _stateLock;
    struct {
        std::map<ImageId,ImagePtr> images;
        std::thread thread;
        std::optional<_Work> work;
        std::condition_variable workSignal;
    } _state;
    
    ImageLibraryPtr _imageLibrary;
    ImageProvider _imageProvider;
};

using ImageCachePtr = std::shared_ptr<ImageCache>;

} // namespace MDCStudio

#pragma once
#include <map>
#include <set>
#include <thread>
#import "Image.h"
#import "ImageLibrary.h"

namespace MDCStudio {

class ImageCache {
public:
    using ImageProvider = std::function<ImagePtr(uint64_t addr)>;
    using ImageLoadedHandler = std::function<void(ImagePtr)>;
    
    ImageCache(ImageLibraryPtr imageLibrary, ImageProvider&& imageProvider) : _imageLibrary(imageLibrary), _imageProvider(std::move(imageProvider)) {
        auto lock = std::unique_lock(_state.lock);
        _state.thread = std::thread([=] { _thread(); });
    }
    
    ~ImageCache() {
        // Signal thread to exit
        {
            auto lock = std::unique_lock(_state.lock);
            _state.threadStop = true;
            _state.threadSignal.notify_all();
        }
        
        _state.thread.join();
        printf("~ImageCache()\n");
    }
    
    ImagePtr imageForId(Img::Id id, ImageLoadedHandler handler) {
        auto lock = std::unique_lock(_state.lock);
        
        // If the image is already in the cache, return it
        ImagePtr image;
        auto find = _state.images.find(id);
        if (find != _state.images.end()) {
            image = find->second;
        }
        
        // Schedule the image/neighbors to be loaded asynchronously
        _state.work = _Work{
            .id = id,
            .handler = handler,
            .loadImage = !image,
            .loadNeighbors = true,
        };
        
        _state.threadSignal.notify_all();
        return image;
    }
    
private:
    static constexpr size_t _CacheImageCount = 32;
    static constexpr size_t _NeighborImageLoadCount = 8;
    
    struct _Work {
        Img::Id id = 0;
        ImageLoadedHandler handler;
        bool loadImage = false;
        bool loadNeighbors = false;
    };
    
    std::optional<uint64_t> _AddrForImageId(ImageLibraryPtr lib, Img::Id id) {
        auto lock = std::unique_lock(*_imageLibrary);
        auto find = _imageLibrary->find(id);
        if (find == _imageLibrary->end()) return std::nullopt;
        return _imageLibrary->recordGet(find)->id;
    }
    
    void _thread() {
        for (;;) {
            std::set<Img::Id> inserted;
            
            // Wait for work
            _Work work;
            {
                auto lock = std::unique_lock(_state.lock);
                for (;;) {
                    if (_state.threadStop) return;
                    if (_state.work) break;
                    _state.threadSignal.wait(lock);
                }
                work = *_state.work;
                _state.work = std::nullopt;
            }
            
            // Load the image itself, if instructed to do so
            if (work.loadImage) {
                const std::optional<uint64_t> addr = _AddrForImageId(_imageLibrary, work.id);
                ImagePtr image;
                if (addr) {
                    // Load the image
                    image = _imageProvider(*addr);
                    if (image) {
                        // Put the image in the cache
                        _state.images[work.id] = image;
                        inserted.insert(work.id);
                    }
                }
                // Notify the handler
                work.handler(image);
            }
            
            // Load the image neighbors, if instructed to do so and there's no further work to do
            if (work.loadNeighbors) {
                struct IdAddr {
                    Img::Id id = 0;
                    uint64_t addr = 0;
                };
                
                std::vector<IdAddr> idAddrs;
                idAddrs.reserve(_NeighborImageLoadCount);
                
                // Collect the neighboring image ids in the order that we want to load them: 3 2 1 0 [img] 0 1 2 3
                {
                    auto lock = std::unique_lock(*_imageLibrary);
                    auto find = _imageLibrary->find(work.id);
                    auto it = find;
                    auto rit = std::make_reverse_iterator(find); // Points to element before `find`
                    
                    for (size_t i=0; i<_NeighborImageLoadCount/2; i++) {
                        if (it != _imageLibrary->end()) it++;
                        
                        if (it != _imageLibrary->end()) {
                            const ImageThumb& thumb = *_imageLibrary->recordGet(it);
                            idAddrs.push_back({ thumb.id, thumb.addr });
                        }
                        
                        if (rit != _imageLibrary->rend()) {
                            const ImageThumb& thumb = *_imageLibrary->recordGet(rit);
                            idAddrs.push_back({ thumb.id, thumb.addr });
                        }
                        
                        // make_reverse_iterator() returns an iterator that points to the element _before_ the
                        // forward iterator (`find`), so we increment `rit` at the end of the loop, instead of
                        // at the beginning (where we increment the forward iterator `it`)
                        if (rit != _imageLibrary->rend()) rit++;
                    }
                }
                
                // Load the neighboring images, bailing if additional work appears
                for (const IdAddr& idAddr : idAddrs) {
                    inserted.insert(idAddr.id);
                    printf("[ImageCache] Loading neighbor %ju\n", (uintmax_t)idAddr.id);
                    
                    auto lock = std::unique_lock(_state.lock);
                        // Bail if more work appears
                        if (_state.work) break;
                        const auto find = _state.images.find(idAddr.id);
                        // Move on if this image is already loaded
                        if (find != _state.images.end()) continue;
                    lock.unlock();
                    
                    // Load the image without the lock held
                    ImagePtr image = _imageProvider(idAddr.addr);
                    
                    if (image) {
                        lock.lock();
                            // `find` stays valid after relinquishing the lock because this thread
                            // is the only thread that modifies `_state.images`
                            _state.images.insert_or_assign(find, idAddr.id, image);
                        lock.unlock();
                    }
                }
            }
            
            // Prune the cache, ensuring that we don't remove any of the images that we just added (`inserted`)
            {
                auto lock = std::unique_lock(_state.lock);
                for (auto it=_state.images.begin(); it!=_state.images.end() && _state.images.size()>_CacheImageCount;) {
                    const Img::Id imageId = it->first;
                    const auto itPrev = it;
                    it++;
                    
                    // Skip removal if this image was just added
                    if (inserted.find(imageId) != inserted.end()) continue;
                    _state.images.erase(itPrev);
                }
            }
        }
    }
    
    struct {
        std::mutex lock; // Protects this struct
        std::map<Img::Id,ImagePtr> images;
        std::thread thread;
        bool threadStop = false;
        std::condition_variable threadSignal;
        std::optional<_Work> work;
    } _state;
    
    ImageLibraryPtr _imageLibrary;
    ImageProvider _imageProvider;
};

using ImageCachePtr = std::shared_ptr<ImageCache>;

} // namespace MDCStudio

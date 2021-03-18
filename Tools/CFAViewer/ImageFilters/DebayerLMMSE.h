#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalTypes.h"
#import "MetalUtil.h"
#import "ImageFilter.h"
#import "RenderManager.h"

namespace CFAViewer::ImageFilter {
    class DebayerLMMSE {
    public:
        DebayerLMMSE() {}
        DebayerLMMSE(id<MTLDevice> dev, id<MTLHeap> heap, id<MTLCommandQueue> q) :
        _dev(dev),
        _heap(heap),
        _q(q),
        _rm(_dev, [_dev newDefaultLibrary], _q) {
        }
        
        void run(const Options& opts, id<MTLTexture> raw) {
        }
    
    private:
        id<MTLDevice> _dev = nil;
        id<MTLHeap> _heap = nil;
        id<MTLCommandQueue> _q = nil;
        RenderManager _rm;
    };
};

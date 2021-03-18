#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalTypes.h"
#import "MetalUtil.h"
#import "ImageFilter.h"
#import "RenderManager.h"

namespace CFAViewer::ImageFilter {
    class DebayerBilinear {
    public:
        DebayerBilinear() {}
        DebayerBilinear(id<MTLDevice> dev, id<MTLCommandQueue> q) :
        _dev(dev),
        _rm(_dev, [_dev newDefaultLibrary], q) {
        }
        
        void run(const CFADesc& cfaDesc, id<MTLTexture> raw, id<MTLTexture> rgb) {
            _rm.renderPass("CFAViewer::ImageFilter::DebayerBilinear::Debayer", rgb,
                [&](id<MTLRenderCommandEncoder> enc) {
                    [enc setFragmentBytes:&cfaDesc length:sizeof(cfaDesc) atIndex:0];
                    [enc setFragmentTexture:raw atIndex:0];
                });
        }
    
    private:
        id<MTLDevice> _dev = nil;
        RenderManager _rm;
    };
};

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <unordered_map>
#import <string>
#import "Assert.h"
#import "MetalTypes.h"
#import "ImageFilterTypes.h"

namespace CFAViewer::ImageFilter {
    class RenderManager {
    public:
        RenderManager() {}
        RenderManager(id<MTLDevice> dev, id<MTLLibrary> lib, id<MTLCommandQueue> q)
        : _dev(dev), _lib(lib), _q(q) {
        }
        
        template <typename Fn>
        void renderPass(
            const std::string& name,
            id<MTLTexture> txt,
            Fn fn
        ) {
            NSParameterAssert(txt);
            
            MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
            [[renderPassDescriptor colorAttachments][0] setTexture:txt];
            [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
            [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
            [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
            id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:renderPassDescriptor];
            
            [enc setRenderPipelineState:_pipelineState(name, [txt pixelFormat])];
            [enc setFrontFacingWinding:MTLWindingCounterClockwise];
            [enc setCullMode:MTLCullModeNone];
            
            fn(enc);
            
            [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0 vertexCount:CFAViewer::MetalTypes::SquareVertIdxCount];
            
            [enc endEncoding];
        }
        
        template <typename Fn>
        void renderPass(
            const std::string& name,
            NSUInteger width,
            NSUInteger height,
            Fn fn
        ) {
            MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
            [renderPassDescriptor setRenderTargetWidth:width];
            [renderPassDescriptor setRenderTargetHeight:height];
            [renderPassDescriptor setDefaultRasterSampleCount:1];
            [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
            [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionDontCare];
            [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionDontCare];
            id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:renderPassDescriptor];
            
            [enc setRenderPipelineState:_pipelineState(name, MTLPixelFormatInvalid)];
            [enc setFrontFacingWinding:MTLWindingCounterClockwise];
            [enc setCullMode:MTLCullModeNone];
            
            fn(enc);
            
            [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0 vertexCount:CFAViewer::MetalTypes::SquareVertIdxCount];
            
            [enc endEncoding];
        }
        
        void copy(id<MTLTexture> src, id<MTLBuffer> dst) {
            const NSUInteger w = [src width];
            const NSUInteger h = [src height];
            const NSUInteger bytesPerPixel = _BytesPerPixelForPixelFormat([src pixelFormat]);
            const NSUInteger bytesPerRow = w*bytesPerPixel;
            const NSUInteger bytesPerImage = h*bytesPerRow;
            id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
            [blit copyFromTexture:src sourceSlice:0 sourceLevel:0 sourceOrigin:{}
                sourceSize:{w,h,1} toBuffer:dst destinationOffset:0
                destinationBytesPerRow:bytesPerRow
                destinationBytesPerImage:bytesPerImage];
            [blit endEncoding];
        }
        
        void copy(id<MTLBuffer> src, id<MTLTexture> dst) {
            const NSUInteger w = [dst width];
            const NSUInteger h = [dst height];
            const NSUInteger bytesPerPixel = _BytesPerPixelForPixelFormat([dst pixelFormat]);
            const NSUInteger bytesPerRow = w*bytesPerPixel;
            const NSUInteger bytesPerImage = h*bytesPerRow;
            id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
            [blit copyFromBuffer:src sourceOffset:0
                sourceBytesPerRow:bytesPerRow
                sourceBytesPerImage:bytesPerImage
                sourceSize:{w,h,1} toTexture:dst
                destinationSlice:0 destinationLevel:0 destinationOrigin:{}];
            [blit endEncoding];
        }
        
        void copy(id<MTLTexture> src, id<MTLTexture> dst) {
            id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
            [blit copyFromTexture:src toTexture:dst];
            [blit endEncoding];
        }
        
        id<MTLCommandBuffer> cmdBuf() {
            if (!_cmdBuf) _cmdBuf = [_q commandBuffer];
            return _cmdBuf;
        }
        
        void commit() {
            [_cmdBuf commit];
            _cmdBuf = nil;
        }
        
        void commitAndWait() {
            [_cmdBuf commit];
            [_cmdBuf waitUntilCompleted];
            _cmdBuf = nil;
        }
    
    private:
        static size_t _BytesPerPixelForPixelFormat(MTLPixelFormat fmt) {
            switch (fmt) {
            case MTLPixelFormatR32Float:    return sizeof(float);
            case MTLPixelFormatRGBA32Float: return 4*sizeof(float);
            default:                        abort();
            }
        }
        
        id<MTLRenderPipelineState> _pipelineState(const std::string& name, MTLPixelFormat fmt) {
            NSParameterAssert(name);
            auto find = _pipelineStates.find(name);
            if (find != _pipelineStates.end()) return find->second;
            
            id<MTLFunction> vertexShader = [_lib newFunctionWithName:@"ImageLayer::VertexShader"];
            Assert(vertexShader, return nil);
            id<MTLFunction> fragmentShader = [_lib newFunctionWithName:@(name.c_str())];
            Assert(fragmentShader, return nil);
            
            MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
            [desc setVertexFunction:vertexShader];
            [desc setFragmentFunction:fragmentShader];
            [[desc colorAttachments][0] setPixelFormat:fmt];
            id<MTLRenderPipelineState> ps = [_dev newRenderPipelineStateWithDescriptor:desc
                error:nil];
            Assert(ps, return nil);
            _pipelineStates.insert(find, {name, ps});
            return ps;
        }
        
        id<MTLDevice> _dev = nil;
        id <MTLLibrary> _lib = nil;
        id <MTLCommandQueue> _q = nil;
        std::unordered_map<std::string,id<MTLRenderPipelineState>> _pipelineStates;
        id<MTLCommandBuffer> _cmdBuf = nil;
    };
};

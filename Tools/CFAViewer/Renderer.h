#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <unordered_map>
#import <string>
#import "Assert.h"
#import "MetalUtil.h"

namespace CFAViewer {
    class Renderer {
    public:
        Renderer() {}
        Renderer(id<MTLDevice> dev, id<MTLLibrary> lib,
        id<MTLCommandQueue> commandQueue, id<MTLHeap> heap) :
        dev(dev), _lib(lib), _commandQueue(commandQueue), _heap(heap) {
        }
        
        // Render pass to a target texture
        template <typename... Args>
        void render(
            const std::string& name,
            id<MTLTexture> txt,
            Args&... args
        ) {
            NSParameterAssert(txt);
            
            MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor new];
            [[desc colorAttachments][0] setTexture:txt];
            [[desc colorAttachments][0] setClearColor:{0,0,0,1}];
            [[desc colorAttachments][0] setLoadAction:MTLLoadActionLoad];
            [[desc colorAttachments][0] setStoreAction:MTLStoreActionStore];
            id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:desc];
            
            [enc setRenderPipelineState:_pipelineState(name, [txt pixelFormat])];
            [enc setFrontFacingWinding:MTLWindingCounterClockwise];
            [enc setCullMode:MTLCullModeNone];
            
            Renderer::_SetBufferArgs(enc, 0, args...);
            
            [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0 vertexCount:CFAViewer::MetalUtil::SquareVertIdxCount];
            
            [enc endEncoding];
        }
        
        // Render pass with no target texture
        // (Fragment shaders typically use texture.write() in this case)
        template <typename... Args>
        void render(
            const std::string& name,
            NSUInteger width,
            NSUInteger height,
            Args&... args
        ) {
            MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor new];
            [desc setRenderTargetWidth:width];
            [desc setRenderTargetHeight:height];
            [desc setDefaultRasterSampleCount:1];
            [[desc colorAttachments][0] setClearColor:{0,0,0,1}];
            [[desc colorAttachments][0] setLoadAction:MTLLoadActionDontCare];
            [[desc colorAttachments][0] setStoreAction:MTLStoreActionDontCare];
            id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:desc];
            
            [enc setRenderPipelineState:_pipelineState(name, MTLPixelFormatInvalid)];
            [enc setFrontFacingWinding:MTLWindingCounterClockwise];
            [enc setCullMode:MTLCullModeNone];
            
            Renderer::_SetBufferArgs(enc, 0, args...);
            
            [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0 vertexCount:CFAViewer::MetalUtil::SquareVertIdxCount];
            
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
        
        id<MTLTexture> createTexture(
            MTLPixelFormat fmt,
            NSUInteger width, NSUInteger height,
            MTLTextureUsage usage=(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)
        ) {
            MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
            [desc setTextureType:MTLTextureType2D];
            [desc setStorageMode:MTLStorageModePrivate];
            [desc setWidth:width];
            [desc setHeight:height];
            [desc setPixelFormat:fmt];
            [desc setUsage:usage];
            id<MTLTexture> txt = [_heap newTextureWithDescriptor:desc];
            Assert(txt, return nil);
            return txt;
        }
        
        id<MTLCommandBuffer> cmdBuf() {
            if (!_cmdBuf) _cmdBuf = [_commandQueue commandBuffer];
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
        
        id<MTLDevice> dev = nil;
    
    private:
        void _SetBufferArgs(id<MTLRenderCommandEncoder> enc, size_t idx) {}
        
        template <typename T, typename... Ts>
        void _SetBufferArgs(id<MTLRenderCommandEncoder> enc, size_t idx, T& t, Ts&... ts) {
            if constexpr (!std::is_same<T,id<MTLTexture>>::value) {
                if constexpr (std::is_same<T,id<MTLBuffer>>::value) {
                    [enc setFragmentBuffer:t offset:0 atIndex:idx];
                } else {
                    [enc setFragmentBytes:&t length:sizeof(t) atIndex:idx];
                }
                _SetBufferArgs(enc, idx+1, ts...);
            } else {
                // Start of texture arguments
                _SetTextureArgs(enc, 0, t, ts...);
            }
        }
        
        void _SetTextureArgs(id<MTLRenderCommandEncoder> enc, size_t idx) {}
        
        template <typename T, typename... Ts>
        void _SetTextureArgs(id<MTLRenderCommandEncoder> enc, size_t idx, T& t, Ts&... ts) {
            static_assert(std::is_same<T,id<MTLTexture>>::value);
            [enc setFragmentTexture:t atIndex:idx];
            _SetTextureArgs(enc, idx+1, ts...);
        }
        
//        template <typename... Ts>
//        static void SetTextureArgs(id<MTLRenderCommandEncoder> enc, id<MTLTexture> t, Ts... ts) {
//            _SetTextureArgs(enc, 0, t, ts...);
//        }
//        
//        static void _SetBufferArgs(id<MTLRenderCommandEncoder> enc, size_t idx) {}
//        
//        template <typename T, typename... Ts>
//        static void _SetBufferArgs(id<MTLRenderCommandEncoder> enc, size_t idx, T& t, Ts&... ts) {
//            [enc setFragmentBytes:&t length:sizeof(t) atIndex:idx];
//            _SetBufferArgs(enc, idx+1, ts...);
//        }
//        
//        static void _SetTextureArgs(id<MTLRenderCommandEncoder> enc, size_t idx) {}
//        
//        template <typename... Ts>
//        static void _SetTextureArgs(id<MTLRenderCommandEncoder> enc, size_t idx,
//        id<MTLTexture> t, Ts... ts) {
//            [enc setFragmentTexture:t atIndex:idx];
//            _SetTextureArgs(enc, idx+1, ts...);
//        }
        
        
//        template <typename T, typename... Ts>
//        static void SetBufferArgs(id<MTLRenderCommandEncoder> enc, T& t, Ts&... ts) {
//            _SetBufferArgs(enc, 0, t, ts...);
//        }
//        
//        template <typename... Ts>
//        static void SetTextureArgs(id<MTLRenderCommandEncoder> enc, id<MTLTexture> t, Ts... ts) {
//            _SetTextureArgs(enc, 0, t, ts...);
//        }
//        
//        static void _SetBufferArgs(id<MTLRenderCommandEncoder> enc, size_t idx) {}
//        
//        template <typename T, typename... Ts>
//        static void _SetBufferArgs(id<MTLRenderCommandEncoder> enc, size_t idx, T& t, Ts&... ts) {
//            [enc setFragmentBytes:&t length:sizeof(t) atIndex:idx];
//            _SetBufferArgs(enc, idx+1, ts...);
//        }
//        
//        static void _SetTextureArgs(id<MTLRenderCommandEncoder> enc, size_t idx) {}
//        
//        template <typename... Ts>
//        static void _SetTextureArgs(id<MTLRenderCommandEncoder> enc, size_t idx,
//        id<MTLTexture> t, Ts... ts) {
//            [enc setFragmentTexture:t atIndex:idx];
//            _SetTextureArgs(enc, idx+1, ts...);
//        }
        
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
            
            id<MTLFunction> vertexShader = [_lib newFunctionWithName:@"CFAViewer::Shader::Renderer::VertexShader"];
            Assert(vertexShader, return nil);
            id<MTLFunction> fragmentShader = [_lib newFunctionWithName:@(name.c_str())];
            Assert(fragmentShader, return nil);
            
            MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
            [desc setVertexFunction:vertexShader];
            [desc setFragmentFunction:fragmentShader];
            [[desc colorAttachments][0] setPixelFormat:fmt];
            id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:desc
                error:nil];
            Assert(ps, return nil);
            _pipelineStates.insert(find, {name, ps});
            return ps;
        }
        
        id <MTLLibrary> _lib = nil;
        id <MTLCommandQueue> _commandQueue = nil;
        std::unordered_map<std::string,id<MTLRenderPipelineState>> _pipelineStates;
        id<MTLCommandBuffer> _cmdBuf = nil;
        id<MTLHeap> _heap = nil;
    };
};

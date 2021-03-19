#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <unordered_map>
#import <queue>
#import <string>
#import <functional>
#import "Assert.h"
#import "MetalUtil.h"
#import "HashInts.h"

namespace CFAViewer {
    class Renderer {
    public:
        class Txt {
        public:
            operator id<MTLTexture>() const { return _state.txt; }
            
            // Default constructor
            Txt() {}
            // Copy constructor: illegal
            Txt(const Txt& x) = delete;
            // Copy assignment operator: illegal
            Txt& operator=(const Txt& x) = delete;
            // Move constructor: use move assignment operator
            Txt(Txt&& x) { *this = std::move(x); }
            // Move assignment operator
            Txt& operator=(Txt&& x) {
                _state = x._state;
                x._state = {};
                return *this;
            }
            
            ~Txt() {
                if (_state.renderer) {
                    _state.renderer->_recycleTxt(_state.txt);
                }
            }
            
        private:
            Txt(Renderer& renderer, id<MTLTexture> txt) : _state{&renderer, txt} {}
            
            struct {
                Renderer* renderer = nullptr;
                id<MTLTexture> txt = nil;
            } _state;
            
            friend class Renderer;
        };
        
        Renderer() {}
        Renderer(id<MTLDevice> dev, id<MTLLibrary> lib,
        id<MTLCommandQueue> commandQueue) :
        dev(dev), _lib(lib), _commandQueue(commandQueue) {
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
        
        void sync(id<MTLTexture> txt) {
            id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
            [blit synchronizeTexture:txt slice:0 level:0];
            [blit endEncoding];
        }
        
        void present(id<CAMetalDrawable> drawable) {
            [cmdBuf() presentDrawable:drawable];
        }
        
        Txt createTexture(
            MTLPixelFormat fmt,
            NSUInteger width, NSUInteger height,
            MTLTextureUsage usage=(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)
        ) {
            // Check if we already have a texture matching the given criteria
            TxtKey key(fmt, width, height, usage);
            auto& txts = _txts[key];
            if (!txts.empty()) {
                Txt txt(*this, txts.front());
                txts.pop();
                return txt;
            }
            
            // We don't have a cached texture matching the criteria, so create a new one
            MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
            [desc setTextureType:MTLTextureType2D];
            [desc setWidth:width];
            [desc setHeight:height];
            [desc setPixelFormat:fmt];
            [desc setUsage:usage];
            id<MTLTexture> txt = [dev newTextureWithDescriptor:desc];
            Assert(txt, return Txt());
            return Txt(*this, txt);
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
            if constexpr (!std::is_same<T,id<MTLTexture>>::value && !std::is_same<T,Txt>::value) {
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
            if constexpr (std::is_same<T,Txt>::value) {
                [enc setFragmentTexture:(id<MTLTexture>)t atIndex:idx];
            } else if constexpr (std::is_same<T,id<MTLTexture>>::value) {
                [enc setFragmentTexture:t atIndex:idx];
            } else {
                static_assert(_AlwaysFalse<T>);
            }
            
            _SetTextureArgs(enc, idx+1, ts...);
        }
        
        static size_t _BytesPerPixelForPixelFormat(MTLPixelFormat fmt) {
            switch (fmt) {
            case MTLPixelFormatR32Float:    return sizeof(float);
            case MTLPixelFormatRGBA32Float: return 4*sizeof(float);
            default:                        abort();
            }
        }
        
        void _recycleTxt(id<MTLTexture> txt) {
            _txts[txt].push(txt);
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
        
        class TxtKey {
        public:
            TxtKey(id<MTLTexture> txt) :
            _fmt([txt pixelFormat]), _width([txt width]), _height([txt height]), _usage([txt usage]) {}
            
            TxtKey(MTLPixelFormat fmt, NSUInteger width, NSUInteger height, MTLTextureUsage usage) :
            _fmt(fmt), _width(width), _height(height), _usage(usage) {}
            
            bool operator==(const TxtKey& x) const {
                return
                    _fmt==x._fmt        &&
                    _width==x._width    &&
                    _height==x._height  &&
                    _usage==x._usage    ;
            }
            
            size_t hash() const {
                return HashInts(_fmt, _width, _height, _usage);
            }
            
            struct Hash {
                size_t operator()(const TxtKey& x) const { return x.hash(); }
            };
        
        private:
            MTLPixelFormat _fmt = MTLPixelFormatInvalid;
            NSUInteger _width = 0;
            NSUInteger _height = 0;
            MTLTextureUsage _usage = MTLTextureUsageUnknown;
        };
        
        id <MTLLibrary> _lib = nil;
        id <MTLCommandQueue> _commandQueue = nil;
        std::unordered_map<std::string,id<MTLRenderPipelineState>> _pipelineStates;
        std::unordered_map<TxtKey,std::queue<id<MTLTexture>>,TxtKey::Hash> _txts;
        id<MTLCommandBuffer> _cmdBuf = nil;
        
        template <class...> static constexpr std::false_type _AlwaysFalse;
        
        friend class Txt;
    };
};

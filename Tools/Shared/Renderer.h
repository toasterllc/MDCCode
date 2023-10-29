#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <map>
#import <unordered_map>
#import <queue>
#import <string>
#import <list>
#import <set>
#import <mutex>
#import <functional>
#import <assert.h>
#import "Assert.h"
#import "MetalUtil.h"
#import "Toastbox/HashInts.h"

namespace MDCTools {

// Renderer is a wrapper for Metal APIs to make them more convenient.
// Renderer particularly improves executing multiple fragment render passes.
class Renderer {
#define _ShaderNamespace "MDCTools::RendererShader::"
#define _DefaultVertexShader _ShaderNamespace "VertexShader"
private:
    template <typename... T_Args>
    struct _VertexShader {
        std::string_view fn;
        std::tuple<T_Args...> args;
    };
    
    template <typename... T_Args>
    struct _FragmentShader {
        std::string_view fn;
        std::tuple<T_Args...> args;
    };
    
    template <typename... T_Args>
    struct _ComputeKernel {
        std::string_view fn;
        std::tuple<T_Args...> args;
    };
    
public:
    template <typename T>
    class Resource {
    public:
        // Default constructor
        Resource() {}
        
        // Copy: deleted
        Resource(const Resource& x) = delete;
        Resource& operator=(const Resource& x) = delete;
        // Move: allowed
        Resource(Resource&& x) { swap(x); }
        Resource& operator=(Resource&& x) { swap(x); return *this; }
        
        void swap(Resource& x) {
            std::swap(_state, x._state);
        }
        
        ~Resource() {
            if (_state.renderer) _state.renderer->_recycle(_state.resource, _state.deferRecycle);
        }
        
        operator T() const { return _state.resource; }
        
    private:
        Resource(Renderer& renderer, T resource, bool deferRecycle=false) : _state{&renderer, resource} {}
        
        struct {
            Renderer* renderer = nullptr;
            T resource = nil;
            bool deferRecycle = false;
        } _state;
        
        friend class Renderer;
    };
    
    using Txt = Resource<id<MTLTexture>>;
    using Buf = Resource<id<MTLBuffer>>;
    
    enum class BlendType {
        None,
        Over,
    };
    
    static id /* CGColorSpaceRef */ GrayColorSpace() {
        static id /* CGColorSpaceRef */ cs = CFBridgingRelease(CGColorSpaceCreateDeviceGray());
        return cs;
    }
    
    static id /* CGColorSpaceRef */ SRGBColorSpace() {
        static id /* CGColorSpaceRef */ cs = CFBridgingRelease(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
        return cs;
    }
    
    static id /* CGColorSpaceRef */ LSRGBColorSpace() {
        static id /* CGColorSpaceRef */ cs = CFBridgingRelease(CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB));
        return cs;
    }
    
    Renderer() {}
    Renderer(id<MTLDevice> dev, id<MTLLibrary> lib, id<MTLCommandQueue> commandQueue) :
    dev(dev), _lib(lib), _commandQueue(commandQueue), _recycleBufs(std::make_shared<_RecycleBufs>()) {
    }
    
    ~Renderer() {
        // When the renderer is destroyed, make sure that there are no resources that were waiting to be recycled.
        // If there are, we likely have a memory leak and our -addCompletedHandler: was never called.
        auto lock = std::unique_lock(_recycleBufs->lock);
        assert(!_recycleBufs->pending);
    }
    
    static size_t SamplesPerPixel(MTLPixelFormat fmt) {
        switch (fmt) {
        case MTLPixelFormatR8Unorm:         return 1;
        case MTLPixelFormatR16Unorm:        return 1;
        case MTLPixelFormatR32Float:        return 1;
        case MTLPixelFormatRGBA8Unorm:      return 4;
        case MTLPixelFormatRGBA8Unorm_sRGB: return 4;
        case MTLPixelFormatBGRA8Unorm:      return 4;
        case MTLPixelFormatBGRA8Unorm_sRGB: return 4;
        case MTLPixelFormatRGBA16Unorm:     return 4;
        case MTLPixelFormatRGBA16Float:     return 4;
        case MTLPixelFormatRGBA32Float:     return 4;
        default:                            throw std::runtime_error("invalid pixel format");
        }
    }
    
    static size_t BytesPerSample(MTLPixelFormat fmt) {
        switch (fmt) {
        case MTLPixelFormatR8Unorm:         return 1;
        case MTLPixelFormatR16Unorm:        return 2;
        case MTLPixelFormatR32Float:        return 4;
        case MTLPixelFormatRGBA8Unorm:      return 1;
        case MTLPixelFormatRGBA8Unorm_sRGB: return 1;
        case MTLPixelFormatBGRA8Unorm:      return 1;
        case MTLPixelFormatBGRA8Unorm_sRGB: return 1;
        case MTLPixelFormatRGBA16Unorm:     return 2;
        case MTLPixelFormatRGBA16Float:     return 2;
        case MTLPixelFormatRGBA32Float:     return 4;
        default:                            throw std::runtime_error("invalid pixel format");
        }
    }
    
    static size_t BytesPerPixel(MTLPixelFormat fmt) {
        return SamplesPerPixel(fmt)*BytesPerSample(fmt);
    }
    
    void clear(id<MTLTexture> txt, const MTLClearColor& color) {
        assert(txt);
        MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor new];
        [[desc colorAttachments][0] setTexture:txt];
        [[desc colorAttachments][0] setClearColor:color];
        [[desc colorAttachments][0] setLoadAction:MTLLoadActionClear];
        [[desc colorAttachments][0] setStoreAction:MTLStoreActionStore];
        id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:desc];
        [enc endEncoding];
    }
    
    template <typename... T_Args>
    _VertexShader<T_Args...> VertexShader(std::string_view fn, T_Args&&... args) {
        return _VertexShader<T_Args...>{
            .fn = fn,
            .args = std::forward_as_tuple(args...),
        };
    }
    
    template <typename... T_Args>
    _FragmentShader<T_Args...> FragmentShader(std::string_view fn, T_Args&&... args) {
        return _FragmentShader<T_Args...>{
            .fn = fn,
            .args = std::forward_as_tuple(args...),
        };
    }
    
    template <typename... T_Args>
    _ComputeKernel<T_Args...> ComputeKernel(std::string_view fn, T_Args&&... args) {
        return _ComputeKernel<T_Args...>{
            .fn = fn,
            .args = std::forward_as_tuple(args...),
        };
    }
    
    // Render pass to a target texture
    template <typename... T_FragArgs>
    void render(
        id<MTLTexture> txt,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        render(txt, BlendType::None,
            VertexShader(_DefaultVertexShader),
            frag
        );
    }
    
    // Render pass to a target texture
    template <typename... T_FragArgs>
    void render(
        id<MTLTexture> txt,
        BlendType blendType,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        render(txt, blendType,
            VertexShader(_DefaultVertexShader),
            frag
        );
    }
    
    // Render pass to a target texture
    template <typename... T_VertArgs, typename... T_FragArgs>
    void render(
        id<MTLTexture> txt,
        BlendType blendType,
        const _VertexShader<T_VertArgs...>& vert,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        render(txt, blendType, MTLPrimitiveTypeTriangle, MDCTools::MetalUtil::SquareVertIdxCount, 1,
            vert,
            frag
        );
    }
    
    // Render pass to a target texture
    template <typename... T_VertArgs, typename... T_FragArgs>
    void render(
        id<MTLTexture> txt,
        BlendType blendType,
        MTLPrimitiveType primitiveType,
        size_t vertexCount,
        size_t instanceCount,
        const _VertexShader<T_VertArgs...>& vert,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        assert(txt);
        
        MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor new];
        [[desc colorAttachments][0] setTexture:txt];
        [[desc colorAttachments][0] setClearColor:{0,0,0,1}];
        [[desc colorAttachments][0] setLoadAction:MTLLoadActionLoad];
        [[desc colorAttachments][0] setStoreAction:MTLStoreActionStore];
        id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:desc];
        
//        [enc setTriangleFillMode:MTLTriangleFillModeLines];
        
        [enc setRenderPipelineState:_renderPipelineState(vert.fn, frag.fn, [txt pixelFormat], blendType)];
        [enc setFrontFacingWinding:MTLWindingCounterClockwise];
        [enc setCullMode:MTLCullModeNone];
        
        std::apply([=] (const auto&... args) {
            _SetBufferArgs(_ShaderType::Vertex, enc, 0, args...);
        }, vert.args);
        
        std::apply([=] (const auto&... args) {
            _SetBufferArgs(_ShaderType::Fragment, enc, 0, args...);
        }, frag.args);
        
        [enc drawPrimitives:primitiveType
            vertexStart:0
            vertexCount:vertexCount
            instanceCount:instanceCount];
        
        [enc endEncoding];
    }
    
    // Render pass with no target texture
    // (Fragment shaders typically use texture.write() in this case)
    template <typename... T_FragArgs>
    void render(
        size_t width,
        size_t height,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        render(width, height, BlendType::None,
            VertexShader(_DefaultVertexShader),
            frag
        );
    }
    
    // Render pass with no target texture
    // (Fragment shaders typically use texture.write() in this case)
    template <typename... T_FragArgs>
    void render(
        size_t width,
        size_t height,
        BlendType blendType,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        render(width, height, blendType,
            VertexShader(_DefaultVertexShader),
            frag
        );
    }
    
    // Render pass with no target texture
    // (Fragment shaders typically use texture.write() in this case)
    template <typename... T_VertArgs, typename... T_FragArgs>
    void render(
        size_t width,
        size_t height,
        BlendType blendType,
        const _VertexShader<T_VertArgs...>& vert,
        const _FragmentShader<T_FragArgs...>& frag
    ) {
        MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor new];
        [desc setRenderTargetWidth:width];
        [desc setRenderTargetHeight:height];
        [desc setDefaultRasterSampleCount:1];
        [[desc colorAttachments][0] setClearColor:{0,0,0,1}];
        [[desc colorAttachments][0] setLoadAction:MTLLoadActionDontCare];
        [[desc colorAttachments][0] setStoreAction:MTLStoreActionDontCare];
        id<MTLRenderCommandEncoder> enc = [cmdBuf() renderCommandEncoderWithDescriptor:desc];
        
        [enc setRenderPipelineState:_renderPipelineState(vert.fn, frag.fn, MTLPixelFormatInvalid, blendType)];
        [enc setFrontFacingWinding:MTLWindingCounterClockwise];
        [enc setCullMode:MTLCullModeNone];
        
        std::apply([=] (const auto&... args) {
            _SetBufferArgs(_ShaderType::Vertex, enc, 0, args...);
        }, vert.args);
        
        std::apply([=] (const auto&... args) {
            _SetBufferArgs(_ShaderType::Fragment, enc, 0, args...);
        }, frag.args);
        
        [enc drawPrimitives:MTLPrimitiveTypeTriangle
            vertexStart:0 vertexCount:MDCTools::MetalUtil::SquareVertIdxCount];
        
        [enc endEncoding];
    }
    
    // Compute pass with compute kernel
    template <typename... T_Args>
    void compute(
        size_t width,
        size_t height,
        const _ComputeKernel<T_Args...>& kernel
    ) {
        id<MTLComputeCommandEncoder> enc = [cmdBuf() computeCommandEncoder];
        id<MTLComputePipelineState> ps = _computePipelineState(kernel.fn);
        [enc setComputePipelineState:ps];
        
        std::apply([=] (const auto&... args) {
            _SetBufferArgs(enc, 0, args...);
        }, kernel.args);
        
        const NSUInteger w = [ps threadExecutionWidth];
        const NSUInteger h = [ps maxTotalThreadsPerThreadgroup] / w;
        const MTLSize threadgroupSize = {w, h, 1};
        const MTLSize threadgroupCount = {((NSUInteger)width+w-1)/w, ((NSUInteger)height+h-1)/h, 1};
        
        [enc dispatchThreadgroups:threadgroupCount threadsPerThreadgroup:threadgroupSize];
        [enc endEncoding];
    }
    
    void copy(id<MTLTexture> src, id<MTLBuffer> dst) {
        const size_t w = [src width];
        const size_t h = [src height];
        const size_t bytesPerPixel = BytesPerPixel([src pixelFormat]);
        const size_t bytesPerRow = w*bytesPerPixel;
        const size_t bytesPerImage = h*bytesPerRow;
        id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
        [blit copyFromTexture:src sourceSlice:0 sourceLevel:0 sourceOrigin:{}
            sourceSize:{w,h,1} toBuffer:dst destinationOffset:0
            destinationBytesPerRow:bytesPerRow
            destinationBytesPerImage:bytesPerImage];
        [blit endEncoding];
    }
    
    void copy(id<MTLBuffer> src, id<MTLTexture> dst) {
        const size_t w = [dst width];
        const size_t h = [dst height];
        const size_t bytesPerPixel = BytesPerPixel([dst pixelFormat]);
        const size_t bytesPerRow = w*bytesPerPixel;
        const size_t bytesPerImage = h*bytesPerRow;
        id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
        [blit copyFromBuffer:src sourceOffset:0
            sourceBytesPerRow:bytesPerRow
            sourceBytesPerImage:bytesPerImage
            sourceSize:{w,h,1} toTexture:dst
            destinationSlice:0 destinationLevel:0 destinationOrigin:{}];
        [blit endEncoding];
    }
    
    void copy(id<MTLTexture> src, id<MTLTexture> dst) {
        assert([src width] == [dst width]);
        assert([src height] == [dst height]);
        const MTLPixelFormat srcFmt = [src pixelFormat];
        const MTLPixelFormat dstFmt = [dst pixelFormat];
        // If the pixel formats are the same, just do a blit
        if (srcFmt == dstFmt) {
            id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
            [blit copyFromTexture:src toTexture:dst];
            [blit endEncoding];
        
        // Otherwise, use a fragment shader to convert between pixel formats
        } else {
            const size_t srcSamples = SamplesPerPixel(srcFmt);
            const size_t dstSamples = SamplesPerPixel(dstFmt);
            const char* fnName = nullptr;
            if (srcSamples==1 && dstSamples==1) {
                fnName = _ShaderNamespace "Copy1To1";
            } else if (srcSamples==1 && dstSamples==4) {
                fnName = _ShaderNamespace "Copy1To4";
            } else if (srcSamples==4 && dstSamples==4) {
                fnName = _ShaderNamespace "Copy4To4";
            } else {
                throw std::runtime_error("invalid source/destination combination");
            }
            
            render(dst, BlendType::None,
                // Fragment shader
                FragmentShader(fnName,
                    // Texture arguments
                    src
                )
            );
        }
    }
    
    void copy(id<MTLBuffer> src, id<MTLBuffer> dst) {
        id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
        [blit copyFromBuffer:src sourceOffset:0 toBuffer:dst destinationOffset:0 size:[src length]];
        [blit endEncoding];
    }
    
    Txt copy(id<MTLTexture> src) {
        Txt dst = textureCreate(src);
        copy(src, dst);
        return dst;
    }
    
    Buf copy(id<MTLBuffer> src) {
        Buf dst = bufferCreate(src);
        copy(src, dst);
        return dst;
    }
    
    void sync(id<MTLResource> rsrc) {
        id<MTLBlitCommandEncoder> blit = [cmdBuf() blitCommandEncoder];
        [blit synchronizeResource:rsrc];
        [blit endEncoding];
    }
    
    Txt textureCreate(
        MTLPixelFormat fmt,
        size_t width, size_t height,
        MTLTextureUsage usage=(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)
    ) {
        // Check if we already have a texture matching the given criteria
        TxtKey key(fmt, width, height, usage);
        TxtQueue& txts = _recycleTxts[key];
        // Check if we have a cached texture that matches our criteria
        if (!txts.empty()) {
            Txt txt = Txt(*this, txts.front());
            txts.pop();
            return txt;
        } else {
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
    }
    
    Txt textureCreate(id<MTLTexture> txt) {
        assert(txt);
        return textureCreate([txt pixelFormat], [txt width], [txt height], [txt usage]);
    }
    
    Txt textureCreate(id<MTLTexture> txt, MTLPixelFormat fmt) {
        assert(txt);
        return textureCreate(fmt, [txt width], [txt height], [txt usage]);
    }
    
    Txt textureCreate(id<MTLTexture> txt, MTLTextureUsage usage) {
        assert(txt);
        return textureCreate([txt pixelFormat], [txt width], [txt height], usage);
    }
    
    Buf bufferCreate(const void* data, size_t len, MTLStorageMode storageMode=MTLStorageModeShared) {
        // Note that we're returning a buffer with deferRecycle=true!
        // This is important because we use memcpy() to copy into the buffer, and the CPU doesn't know
        // when the GPU's done with the buffer. Therefore the buffer can't be recycled until the
        // MTLCommandBuffer is complete. See recycle login in _prepareDeferredRecycle().
        Buf buf = _bufferCreate(len, storageMode, true);
        memcpy([buf contents], data, len);
        if (storageMode == MTLStorageModeManaged) {
            [buf didModifyRange:{0,len}];
        }
        return buf;
    }
    
    Buf bufferCreate(size_t len, MTLStorageMode storageMode=MTLStorageModeShared) {
        return _bufferCreate(len, storageMode, false);
    }
    
    Buf bufferCreate(id<MTLBuffer> buf) {
        assert(buf);
        return _bufferCreate([buf length], [buf storageMode], false);
    }
    
    // Write samples (from a raw pointer) to a texture
    template <typename T>
    void textureWrite(
        id<MTLTexture> txt,
        T* samples,
        size_t samplesPerPixel,
        size_t bytesPerSample=sizeof(T),
        uintmax_t maxValue=std::numeric_limits<T>::max()
    ) {
        // Create a Metal buffer from `samples`, and copy it into the texture
        const size_t w = [txt width];
        const size_t h = [txt height];
        const size_t len = w*h*samplesPerPixel*sizeof(T);
        const Renderer::Buf buf = bufferCreate(samples, len);
        textureWrite(txt, buf, samplesPerPixel, bytesPerSample, maxValue);
    }
    
    // Write samples (from a MTLBuffer) to a texture
    void textureWrite(
        id<MTLTexture> txt,
        id<MTLBuffer> buf,
        size_t samplesPerPixel,
        size_t bytesPerSample,
        uintmax_t maxValue
    ) {
        const MTLPixelFormat fmt = [txt pixelFormat];
        const size_t w = [txt width];
        const size_t h = [txt height];
        const size_t inSamplesPerPixel = samplesPerPixel;
        const size_t inBytesPerSample = bytesPerSample;
        const size_t outSamplesPerPixel = SamplesPerPixel(fmt);
        
        const char* fnName = nullptr;
        if (inBytesPerSample == 1) {
            if (outSamplesPerPixel == 1)         fnName = _ShaderNamespace "LoadFloatFromU8";
            else if (outSamplesPerPixel == 4)    fnName = _ShaderNamespace "LoadFloat4FromU8";
        } else if (inBytesPerSample == 2) {
            if (outSamplesPerPixel == 1)         fnName = _ShaderNamespace "LoadFloatFromU16";
            else if (outSamplesPerPixel == 4)    fnName = _ShaderNamespace "LoadFloat4FromU16";
        }
        if (!fnName) throw std::runtime_error("invalid input/output data format");
        
        const uint32_t w32 = (uint32_t)w;
        const uint32_t h32 = (uint32_t)h;
        const uint32_t inSamplesPerPixel32 = (uint32_t)inSamplesPerPixel;
        const uint32_t maxValue32 = (uint32_t)maxValue;
        // Load pixel data into `txt`
        render(txt, BlendType::None,
            FragmentShader(
                fnName,
                // Buffer args
                w32,
                h32,
                inSamplesPerPixel32,
                maxValue32,
                buf
                // Texture args
            )
        );
    }
    
    // Read samples from a texture
    template <typename T>
    std::vector<T> textureRead(id<MTLTexture> txt) {
        const size_t w = [txt width];
        const size_t h = [txt height];
        const MTLPixelFormat fmt = [txt pixelFormat];
        const size_t samplesPerPixel = SamplesPerPixel(fmt);
        const size_t len = samplesPerPixel*w*h;
        std::vector<T> r;
        r.resize(len);
        textureRead(txt, r.data(), len, MTLRegionMake2D(0,0,w,h));
        return r;
    }
    
    // Read samples from a texture
    template <typename T>
    void textureRead(id<MTLTexture> txt, T* samples, size_t cap) {
        const size_t w = [txt width];
        const size_t h = [txt height];
        textureRead(txt, samples, cap, MTLRegionMake2D(0,0,w,h));
    }
    
    // Read samples from a texture
    template <typename T>
    void textureRead(id<MTLTexture> txt, T* samples, size_t cap, MTLRegion region) {
        const size_t w = [txt width];
        const MTLPixelFormat fmt = [txt pixelFormat];
        const size_t samplesPerPixel = SamplesPerPixel(fmt);
        assert(cap >= samplesPerPixel*region.size.width*region.size.height);
        const size_t bytesPerSample = BytesPerSample(fmt);
        assert(bytesPerSample == sizeof(T));
        const size_t bytesPerRow = samplesPerPixel*bytesPerSample*w;
        [txt getBytes:samples bytesPerRow:bytesPerRow fromRegion:region mipmapLevel:0];
    }
    
    void bufferClear(id<MTLBuffer> buf) {
        const size_t len = [buf length];
        memset([buf contents], 0, len);
        if ([buf resourceOptions] & MTLResourceStorageModeManaged) {
            [buf didModifyRange:{0,len}];
        }
    }
    
    // Create a CGImage from a texture
    id /* CGImageRef */ imageCreate(id<MTLTexture> txt) {
        const size_t w = [txt width];
        const size_t h = [txt height];
        const MTLPixelFormat fmt = [txt pixelFormat];
        const size_t samplesPerPixel = SamplesPerPixel(fmt);
        const size_t bytesPerSample = BytesPerSample(fmt);
        const size_t sampleCount = samplesPerPixel*w*h;
        const size_t bytesPerRow = samplesPerPixel*bytesPerSample*w;
        uint32_t opts = 0;
        
        // Add support for more pixel formats as needed...
        bool premulAlpha = false;
        bool srgbGammaApplied = false;
        switch (fmt) {
        // Gray
        case MTLPixelFormatR8Unorm:
            opts = 0;
            break;
        case MTLPixelFormatR16Unorm:
            opts = kCGBitmapByteOrder16Host;
            break;
        case MTLPixelFormatR16Float:
            opts = kCGBitmapFloatComponents|kCGBitmapByteOrder16Host;
            break;
        case MTLPixelFormatR32Float:
            opts = kCGBitmapFloatComponents|kCGBitmapByteOrder32Host;
            break;
        
        // Color
        case MTLPixelFormatRGBA8Unorm:
            opts = kCGImageAlphaPremultipliedLast;
            premulAlpha = true;
            break;
        case MTLPixelFormatRGBA8Unorm_sRGB:
            opts = kCGImageAlphaPremultipliedLast;
            premulAlpha = true;
            srgbGammaApplied = true;
            break;
        case MTLPixelFormatRGBA16Unorm:
            opts = kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder16Host;
            premulAlpha = true;
            break;
        case MTLPixelFormatRGBA16Float:
            opts = kCGImageAlphaPremultipliedLast|kCGBitmapFloatComponents|kCGBitmapByteOrder16Host;
            premulAlpha = true;
            break;
        case MTLPixelFormatRGBA32Float:
            opts = kCGImageAlphaPremultipliedLast|kCGBitmapFloatComponents|kCGBitmapByteOrder32Host;
            premulAlpha = true;
            break;
        default:
            throw std::runtime_error("invalid texture format");
        }
        
        if (premulAlpha) {
            // Load pixel data into `txt`
            Txt tmp = textureCreate(fmt, w, h);
            render(tmp, BlendType::None,
                FragmentShader(
                    _ShaderNamespace "PremulAlpha",
                    // Texture args
                    txt
                )
            );
            sync(tmp);
            commitAndWait();
            txt = tmp;
        }
        
        // Choose a colorspace if one wasn't supplied
        id /* CGColorSpaceRef */ colorSpace = nil;
        if (samplesPerPixel == 1) {
            colorSpace = GrayColorSpace();
        } else if (samplesPerPixel == 4) {
            if (srgbGammaApplied) {
                colorSpace = SRGBColorSpace();
            } else {
                colorSpace = LSRGBColorSpace();
            }
        } else {
            throw std::runtime_error("invalid texture format");
        }
        
        id ctx = CFBridgingRelease(CGBitmapContextCreate(nullptr, w, h, bytesPerSample*8,
            bytesPerRow, (CGColorSpaceRef)colorSpace, opts));
        
        if (!ctx) throw std::runtime_error("CGBitmapContextCreate returned nil");
        
        void* data = CGBitmapContextGetData((CGContextRef)ctx);
        if (bytesPerSample == 1)        textureRead(txt, (uint8_t*)data, sampleCount);
        else if (bytesPerSample == 2)   textureRead(txt, (uint16_t*)data, sampleCount);
        else if (bytesPerSample == 4)   textureRead(txt, (uint32_t*)data, sampleCount);
        else                            throw std::runtime_error("invalid bytesPerSample");
        return CFBridgingRelease(CGBitmapContextCreateImage((CGContextRef)ctx));
    }
    
    void debugTextureShow(id<MTLTexture> txt) {
        const char* outputPath = "/tmp/tempimage.png";
        
        sync(txt);
        commitAndWait();
        
        id img = imageCreate(txt);
        assert(img);
        NSURL* outputURL = [NSURL fileURLWithPath:@(outputPath)];
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithURL((CFURLRef)outputURL, kUTTypePNG, 1, nullptr);
        CGImageDestinationAddImage(imageDest, (__bridge CGImageRef)img, nullptr);
        CGImageDestinationFinalize(imageDest);
        system((std::string("open ") + outputPath).c_str());
    }
    
    id<MTLCommandBuffer> cmdBuf() {
        if (!_cmdBuf) _cmdBuf = [_commandQueue commandBuffer];
        return _cmdBuf;
    }
    
    // _prepareDeferredRecycle(): arrange for resources to be recycled after the MTLCommandBuffer is completed
    void _prepareDeferredRecycle() {
        __block std::list<id<MTLBuffer>> pending;
        {
            auto lock = std::unique_lock(_recycleBufs->lock);
            
            // Nothing to do if there are no pending buffers
            if (_recycleBufs->defer.empty()) return;
            
            _recycleBufs->pending++;
            pending = std::move(_recycleBufs->defer);
        }
        
        std::shared_ptr<_RecycleBufs> bufs = _recycleBufs;
        [_cmdBuf addCompletedHandler:^(id<MTLCommandBuffer>) {
            auto lock = std::unique_lock(bufs->lock);
            bufs->bufs.splice(bufs->bufs.end(), pending);
            bufs->pending--;
        }];
    }
    
    void commit() {
        if (!_cmdBuf) return;
        _prepareDeferredRecycle();
        [_cmdBuf commit];
        _cmdBuf = nil;
    }
    
    void commitAndWait() {
        if (!_cmdBuf) return;
        _prepareDeferredRecycle();
        [_cmdBuf commit];
        [_cmdBuf waitUntilCompleted];
        _cmdBuf = nil;
    }
    
    id<MTLDevice> dev = nil;

private:
    enum class _ShaderType {
        Vertex,
        Fragment,        
    };
    
    void _SetBufferArgs(_ShaderType type, id<MTLRenderCommandEncoder> enc, size_t idx) {}
    
    template <typename T, typename... Ts>
    void _SetBufferArgs(_ShaderType type, id<MTLRenderCommandEncoder> enc, size_t idx, T& t, Ts&&... ts) {
        using U = typename std::remove_cv<T>::type;
        if constexpr (!std::is_same<U,Txt>::value && !std::is_same<U,id<MTLTexture>>::value) {
            if constexpr (std::is_same<U,Buf>::value) {
                switch (type) {
                case _ShaderType::Vertex:   [enc setVertexBuffer:(id<MTLBuffer>)t offset:0 atIndex:idx]; break;
                case _ShaderType::Fragment: [enc setFragmentBuffer:(id<MTLBuffer>)t offset:0 atIndex:idx]; break;
                default:                    abort();
                }
            } else if constexpr (std::is_same<U,id<MTLBuffer>>::value) {
                switch (type) {
                case _ShaderType::Vertex:   [enc setVertexBuffer:t offset:0 atIndex:idx]; break;
                case _ShaderType::Fragment: [enc setFragmentBuffer:t offset:0 atIndex:idx]; break;
                default:                    abort();
                }
            } else {
                switch (type) {
                case _ShaderType::Vertex:   [enc setVertexBytes:&t length:sizeof(t) atIndex:idx]; break;
                case _ShaderType::Fragment: [enc setFragmentBytes:&t length:sizeof(t) atIndex:idx]; break;
                default:                    abort();
                }
            }
            _SetBufferArgs(type, enc, idx+1, std::forward<Ts>(ts)...);
        } else {
            // Start of texture arguments
            _SetTextureArgs(type, enc, 0, t, std::forward<Ts>(ts)...);
        }
    }
    
    void _SetTextureArgs(_ShaderType type, id<MTLRenderCommandEncoder> enc, size_t idx) {}
    
    template <typename T, typename... Ts>
    void _SetTextureArgs(_ShaderType type, id<MTLRenderCommandEncoder> enc, size_t idx, T& t, Ts&&... ts) {
        using U = typename std::remove_cv<T>::type;
        if constexpr (std::is_same<U,Txt>::value) {
            switch (type) {
            case _ShaderType::Vertex:   [enc setVertexTexture:(id<MTLTexture>)t atIndex:idx]; break;
            case _ShaderType::Fragment: [enc setFragmentTexture:(id<MTLTexture>)t atIndex:idx]; break;
            default:                    abort();
            }
        } else if constexpr (std::is_same<U,id<MTLTexture>>::value) {
            switch (type) {
            case _ShaderType::Vertex:   [enc setVertexTexture:t atIndex:idx]; break;
            case _ShaderType::Fragment: [enc setFragmentTexture:t atIndex:idx]; break;
            default:                    abort();
            }
        } else {
            static_assert(_AlwaysFalse<U>);
        }
        
        _SetTextureArgs(type, enc, idx+1, std::forward<Ts>(ts)...);
    }
    
    
    
    
    
    
    
    
    void _SetBufferArgs(id<MTLComputeCommandEncoder> enc, size_t idx) {}
    
    template <typename T, typename... Ts>
    void _SetBufferArgs(id<MTLComputeCommandEncoder> enc, size_t idx, T& t, Ts&&... ts) {
        using U = typename std::remove_cv<T>::type;
        if constexpr (!std::is_same<U,Txt>::value && !std::is_same<U,id<MTLTexture>>::value) {
            if constexpr (std::is_same<U,Buf>::value) {
                [enc setBuffer:(id<MTLBuffer>)t offset:0 atIndex:idx];
            } else if constexpr (std::is_same<U,id<MTLBuffer>>::value) {
                [enc setBuffer:t offset:0 atIndex:idx];
            } else {
                [enc setBytes:&t length:sizeof(t) atIndex:idx];
            }
            _SetBufferArgs(enc, idx+1, std::forward<Ts>(ts)...);
        } else {
            // Start of texture arguments
            _SetTextureArgs(enc, 0, t, std::forward<Ts>(ts)...);
        }
    }
    
    void _SetTextureArgs(id<MTLComputeCommandEncoder> enc, size_t idx) {}
    
    template <typename T, typename... Ts>
    void _SetTextureArgs(id<MTLComputeCommandEncoder> enc, size_t idx, T& t, Ts&&... ts) {
        using U = typename std::remove_cv<T>::type;
        if constexpr (std::is_same<U,Txt>::value) {
            [enc setTexture:(id<MTLTexture>)t atIndex:idx];
        } else if constexpr (std::is_same<U,id<MTLTexture>>::value) {
            [enc setTexture:t atIndex:idx];
        } else {
            static_assert(_AlwaysFalse<U>);
        }
        
        _SetTextureArgs(enc, idx+1, std::forward<Ts>(ts)...);
    }
    
    
    
    
    
    
    
    
    
    
    Buf _bufferCreate(size_t len, MTLStorageMode storageMode, bool deferRecycle) {
        // Return an existing buffer if its length is between len and 2*len,
        // and its options match `opts`
        auto lock = std::unique_lock(_recycleBufs->lock);
        for (auto it=_recycleBufs->bufs.begin(); it!=_recycleBufs->bufs.end(); it++) {
            id<MTLBuffer> buf = *it;
            const size_t bufLen = [buf length];
            const MTLStorageMode bufStorageMode = [buf storageMode];
            if (bufLen>=len && bufLen<=2*len && bufStorageMode==storageMode) {
                Buf b(*this, buf, deferRecycle);
                _recycleBufs->bufs.erase(it);
                return b;
            }
        }
        
        id<MTLBuffer> buf = [dev newBufferWithLength:len options:(storageMode<<MTLResourceStorageModeShift)];
        Assert(buf, return Buf());
        return Buf(*this, buf, deferRecycle);
    }
    
    void _recycle(id<MTLTexture> txt, bool deferRecycle) {
        assert(!deferRecycle); // We only defer recycling of buffers
        _recycleTxts[txt].push(txt);
    }
    
    void _recycle(id<MTLBuffer> buf, bool deferRecycle) {
        auto lock = std::unique_lock(_recycleBufs->lock);
        if (deferRecycle) {
            _recycleBufs->defer.push_back(buf);
        } else {
            _recycleBufs->bufs.push_back(buf);
        }
    }
    
    id<MTLRenderPipelineState> _renderPipelineState(std::string_view vertName, std::string_view fragName, MTLPixelFormat fmt, BlendType blendType) {
        RenderPipelineStateKey key(vertName, fragName, fmt, blendType);
        auto find = _renderPipelineStates.find(key);
        if (find != _renderPipelineStates.end()) return find->second;
        
        id<MTLFunction> vertShader = MDCTools::MetalUtil::MTLFunctionWithName(_lib, vertName);
        assert(vertShader);
        id<MTLFunction> fragShader = MDCTools::MetalUtil::MTLFunctionWithName(_lib, fragName);
        assert(fragShader);
        
        MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
        [desc setVertexFunction:vertShader];
        [desc setFragmentFunction:fragShader];
        [[desc colorAttachments][0] setPixelFormat:fmt];
        
        if (blendType == BlendType::Over) {
            [[desc colorAttachments][0] setBlendingEnabled:true];
            [[desc colorAttachments][0] setAlphaBlendOperation:MTLBlendOperationAdd];
            [[desc colorAttachments][0] setSourceAlphaBlendFactor:MTLBlendFactorSourceAlpha];
            [[desc colorAttachments][0] setDestinationAlphaBlendFactor:MTLBlendFactorOneMinusSourceAlpha];

            [[desc colorAttachments][0] setRgbBlendOperation:MTLBlendOperationAdd];
            [[desc colorAttachments][0] setSourceRGBBlendFactor:MTLBlendFactorSourceAlpha];
            [[desc colorAttachments][0] setDestinationRGBBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
        }
        
        id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:desc error:nil];
        Assert(ps, return nil);
        _renderPipelineStates.insert(find, {key, ps});
        return ps;
    }
    
    id<MTLComputePipelineState> _computePipelineState(std::string_view fnName) {
        auto find = _computePipelineStates.find(fnName);
        if (find != _computePipelineStates.end()) return find->second;
        
        id<MTLFunction> fn = MDCTools::MetalUtil::MTLFunctionWithName(_lib, fnName);
        assert(fn);
        
        id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn error:nil];
        Assert(ps, return nil);
        
        _computePipelineStates.insert(find, {std::string(fnName), ps});
        return ps;
    }
    
    class RenderPipelineStateKey {
    public:
        RenderPipelineStateKey(std::string_view vertName, std::string_view fragName, MTLPixelFormat fmt, BlendType blendType) :
        _vertName(vertName), _fragName(fragName), _fmt(fmt), _blendType(blendType) {}
        
        bool operator==(const RenderPipelineStateKey& x) const {
            if (_vertName != x._vertName)   return false;
            if (_fragName != x._fragName)   return false;
            if (_fmt != x._fmt)             return false;
            if (_blendType != x._blendType) return false;
            return true;
        }
        
        bool operator<(const RenderPipelineStateKey& x) const {
            if (_vertName != x._vertName)   return _vertName < x._vertName;
            if (_fragName != x._fragName)   return _fragName < x._fragName;
            if (_fmt != x._fmt)             return _fmt < x._fmt;
            if (_blendType != x._blendType) return _blendType < x._blendType;
            return false;
        }
        
//        size_t hash() const {
//            return Toastbox::HashInts(std::hash<std::string>{}(_vertName), std::hash<std::string>{}(_fragName), _fmt, _blendType);
//        }
//        
//        struct Hash {
//            size_t operator()(const RenderPipelineStateKey& x) const { return x.hash(); }
//        };
    
    private:
        std::string _vertName;
        std::string _fragName;
        MTLPixelFormat _fmt = MTLPixelFormatInvalid;
        BlendType _blendType = BlendType::None;
    };
    
    class TxtKey {
    public:
        TxtKey(id<MTLTexture> txt) :
        _fmt([txt pixelFormat]), _width([txt width]), _height([txt height]), _usage([txt usage]) {}
        
        TxtKey(MTLPixelFormat fmt, size_t width, size_t height, MTLTextureUsage usage) :
        _fmt(fmt), _width(width), _height(height), _usage(usage) {}
        
        bool operator==(const TxtKey& x) const {
            if (_fmt != x._fmt)         return false;
            if (_width != x._width)     return false;
            if (_height != x._height)   return false;
            if (_usage != x._usage)     return false;
            return true;
        }
        
        bool operator<(const TxtKey& x) const {
            if (_fmt != x._fmt)         return _fmt < x._fmt;
            if (_width != x._width)     return _width < x._width;
            if (_height != x._height)   return _height < x._height;
            if (_usage != x._usage)     return _usage < x._usage;
            return false;
        }
        
//        size_t hash() const {
//            return Toastbox::HashInts(_fmt, _width, _height, _usage);
//        }
//        
//        struct Hash {
//            size_t operator()(const TxtKey& x) const { return x.hash(); }
//        };
    
    private:
        MTLPixelFormat _fmt = MTLPixelFormatInvalid;
        size_t _width = 0;
        size_t _height = 0;
        MTLTextureUsage _usage = MTLTextureUsageUnknown;
    };
    
    using TxtQueue = std::queue<id<MTLTexture>>;
    
    struct _RecycleBufs {
        std::mutex lock; // Protects this struct
        std::list<id<MTLBuffer>> bufs;
        std::list<id<MTLBuffer>> defer;
        uint32_t pending = 0;
    };
    
    id <MTLLibrary> _lib = nil;
    id <MTLCommandQueue> _commandQueue = nil;
    std::map<RenderPipelineStateKey,id<MTLRenderPipelineState>> _renderPipelineStates;
    std::map<std::string,id<MTLComputePipelineState>,std::less<>> _computePipelineStates;
    std::map<TxtKey,TxtQueue> _recycleTxts;
    std::shared_ptr<_RecycleBufs> _recycleBufs;
    
    id<MTLCommandBuffer> _cmdBuf = nil;
    
    template <class...> static constexpr std::false_type _AlwaysFalse;
    
    friend class Resource<id<MTLTexture>>;
    friend class Resource<id<MTLBuffer>>;
#undef _DefaultVertexShader
#undef _ShaderNamespace
}; // class Renderer

} // namespace MDCTools

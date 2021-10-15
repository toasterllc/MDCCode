#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <unordered_map>
#import <queue>
#import <string>
#import <list>
#import <functional>
#import <assert.h>
#import "Assert.h"
#import "MetalUtil.h"
#import "HashInts.h"

namespace CFAViewer {

// Renderer is a wrapper for Metal APIs to make them more convenient.
// Renderer particularly improves executing multiple fragment render passes.
class Renderer {
public:
    template <typename T>
    class Resource {
    public:
        // Default constructor
        Resource() {}
        // Copy constructor: illegal
        Resource(const Resource& x) = delete;
        // Copy assignment operator: illegal
        Resource& operator=(const Resource& x) = delete;
        // Move constructor: use move assignment operator
        Resource(Resource&& x) { *this = std::move(x); }
        // Move assignment operator
        Resource& operator=(Resource&& x) {
            if (this != &x) {
                _recycle();
                _state = x._state;
                x._state = {};
            }
            return *this;
        }
        
        ~Resource() {
            _recycle();
        }
        
        operator T() const { return _state.resource; }
        
    private:
        Resource(Renderer& renderer, T resource) : _state{&renderer, resource} {}
        
        struct {
            Renderer* renderer = nullptr;
            T resource = nil;
        } _state;
        
        void _recycle() {
            if (_state.renderer) _state.renderer->_recycle(_state.resource);
            _state = {};
        }
        
        friend class Renderer;
    };
    
    using Txt = Resource<id<MTLTexture>>;
    using Buf = Resource<id<MTLBuffer>>;
    
    Renderer() {}
    Renderer(id<MTLDevice> dev, id<MTLLibrary> lib, id<MTLCommandQueue> commandQueue) :
    dev(dev), _lib(lib), _commandQueue(commandQueue) {
    }
    
    static size_t SamplesPerPixel(MTLPixelFormat fmt) {
        switch (fmt) {
        case MTLPixelFormatR8Unorm:     return 1;
        case MTLPixelFormatR16Unorm:    return 1;
        case MTLPixelFormatR32Float:    return 1;
        case MTLPixelFormatBGRA8Unorm:  return 4;
        case MTLPixelFormatRGBA16Unorm: return 4;
        case MTLPixelFormatRGBA16Float: return 4;
        case MTLPixelFormatRGBA32Float: return 4;
        default:                        throw std::runtime_error("invalid pixel format");
        }
    }
    
    static size_t BytesPerSample(MTLPixelFormat fmt) {
        switch (fmt) {
        case MTLPixelFormatR8Unorm:     return 1;
        case MTLPixelFormatR16Unorm:    return 2;
        case MTLPixelFormatR32Float:    return 4;
        case MTLPixelFormatBGRA8Unorm:  return 1;
        case MTLPixelFormatRGBA16Unorm: return 2;
        case MTLPixelFormatRGBA16Float: return 2;
        case MTLPixelFormatRGBA32Float: return 4;
        default:                        throw std::runtime_error("invalid pixel format");
        }
    }
    
    static size_t BytesPerPixel(MTLPixelFormat fmt) {
        return SamplesPerPixel(fmt)*BytesPerSample(fmt);
    }
    
    // Render pass to a target texture
    template <typename... Args>
    void render(
        const std::string& name,
        id<MTLTexture> txt,
        Args&... args
    ) {
        assert(txt);
        
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
        const NSUInteger bytesPerPixel = BytesPerPixel([src pixelFormat]);
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
        const NSUInteger bytesPerPixel = BytesPerPixel([dst pixelFormat]);
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
                fnName = "CFAViewer::Shader::Renderer::Copy1To1";
            } else if (srcSamples==1 && dstSamples==4) {
                fnName = "CFAViewer::Shader::Renderer::Copy1To4";
            } else if (srcSamples==4 && dstSamples==4) {
                fnName = "CFAViewer::Shader::Renderer::Copy4To4";
            } else {
                throw std::runtime_error("invalid source/destination combination");
            }
            
            render(fnName, dst,
                // Texture args
                src
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
    
    void present(id<CAMetalDrawable> drawable) {
        [cmdBuf() presentDrawable:drawable];
    }
    
    Txt textureCreate(
        MTLPixelFormat fmt,
        NSUInteger width, NSUInteger height,
        MTLTextureUsage usage=(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)
    ) {
        // Check if we already have a texture matching the given criteria
        TxtKey key(fmt, width, height, usage);
        TxtQueue& txts = _txts[key];
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
    
    Buf bufferCreate(NSUInteger len, MTLResourceOptions opts=MTLResourceStorageModeShared) {
        // Return an existing buffer if its length is between len and 2*len,
        // and its options match `opts`
        for (auto it=_bufs.begin(); it!=_bufs.end(); it++) {
            id<MTLBuffer> buf = *it;
            const NSUInteger bufLen = [buf length];
            const MTLResourceOptions bufOpts = [buf resourceOptions];
            if (bufLen>=len && bufLen<=2*len && bufOpts==opts) {
                Buf b(*this, buf);
                _bufs.erase(it);
                return b;
            }
        }
        
        id<MTLBuffer> buf = [dev newBufferWithLength:len options:opts];
        Assert(buf, return Buf());
        return Buf(*this, buf);
    }
    
    Buf bufferCreate(id<MTLBuffer> buf) {
        assert(buf);
        return bufferCreate([buf length], [buf resourceOptions]);
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
        // Create a Metal buffer, and copy the image contents into it
        const size_t w = [txt width];
        const size_t h = [txt height];
        const size_t len = w*h*samplesPerPixel*sizeof(T);
        Renderer::Buf buf = bufferCreate(len);
        memcpy([buf contents], samples, len);
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
            if (outSamplesPerPixel == 1)         fnName = "CFAViewer::Shader::Renderer::LoadFloatFromU8";
            else if (outSamplesPerPixel == 4)    fnName = "CFAViewer::Shader::Renderer::LoadFloat4FromU8";
        } else if (inBytesPerSample == 2) {
            if (outSamplesPerPixel == 1)         fnName = "CFAViewer::Shader::Renderer::LoadFloatFromU16";
            else if (outSamplesPerPixel == 4)    fnName = "CFAViewer::Shader::Renderer::LoadFloat4FromU16";
        }
        if (!fnName) throw std::runtime_error("invalid input/output data format");
        
        const uint32_t w32 = (uint32_t)w;
        const uint32_t h32 = (uint32_t)h;
        const uint32_t inSamplesPerPixel32 = (uint32_t)inSamplesPerPixel;
        const uint32_t maxValue32 = (uint32_t)maxValue;
        // Load pixel data into `txt`
        render(fnName, txt,
            // Buffer args
            w32,
            h32,
            inSamplesPerPixel32,
            maxValue32,
            buf
            // Texture args
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
        const NSUInteger len = [buf length];
        memset([buf contents], 0, len);
        [buf didModifyRange:{0,len}];
    }
    
    // Create a CGImage from a texture
    id /* CGImageRef */ createCGImage(id<MTLTexture> txt, id /* CGColorSpaceRef */ colorSpace=nil) {
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
            render("CFAViewer::Shader::Renderer::PremulAlpha", tmp,
                // Texture args
                txt
            );
            sync(tmp);
            commitAndWait();
            txt = tmp;
        }
        
        // Choose a colorspace if one wasn't supplied
        if (!colorSpace) {
            if (samplesPerPixel == 1) {
                colorSpace = _GrayColorSpace();
            } else if (samplesPerPixel == 4) {
                colorSpace = _SRGBColorSpace();
            } else {
                throw std::runtime_error("invalid texture format");
            }
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
    
    void debugShowTexture(id<MTLTexture> txt, id /* CGColorSpaceRef */ colorSpace=nil) {
        const char* outputPath = "/tmp/tempimage.png";
        
        sync(txt);
        commitAndWait();
        
        id img = createCGImage(txt, colorSpace);
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
        using U = typename std::remove_cv<T>::type;
        if constexpr (!std::is_same<U,Txt>::value &&
                      !std::is_same<U,id<MTLTexture>>::value) {
            if constexpr (std::is_same<U,Buf>::value) {
                [enc setFragmentBuffer:(id<MTLBuffer>)t offset:0 atIndex:idx];
            } else if constexpr (std::is_same<U,id<MTLBuffer>>::value) {
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
        using U = typename std::remove_cv<T>::type;
        if constexpr (std::is_same<U,Txt>::value) {
            [enc setFragmentTexture:(id<MTLTexture>)t atIndex:idx];
        } else if constexpr (std::is_same<U,id<MTLTexture>>::value) {
            [enc setFragmentTexture:t atIndex:idx];
        } else {
            static_assert(_AlwaysFalse<U>);
        }
        
        _SetTextureArgs(enc, idx+1, ts...);
    }
    
    static id _GrayColorSpace() {
        static CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
        return (__bridge id)cs;
    }
    
    static id _SRGBColorSpace() {
        static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        return (__bridge id)cs;
    }
    
    void _recycle(id<MTLTexture> txt) {
        _txts[txt].push(txt);
    }
    
    void _recycle(id<MTLBuffer> buf) {
        _bufs.push_back(buf);
    }
    
    id<MTLRenderPipelineState> _pipelineState(const std::string& name, MTLPixelFormat fmt) {
        PipelineStateKey key(name, fmt);
        auto find = _pipelineStates.find(key);
        if (find != _pipelineStates.end()) return find->second;
        
        id<MTLFunction> vertexShader = [_lib newFunctionWithName:@"CFAViewer::Shader::Renderer::VertexShader"];
        Assert(vertexShader, return nil);
        id<MTLFunction> fragmentShader = [_lib newFunctionWithName:@(name.c_str())];
        Assert(fragmentShader, return nil);
        
        MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
        [desc setVertexFunction:vertexShader];
        [desc setFragmentFunction:fragmentShader];
        [[desc colorAttachments][0] setPixelFormat:fmt];
        id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:desc error:nil];
        Assert(ps, return nil);
        _pipelineStates.insert(find, {key, ps});
        return ps;
    }
    
    class PipelineStateKey {
    public:
        PipelineStateKey(const std::string& name, MTLPixelFormat fmt) :
        _name(name), _fmt(fmt) {}
        
        bool operator==(const PipelineStateKey& x) const {
            return
                _name==x._name      &&
                _fmt==x._fmt        ;
        }
        
        size_t hash() const {
            return std::hash<std::string>{}(_name) ^ Toastbox::HashInts(_fmt);
        }
        
        struct Hash {
            size_t operator()(const PipelineStateKey& x) const { return x.hash(); }
        };
    
    private:
        std::string _name;
        MTLPixelFormat _fmt = MTLPixelFormatInvalid;
    };
    
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
            return Toastbox::HashInts(_fmt, _width, _height, _usage);
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
    
    using TxtQueue = std::queue<id<MTLTexture>>;
    id <MTLLibrary> _lib = nil;
    id <MTLCommandQueue> _commandQueue = nil;
    std::unordered_map<PipelineStateKey,id<MTLRenderPipelineState>,PipelineStateKey::Hash> _pipelineStates;
    std::unordered_map<TxtKey,TxtQueue,TxtKey::Hash> _txts;
    std::list<id<MTLBuffer>> _bufs;
    id<MTLCommandBuffer> _cmdBuf = nil;
    
    template <class...> static constexpr std::false_type _AlwaysFalse;
    
    friend class Resource<id<MTLTexture>>;
    friend class Resource<id<MTLBuffer>>;
}; // class Renderer

}; // namespace CFAViewer

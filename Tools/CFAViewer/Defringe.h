#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <unordered_map>
#import <string>
#import "Assert.h"
#import "MetalTypes.h"
#import "MetalUtil.h"
#import "ImageFilterTypes.h"
#import "DefringeTypes.h"

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
            [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
            [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
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
    
    class Defringe {
    public:
        Defringe() {}
        Defringe(id<MTLDevice> dev, id<MTLHeap> heap, id<MTLCommandQueue> q) :
        _dev(dev),
        _heap(heap),
        _q(q),
        _rm(_dev, [_dev newDefaultLibrary], _q) {
        }
        
        void run(const DefringeTypes::Options& opts, id<MTLTexture> raw) {
            const NSUInteger w = [raw width];
            const NSUInteger h = [raw height];
            
            id<MTLTexture> gInterp = MetalUtil::CreateTexture(_heap,
                MTLPixelFormatR32Float, w, h);
            
            _rm.renderPass("CFAViewer::ImageFilter::Defringe::WhiteBalanceForward", raw,
                [&](id<MTLRenderCommandEncoder> enc) {
                    [enc setFragmentBytes:&opts length:sizeof(opts) atIndex:0];
                    [enc setFragmentTexture:raw atIndex:0];
                });
            
            _rm.renderPass("CFAViewer::ImageFilter::Defringe::InterpolateG", gInterp,
                [&](id<MTLRenderCommandEncoder> enc) {
                    [enc setFragmentBytes:&opts length:sizeof(opts) atIndex:0];
                    [enc setFragmentTexture:raw atIndex:0];
                });
            
            for (uint32_t i=0; i<opts.iterations; i++) {
                _defringe(opts, raw, gInterp);
            }
            
            _rm.renderPass("CFAViewer::ImageFilter::Defringe::WhiteBalanceReverse", raw,
                [&](id<MTLRenderCommandEncoder> enc) {
                    [enc setFragmentBytes:&opts length:sizeof(opts) atIndex:0];
                    [enc setFragmentTexture:raw atIndex:0];
                });
            
            _rm.commit();
        }
    
    private:
        using Poly = Poly2D<double,4>;
        
        class TileAxis {
        private:
            static uint32_t _tileCount(uint32_t axisSize, uint32_t tileSize) {
                const uint32_t count = axisSize/tileSize;
                const uint32_t excess = axisSize%tileSize;
                const uint32_t rightSlice = excess/2;
                const uint32_t leftSlice = excess-rightSlice;
                return count + (leftSlice?1:0) + (rightSlice?1:0);
            }
            
        public:
            TileAxis(uint32_t axisSize, uint32_t tileSize, uint32_t tileOverlap) {
                _axisSize = axisSize;
                _tileSize = tileSize;
                _tileOverlap = tileOverlap;
                
                // Calculate number of full tiles (ignoring excess)
                tileCount = (_axisSize-_tileOverlap)/(_tileSize-_tileOverlap);
                // w: width of full tiles (ignoring excess)
                const uint32_t w = tileCount*_tileSize - (tileCount ? (tileCount-1)*_tileOverlap : 0);
                // Calculate total excess on left/right
                const uint32_t excess = _axisSize-w;
                // Calculate right/left excess. Update tile count if we have either.
                _rightExcess = excess/2;
                if (_rightExcess) tileCount++;
                _leftExcess = excess-_rightExcess;
                if (_leftExcess) tileCount++;
            }
            
            // tileOffset(): returns of the offset for the tile at a given index.
            // Border tiles and interior tiles will overlap.
            uint32_t tileOffset(uint32_t idx) const {
                if (_leftExcess && idx==0) return 0;
                if (_rightExcess && idx==tileCount-1) return _axisSize-_tileSize;
                return _leftExcess + (_tileSize-_tileOverlap)*(_leftExcess ? idx-1 : idx);
            }
            
            bool excessTile(uint32_t idx) const {
                if (_leftExcess && idx==0) return true;
                if (_rightExcess && idx==tileCount-1) return true;
                return false;
            }
            
            // Templated to allow support for doubles, while also being usable
            // from Metal shader contexts (which doesn't support doubles).
            template <typename T>
            T tileNormalizedCenter(uint32_t idx) const {
                return ((T)tileOffset(idx) + (T)_tileSize/2) / _axisSize;
            }
            
            uint32_t tileCount = 0;
            
        private:
            uint32_t _axisSize = 0;
            uint32_t _tileSize = 0;
            uint32_t _tileOverlap = 0;
            uint32_t _leftExcess = 0;
            uint32_t _rightExcess = 0;
        };
        
        class TileGrid {
        public:
            TileGrid(uint32_t imageWidth, uint32_t imageHeight, uint32_t tileSize, uint32_t tileOverlap) :
            x(imageWidth, tileSize, tileOverlap),
            y(imageHeight, tileSize, tileOverlap) {}
            
            const TileAxis x;
            const TileAxis y;
        };
        
        enum class Dir : uint8_t {
            X = 0,
            Y = 1,
        };
        
        template <typename T>
        class ColorDir {
        public:
            T& operator()(CFAColor color, Dir dir) {
                return _t[((uint8_t)color)>>1][(uint8_t)dir];
            }
            
            const T& operator()(CFAColor color, Dir dir) const {
                return _t[((uint8_t)color)>>1][(uint8_t)dir];
            }
        private:
            T _t[2][2] = {}; // _t[color][dir]; only red/blue colors allowed
        };
        
        template <typename T>
        class BufSampler {
        public:
            BufSampler(size_t imageWidth, size_t imageHeight, id<MTLBuffer> buf) :
            _imageWidth(imageWidth),
            _imageHeight(imageHeight) {
                _buf = (T*)[buf contents];
            }
            
            T px(ssize_t x, ssize_t y) const {
                x = std::clamp(x, (ssize_t)0, (ssize_t)_imageWidth-1);
                y = std::clamp(y, (ssize_t)0, (ssize_t)_imageHeight-1);
                const size_t idx = (y*_imageWidth)+x;
                return _buf[idx];
            }
            
        private:
            const size_t _imageWidth = 0;
            const size_t _imageHeight = 0;
            const T* _buf = nullptr;
        };
        
        struct TileTerms {
            double t0 = 0;
            double t1 = 0;
            double t2 = 0;
        };
        
        static constexpr uint32_t TileSize = 128;
        static constexpr uint32_t TileOverlap = 16;
        static constexpr double Eps = 1e-5;
        
        void _defringe(const DefringeTypes::Options& opts,
            id<MTLTexture> raw, id<MTLTexture> gInterp) {
            
            const NSUInteger w = [raw width];
            const NSUInteger h = [raw height];
            
            TileGrid grid((uint32_t)w, (uint32_t)h, TileSize, TileOverlap);
            ColorDir<Poly> polys = _solveForPolys(opts, grid, raw, gInterp);
            
            constexpr size_t ShiftTextureWidth = 20;
            constexpr size_t ShiftTextureSize = sizeof(float)*ShiftTextureWidth*ShiftTextureWidth;
            
            // Populate _shiftTxtBufs
            if (!_shiftTxtBufs(CFAColor::Red,Dir::X)) {
                for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
                    for (Dir dir : {Dir::X, Dir::Y}) {
                        _shiftTxtBufs(c,dir) = [_dev newBufferWithLength:ShiftTextureSize
                            options:MTLResourceCPUCacheModeDefaultCache];
                    }
                }
            }
            
            ColorDir<id<MTLTexture>> shiftTxts;
            for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
                for (Dir dir : {Dir::X, Dir::Y}) {
                    id<MTLBuffer> buf = _shiftTxtBufs(c,dir);
                    float* bufContents = (float*)[buf contents];
                    id<MTLTexture> txt = MetalUtil::CreateTexture(_heap, MTLPixelFormatR32Float, ShiftTextureWidth, ShiftTextureWidth);
                    
                    shiftTxts(c,dir) = txt;
                    
                    for (uint32_t y=0, i=0; y<ShiftTextureWidth; y++) {
                        for (uint32_t x=0; x<ShiftTextureWidth; x++, i++) {
                            const float xf = (x+.5)/ShiftTextureWidth;
                            const float yf = (y+.5)/ShiftTextureWidth;
                            bufContents[i] = polys(c,dir).eval(xf,yf);
                        }
                    }
                    
                    _rm.copy(buf, txt);
                }
            }
            
            id<MTLTexture> tmp = MetalUtil::CreateTexture(_heap, MTLPixelFormatR32Float, w, h);
            _rm.renderPass("CFAViewer::ImageFilter::Defringe::ApplyCorrection", raw,
                [&](id<MTLRenderCommandEncoder> enc) {
                    [enc setFragmentBytes:&opts length:sizeof(opts) atIndex:0];
                    [enc setFragmentBytes:&grid length:sizeof(grid) atIndex:1];
                    [enc setFragmentTexture:raw atIndex:0];
                    [enc setFragmentTexture:gInterp atIndex:1];
                    [enc setFragmentTexture:shiftTxts(CFAColor::Red,Dir::X) atIndex:2];
                    [enc setFragmentTexture:shiftTxts(CFAColor::Red,Dir::Y) atIndex:3];
                    [enc setFragmentTexture:shiftTxts(CFAColor::Blue,Dir::X) atIndex:4];
                    [enc setFragmentTexture:shiftTxts(CFAColor::Blue,Dir::Y) atIndex:5];
                });
            
            _rm.copy(tmp, raw);
        }
        
        ColorDir<Poly> _solveForPolys(const DefringeTypes::Options& opts, const TileGrid& grid, id<MTLTexture> raw, id<MTLTexture> gInterp) {
            
            const NSUInteger w = [raw width];
            const NSUInteger h = [raw height];
            const size_t bufLen = w*h*sizeof(float);
            if (!_rawBuf || [_rawBuf length]<bufLen) {
                _rawBuf = [_dev newBufferWithLength:bufLen
                    options:MTLResourceCPUCacheModeDefaultCache];
            }
            
            if (!_gInterpBuf || [_gInterpBuf length]<bufLen) {
                _gInterpBuf = [_dev newBufferWithLength:bufLen
                    options:MTLResourceCPUCacheModeDefaultCache];
            }
            
            _rm.copy(raw, _rawBuf);
            _rm.copy(gInterp, _gInterpBuf);
            _rm.commitAndWait();
            
            BufSampler<float> rawPx(w, h, _rawBuf);
            BufSampler<float> gInterpPx(w, h, _gInterpBuf);
            
            ColorDir<Poly> polys;
            for (uint32_t ty=0; ty<grid.y.tileCount; ty++) {
                for (uint32_t tx=0; tx<grid.x.tileCount; tx++) {
                    ColorDir<TileTerms> terms;
                    for (int32_t y=grid.y.tileOffset(ty); y<grid.y.tileOffset(ty)+TileSize; y++) {
                        int32_t x = grid.x.tileOffset(tx);
                        if (opts.cfaDesc.color(x,y) == CFAColor::Green) {
                            x++;
                        }
                        
                        const CFAColor c = opts.cfaDesc.color(x,y);
                        for (; x<grid.x.tileOffset(tx)+TileSize; x+=2) {
                            const double gSlopeX =
                                ( 3./16)*(gInterpPx.px(x+1,y+1) - gInterpPx.px(x-1,y+1)) +
                                (10./16)*(gInterpPx.px(x+1,y  ) - gInterpPx.px(x-1,y  )) +
                                ( 3./16)*(gInterpPx.px(x+1,y-1) - gInterpPx.px(x-1,y-1)) ;
                            
                            const double gSlopeY =
                                ( 3./16)*(gInterpPx.px(x+1,y+1) - gInterpPx.px(x+1,y-1)) +
                                (10./16)*(gInterpPx.px(x  ,y+1) - gInterpPx.px(x  ,y-1)) +
                                ( 3./16)*(gInterpPx.px(x-1,y+1) - gInterpPx.px(x-1,y-1)) ;
                            
                            const double rgDelta = rawPx.px(x,y) - gInterpPx.px(x,y);
                            
                            terms(c,Dir::X).t0 += rgDelta*rgDelta;
                            terms(c,Dir::Y).t0 += rgDelta*rgDelta;
                            
                            terms(c,Dir::X).t1 += gSlopeX*rgDelta;
                            terms(c,Dir::Y).t1 += gSlopeY*rgDelta;
                            
                            terms(c,Dir::X).t2 += gSlopeX*gSlopeX;
                            terms(c,Dir::Y).t2 += gSlopeY*gSlopeY;
                        }
                    }
                    
                    for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
                        for (Dir dir : {Dir::X, Dir::Y}) {
                            // Skip this tile if the shift denominator is too small
                            if (terms(c,dir).t2 < Eps) continue; // Prevent divide by 0
                            
                            const double shift = 2*( terms(c,dir).t1 /        terms(c,dir).t2 );
                            const double weight =  ( terms(c,dir).t2 / (Eps + terms(c,dir).t0 ));
                            const double x = grid.x.tileNormalizedCenter<double>(tx);
                            const double y = grid.y.tileNormalizedCenter<double>(ty);
                            
                            polys(c,dir).addPoint(weight, x, y, shift);
                        }
                    }
                }
            }
            
            return polys;
        }
        
        id<MTLDevice> _dev = nil;
        id<MTLHeap> _heap = nil;
        id<MTLCommandQueue> _q = nil;
        id<MTLBuffer> _rawBuf = nil;
        id<MTLBuffer> _gInterpBuf = nil;
        ColorDir<id<MTLBuffer>> _shiftTxtBufs;
        RenderManager _rm;
    };
};

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalTypes.h"
#import "MetalUtil.h"
#import "ImageFilterTypes.h"
#import "DefringeTypes.h"
#import "RenderManager.h"

namespace CFAViewer::ImageFilter {
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
            _rm.renderPass("CFAViewer::ImageFilter::Defringe::ApplyCorrection", tmp,
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
        
        // _solveForPolys(): this function returns a 2D polynomial whose value is
        // the shift amount (at a particular {x,y} point) to apply to the g channel
        // to minimize the difference between g and r/b. This function returns a
        // polynomial for each color and direction, so there are 4 polynomials
        // returned: redX, redY, blueX, blueY.
        //
        // Deriving this 2D polynomial requires 2 stages:
        //   - Stage 1: for each tile, solve for the shift amount that minimizes the
        //              difference between the g and r/b channels (see theory below).
        //   - Stage 2: smooth and interpolate the per-tile shift values by solving
        //              for a 2D polynomial whose independent variable is the {x,y}
        //              coordinate of the tile, and the dependent variable is the
        //              shift amount.
        // =========================
        // The theory behind Stage 1 (solving for the per-tile shift between the g and r/b
        // channels is):
        //
        //   Take two single-dimensional continuous functions: f(t) and g(t). Assume:
        //     1. f'(t) = d/dt[f(t)]     f'(t) is the derivative of f(t)
        //     2. g(t) = f(t+x)          g(t) is a time-shifted version of f(t)
        //
        //   f(t+x) can be approximated using the tangent line of f(t) at t, thus assuming
        //   that f(t) has constant slope in the neighborhood of `t`:
        //     g(t) = f(t+x) ≈ f(t) + x f'(t)
        //
        //   Solving for x (the amount that g(t) is shifted relative to f(t)):
        //     x ≈ (g(t) - f(t)) / f'(t)
        //
        //   Using this formula, we can perform a least squares regression to solve for x.
        //   We solve for this shift in the x and y directions independently.
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
                    
                    // For each color and direction, solve for the shift amount and
                    // its associated weight for this tile.
                    for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
                        for (Dir dir : {Dir::X, Dir::Y}) {
                            // Skip this tile if the shift denominator is too small
                            if (terms(c,dir).t2 < Eps) continue; // Prevent divide by 0
                            
                            // Multiply the shift by 2, because the result of the regression
                            // will be normalized to a magnitude of 1, but it needs to be
                            // normalized to a magnitude of 2, since the g pixels in the CFA
                            // occur every 2 pixels.
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

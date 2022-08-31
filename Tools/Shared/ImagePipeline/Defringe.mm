#import "Defringe.h"
#import <queue>
#import <thread>
#import "../Renderer.h"
#import "../Poly2D.h"
#import "../PixelSampler.h"
#import "../MetalUtil.h"
#import "ImagePipelineTypes.h"
using namespace MDCTools;
using namespace MDCTools::ImagePipeline;
using namespace MDCTools;

using Poly = Poly2D<double,4>;

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

struct TileShift {
    double x = 0;
    double y = 0;
    double shift = 0;
    double weight = 0;
};

static constexpr uint32_t TileSize = 128;
static constexpr uint32_t TileOverlap = 16;
static constexpr double Eps = 1e-5;

// Calculate the shift for a given tile.
// We solve for the shift indepedently for the x/y directions and red/blue colors,
// so there are 4 TileShifts returned: redX, redY, blueX, blueY.
// See theory explained above.
static ColorDir<TileShift> _calcTileShift(
    Renderer& renderer,
    const CFADesc& cfaDesc,
    const Defringe::Options& opts,
    const TileGrid& grid,
    const PixelSampler<float>& raw,
    const PixelSampler<float>& gInterp,
    uint32_t tx,
    uint32_t ty
) {
    struct TileTerms {
        double t0 = 0;
        double t1 = 0;
        double t2 = 0;
    };
    
    ColorDir<TileTerms> terms;
    for (int32_t y=grid.y.tileOffset(ty); y<grid.y.tileOffset(ty)+TileSize; y++) {
        int32_t x = grid.x.tileOffset(tx);
        if (cfaDesc.color(x,y) == CFAColor::Green) {
            x++;
        }
        
        const CFAColor c = cfaDesc.color(x,y);
        for (; x<grid.x.tileOffset(tx)+TileSize; x+=2) {
            const double k = opts.δfactor;
            const double kadj = (1-opts.δfactor)/2;
            const double gSlopeX =
                kadj*(gInterp.px(x+1,y+1) - gInterp.px(x-1,y+1)) +
                k   *(gInterp.px(x+1,y  ) - gInterp.px(x-1,y  )) +
                kadj*(gInterp.px(x+1,y-1) - gInterp.px(x-1,y-1)) ;
            
            const double gSlopeY =
                kadj*(gInterp.px(x+1,y+1) - gInterp.px(x+1,y-1)) +
                k   *(gInterp.px(x  ,y+1) - gInterp.px(x  ,y-1)) +
                kadj*(gInterp.px(x-1,y+1) - gInterp.px(x-1,y-1)) ;
            
            const double rgDelta = raw.px(x,y) - gInterp.px(x,y);
            
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
    ColorDir<TileShift> shifts;
    for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
        for (Dir dir : {Dir::X, Dir::Y}) {
            // Skip this tile if the shift denominator is too small
            if (terms(c,dir).t2 < Eps) continue; // Prevent divide by 0
            
            // Multiply the shift by 2, because the result of the regression
            // will be normalized to a magnitude of 1, but it needs to be
            // normalized to a magnitude of 2, since the g pixels in the CFA
            // occur every 2 pixels.
            shifts(c,dir).x = grid.x.tileNormalizedCenter<double>(tx);
            shifts(c,dir).y = grid.y.tileNormalizedCenter<double>(ty);
            shifts(c,dir).shift  = 2*( terms(c,dir).t1 /        terms(c,dir).t2  );
            shifts(c,dir).weight =   ( terms(c,dir).t2 / (Eps + terms(c,dir).t0 ));
        }
    }
    
    return shifts;
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
// channels) is:
//
//   Take two single-dimensional continuous functions: f(t) and g(t). Assume:
//     1. f'(t) = d/dt[f(t)]     f'(t) is the derivative of f(t)
//     2. g(t) = f(t+x)          g(t) is a time-shifted version of f(t)
//
//   f(t+x) can be approximated using the tangent line of f(t) at t, assuming
//   that f(t) has constant slope in the neighborhood of `t`. Therefore:
//     g(t) = f(t+x) ≈ f(t) + x f'(t)
//
//   Rearranging into the form of the standard matrix equation `Ax=b`:
//     f'(t) x ≈ g(t) - f(t)
//
//   Using this formula, we can perform a least squares regression to solve for x
//   (the amount that g(t) is shifted relative to f(t)).
//   We solve for this shift indepedently for the x/y directions and red/blue colors.

static ColorDir<Poly> _solveForPolys(Renderer& renderer,
    const CFADesc& cfaDesc, const Defringe::Options& opts,
    id<MTLTexture> raw, id<MTLTexture> gInterp
) {
    
    const size_t w = [raw width];
    const size_t h = [raw height];
    const size_t bufLen = w*h*sizeof(float);
    Renderer::Buf rawBuf = renderer.bufferCreate(bufLen);
    Renderer::Buf gInterpBuf = renderer.bufferCreate(bufLen);
    
    renderer.copy(raw, rawBuf);
    renderer.copy(gInterp, gInterpBuf);
    renderer.commitAndWait();
    
    PixelSampler<float> rawPx(w, h, (float*)[rawBuf contents]);
    PixelSampler<float> gInterpPx(w, h, (float*)[gInterpBuf contents]);
    
    TileGrid grid((uint32_t)w, (uint32_t)h, TileSize, TileOverlap);
    ColorDir<std::mutex> polyLocks;
    ColorDir<Poly> polys;
    
    struct TilePos {
        uint32_t x = 0;
        uint32_t y = 0;
    };
    
    // Populate `tiles`, the work queue for the worker threads
    std::mutex tilesLock;
    std::queue<TilePos> tiles;
    for (uint32_t ty=0; ty<grid.y.tileCount; ty++) {
        for (uint32_t tx=0; tx<grid.x.tileCount; tx++) {
            tiles.push({tx,ty});
        }
    }
    
    // Spawn N worker threads (N=number of cores)
    // Each thread calculates the shift for a specific tile and updates `polys` when complete.
    // The work is complete when all threads have exited.
    std::vector<std::thread> workers;
    for (int i=0; i<std::max(1,(int)std::thread::hardware_concurrency()); i++) {
        workers.emplace_back([&](){
            for (;;) {
                auto lock = std::unique_lock(tilesLock);
                    if (tiles.empty()) return;
                    TilePos tilePos = tiles.front();
                    tiles.pop();
                lock.unlock();
                
                const ColorDir<TileShift> tileShift = _calcTileShift(
                    renderer, cfaDesc, opts, grid,
                    rawPx, gInterpPx,
                    tilePos.x, tilePos.y
                );
                
                for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
                    for (Dir dir : {Dir::X, Dir::Y}) {
                        auto lock = std::unique_lock(polyLocks(c,dir));
                        polys(c,dir).addPoint(
                            tileShift(c,dir).weight,
                            tileShift(c,dir).x,
                            tileShift(c,dir).y,
                            tileShift(c,dir).shift
                        );
                    }
                }
            }
        });
    }
    
    // Wait for workers to complete
    for (std::thread& t : workers) t.join();
    
    return polys;
}

static void _defringe(Renderer& renderer,
    const CFADesc& cfaDesc, const Defringe::Options& opts,
    id<MTLTexture> raw, id<MTLTexture> gInterp
) {
    
    const size_t w = [raw width];
    const size_t h = [raw height];
    
    // Solve for the 2D polynomials that minimize the g-r/b difference
    ColorDir<Poly> polys = _solveForPolys(renderer, cfaDesc, opts, raw, gInterp);
    
    // Using the 2D polynomials, create small textures containing the shift
    // amounts across the image.
    // The final fragment shader will simply sample these textures to
    // determine the appropriate shift amount to use for each pixel.
    constexpr size_t ShiftTextureWidth = 20;
    ColorDir<float[16]> polyCoeffs;
    ColorDir<Renderer::Txt> shiftTxts;
    for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
        for (Dir dir : {Dir::X, Dir::Y}) {
            const auto& coeffs = polys(c,dir).coeffs();
            std::copy(coeffs.begin(), coeffs.end(), polyCoeffs(c,dir));
            
            shiftTxts(c,dir) = renderer.textureCreate(MTLPixelFormatR32Float,
                ShiftTextureWidth, ShiftTextureWidth,
                (MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite));
        }
    }
    
    renderer.render(ShiftTextureWidth, ShiftTextureWidth,
        renderer.FragmentShader(ImagePipelineShaderNamespace "Defringe::GenerateShiftTxts",
            // Buffer args
            cfaDesc,
            polyCoeffs(CFAColor::Red,Dir::X),
            polyCoeffs(CFAColor::Red,Dir::Y),
            polyCoeffs(CFAColor::Blue,Dir::X),
            polyCoeffs(CFAColor::Blue,Dir::Y),
            // Texture args
            shiftTxts(CFAColor::Red,Dir::X),
            shiftTxts(CFAColor::Red,Dir::Y),
            shiftTxts(CFAColor::Blue,Dir::X),
            shiftTxts(CFAColor::Blue,Dir::Y)
        )
    );
    
    // Apply the defringe correction.
    // We have to render to `tmp` (not `raw`), because
    // ApplyCorrection() samples pixels in `raw` outside the render target pixel,
    // which would introduce a data race if we rendered to `raw` while also sampling it.
    Renderer::Txt tmp = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
    renderer.render(tmp,
        renderer.FragmentShader(ImagePipelineShaderNamespace "Defringe::ApplyCorrection",
            // Buffer args
            cfaDesc,
            opts.αthresh,
            opts.γthresh,
            opts.γfactor,
            opts.δfactor,
            // Texture args
            raw,
            gInterp,
            shiftTxts(CFAColor::Red,Dir::X),
            shiftTxts(CFAColor::Red,Dir::Y),
            shiftTxts(CFAColor::Blue,Dir::X),
            shiftTxts(CFAColor::Blue,Dir::Y)
        )
    );
    
    renderer.copy(tmp, raw);
}

namespace MDCTools::ImagePipeline {

void Defringe::Run(Renderer& renderer, const CFADesc& cfaDesc,
    const Options& opts, id<MTLTexture> raw) {
    
    const size_t w = [raw width];
    const size_t h = [raw height];
    
    Renderer::Txt gInterp = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
    renderer.render(gInterp,
        renderer.FragmentShader(ImagePipelineShaderNamespace "Defringe::InterpolateG",
            // Buffer args
            cfaDesc,
            // Texture args
            raw
        )
    );
    
    for (uint32_t i=0; i<opts.rounds; i++) {
        _defringe(renderer, cfaDesc, opts, raw, gInterp);
    }
}

}; // MDCTools::ImagePipeline

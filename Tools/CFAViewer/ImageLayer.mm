#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <mutex>
#import <vector>
#import "ImageLayer.h"
#import "ImageLayerTypes.h"
#import "Assert.h"
#import "Util.h"
#import "ColorUtil.h"
#import "TimeInstant.h"
#import "Poly2D.h"
using namespace CFAViewer;
using namespace CFAViewer::MetalTypes;
using namespace CFAViewer::ImageLayerTypes;
using namespace ColorUtil;

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _library;
    NSMutableDictionary* _pipelineStates;
//    id<MTLRenderPipelineState> _debayerPipelineState;
//    id<MTLRenderPipelineState> _colorAdjustPipelineState;
//    id<MTLRenderPipelineState> _findHighlightsPipelineState;
//    id<MTLRenderPipelineState> _srgbGammaPipelineState;
    
    struct {
        std::mutex lock; // Protects this struct
        bool rawMode = false;
        bool correctChromaticAberration = false;
        RenderContext ctx;
        bool debayerLMMSEGammaEnabled = false;
        ImageAdjustments imageAdjustments;
        id<MTLBuffer> pixelData = nil;
        
        id<MTLBuffer> sampleBuf_CamRaw_D50 = nil;
        id<MTLBuffer> sampleBuf_XYZ_D50 = nil;
        id<MTLBuffer> sampleBuf_SRGB_D65 = nil;
        
        ImageLayerDataChangedHandler dataChangedHandler = nil;
    } _state;
    
    Histogram _inputHistogram __attribute__((aligned(4096)));
    id<MTLBuffer> _inputHistogramBuf;
    Histogram _outputHistogram __attribute__((aligned(4096)));
    id<MTLBuffer> _outputHistogramBuf;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setActions:LayerNullActions()];
    
    _device = MTLCreateSystemDefaultDevice();
    Assert(_device, return nil);
    [self setDevice:_device];
    [self setPixelFormat:MTLPixelFormatBGRA8Unorm];
    
    _commandQueue = [_device newCommandQueue];
    
    _library = [_device newDefaultLibraryWithBundle:[NSBundle bundleForClass:[self class]] error:nil];
    Assert(_library, return nil);
    
    _pipelineStates = [NSMutableDictionary new];
    
    auto lock = std::lock_guard(_state.lock);
        _state.sampleBuf_CamRaw_D50 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
        _state.sampleBuf_XYZ_D50 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
        _state.sampleBuf_SRGB_D65 = [_device newBufferWithLength:sizeof(simd::float3) options:MTLResourceStorageModeShared];
    
    return self;
}

- (void)setImage:(const Image&)image {
    // If we don't have pixel data, ensure that our image has 0 pixels
    NSParameterAssert(image.pixels || (image.width*image.height)==0);
    
    auto lock = std::lock_guard(_state.lock);
    
    const size_t pixelCount = image.width*image.height;
    
    // Reset image size in case something fails
    _state.ctx.imageWidth = 0;
    _state.ctx.imageHeight = 0;
    
    const size_t len = pixelCount*sizeof(ImagePixel);
    if (len) {
        if (!_state.pixelData || [_state.pixelData length]<len) {
            _state.pixelData = [_device newBufferWithLength:len options:MTLResourceCPUCacheModeDefaultCache];
            Assert(_state.pixelData, return);
        }
        
        // Copy the pixel data into the Metal buffer
        memcpy([_state.pixelData contents], image.pixels, len);
        
        // Set the image size now that we have image data
        _state.ctx.imageWidth = image.width;
        _state.ctx.imageHeight = image.height;
    
    } else {
        _state.pixelData = nil;
    }
    
    const CGFloat scale = [self contentsScale];
    [self setBounds:{0, 0, _state.ctx.imageWidth/scale, _state.ctx.imageHeight/scale}];
    [self setNeedsDisplay];
}

- (void)setRawMode:(bool)rawMode {
    auto lock = std::lock_guard(_state.lock);
    _state.rawMode = rawMode;
    [self setNeedsDisplay];
}

- (void)setCorrectChromaticAberration:(bool)correctChromaticAberration {
    auto lock = std::lock_guard(_state.lock);
    _state.correctChromaticAberration = correctChromaticAberration;
    [self setNeedsDisplay];
}

static simd::float3x3 simdFromMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
    };
}

static simd::float3 simdFromMat(const Mat<double,3,1>& m) {
    return {(float)m[0], (float)m[1], (float)m[2]};
}

- (void)setColorMatrix:(const Mat<double,3,3>&)cm {
    auto lock = std::lock_guard(_state.lock);
    _state.ctx.colorMatrix = simdFromMat(cm);
    
    // From "How the CIE 1931 Color-Matching Functions Were
    // Derived from Wright–Guild Data", page 19
    const Mat<double,3,3> XYZ_E_From_CIERGB_E(
        0.49000, 0.31000, 0.20000,
        0.17697, 0.81240, 0.01063,
        0.00000, 0.01000, 0.99000
    );
    
    // Bradform chromatic adaptation: XYZ.E -> XYZ.D50
    const Mat<double,3,3> XYZ_D50_From_XYZ_E(
         0.9977545, -0.0041632, -0.0293713,
        -0.0097677,  1.0183168, -0.0085490,
        -0.0074169,  0.0134416,  0.8191853
    );
    
    const Mat<double,3,3> XYZ_D50_From_CIERGB_E = XYZ_D50_From_XYZ_E * XYZ_E_From_CIERGB_E;
    const Mat<double,3,3> CameraRaw_D50_From_XYZ_D50 = cm.inv();
    
    // maxY = maximum luminance possible, given the color matrix `cm`
//    const double maxY = std::max(0.,cm[3]) + std::max(0.,cm[4]) + std::max(0.,cm[5]);
    
    // Luminance to apply to the primaries
    const double maxY = 6.5;
    
    // Enumerate the primaries in the CIE RGB colorspace, and convert them to XYY
    Color_XYY_D50 whitePoint_XYY_D50 = XYYFromXYZ(XYZ_D50_From_CIERGB_E * Color_CIERGB_E(1.,1.,1.));
    
    // Set the luminance of every color to the maximum luminance possible
    whitePoint_XYY_D50[2] = maxY;
    
    _state.ctx.whitePoint_XYY_D50 = simdFromMat(whitePoint_XYY_D50);
    _state.ctx.whitePoint_CamRaw_D50 = simdFromMat(CameraRaw_D50_From_XYZ_D50 * XYZFromXYY(whitePoint_XYY_D50));
    
    [self setNeedsDisplay];
}

- (void)setDebayerLMMSEGammaEnabled:(bool)en {
    auto lock = std::lock_guard(_state.lock);
    _state.debayerLMMSEGammaEnabled = en;
    [self setNeedsDisplay];
}

- (void)setImageAdjustments:(const CFAViewer::ImageLayerTypes::ImageAdjustments&)adj {
    auto lock = std::lock_guard(_state.lock);
    _state.imageAdjustments = adj;
    [self setNeedsDisplay];
}

- (void)setHighlightFactor:(const Mat<double,3,3>&)hf {
    auto lock = std::lock_guard(_state.lock);
    _state.ctx.highlightFactorR = {(float)hf.at(0,0), (float)hf.at(0,1), (float)hf.at(0,2)};
    _state.ctx.highlightFactorG = {(float)hf.at(1,0), (float)hf.at(1,1), (float)hf.at(1,2)};
    _state.ctx.highlightFactorB = {(float)hf.at(2,0), (float)hf.at(2,1), (float)hf.at(2,2)};
    [self setNeedsDisplay];
}

- (MetalTypes::Histogram)inputHistogram {
    return _inputHistogram;
}

- (MetalTypes::Histogram)outputHistogram {
    return _outputHistogram;
}

- (id<MTLRenderPipelineState>)_pipelineState:(NSString*)name {
    return [self _pipelineState:name format:MTLPixelFormatRGBA32Float];
}

- (id<MTLRenderPipelineState>)_pipelineState:(NSString*)name format:(MTLPixelFormat)format {
    NSParameterAssert(name);
    id<MTLRenderPipelineState> ps = _pipelineStates[name];
    if (!ps) {
        id<MTLFunction> vertexShader = [_library newFunctionWithName:@"ImageLayer::VertexShader"];
        Assert(vertexShader, return nil);
        id<MTLFunction> fragmentShader = [_library newFunctionWithName:name];
        Assert(fragmentShader, return nil);
        
        MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
        [pipelineDescriptor setVertexFunction:vertexShader];
        [pipelineDescriptor setFragmentFunction:fragmentShader];
        [[pipelineDescriptor colorAttachments][0] setPixelFormat:format];
        ps = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
        Assert(ps, return nil);
        _pipelineStates[name] = ps;
    }
    return ps;
}

using RenderPassBlock = void(^)(id<MTLRenderCommandEncoder>);
// _state.lock must be held
- (void)_renderPass:(id<MTLCommandBuffer>)cmdBuf texture:(id<MTLTexture>)texture
    name:(NSString*)name block:(NS_NOESCAPE RenderPassBlock)block {
    
    NSParameterAssert(cmdBuf);
    NSParameterAssert(texture);
    NSParameterAssert(name);
    NSParameterAssert(block);
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [[renderPassDescriptor colorAttachments][0] setTexture:texture];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    id<MTLRenderCommandEncoder> encoder = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    [encoder setRenderPipelineState:[self _pipelineState:name format:[texture pixelFormat]]];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
    
    block(encoder);
    
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
        vertexStart:0 vertexCount:MetalTypes::SquareVertIdxCount];
    
    [encoder endEncoding];
}

// _state.lock must be held
- (id<MTLTexture>)_newTextureWithPixelFormat:(MTLPixelFormat)fmt {
    return [self _newTextureWithPixelFormat:fmt
        width:_state.ctx.imageWidth
        height:_state.ctx.imageHeight
        usage:(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)];
}

// _state.lock must be held
- (id<MTLTexture>)_newTextureWithPixelFormat:(MTLPixelFormat)fmt
    usage:(MTLTextureUsage)usage {
    return [self _newTextureWithPixelFormat:fmt
        width:_state.ctx.imageWidth
        height:_state.ctx.imageHeight
        usage:usage];
}

- (id<MTLTexture>)_newTextureWithPixelFormat:(MTLPixelFormat)fmt
    width:(NSUInteger)width
    height:(NSUInteger)height
    usage:(MTLTextureUsage)usage {
    
    MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
    [desc setTextureType:MTLTextureType2D];
    [desc setWidth:width];
    [desc setHeight:height];
    [desc setPixelFormat:fmt];
    [desc setUsage:usage];
    id<MTLTexture> txt = [_device newTextureWithDescriptor:desc];
    Assert(txt, return nil);
    return txt;
}

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
    
//    // tileIndex(): returns the index for a tile at the given offset.
//    // For border tiles that overlap interior tiles, gives precedence to interior tiles.
//    uint32_t tileIndex(uint32_t off) const {
//        if (off < _leftExcess) return 0;
//        if (off >= _axisSize-_rightExcess) return tileCount-1;
//        return ((off-_leftExcess)/_tileSize) + (_leftExcess?1:0);
//    }
    
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

enum class TileDir : uint8_t {
    X = 0,
    Y = 1,
};

template <typename T>
class ColorDir {
public:
    T& operator()(CFAColor color, TileDir dir) {
        return _t[((uint8_t)color)>>1][(uint8_t)dir];
    }
    
    const T& operator()(CFAColor color, TileDir dir) const {
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

- (id<MTLTexture>)_correctChromaticAberrationIteration:(id<MTLTexture>)rawTxt gInterpTxt:(id<MTLTexture>)gInterpTxt {
    id<MTLTexture> raw2Txt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
    id<MTLBuffer> rawBuf = [_device newBufferWithLength:4*_state.ctx.imageWidth*_state.ctx.imageHeight
        options:MTLResourceCPUCacheModeDefaultCache];
    
    id<MTLBuffer> gInterpBuf = [_device newBufferWithLength:4*_state.ctx.imageWidth*_state.ctx.imageHeight
        options:MTLResourceCPUCacheModeDefaultCache];
    
    id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
    
    [blit copyFromTexture:rawTxt sourceSlice:0 sourceLevel:0 sourceOrigin:{}
        sourceSize:{[rawTxt width], [rawTxt height], 1} toBuffer:rawBuf
        destinationOffset:0 destinationBytesPerRow:4*[rawTxt width]
        destinationBytesPerImage:4*[rawTxt width]*[rawTxt height]];
    
    [blit copyFromTexture:gInterpTxt sourceSlice:0 sourceLevel:0 sourceOrigin:{}
        sourceSize:{[gInterpTxt width], [gInterpTxt height], 1} toBuffer:gInterpBuf
        destinationOffset:0 destinationBytesPerRow:4*[gInterpTxt width]
        destinationBytesPerImage:4*[gInterpTxt width]*[gInterpTxt height]];
    
    [blit endEncoding];
    
    [cmdBuf commit];
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [cmdBuf waitUntilCompleted];
    
    cmdBuf = [_commandQueue commandBuffer];
    
//    NSLog(@"gInterpTxt:%@\n\nbuffer:%p\n", gInterpTxt, [gInterpTxt buffer]);
//    NSLog(@"gInterpBuf:%@\n\ncontents: %p\n\n", gInterpBuf, [gInterpBuf contents]);
//    exit(0);
    
    BufSampler<float> rawPx([rawTxt width], [rawTxt height], rawBuf);
    BufSampler<float> gInterpPx([gInterpTxt width], [gInterpTxt height], gInterpBuf);
    
    constexpr double Eps = 1e-5;
    constexpr uint32_t TileSize = 128;
    constexpr uint32_t TileOverlap = 16;
    using Dir = TileDir;
    using Poly = Poly2D<double,4>;
    
    TileGrid grid(_state.ctx.imageWidth, _state.ctx.imageHeight, TileSize, TileOverlap);
    ColorDir<Poly> polys;
    
    for (uint32_t ty=0; ty<grid.y.tileCount; ty++) {
        for (uint32_t tx=0; tx<grid.x.tileCount; tx++) {
            ColorDir<TileTerms> terms;
            for (int32_t y=grid.y.tileOffset(ty); y<grid.y.tileOffset(ty)+TileSize; y++) {
                int32_t x = grid.x.tileOffset(tx);
                if (_state.ctx.cfaColor(x,y) == CFAColor::Green) {
                    x++;
                }
                
                const CFAColor c = _state.ctx.cfaColor(x,y);
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
    
    constexpr size_t ShiftTextureWidth = 20;
    constexpr size_t ShiftTextureSize = sizeof(float)*ShiftTextureWidth*ShiftTextureWidth;
    ColorDir<id<MTLTexture>> shiftTxts;
    blit = [cmdBuf blitCommandEncoder];
    for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
        for (Dir dir : {Dir::X, Dir::Y}) {
            id<MTLBuffer> buf = [_device newBufferWithLength:ShiftTextureSize
                options:MTLResourceCPUCacheModeDefaultCache];
            float* bufContents = (float*)[buf contents];
            id<MTLTexture> txt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float
                width:ShiftTextureWidth
                height:ShiftTextureWidth
                usage:MTLTextureUsageShaderRead];
            
            shiftTxts(c,dir) = txt;
            
            for (uint32_t y=0, i=0; y<ShiftTextureWidth; y++) {
                for (uint32_t x=0; x<ShiftTextureWidth; x++, i++) {
                    const float xf = (x+.5)/ShiftTextureWidth;
                    const float yf = (y+.5)/ShiftTextureWidth;
                    bufContents[i] = polys(c,dir).eval(xf,yf);
                }
            }
            
            [blit copyFromBuffer:buf sourceOffset:0 sourceBytesPerRow:sizeof(float)*ShiftTextureWidth
                sourceBytesPerImage:ShiftTextureSize sourceSize:{ShiftTextureWidth, ShiftTextureWidth, 1}
                toTexture:txt destinationSlice:0 destinationLevel:0 destinationOrigin:{0,0,0}];
        }
    }
    [blit endEncoding];
    
    [self _renderPass:cmdBuf texture:raw2Txt name:@"ChromaticAberrationCorrector::ApplyCorrection"
        block:^(id<MTLRenderCommandEncoder> encoder) {
            [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
            [encoder setFragmentBytes:&grid length:sizeof(grid) atIndex:1];
            [encoder setFragmentTexture:rawTxt atIndex:0];
            [encoder setFragmentTexture:gInterpTxt atIndex:1];
            [encoder setFragmentTexture:shiftTxts(CFAColor::Red,Dir::X) atIndex:2];
            [encoder setFragmentTexture:shiftTxts(CFAColor::Red,Dir::Y) atIndex:3];
            [encoder setFragmentTexture:shiftTxts(CFAColor::Blue,Dir::X) atIndex:4];
            [encoder setFragmentTexture:shiftTxts(CFAColor::Blue,Dir::Y) atIndex:5];
        }
    ];
    
    [cmdBuf commit];
    
    return raw2Txt;
}

- (void)_correctChromaticAberration:(id<MTLTexture>)rawTxt iterations:(NSUInteger)iterations {
    id<MTLTexture> gInterpTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    {
        id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
        [self _renderPass:cmdBuf texture:rawTxt name:@"ChromaticAberrationCorrector::WhiteBalanceForward"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                [encoder setFragmentTexture:rawTxt atIndex:0];
            }
        ];
        
        [self _renderPass:cmdBuf texture:gInterpTxt name:@"ChromaticAberrationCorrector::InterpolateG"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                [encoder setFragmentTexture:rawTxt atIndex:0];
            }
        ];
        
        [cmdBuf commit];
    }
    
    id<MTLTexture> cacTxt = rawTxt;
    for (NSUInteger i=0; i<iterations; i++) {
        cacTxt = [self _correctChromaticAberrationIteration:cacTxt gInterpTxt:gInterpTxt];
    }
    
    {
        id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
        [self _renderPass:cmdBuf texture:rawTxt name:@"ChromaticAberrationCorrector::WhiteBalanceReverse"
            block:^(id<MTLRenderCommandEncoder> encoder) {
                [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                [encoder setFragmentTexture:cacTxt atIndex:0];
            }
        ];
        [cmdBuf commit];
    }
}

// Lock must be held
- (void)_displayToTexture:(id<MTLTexture>)outTxt drawable:(id<CAMetalDrawable>)drawable {
    NSParameterAssert(outTxt);
    
//    TileAxis axis(211, 100);
//    for (uint32_t off=0; off<250; off++) {
//        printf("off=%u idx=%u\n", off, axis.tileIndex(off));
//    }
//    exit(0);
    
    // Short-circuit if we don't have any image data
    if (!_state.pixelData) return;
    
    _inputHistogram = Histogram();
    _outputHistogram = Histogram();
    
//    id<MTLTexture> rgDeltaTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
//    id<MTLTexture> gSlopeXTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
//    id<MTLTexture> gSlopeYTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
//    id<MTLTexture> tmpTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float
//        usage:(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite)];
    
    id<MTLTexture> rawTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> raw2Txt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> filteredHTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> filteredVTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> diffHTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> diffVTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> diffGRTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> diffGBTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> lTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> blurredLTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float
        usage:(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite)];
    id<MTLTexture> txt = [self _newTextureWithPixelFormat:MTLPixelFormatRGBA32Float];
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
    [self _renderPass:cmdBuf texture:rawTxt name:@"ImageLayer::LoadRaw"
        block:^(id<MTLRenderCommandEncoder> encoder) {
            [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
            [encoder setFragmentBuffer:_state.pixelData offset:0 atIndex:1];
            [encoder setFragmentBuffer:_state.sampleBuf_CamRaw_D50 offset:0 atIndex:2];
        }
    ];
    
    // Raw mode (bilinear debayer only)
    if (_state.rawMode) {
        // De-bayer render pass
        {
            // ImageLayer_DebayerBilinear
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::DebayerBilinear"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:rawTxt atIndex:0];
                }
            ];
        }
        
        // Run the final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
        {
            [self _renderPass:cmdBuf texture:outTxt name:@"ImageLayer::Display"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
    
    } else {
        if (_state.correctChromaticAberration) {
            [cmdBuf commit];
            [self _correctChromaticAberration:rawTxt iterations:2];
            cmdBuf = [_commandQueue commandBuffer];
        }
        
        // Fix highlights
        {
            [self _renderPass:cmdBuf texture:raw2Txt name:@"ImageLayer::FixHighlightsRaw"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:rawTxt atIndex:0];
                }
            ];
            // TODO: figure out a better way to do this. Once we start using an
            // TODO: MTLHeap (or similar) does that solve this?
            std::swap(rawTxt, raw2Txt);
        }
        
        // LMMSE Debayer
        {
            // Gamma before (improves quality of edges)
            if (_state.debayerLMMSEGammaEnabled) {
                [self _renderPass:cmdBuf texture:rawTxt name:@"ImageLayer::DebayerLMMSE_Gamma"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                    }
                ];
            }
            
            // Horizontal interpolation
            {
                const bool h = true;
                [self _renderPass:cmdBuf texture:filteredHTxt name:@"ImageLayer::DebayerLMMSE_Interp5"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                    }
                ];
            }
            
            // Vertical interpolation
            {
                const bool h = false;
                [self _renderPass:cmdBuf texture:filteredVTxt name:@"ImageLayer::DebayerLMMSE_Interp5"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                    }
                ];
            }
            
            // Calculate DiffH
            {
                [self _renderPass:cmdBuf texture:diffHTxt name:@"ImageLayer::DebayerLMMSE_NoiseEst"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:filteredHTxt atIndex:1];
                    }
                ];
            }
            
            // Calculate DiffV
            {
                [self _renderPass:cmdBuf texture:diffVTxt name:@"ImageLayer::DebayerLMMSE_NoiseEst"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:filteredVTxt atIndex:1];
                    }
                ];
            }
            
            // Smooth DiffH
            {
                const bool h = true;
                [self _renderPass:cmdBuf texture:filteredHTxt name:@"ImageLayer::DebayerLMMSE_Smooth9"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:diffHTxt atIndex:0];
                    }
                ];
            }
            
            // Smooth DiffV
            {
                const bool h = false;
                [self _renderPass:cmdBuf texture:filteredVTxt name:@"ImageLayer::DebayerLMMSE_Smooth9"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&h length:sizeof(h) atIndex:1];
                        [encoder setFragmentTexture:diffVTxt atIndex:0];
                    }
                ];
            }
            
            // Calculate txt.g
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::DebayerLMMSE_CalcG"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:filteredHTxt atIndex:1];
                        [encoder setFragmentTexture:diffHTxt atIndex:2];
                        [encoder setFragmentTexture:filteredVTxt atIndex:3];
                        [encoder setFragmentTexture:diffVTxt atIndex:4];
                    }
                ];
            }
            
            // Calculate diffGRTxt.r
            {
                const bool modeGR = true;
                [self _renderPass:cmdBuf texture:diffGRTxt name:@"ImageLayer::DebayerLMMSE_CalcDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                    }
                ];
            }
            
            // Calculate diffGBTxt.b
            {
                const bool modeGR = false;
                [self _renderPass:cmdBuf texture:diffGBTxt name:@"ImageLayer::DebayerLMMSE_CalcDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                    }
                ];
            }
            
            // Calculate diffGRTxt.b
            {
                const bool modeGR = true;
                [self _renderPass:cmdBuf texture:diffGRTxt name:@"ImageLayer::DebayerLMMSE_CalcDiagAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGRTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGBTxt.r
            {
                const bool modeGR = false;
                [self _renderPass:cmdBuf texture:diffGBTxt name:@"ImageLayer::DebayerLMMSE_CalcDiagAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBytes:&modeGR length:sizeof(modeGR) atIndex:1];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGRTxt.g
            {
                [self _renderPass:cmdBuf texture:diffGRTxt name:@"ImageLayer::DebayerLMMSE_CalcAxialAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGRTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate diffGBTxt.g
            {
                [self _renderPass:cmdBuf texture:diffGBTxt name:@"ImageLayer::DebayerLMMSE_CalcAxialAvgDiffGRGB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:rawTxt atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Calculate txt.rb
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::DebayerLMMSE_CalcRB"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:0];
                        [encoder setFragmentTexture:diffGRTxt atIndex:1];
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
                    }
                ];
            }
            
            // Gamma after (improves quality of edges)
            if (_state.debayerLMMSEGammaEnabled) {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::DebayerLMMSE_Degamma"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
        }
        
        // Camera raw -> XYY.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::XYYD50FromCameraRaw"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Exposure
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::Exposure"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    const float exposure = pow(2, _state.imageAdjustments.exposure);
                    [encoder setFragmentBytes:&exposure length:sizeof(exposure) atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
//        // Decrease luminance
//        {
//            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::DecreaseLuminance"
//                block:^(id<MTLRenderCommandEncoder> encoder) {
//                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
//                    [encoder setFragmentTexture:txt atIndex:0];
//                }
//            ];
//        }
        
        // XYY.D50 -> XYZ.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::XYZD50FromXYYD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // XYZ.D50 -> Lab.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::LabD50FromXYZD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Brightness
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::Brightness"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    auto brightness = _state.imageAdjustments.brightness;
                    [encoder setFragmentBytes:&brightness length:sizeof(brightness) atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Contrast
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::Contrast"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    const float contrast = _state.imageAdjustments.contrast;
                    [encoder setFragmentBytes:&contrast length:sizeof(contrast) atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Local contrast
        if (_state.imageAdjustments.localContrast.enable) {
            // Extract L
            {
                [self _renderPass:cmdBuf texture:lTxt name:@"ImageLayer::ExtractL"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Blur L channel
            {
                MPSImageGaussianBlur* blur = [[MPSImageGaussianBlur alloc] initWithDevice:_device
                    sigma:_state.imageAdjustments.localContrast.radius];
                [blur setEdgeMode:MPSImageEdgeModeClamp];
                [blur encodeToCommandBuffer:cmdBuf sourceTexture:lTxt destinationTexture:blurredLTxt];
            }
            
            // Local contrast
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::LocalContrast"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        auto& amount = _state.imageAdjustments.localContrast.amount;
                        [encoder setFragmentBytes:&amount length:sizeof(amount) atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                        [encoder setFragmentTexture:blurredLTxt atIndex:1];
                    }
                ];
            }
        }
        
        // Lab.D50 -> XYZ.D50
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::XYZD50FromLabD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Saturation
        {
            // XYZ.D50 -> Luv.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::LuvD50FromXYZD50"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Luv.D50 -> LCHuv.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::LCHuvFromLuv"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Saturation
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::Saturation"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        const float sat = pow(2, 2*_state.imageAdjustments.saturation);
                        [encoder setFragmentBytes:&sat length:sizeof(sat) atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // LCHuv.D50 -> Luv.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::LuvFromLCHuv"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
            
            // Luv.D50 -> XYZ.D50
            {
                [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::XYZD50FromLuvD50"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                        [encoder setFragmentTexture:txt atIndex:0];
                    }
                ];
            }
        }
        
        // XYZ.D50 -> LSRGB.D65
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::LSRGBD65FromXYZD50"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentBuffer:_state.sampleBuf_XYZ_D50 offset:0 atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Apply SRGB gamma
        {
            [self _renderPass:cmdBuf texture:txt name:@"ImageLayer::SRGBGamma"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentBuffer:_state.sampleBuf_SRGB_D65 offset:0 atIndex:1];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
        
        // Run the final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
        {
            [self _renderPass:cmdBuf texture:outTxt name:@"ImageLayer::Display"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:txt atIndex:0];
                }
            ];
        }
    }
    
    // If outTxt isn't framebuffer-only, then do a blit-sync, which is
    // apparently required for [outTxt getBytes:] to work, which
    // -CGImage uses.
    {
        if (![outTxt isFramebufferOnly]) {
            id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
            [blit synchronizeTexture:outTxt slice:0 level:0];
            [blit endEncoding];
        }
    }
    
    if (drawable) [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
    // Wait for the render to complete, since the lock needs to be
    // held because the shader accesses _state
    [cmdBuf waitUntilCompleted];
    
    // Notify that our histogram changed
    auto dataChangedHandler = _state.dataChangedHandler;
    if (dataChangedHandler) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            dataChangedHandler(self);
        });
    }
}

- (void)display {
    auto lock = std::lock_guard(_state.lock);
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)_state.ctx.imageWidth, (CGFloat)_state.ctx.imageHeight}];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    id<MTLTexture> txt = [drawable texture];
    Assert(txt, return);
    
    TimeInstant start;
    [self _displayToTexture:txt drawable:drawable];
    printf("Display took %f\n", start.durationMs()/1000.);
}

- (id)CGImage {
    auto lock = std::lock_guard(_state.lock);
    id<MTLTexture> txt = [self _newTextureWithPixelFormat:MTLPixelFormatBGRA8Unorm
        usage:(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)];
    [self _displayToTexture:txt drawable:nil];
    const NSUInteger w = [txt width];
    const NSUInteger h = [txt height];
    
    uint32_t opts = kCGImageAlphaNoneSkipFirst;
    id ctx = CFBridgingRelease(CGBitmapContextCreate(nullptr, w, h, 8, 4*w, SRGBColorSpace(), opts));
    Assert(ctx, return nil);
    
    uint8_t* data = (uint8_t*)CGBitmapContextGetData((CGContextRef)ctx);
    [txt getBytes:data bytesPerRow:4*w fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    
    // BGRA -> ARGB
    for (size_t i=0; i<4*w*h; i+=4) {
        std::swap(data[i], data[i+3]);
        std::swap(data[i+1], data[i+2]);
    }
    
    return CFBridgingRelease(CGBitmapContextCreateImage((CGContextRef)ctx));
}

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

- (void)setNeedsDisplay {
    if ([NSThread isMainThread]) {
        [super setNeedsDisplay];
    
    } else {
        // Call -setNeedsDisplay on the main thread, so that drawing is
        // sync'd with drawing triggered by the main thread.
        // Don't use dispatch_async here, because dispatch_async's don't get drained
        // while the runloop is run recursively, eg during mouse tracking.
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [self setNeedsDisplay];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

//- (float)_sampleX:(int32_t)x y:(int32_t)y {
//    NSParameterAssert(x>=0 && x<_ctx.imageWidth);
//    NSParameterAssert(y>=0 && y<_ctx.imageHeight);
//    const ImagePixel* pixels = (const ImagePixel*)[_pixelData contents];
//    return (float)pixels[y*_ctx.imageWidth+x] / ImagePixelMax;
//}
//
//- (simd::float3)sampleCameraRaw:(CGRect)rect {
//    //  Row0    G1  R
//    //  Row1    B   G2
//    int32_t left = std::clamp((int32_t)round(rect.origin.x), 0, (int32_t)_ctx.imageWidth);
//    int32_t right = std::clamp((int32_t)round(rect.origin.x+rect.size.width), 0, (int32_t)_ctx.imageWidth);
//    int32_t top = std::clamp((int32_t)round(rect.origin.y), 0, (int32_t)_ctx.imageHeight);
//    int32_t bottom = std::clamp((int32_t)round(rect.origin.y+rect.size.height), 0, (int32_t)_ctx.imageHeight);
//    simd::float3 color = {0,0,0};
//    int32_t i = 0;
//    for (int32_t y=top; y<bottom; y++) {
//        for (int32_t x=left; x<right; x++, i++) {
//            const bool r = (!(y%2) && (x%2));
//            const bool g = ((!(y%2) && !(x%2)) || ((y%2) && (x%2)));
//            const bool b = ((y%2) && !(x%2));
//            const float val = [self _sampleX:x y:y];
//            if (r)      color[0] += val;
//            else if (g) color[1] += val;
//            else if (b) color[2] += val;
//        }
//    }
//    color /= i;
//    return color;
//}

- (void)setSampleRect:(CGRect)rect {
    auto lock = std::lock_guard(_state.lock);
    auto& ctx = _state.ctx;
    
    rect.origin.x *= ctx.imageWidth;
    rect.origin.y *= ctx.imageHeight;
    rect.size.width *= ctx.imageWidth;
    rect.size.height *= ctx.imageHeight;
    ctx.sampleRect = {
        .left = (uint32_t)std::clamp((int32_t)round(CGRectGetMinX(rect)), 0, (int32_t)ctx.imageWidth),
        .right = (uint32_t)std::clamp((int32_t)round(CGRectGetMaxX(rect)), 0, (int32_t)ctx.imageWidth),
        .top = (uint32_t)std::clamp((int32_t)round(CGRectGetMinY(rect)), 0, (int32_t)ctx.imageHeight),
        .bottom = (uint32_t)std::clamp((int32_t)round(CGRectGetMaxY(rect)), 0, (int32_t)ctx.imageHeight),
    };
    
    if (ctx.sampleRect.left == ctx.sampleRect.right) ctx.sampleRect.right++;
    if (ctx.sampleRect.top == ctx.sampleRect.bottom) ctx.sampleRect.bottom++;
    
    _state.sampleBuf_CamRaw_D50 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    _state.sampleBuf_XYZ_D50 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    _state.sampleBuf_SRGB_D65 = [_device newBufferWithLength:
        sizeof(simd::float3)*std::max((uint32_t)1, ctx.sampleRect.count())
        options:MTLResourceStorageModeShared];
    
    [self setNeedsDisplay];
}

- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler {
    auto lock = std::lock_guard(_state.lock);
    _state.dataChangedHandler = handler;
}

template <typename T>
std::unique_ptr<T[]> copyMTLBuffer(id<MTLBuffer> buf) {
    auto p = std::make_unique<T[]>([buf length]/sizeof(T));
    memcpy(p.get(), [buf contents], [buf length]);
    return p;
}

- (Color_CamRaw_D50)sample_CamRaw_D50 {
    // Copy _state.sampleBuf_CamRaw_D50 locally
    auto lock = std::unique_lock(_state.lock);
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleBuf_CamRaw_D50);
        auto rect = _state.ctx.sampleRect;
    lock.unlock();
    
    size_t i = 0;
    simd::double3 c = {};
    simd::uint3 count = {};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const bool r = (!(y%2) && (x%2));
            const bool g = ((!(y%2) && !(x%2)) || ((y%2) && (x%2)));
            const bool b = ((y%2) && !(x%2));
            const simd::float3& val = vals[i];
            if (r) count[0]++;
            if (g) count[1]++;
            if (b) count[2]++;
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (count[0]) c[0] /= count[0];
    if (count[1]) c[1] /= count[1];
    if (count[2]) c[2] /= count[2];
    return {(float)c[0], (float)c[1], (float)c[2]};
}

- (Color_XYZ_D50)sample_XYZ_D50 {
    // Copy _state.sampleBuf_XYZ_D50 locally
    auto lock = std::unique_lock(_state.lock);
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleBuf_XYZ_D50);
        auto rect = _state.ctx.sampleRect;
    lock.unlock();
    
    size_t i = 0;
    simd::double3 c = {0,0,0};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const simd::float3& val = vals[i];
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (i) c /= i;
    return {(float)c[0], (float)c[1], (float)c[2]};
}

- (Color_SRGB_D65)sample_SRGB_D65 {
    // Copy _state.sampleBuf_SRGB_D65 locally
    auto lock = std::unique_lock(_state.lock);
        auto vals = copyMTLBuffer<simd::float3>(_state.sampleBuf_SRGB_D65);
        auto rect = _state.ctx.sampleRect;
    lock.unlock();
    
    size_t i = 0;
    simd::double3 c = {0,0,0};
    for (size_t y=rect.top; y<rect.bottom; y++) {
        for (size_t x=rect.left; x<rect.right; x++, i++) {
            const simd::float3& val = vals[i];
            c += {(double)val[0], (double)val[1], (double)val[2]};
        }
    }
    if (i) c /= i;
    return {(float)c[0], (float)c[1], (float)c[2]};
}

@end

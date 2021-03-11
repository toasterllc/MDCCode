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

- (id<MTLTexture>)_newTextureWithPixelFormat:(MTLPixelFormat)fmt {
    return [self _newTextureWithPixelFormat:fmt
        usage:(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)];
}

// _state.lock must be held
- (id<MTLTexture>)_newTextureWithPixelFormat:(MTLPixelFormat)fmt
    usage:(MTLTextureUsage)usage {
    
    MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
    [desc setTextureType:MTLTextureType2D];
    [desc setWidth:_state.ctx.imageWidth];
    [desc setHeight:_state.ctx.imageHeight];
    [desc setPixelFormat:fmt];
    [desc setUsage:usage];
    id<MTLTexture> txt = [_device newTextureWithDescriptor:desc];
    Assert(txt, return nil);
    return txt;
}

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

struct TileTerms {
    double t0 = 0;
    double t1 = 0;
    double t2 = 0;
};

//template <typename T>
//class ColorDirDict {
//public:
//    T& operator()(CFAColor color, TileDir dir) {
//        return _t[(uint8_t)color][(uint8_t)dir];
//    }
//private:
//    T _t[3][2] = {};  // _t[color][dir][idx]
//};
//
//class TileTerms {
//public:
//    double& operator()(CFAColor color, TileDir dir, size_t idx) {
//        return _terms[(uint8_t)color][(uint8_t)dir][idx];
//    }
//    
//private:
//    double _terms[3][2][3] = {}; // _terms[color][dir][idx]
//};

struct TileShift {
    double shift = 0;
    double weight = 0;
};

- (void)_correctChromaticAberration:(id<MTLTexture>)rawTxt {
    id<MTLTexture> gInterpTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    id<MTLTexture> raw2Txt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
    
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    
    [self _renderPass:cmdBuf texture:rawTxt name:@"ChromaticAberrationCorrector::WhiteBalanceForward"
        block:^(id<MTLRenderCommandEncoder> encoder) {
            [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
            [encoder setFragmentTexture:rawTxt atIndex:0];
        }
    ];
    
    [self _renderPass:cmdBuf texture:gInterpTxt name:@"ChromaticAberrationCorrector::InterpG"
        block:^(id<MTLRenderCommandEncoder> encoder) {
            [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
            [encoder setFragmentTexture:rawTxt atIndex:0];
        }
    ];
    
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
    using Dir = TileDir;
    using Poly = Poly2D<double,4>;
    
    TileGrid grid(_state.ctx.imageWidth, _state.ctx.imageHeight, TileSize);
    ColorDir<Poly> polys;
    ColorDir<TileShifts> shifts;
//    ColorDir<TileShift> shifts[grid.tileCountY()][grid.tileCountX()];
    
//    printf("%u\n", grid.y.tileOffset(11));
//    exit(0);
    
    for (uint32_t ty=0; ty<grid.y.tileCount; ty++) {
        for (uint32_t tx=0; tx<grid.x.tileCount; tx++) {
//            printf("[%u %u]: X:%u-%u Y:%u-%u\n",
//                tx, ty,
//                grid.x.tileOffset(tx), grid.x.tileOffset(tx)+TileSize-1,
//                grid.y.tileOffset(ty), grid.y.tileOffset(ty)+TileSize-1
//            );
            
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
                    
                    const double rbgDelta = rawPx.px(x,y) - gInterpPx.px(x,y);
                    
                    terms(c,Dir::X).t0 += rbgDelta*rbgDelta;
                    terms(c,Dir::Y).t0 += rbgDelta*rbgDelta;
                    
                    terms(c,Dir::X).t1 += gSlopeX*rbgDelta;
                    terms(c,Dir::Y).t1 += gSlopeY*rbgDelta;
                    
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
                    
//                    shifts[ty][tx](c,dir) = {
//                        .shift  = 2*( terms(c,dir).t1 /        terms(c,dir).t2 ),
//                        .weight =   ( terms(c,dir).t2 / (Eps + terms(c,dir).t0 ))
//                    };
//                    
//                    if (c == CFAColor::Red) {
//                        printf("[%zu %zu]: shift=%f weight=%f\n",
//                            tx, ty,
//                            shift, weight
//                        );
//                    }
                }
            }
        }
    }
    
//    // Fill in terms for polynomial
//    {
//        {
//            Poly& p = polys(CFAColor::Red,Dir::X);
//            p.eval(0,0); // Trigger polynomial solve
//            double terms[] = {-0.27811032088816589613600172015140, 7.81932488864507924120061943540350, -20.06600039449189054607813886832446, 12.44801450602614067975082434713840, 6.16575866161194596770656062290072, -60.38837890648925110781419789418578, 133.42837980400159381133562419563532, -82.45843756001698920954368077218533, -13.36624166964552351544170960551128, 117.41084047178651417198125272989273, -248.53469754379801770483027212321758, 148.89658246210373704343510325998068, 8.39301121637259939234354533255100, -68.02723629661505810872768051922321, 138.63899902050394530306220985949039, -80.35001297760241811829473590478301, };
//            std::copy(terms, terms+std::size(terms), p._x.value().vals);
//        }
//        
//        {
//            Poly& p = polys(CFAColor::Red,Dir::Y);
//            p.eval(0,0); // Trigger polynomial solve
//            double terms[] = {0.00978314910178040668398136148198, 0.24372637408131966885171948433708, 0.14998435320626704592150701955688, -0.34453590990596422161118539406743, 6.57514440010979495099263658630662, 17.48259011236838489367073634639382, -74.73804683044009777859173482283950, 58.86404477847909788579272571951151, -13.28972123345824485340926912613213, -61.04270854490188469299027929082513, 214.39046298086202568811131641268730, -165.21459481032448479709273669868708, 7.35798319563068936588479118654504, 41.10000668909906806902654352597892, -139.26632576299473953440610785037279, 108.34221154489722493963199667632580, };
//            std::copy(terms, terms+std::size(terms), p._x.value().vals);
//        }
//        
//        {
//            Poly& p = polys(CFAColor::Blue,Dir::X);
//            p.eval(0,0); // Trigger polynomial solve
//            double terms[] = {0.19677879270474407658042537150322, -0.71073918165571026150928446440957, 0.38518516145613812540204889955930, 0.35217351395895268861835347706801, 0.95049699061372194819341530092061, -21.47164898042775860176334390416741, 58.51025596386023153172573074698448, -39.98394373659021283629044773988426, -5.82807161033844778330603730864823, 71.07181330762506377141107805073261, -170.24581580460051100089913234114647, 110.45558715795229431932966690510511, 4.26575974345947273036472324747592, -48.66886469583310770303796743974090, 112.95242364437768856078037060797215, -72.42686299727407117643451783806086, };
//            std::copy(terms, terms+std::size(terms), p._x.value().vals);
//        }
//        
//        {
//            Poly& p = polys(CFAColor::Blue,Dir::Y);
//            p.eval(0,0); // Trigger polynomial solve
//            double terms[] = {0.85801988817554131205866951859207, -6.92688374829755382222629123134539, 11.40394904692320388051030022324994, -5.31321263135294508117567602312192, -15.81992294371445240130924503318965, 57.46295789378189056151313707232475, -61.43062653152803420653071952983737, 15.86125851037025569212346454150975, 33.87152660248130331410720827989280, -124.82642427962376530103938421234488, 140.39674997413249002420343458652496, -38.92278617366561377366451779380441, -20.57451322625954048817220609635115, 85.14727936414594466896232916042209, -108.82449475046902875874366145581007, 37.32015412329630521526269149035215, };
//            std::copy(terms, terms+std::size(terms), p._x.value().vals);
//        }
//    }
    
    
    
    for (uint32_t ty=0; ty<grid.y.tileCount; ty++) {
        for (uint32_t tx=0; tx<grid.x.tileCount; tx++) {
            for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
                for (Dir dir : {Dir::X, Dir::Y}) {
                    const double x = grid.x.tileNormalizedCenter<double>(tx);
                    const double y = grid.y.tileNormalizedCenter<double>(ty);
                    shifts(c,dir)(tx,ty) = polys(c,dir).eval(x,y);
                }
            }
        }
    }
    
    
//    {
//        // c=red dir=X
//        auto& ts = shifts(CFAColor::Red,Dir::X);
//        ts(0,0) = 0.126212;
//        ts(1,0) = 0.328432;
//        ts(2,0) = 0.457293;
//        ts(3,0) = 0.521778;
//        ts(4,0) = 0.530866;
//        ts(5,0) = 0.493540;
//        ts(6,0) = 0.418779;
//        ts(7,0) = 0.315564;
//        ts(8,0) = 0.192877;
//        ts(9,0) = 0.059698;
//        ts(10,0) = -0.074992;
//        ts(11,0) = -0.202212;
//        ts(12,0) = -0.312980;
//        ts(13,0) = -0.398317;
//        ts(14,0) = -0.449241;
//        ts(15,0) = -0.456772;
//        ts(16,0) = -0.411928;
//        ts(17,0) = -0.305728;
//        ts(0,1) = 0.148212;
//        ts(1,1) = 0.337656;
//        ts(2,1) = 0.457234;
//        ts(3,1) = 0.515497;
//        ts(4,1) = 0.520998;
//        ts(5,1) = 0.482288;
//        ts(6,1) = 0.407921;
//        ts(7,1) = 0.306447;
//        ts(8,1) = 0.186421;
//        ts(9,1) = 0.056393;
//        ts(10,1) = -0.075084;
//        ts(11,1) = -0.199458;
//        ts(12,1) = -0.308176;
//        ts(13,1) = -0.392686;
//        ts(14,1) = -0.444437;
//        ts(15,1) = -0.454875;
//        ts(16,1) = -0.415449;
//        ts(17,1) = -0.317606;
//        ts(0,2) = 0.411282;
//        ts(1,2) = 0.440913;
//        ts(2,2) = 0.444982;
//        ts(3,2) = 0.426547;
//        ts(4,2) = 0.388668;
//        ts(5,2) = 0.334405;
//        ts(6,2) = 0.266816;
//        ts(7,2) = 0.188962;
//        ts(8,2) = 0.103900;
//        ts(9,2) = 0.014691;
//        ts(10,2) = -0.075607;
//        ts(11,2) = -0.163933;
//        ts(12,2) = -0.247230;
//        ts(13,2) = -0.322436;
//        ts(14,2) = -0.386494;
//        ts(15,2) = -0.436344;
//        ts(16,2) = -0.468926;
//        ts(17,2) = -0.481182;
//        ts(0,3) = 0.533225;
//        ts(1,3) = 0.475177;
//        ts(2,3) = 0.417032;
//        ts(3,3) = 0.358600;
//        ts(4,3) = 0.299688;
//        ts(5,3) = 0.240105;
//        ts(6,3) = 0.179659;
//        ts(7,3) = 0.118158;
//        ts(8,3) = 0.055410;
//        ts(9,3) = -0.008777;
//        ts(10,3) = -0.074593;
//        ts(11,3) = -0.142232;
//        ts(12,3) = -0.211884;
//        ts(13,3) = -0.283743;
//        ts(14,3) = -0.357998;
//        ts(15,3) = -0.434843;
//        ts(16,3) = -0.514468;
//        ts(17,3) = -0.597066;
//        ts(0,4) = 0.552242;
//        ts(1,4) = 0.461491;
//        ts(2,4) = 0.381502;
//        ts(3,4) = 0.310596;
//        ts(4,4) = 0.247096;
//        ts(5,4) = 0.189323;
//        ts(6,4) = 0.135597;
//        ts(7,4) = 0.084240;
//        ts(8,4) = 0.033572;
//        ts(9,4) = -0.018083;
//        ts(10,4) = -0.072407;
//        ts(11,4) = -0.131076;
//        ts(12,4) = -0.195771;
//        ts(13,4) = -0.268169;
//        ts(14,4) = -0.349950;
//        ts(15,4) = -0.442792;
//        ts(16,4) = -0.548375;
//        ts(17,4) = -0.668376;
//        ts(0,5) = 0.506535;
//        ts(1,5) = 0.420898;
//        ts(2,5) = 0.346504;
//        ts(3,5) = 0.281475;
//        ts(4,5) = 0.223931;
//        ts(5,5) = 0.171991;
//        ts(6,5) = 0.123778;
//        ts(7,5) = 0.077410;
//        ts(8,5) = 0.031009;
//        ts(9,5) = -0.017304;
//        ts(10,5) = -0.069411;
//        ts(11,5) = -0.127189;
//        ts(12,5) = -0.192519;
//        ts(13,5) = -0.267281;
//        ts(14,5) = -0.353352;
//        ts(15,5) = -0.452615;
//        ts(16,5) = -0.566946;
//        ts(17,5) = -0.698228;
//        ts(0,6) = 0.434304;
//        ts(1,6) = 0.374441;
//        ts(2,6) = 0.320155;
//        ts(3,6) = 0.270175;
//        ts(4,6) = 0.223229;
//        ts(5,6) = 0.178045;
//        ts(6,6) = 0.133350;
//        ts(7,6) = 0.087874;
//        ts(8,6) = 0.040343;
//        ts(9,6) = -0.010514;
//        ts(10,6) = -0.065969;
//        ts(11,6) = -0.127294;
//        ts(12,6) = -0.195760;
//        ts(13,6) = -0.272641;
//        ts(14,6) = -0.359207;
//        ts(15,6) = -0.456730;
//        ts(16,6) = -0.566484;
//        ts(17,6) = -0.689739;
//        ts(0,7) = 0.373751;
//        ts(1,7) = 0.343163;
//        ts(2,7) = 0.310570;
//        ts(3,7) = 0.275637;
//        ts(4,7) = 0.238031;
//        ts(5,7) = 0.197417;
//        ts(6,7) = 0.153462;
//        ts(7,7) = 0.105833;
//        ts(8,7) = 0.054194;
//        ts(9,7) = -0.001787;
//        ts(10,7) = -0.062444;
//        ts(11,7) = -0.128112;
//        ts(12,7) = -0.199124;
//        ts(13,7) = -0.275813;
//        ts(14,7) = -0.358515;
//        ts(15,7) = -0.447561;
//        ts(16,7) = -0.543287;
//        ts(17,7) = -0.646026;
//        ts(0,8) = 0.363076;
//        ts(1,8) = 0.348108;
//        ts(2,8) = 0.325864;
//        ts(3,8) = 0.296800;
//        ts(4,8) = 0.261374;
//        ts(5,8) = 0.220042;
//        ts(6,8) = 0.173262;
//        ts(7,8) = 0.121491;
//        ts(8,8) = 0.065185;
//        ts(9,8) = 0.004802;
//        ts(10,8) = -0.059201;
//        ts(11,8) = -0.126368;
//        ts(12,8) = -0.196241;
//        ts(13,8) = -0.268363;
//        ts(14,8) = -0.342278;
//        ts(15,8) = -0.417528;
//        ts(16,8) = -0.493657;
//        ts(17,8) = -0.570207;
//        ts(0,9) = 0.440482;
//        ts(1,9) = 0.410318;
//        ts(2,9) = 0.374151;
//        ts(3,9) = 0.332603;
//        ts(4,9) = 0.286296;
//        ts(5,9) = 0.235854;
//        ts(6,9) = 0.181898;
//        ts(7,9) = 0.125052;
//        ts(8,9) = 0.065939;
//        ts(9,9) = 0.005180;
//        ts(10,9) = -0.056602;
//        ts(11,9) = -0.118783;
//        ts(12,9) = -0.180741;
//        ts(13,9) = -0.241854;
//        ts(14,9) = -0.301499;
//        ts(15,9) = -0.359053;
//        ts(16,9) = -0.413894;
//        ts(17,9) = -0.465398;
//        ts(0,10) = 0.644169;
//        ts(1,10) = 0.550837;
//        ts(2,10) = 0.463548;
//        ts(3,10) = 0.381986;
//        ts(4,10) = 0.305837;
//        ts(5,10) = 0.234786;
//        ts(6,10) = 0.168519;
//        ts(7,10) = 0.106720;
//        ts(8,10) = 0.049075;
//        ts(9,10) = -0.004730;
//        ts(10,10) = -0.055011;
//        ts(11,10) = -0.102081;
//        ts(12,10) = -0.146256;
//        ts(13,10) = -0.187851;
//        ts(14,10) = -0.227179;
//        ts(15,10) = -0.264557;
//        ts(16,10) = -0.300297;
//        ts(17,10) = -0.334716;
//        ts(0,11) = 0.661964;
//        ts(1,11) = 0.562700;
//        ts(2,11) = 0.470685;
//        ts(3,11) = 0.385499;
//        ts(4,11) = 0.306721;
//        ts(5,11) = 0.233929;
//        ts(6,11) = 0.166704;
//        ts(7,11) = 0.104624;
//        ts(8,11) = 0.047268;
//        ts(9,11) = -0.005784;
//        ts(10,11) = -0.054953;
//        ts(11,11) = -0.100660;
//        ts(12,11) = -0.143325;
//        ts(13,11) = -0.183370;
//        ts(14,11) = -0.221215;
//        ts(15,11) = -0.257282;
//        ts(16,11) = -0.291990;
//        ts(17,11) = -0.325761;
//    }
//    
//    {
//        // c=red dir=Y
//        auto& ts = shifts(CFAColor::Red,Dir::Y);
//        ts(0,0) = 0.327418;
//        ts(1,0) = 0.363404;
//        ts(2,0) = 0.384010;
//        ts(3,0) = 0.391471;
//        ts(4,0) = 0.388021;
//        ts(5,0) = 0.375896;
//        ts(6,0) = 0.357331;
//        ts(7,0) = 0.334561;
//        ts(8,0) = 0.309822;
//        ts(9,0) = 0.285347;
//        ts(10,0) = 0.263372;
//        ts(11,0) = 0.246133;
//        ts(12,0) = 0.235864;
//        ts(13,0) = 0.234800;
//        ts(14,0) = 0.245177;
//        ts(15,0) = 0.269229;
//        ts(16,0) = 0.309191;
//        ts(17,0) = 0.367299;
//        ts(0,1) = 0.361481;
//        ts(1,1) = 0.399494;
//        ts(2,1) = 0.420496;
//        ts(3,1) = 0.426992;
//        ts(4,1) = 0.421487;
//        ts(5,1) = 0.406484;
//        ts(6,1) = 0.384488;
//        ts(7,1) = 0.358004;
//        ts(8,1) = 0.329536;
//        ts(9,1) = 0.301589;
//        ts(10,1) = 0.276667;
//        ts(11,1) = 0.257275;
//        ts(12,1) = 0.245916;
//        ts(13,1) = 0.245097;
//        ts(14,1) = 0.257320;
//        ts(15,1) = 0.285090;
//        ts(16,1) = 0.330913;
//        ts(17,1) = 0.397292;
//        ts(0,2) = 0.775413;
//        ts(1,2) = 0.827454;
//        ts(2,2) = 0.845613;
//        ts(3,2) = 0.835241;
//        ts(4,2) = 0.801693;
//        ts(5,2) = 0.750320;
//        ts(6,2) = 0.686475;
//        ts(7,2) = 0.615513;
//        ts(8,2) = 0.542785;
//        ts(9,2) = 0.473644;
//        ts(10,2) = 0.413443;
//        ts(11,2) = 0.367536;
//        ts(12,2) = 0.341274;
//        ts(13,2) = 0.340012;
//        ts(14,2) = 0.369101;
//        ts(15,2) = 0.433895;
//        ts(16,2) = 0.539747;
//        ts(17,2) = 0.692009;
//        ts(0,3) = 0.975970;
//        ts(1,3) = 1.013305;
//        ts(2,3) = 1.014475;
//        ts(3,3) = 0.985372;
//        ts(4,3) = 0.931888;
//        ts(5,3) = 0.859914;
//        ts(6,3) = 0.775343;
//        ts(7,3) = 0.684066;
//        ts(8,3) = 0.591977;
//        ts(9,3) = 0.504966;
//        ts(10,3) = 0.428926;
//        ts(11,3) = 0.369748;
//        ts(12,3) = 0.333326;
//        ts(13,3) = 0.325550;
//        ts(14,3) = 0.352313;
//        ts(15,3) = 0.419507;
//        ts(16,3) = 0.533023;
//        ts(17,3) = 0.698755;
//        ts(0,4) = 1.011677;
//        ts(1,4) = 1.014150;
//        ts(2,4) = 0.988763;
//        ts(3,4) = 0.940280;
//        ts(4,4) = 0.873470;
//        ts(5,4) = 0.793097;
//        ts(6,4) = 0.703929;
//        ts(7,4) = 0.610730;
//        ts(8,4) = 0.518267;
//        ts(9,4) = 0.431306;
//        ts(10,4) = 0.354614;
//        ts(11,4) = 0.292956;
//        ts(12,4) = 0.251099;
//        ts(13,4) = 0.233809;
//        ts(14,4) = 0.245851;
//        ts(15,4) = 0.291992;
//        ts(16,4) = 0.376998;
//        ts(17,4) = 0.505635;
//        ts(0,5) = 0.931059;
//        ts(1,5) = 0.887092;
//        ts(2,5) = 0.830153;
//        ts(3,5) = 0.762862;
//        ts(4,5) = 0.687839;
//        ts(5,5) = 0.607702;
//        ts(6,5) = 0.525073;
//        ts(7,5) = 0.442569;
//        ts(8,5) = 0.362810;
//        ts(9,5) = 0.288417;
//        ts(10,5) = 0.222008;
//        ts(11,5) = 0.166203;
//        ts(12,5) = 0.123622;
//        ts(13,5) = 0.096884;
//        ts(14,5) = 0.088609;
//        ts(15,5) = 0.101416;
//        ts(16,5) = 0.137925;
//        ts(17,5) = 0.200755;
//        ts(0,6) = 0.782639;
//        ts(1,6) = 0.689233;
//        ts(2,6) = 0.600326;
//        ts(3,6) = 0.516014;
//        ts(4,6) = 0.436393;
//        ts(5,6) = 0.361561;
//        ts(6,6) = 0.291614;
//        ts(7,6) = 0.226648;
//        ts(8,6) = 0.166760;
//        ts(9,6) = 0.112047;
//        ts(10,6) = 0.062605;
//        ts(11,6) = 0.018531;
//        ts(12,6) = -0.020079;
//        ts(13,6) = -0.053128;
//        ts(14,6) = -0.080519;
//        ts(15,6) = -0.102156;
//        ts(16,6) = -0.117943;
//        ts(17,6) = -0.127782;
//        ts(0,7) = 0.614944;
//        ts(1,7) = 0.477678;
//        ts(2,7) = 0.360959;
//        ts(3,7) = 0.262630;
//        ts(4,7) = 0.180531;
//        ts(5,7) = 0.112504;
//        ts(6,7) = 0.056391;
//        ts(7,7) = 0.010033;
//        ts(8,7) = -0.028728;
//        ts(9,7) = -0.062051;
//        ts(10,7) = -0.092094;
//        ts(11,7) = -0.121016;
//        ts(12,7) = -0.150975;
//        ts(13,7) = -0.184129;
//        ts(14,7) = -0.222637;
//        ts(15,7) = -0.268658;
//        ts(16,7) = -0.324349;
//        ts(17,7) = -0.391870;
//        ts(0,8) = 0.476496;
//        ts(1,8) = 0.309528;
//        ts(2,8) = 0.173732;
//        ts(3,8) = 0.065607;
//        ts(4,8) = -0.018348;
//        ts(5,8) = -0.081636;
//        ts(6,8) = -0.127756;
//        ts(7,8) = -0.160211;
//        ts(8,8) = -0.182501;
//        ts(9,8) = -0.198128;
//        ts(10,8) = -0.210592;
//        ts(11,8) = -0.223396;
//        ts(12,8) = -0.240039;
//        ts(13,8) = -0.264024;
//        ts(14,8) = -0.298852;
//        ts(15,8) = -0.348024;
//        ts(16,8) = -0.415041;
//        ts(17,8) = -0.503404;
//        ts(0,9) = 0.415821;
//        ts(1,9) = 0.241888;
//        ts(2,9) = 0.100324;
//        ts(3,9) = -0.012158;
//        ts(4,9) = -0.098846;
//        ts(5,9) = -0.163027;
//        ts(6,9) = -0.207989;
//        ts(7,9) = -0.237019;
//        ts(8,9) = -0.253403;
//        ts(9,9) = -0.260431;
//        ts(10,9) = -0.261389;
//        ts(11,9) = -0.259564;
//        ts(12,9) = -0.258244;
//        ts(13,9) = -0.260717;
//        ts(14,9) = -0.270269;
//        ts(15,9) = -0.290189;
//        ts(16,9) = -0.323763;
//        ts(17,9) = -0.374279;
//        ts(0,10) = 0.481443;
//        ts(1,10) = 0.331860;
//        ts(2,10) = 0.202412;
//        ts(3,10) = 0.092229;
//        ts(4,10) = 0.000436;
//        ts(5,10) = -0.073839;
//        ts(6,10) = -0.131468;
//        ts(7,10) = -0.173325;
//        ts(8,10) = -0.200281;
//        ts(9,10) = -0.213210;
//        ts(10,10) = -0.212985;
//        ts(11,10) = -0.200478;
//        ts(12,10) = -0.176562;
//        ts(13,10) = -0.142110;
//        ts(14,10) = -0.097994;
//        ts(15,10) = -0.045086;
//        ts(16,10) = 0.015739;
//        ts(17,10) = 0.083609;
//        ts(0,11) = 0.490846;
//        ts(1,11) = 0.344020;
//        ts(2,11) = 0.216028;
//        ts(3,11) = 0.106237;
//        ts(4,11) = 0.014012;
//        ts(5,11) = -0.061281;
//        ts(6,11) = -0.120275;
//        ts(7,11) = -0.163604;
//        ts(8,11) = -0.191904;
//        ts(9,11) = -0.205807;
//        ts(10,11) = -0.205947;
//        ts(11,11) = -0.192960;
//        ts(12,11) = -0.167478;
//        ts(13,11) = -0.130136;
//        ts(14,11) = -0.081567;
//        ts(15,11) = -0.022407;
//        ts(16,11) = 0.046712;
//        ts(17,11) = 0.125155;
//    }
//    
//    {
//        // c=blue dir=X
//        auto& ts = shifts(CFAColor::Blue,Dir::X);
//        ts(0,0) = 0.187661;
//        ts(1,0) = 0.115547;
//        ts(2,0) = 0.059067;
//        ts(3,0) = 0.016819;
//        ts(4,0) = -0.012598;
//        ts(5,0) = -0.030584;
//        ts(6,0) = -0.038540;
//        ts(7,0) = -0.037868;
//        ts(8,0) = -0.029969;
//        ts(9,0) = -0.016242;
//        ts(10,0) = 0.001910;
//        ts(11,0) = 0.023087;
//        ts(12,0) = 0.045889;
//        ts(13,0) = 0.068913;
//        ts(14,0) = 0.090759;
//        ts(15,0) = 0.110027;
//        ts(16,0) = 0.125315;
//        ts(17,0) = 0.135222;
//        ts(0,1) = 0.187693;
//        ts(1,1) = 0.112120;
//        ts(2,1) = 0.053489;
//        ts(3,1) = 0.010214;
//        ts(4,1) = -0.019290;
//        ts(5,1) = -0.036607;
//        ts(6,1) = -0.043323;
//        ts(7,1) = -0.041023;
//        ts(8,1) = -0.031292;
//        ts(9,1) = -0.015715;
//        ts(10,1) = 0.004123;
//        ts(11,1) = 0.026638;
//        ts(12,1) = 0.050243;
//        ts(13,1) = 0.073354;
//        ts(14,1) = 0.094386;
//        ts(15,1) = 0.111754;
//        ts(16,1) = 0.123872;
//        ts(17,1) = 0.129157;
//        ts(0,2) = 0.154987;
//        ts(1,2) = 0.049236;
//        ts(2,2) = -0.026194;
//        ts(3,2) = -0.074858;
//        ts(4,2) = -0.100310;
//        ts(5,2) = -0.106101;
//        ts(6,2) = -0.095787;
//        ts(7,2) = -0.072919;
//        ts(8,2) = -0.041052;
//        ts(9,2) = -0.003739;
//        ts(10,2) = 0.035467;
//        ts(11,2) = 0.073012;
//        ts(12,2) = 0.105344;
//        ts(13,2) = 0.128908;
//        ts(14,2) = 0.140152;
//        ts(15,2) = 0.135521;
//        ts(16,2) = 0.111463;
//        ts(17,2) = 0.064425;
//        ts(0,3) = 0.071670;
//        ts(1,3) = -0.025017;
//        ts(2,3) = -0.089895;
//        ts(3,3) = -0.126940;
//        ts(4,3) = -0.140133;
//        ts(5,3) = -0.133449;
//        ts(6,3) = -0.110866;
//        ts(7,3) = -0.076363;
//        ts(8,3) = -0.033917;
//        ts(9,3) = 0.012494;
//        ts(10,3) = 0.058893;
//        ts(11,3) = 0.101302;
//        ts(12,3) = 0.135742;
//        ts(13,3) = 0.158237;
//        ts(14,3) = 0.164809;
//        ts(15,3) = 0.151480;
//        ts(16,3) = 0.114272;
//        ts(17,3) = 0.049207;
//        ts(0,4) = -0.044920;
//        ts(1,4) = -0.105135;
//        ts(2,4) = -0.140554;
//        ts(3,4) = -0.154469;
//        ts(4,4) = -0.150167;
//        ts(5,4) = -0.130936;
//        ts(6,4) = -0.100067;
//        ts(7,4) = -0.060848;
//        ts(8,4) = -0.016568;
//        ts(9,4) = 0.029485;
//        ts(10,4) = 0.074022;
//        ts(11,4) = 0.113754;
//        ts(12,4) = 0.145392;
//        ts(13,4) = 0.165647;
//        ts(14,4) = 0.171230;
//        ts(15,4) = 0.158853;
//        ts(16,4) = 0.125227;
//        ts(17,4) = 0.067063;
//        ts(0,5) = -0.177445;
//        ts(1,5) = -0.185610;
//        ts(2,5) = -0.181116;
//        ts(3,5) = -0.165880;
//        ts(4,5) = -0.141820;
//        ts(5,5) = -0.110853;
//        ts(6,5) = -0.074897;
//        ts(7,5) = -0.035868;
//        ts(8,5) = 0.004315;
//        ts(9,5) = 0.043735;
//        ts(10,5) = 0.080476;
//        ts(11,5) = 0.112618;
//        ts(12,5) = 0.138246;
//        ts(13,5) = 0.155441;
//        ts(14,5) = 0.162287;
//        ts(15,5) = 0.156865;
//        ts(16,5) = 0.137259;
//        ts(17,5) = 0.101551;
//        ts(0,6) = -0.308566;
//        ts(1,6) = -0.260937;
//        ts(2,6) = -0.214521;
//        ts(3,6) = -0.169611;
//        ts(4,6) = -0.126501;
//        ts(5,6) = -0.085486;
//        ts(6,6) = -0.046860;
//        ts(7,6) = -0.010917;
//        ts(8,6) = 0.022049;
//        ts(9,6) = 0.051744;
//        ts(10,6) = 0.077874;
//        ts(11,6) = 0.100143;
//        ts(12,6) = 0.118259;
//        ts(13,6) = 0.131926;
//        ts(14,6) = 0.140852;
//        ts(15,6) = 0.144741;
//        ts(16,6) = 0.143299;
//        ts(17,6) = 0.136232;
//        ts(0,7) = -0.420944;
//        ts(1,7) = -0.325611;
//        ts(2,7) = -0.243712;
//        ts(3,7) = -0.174098;
//        ts(4,7) = -0.115619;
//        ts(5,7) = -0.067124;
//        ts(6,7) = -0.027464;
//        ts(7,7) = 0.004513;
//        ts(8,7) = 0.029955;
//        ts(9,7) = 0.050013;
//        ts(10,7) = 0.065837;
//        ts(11,7) = 0.078577;
//        ts(12,7) = 0.089384;
//        ts(13,7) = 0.099407;
//        ts(14,7) = 0.109797;
//        ts(15,7) = 0.121703;
//        ts(16,7) = 0.136276;
//        ts(17,7) = 0.154665;
//        ts(0,8) = -0.497242;
//        ts(1,8) = -0.374124;
//        ts(2,8) = -0.271632;
//        ts(3,8) = -0.187779;
//        ts(4,8) = -0.120582;
//        ts(5,8) = -0.068055;
//        ts(6,8) = -0.028214;
//        ts(7,8) = 0.000926;
//        ts(8,8) = 0.021350;
//        ts(9,8) = 0.035042;
//        ts(10,8) = 0.043987;
//        ts(11,8) = 0.050170;
//        ts(12,8) = 0.055576;
//        ts(13,8) = 0.062189;
//        ts(14,8) = 0.071994;
//        ts(15,8) = 0.086976;
//        ts(16,8) = 0.109119;
//        ts(17,8) = 0.140409;
//        ts(0,9) = -0.520121;
//        ts(1,9) = -0.400972;
//        ts(2,9) = -0.301221;
//        ts(3,9) = -0.219090;
//        ts(4,9) = -0.152797;
//        ts(5,9) = -0.100566;
//        ts(6,9) = -0.060617;
//        ts(7,9) = -0.031170;
//        ts(8,9) = -0.010447;
//        ts(9,9) = 0.003331;
//        ts(10,9) = 0.011944;
//        ts(11,9) = 0.017169;
//        ts(12,9) = 0.020787;
//        ts(13,9) = 0.024576;
//        ts(14,9) = 0.030315;
//        ts(15,9) = 0.039783;
//        ts(16,9) = 0.054760;
//        ts(17,9) = 0.077024;
//        ts(0,10) = -0.472242;
//        ts(1,10) = -0.400648;
//        ts(2,10) = -0.335424;
//        ts(3,10) = -0.276467;
//        ts(4,10) = -0.223675;
//        ts(5,10) = -0.176946;
//        ts(6,10) = -0.136178;
//        ts(7,10) = -0.101269;
//        ts(8,10) = -0.072116;
//        ts(9,10) = -0.048618;
//        ts(10,10) = -0.030672;
//        ts(11,10) = -0.018176;
//        ts(12,10) = -0.011028;
//        ts(13,10) = -0.009126;
//        ts(14,10) = -0.012367;
//        ts(15,10) = -0.020650;
//        ts(16,10) = -0.033872;
//        ts(17,10) = -0.051932;
//        ts(0,11) = -0.466504;
//        ts(1,11) = -0.399600;
//        ts(2,11) = -0.337782;
//        ts(3,11) = -0.281111;
//        ts(4,11) = -0.229649;
//        ts(5,11) = -0.183457;
//        ts(6,11) = -0.142596;
//        ts(7,11) = -0.107128;
//        ts(8,11) = -0.077115;
//        ts(9,11) = -0.052617;
//        ts(10,11) = -0.033695;
//        ts(11,11) = -0.020411;
//        ts(12,11) = -0.012827;
//        ts(13,11) = -0.011004;
//        ts(14,11) = -0.015003;
//        ts(15,11) = -0.024885;
//        ts(16,11) = -0.040711;
//        ts(17,11) = -0.062544;
//    }
//    
//    {
//        // c=blue dir=Y
//        auto& ts = shifts(CFAColor::Blue,Dir::Y);
//        ts(0,0) = 0.041766;
//        ts(1,0) = -0.150628;
//        ts(2,0) = -0.296450;
//        ts(3,0) = -0.400455;
//        ts(4,0) = -0.467395;
//        ts(5,0) = -0.502025;
//        ts(6,0) = -0.509098;
//        ts(7,0) = -0.493367;
//        ts(8,0) = -0.459585;
//        ts(9,0) = -0.412507;
//        ts(10,0) = -0.356885;
//        ts(11,0) = -0.297473;
//        ts(12,0) = -0.239025;
//        ts(13,0) = -0.186294;
//        ts(14,0) = -0.144033;
//        ts(15,0) = -0.116996;
//        ts(16,0) = -0.109936;
//        ts(17,0) = -0.127608;
//        ts(0,1) = -0.027495;
//        ts(1,1) = -0.206205;
//        ts(2,1) = -0.340043;
//        ts(3,1) = -0.433684;
//        ts(4,1) = -0.491807;
//        ts(5,1) = -0.519087;
//        ts(6,1) = -0.520202;
//        ts(7,1) = -0.499827;
//        ts(8,1) = -0.462640;
//        ts(9,1) = -0.413317;
//        ts(10,1) = -0.356536;
//        ts(11,1) = -0.296973;
//        ts(12,1) = -0.239303;
//        ts(13,1) = -0.188206;
//        ts(14,1) = -0.148356;
//        ts(15,1) = -0.124431;
//        ts(16,1) = -0.121107;
//        ts(17,1) = -0.143061;
//        ts(0,2) = -0.868585;
//        ts(1,2) = -0.880517;
//        ts(2,2) = -0.868044;
//        ts(3,2) = -0.834926;
//        ts(4,2) = -0.784923;
//        ts(5,2) = -0.721797;
//        ts(6,2) = -0.649308;
//        ts(7,2) = -0.571216;
//        ts(8,2) = -0.491281;
//        ts(9,2) = -0.413266;
//        ts(10,2) = -0.340929;
//        ts(11,2) = -0.278032;
//        ts(12,2) = -0.228335;
//        ts(13,2) = -0.195599;
//        ts(14,2) = -0.183584;
//        ts(15,2) = -0.196051;
//        ts(16,2) = -0.236761;
//        ts(17,2) = -0.309474;
//        ts(0,3) = -1.279635;
//        ts(1,3) = -1.206752;
//        ts(2,3) = -1.119742;
//        ts(3,3) = -1.021884;
//        ts(4,3) = -0.916456;
//        ts(5,3) = -0.806738;
//        ts(6,3) = -0.696009;
//        ts(7,3) = -0.587546;
//        ts(8,3) = -0.484630;
//        ts(9,3) = -0.390539;
//        ts(10,3) = -0.308552;
//        ts(11,3) = -0.241947;
//        ts(12,3) = -0.194005;
//        ts(13,3) = -0.168002;
//        ts(14,3) = -0.167219;
//        ts(15,3) = -0.194935;
//        ts(16,3) = -0.254427;
//        ts(17,3) = -0.348976;
//        ts(0,4) = -1.366387;
//        ts(1,4) = -1.267069;
//        ts(2,4) = -1.157265;
//        ts(3,4) = -1.039983;
//        ts(4,4) = -0.918233;
//        ts(5,4) = -0.795026;
//        ts(6,4) = -0.673370;
//        ts(7,4) = -0.556275;
//        ts(8,4) = -0.446752;
//        ts(9,4) = -0.347809;
//        ts(10,4) = -0.262456;
//        ts(11,4) = -0.193704;
//        ts(12,4) = -0.144561;
//        ts(13,4) = -0.118037;
//        ts(14,4) = -0.117142;
//        ts(15,4) = -0.144886;
//        ts(16,4) = -0.204278;
//        ts(17,4) = -0.298329;
//        ts(0,5) = -1.234578;
//        ts(1,5) = -1.143626;
//        ts(2,5) = -1.042739;
//        ts(3,5) = -0.934647;
//        ts(4,5) = -0.822083;
//        ts(5,5) = -0.707776;
//        ts(6,5) = -0.594458;
//        ts(7,5) = -0.484860;
//        ts(8,5) = -0.381712;
//        ts(9,5) = -0.287747;
//        ts(10,5) = -0.205694;
//        ts(11,5) = -0.138286;
//        ts(12,5) = -0.088252;
//        ts(13,5) = -0.058324;
//        ts(14,5) = -0.051233;
//        ts(15,5) = -0.069710;
//        ts(16,5) = -0.116486;
//        ts(17,5) = -0.194292;
//        ts(0,6) = -0.989950;
//        ts(1,6) = -0.918582;
//        ts(2,6) = -0.838292;
//        ts(3,6) = -0.751302;
//        ts(4,6) = -0.659833;
//        ts(5,6) = -0.566104;
//        ts(6,6) = -0.472338;
//        ts(7,6) = -0.380756;
//        ts(8,6) = -0.293578;
//        ts(9,6) = -0.213025;
//        ts(10,6) = -0.141318;
//        ts(11,6) = -0.080678;
//        ts(12,6) = -0.033327;
//        ts(13,6) = -0.001485;
//        ts(14,6) = 0.012627;
//        ts(15,6) = 0.006788;
//        ts(16,6) = -0.021223;
//        ts(17,6) = -0.073627;
//        ts(0,7) = -0.738241;
//        ts(1,7) = -0.674094;
//        ts(2,7) = -0.606052;
//        ts(3,7) = -0.535372;
//        ts(4,7) = -0.463311;
//        ts(5,7) = -0.391127;
//        ts(6,7) = -0.320078;
//        ts(7,7) = -0.251421;
//        ts(8,7) = -0.186413;
//        ts(9,7) = -0.126314;
//        ts(10,7) = -0.072379;
//        ts(11,7) = -0.025866;
//        ts(12,7) = 0.011966;
//        ts(13,7) = 0.039860;
//        ts(14,7) = 0.056559;
//        ts(15,7) = 0.060805;
//        ts(16,7) = 0.051340;
//        ts(17,7) = 0.026907;
//        ts(0,8) = -0.585193;
//        ts(1,8) = -0.492323;
//        ts(2,8) = -0.408146;
//        ts(3,8) = -0.332281;
//        ts(4,8) = -0.264345;
//        ts(5,8) = -0.203959;
//        ts(6,8) = -0.150741;
//        ts(7,8) = -0.104310;
//        ts(8,8) = -0.064285;
//        ts(9,8) = -0.030285;
//        ts(10,8) = -0.001928;
//        ts(11,8) = 0.021165;
//        ts(12,8) = 0.039377;
//        ts(13,8) = 0.053089;
//        ts(14,8) = 0.062680;
//        ts(15,8) = 0.068534;
//        ts(16,8) = 0.071030;
//        ts(17,8) = 0.070549;
//        ts(0,9) = -0.636544;
//        ts(1,9) = -0.455427;
//        ts(2,9) = -0.306702;
//        ts(3,9) = -0.187454;
//        ts(4,9) = -0.094765;
//        ts(5,9) = -0.025717;
//        ts(6,9) = 0.022605;
//        ts(7,9) = 0.053119;
//        ts(8,9) = 0.068741;
//        ts(9,9) = 0.072390;
//        ts(10,9) = 0.066981;
//        ts(11,9) = 0.055432;
//        ts(12,9) = 0.040659;
//        ts(13,9) = 0.025580;
//        ts(14,9) = 0.013112;
//        ts(15,9) = 0.006171;
//        ts(16,9) = 0.007674;
//        ts(17,9) = 0.020539;
//        ts(0,10) = -0.998035;
//        ts(1,10) = -0.645563;
//        ts(2,10) = -0.363847;
//        ts(3,10) = -0.146316;
//        ts(4,10) = 0.013603;
//        ts(5,10) = 0.122483;
//        ts(6,10) = 0.186894;
//        ts(7,10) = 0.213409;
//        ts(8,10) = 0.208600;
//        ts(9,10) = 0.179039;
//        ts(10,10) = 0.131298;
//        ts(11,10) = 0.071949;
//        ts(12,10) = 0.007564;
//        ts(13,10) = -0.055286;
//        ts(14,10) = -0.110027;
//        ts(15,10) = -0.150088;
//        ts(16,10) = -0.168898;
//        ts(17,10) = -0.159883;
//        ts(0,11) = -1.033339;
//        ts(1,11) = -0.666860;
//        ts(2,11) = -0.374103;
//        ts(3,11) = -0.148224;
//        ts(4,11) = 0.017617;
//        ts(5,11) = 0.130266;
//        ts(6,11) = 0.196563;
//        ts(7,11) = 0.223352;
//        ts(8,11) = 0.217475;
//        ts(9,11) = 0.185776;
//        ts(10,11) = 0.135096;
//        ts(11,11) = 0.072278;
//        ts(12,11) = 0.004165;
//        ts(13,11) = -0.062400;
//        ts(14,11) = -0.120574;
//        ts(15,11) = -0.163516;
//        ts(16,11) = -0.184382;
//        ts(17,11) = -0.176329;
//    }
    
    
    
    
    for (CFAColor c : {CFAColor::Red, CFAColor::Blue}) {
        for (Dir dir : {Dir::X, Dir::Y}) {
            printf("c=%s dir=%s\n",
                (c==CFAColor::Red ? "red" : "blue"),
                (dir==Dir::X ? "X" : "Y")
            );
            for (uint32_t ty=0; ty<grid.y.tileCount; ty++) {
                for (uint32_t tx=0; tx<grid.x.tileCount; tx++) {
                    printf("shifts(%u,%u) = %f;\n", tx, ty, shifts(c,dir)(tx,ty));
                }
            }
            printf("\n\n");
        }
    }
    
    [self _renderPass:cmdBuf texture:raw2Txt name:@"ChromaticAberrationCorrector::ApplyCorrection"
        block:^(id<MTLRenderCommandEncoder> encoder) {
            [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
            [encoder setFragmentBytes:&grid length:sizeof(grid) atIndex:1];
            [encoder setFragmentBytes:&shifts(CFAColor::Red,Dir::X)
                length:sizeof(shifts(CFAColor::Red,Dir::X)) atIndex:2];
            [encoder setFragmentBytes:&shifts(CFAColor::Red,Dir::Y)
                length:sizeof(shifts(CFAColor::Red,Dir::Y)) atIndex:3];
            [encoder setFragmentBytes:&shifts(CFAColor::Blue,Dir::X)
                length:sizeof(shifts(CFAColor::Blue,Dir::X)) atIndex:4];
            [encoder setFragmentBytes:&shifts(CFAColor::Blue,Dir::Y)
                length:sizeof(shifts(CFAColor::Blue,Dir::Y)) atIndex:5];
            [encoder setFragmentTexture:rawTxt atIndex:0];
            [encoder setFragmentTexture:gInterpTxt atIndex:1];
        }
    ];
    
    [self _renderPass:cmdBuf texture:rawTxt name:@"ChromaticAberrationCorrector::WhiteBalanceReverse"
        block:^(id<MTLRenderCommandEncoder> encoder) {
            [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
            [encoder setFragmentTexture:raw2Txt atIndex:0];
        }
    ];
    
    [cmdBuf commit];
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
    
//    id<MTLTexture> rbgDeltaTxt = [self _newTextureWithPixelFormat:MTLPixelFormatR32Float];
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
    
    [cmdBuf commit];
    
    if (_state.correctChromaticAberration) {
        [self _correctChromaticAberration:rawTxt];
    }
    
    cmdBuf = [_commandQueue commandBuffer];
    
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
        // Fix highlights
        {
            [self _renderPass:cmdBuf texture:raw2Txt name:@"ImageLayer::FixHighlightsRaw"
                block:^(id<MTLRenderCommandEncoder> encoder) {
                    [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                    [encoder setFragmentTexture:rawTxt atIndex:0];
                }
            ];
        }
        
        // LMMSE Debayer
        {
            // Gamma before (improves quality of edges)
            if (_state.debayerLMMSEGammaEnabled) {
                [self _renderPass:cmdBuf texture:rawTxt name:@"ImageLayer::DebayerLMMSE_Gamma"
                    block:^(id<MTLRenderCommandEncoder> encoder) {
                        [encoder setFragmentBytes:&_state.ctx length:sizeof(_state.ctx) atIndex:0];
                        [encoder setFragmentTexture:raw2Txt atIndex:0];
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
                        [encoder setFragmentTexture:diffGRTxt atIndex:2];
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
                        [encoder setFragmentTexture:diffGBTxt atIndex:2];
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

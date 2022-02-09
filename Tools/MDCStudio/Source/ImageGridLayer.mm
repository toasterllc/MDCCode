#import "ImageGridLayer.h"
#import <simd/simd.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "ImageGridLayerTypes.h"
#import "Mmap.h"
#import "RecordStore.h"
using namespace MDCStudio;
namespace fs = std::filesystem;

static constexpr auto _ThumbWidth = ImageRef::ThumbWidth;
static constexpr auto _ThumbHeight = ImageRef::ThumbHeight;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

static matrix_float4x4 _Scale(float x, float y, float z) {
    return matrix_float4x4{
        .columns[0] = { x, 0, 0, 0 },
        .columns[1] = { 0, y, 0, 0 },
        .columns[2] = { 0, 0, z, 0 },
        .columns[3] = { 0, 0, 0, 1 },
    };
}

static matrix_float4x4 _Translate(float x, float y, float z) {
    return {
        .columns[0] = { 1, 0, 0, 0},
        .columns[1] = { 0, 1, 0, 0},
        .columns[2] = { 0, 0, 1, 0},
        .columns[3] = { x, y, z, 1},
    };
}

static NSDictionary* _LayerNullActions = @{
    kCAOnOrderIn: [NSNull null],
    kCAOnOrderOut: [NSNull null],
    @"bounds": [NSNull null],
    @"frame": [NSNull null],
    @"position": [NSNull null],
    @"sublayers": [NSNull null],
    @"transform": [NSNull null],
    @"contents": [NSNull null],
    @"contentsScale": [NSNull null],
    @"hidden": [NSNull null],
    @"fillColor": [NSNull null],
    @"fontSize": [NSNull null],
};

using ThumbFile = Mmap;

@implementation ImageGridLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    id<MTLTexture> _depthTexture;
    id<MTLTexture> _outlineTexture;
    id<MTLTexture> _maskTexture;
    id<MTLTexture> _shadowTexture;
    MTLRenderPassDepthAttachmentDescriptor* _depthAttachment;
    
    CGFloat _contentsScale;
    
    Grid _grid;
    uint32_t _cellWidth;
    uint32_t _cellHeight;
    ImageLibraryPtr _imgLib;
//    uint32_t _thumbInset;
}

- (instancetype)init {
//    extern void CreateThumbBuf();
//    CreateThumbBuf();
    
    if (!(self = [super init])) return nil;
    
    [self setOpaque:false];
    
    _contentsScale = 1;
    
    [self setActions:_LayerNullActions];
    [self setNeedsDisplayOnBoundsChange:true];
    #warning TODO: we need PresentsWithTransaction=1 while window is resizing (to prevent artifacts), and PresentsWithTransaction=0 while scrolling (to prevent stutters)
//    [self setPresentsWithTransaction:true]; // Necessary to prevent artifacts when resizing window
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:_device];
    // TODO: supply scaleFactor properly
    
    // Loading these textures from an asset catalog causes incorrect colors to be
    // sampled by our fragment shader (particularly noticeable when rendering the
    // thumbnail shadow texture). Meanwhile loading the textures directly from
    // the file within the bundle works fine.
    // We were unable to determine why this happens, but it likely has something
    // to do with the APIs doing something wrong with color profiles.
    _outlineTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"Outline"] options:nil error:nil];
    assert(_outlineTexture);
    
    _maskTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"Mask"] options:nil error:nil];
    assert(_maskTexture);
    
//    _shadowTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"Shadow"] options:@{
//        MTKTextureLoaderOptionSRGB: @NO,
//    } error:nil];
    
    _shadowTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"Shadow"] options:nil error:nil];
    assert(_shadowTexture);
    
//    _outlineTexture = [loader newTextureWithName:@"Outline.png" scaleFactor:2 bundle:nil options:nil error:nil];
//    _maskTexture = [loader newTextureWithName:@"Mask.png" scaleFactor:2 bundle:nil options:nil error:nil];
//    _shadowTexture = [loader newTextureWithName:@"Shadow.png" scaleFactor:2 bundle:nil options:nil error:nil];
//    assert(_outlineTexture && _maskTexture && _shadowTexture);
    
//    _shadowTexture = [loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:@"/Users/dave/Desktop/MDCStudio/Resources/Shadow.png"] options:nil error:nil];
//    [loader newTextureWith]
    
//    _shadowTexture = [loader newTextureWithName:@"Shadow" scaleFactor:2 displayGamut:NSDisplayGamutSRGB bundle:nil options:nil error:nil];
//    assert(_shadowTexture);
    
//    _shadowTexture = [loader newTextureWithName:@"Shadow" scaleFactor:2 displayGamut:NSDisplayGamutSRGB bundle:nil options:nil error:nil];
//    assert(_shadowTexture);
    
//    {
//        using ThumbFile = Mmap<uint8_t>;
//        auto dev = MTLCreateSystemDefaultDevice();
//        auto thumbFile = ThumbFile("/Users/dave/Desktop/Thumbs", MAP_PRIVATE);
//        
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
//        auto thumbBuf = [dev newBufferWithBytesNoCopy:thumbFile.data() length:thumbFile.byteLen() options:BufOpts deallocator:nil];
//        assert(thumbBuf);
//        
//        NSLog(@"thumbBuf: %p", thumbBuf);
//    }
    
//    // WORKS
//    {
//        using ThumbFile = Mmap<uint8_t>;
//        _thumbFile = ThumbFile("/Users/dave/Desktop/Thumbs", MAP_PRIVATE);
//        
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
//        auto thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:_thumbFile.byteLen() options:BufOpts deallocator:nil];
//        assert(thumbBuf);
//        
//        NSLog(@"thumbBuf: %p", thumbBuf);
//    }
    
    
    // FAILS
//    {
//        const fs::path ThumbFilePath = "/Users/dave/Desktop/Thumbs";
//        
//        _thumbFile = ThumbFile(ThumbFilePath, MAP_PRIVATE);
//        
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
//        _thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:_thumbFile.byteLen() options:BufOpts deallocator:nil];
//        assert(_thumbBuf);
//    }
    
    _commandQueue = [_device newCommandQueue];
    
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:
        [NSBundle bundleForClass:[self class]] error:nil];
    assert(library);
    
    id<MTLFunction> vertexShader = [library newFunctionWithName:@"MDCStudio::ImageGridLayerShader::VertexShader"];
    assert(vertexShader);
    
    id<MTLFunction> fragmentShader = [library newFunctionWithName:@"MDCStudio::ImageGridLayerShader::FragmentShader"];
    assert(fragmentShader);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    
    [pipelineDescriptor setDepthAttachmentPixelFormat:MTLPixelFormatDepth32Float];
    [[pipelineDescriptor colorAttachments][0] setPixelFormat:_PixelFormat];
    [[pipelineDescriptor colorAttachments][0] setBlendingEnabled:true];
    
    [[pipelineDescriptor colorAttachments][0] setRgbBlendOperation:MTLBlendOperationAdd];
    [[pipelineDescriptor colorAttachments][0] setAlphaBlendOperation:MTLBlendOperationAdd];
    [[pipelineDescriptor colorAttachments][0] setSourceRGBBlendFactor:MTLBlendFactorSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setSourceAlphaBlendFactor:MTLBlendFactorSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setDestinationRGBBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setDestinationAlphaBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    assert(_pipelineState);
    
    MTLDepthStencilDescriptor* depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    [depthStencilDescriptor setDepthCompareFunction:MTLCompareFunctionLess];
    [depthStencilDescriptor setDepthWriteEnabled:true];
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
    
    _depthAttachment = [MTLRenderPassDepthAttachmentDescriptor new];
    [_depthAttachment setLoadAction:MTLLoadActionClear];
    [_depthAttachment setStoreAction:MTLStoreActionDontCare];
    [_depthAttachment setClearDepth:1];
    
//    for (;;) {
//        _thumbFile = ThumbFile(ThumbFilePath, MAP_PRIVATE);
//        
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//        _thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:_thumbFile.byteLen() options:BufOpts deallocator:nil];
//        if (_thumbBuf) break;
//    }
    
//    const fs::path ThumbFilePath = "/Users/dave/Desktop/Thumbs";
//    const int fdi = open(ThumbFilePath.c_str(), O_RDWR|O_CREAT /* |O_EXCL */ |O_CLOEXEC, S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH);
//    assert(fdi >= 0);
//    FileDescriptor fd(fdi);
//    _thumbFile = ThumbFile(std::move(fd), MAP_PRIVATE);
    
//    NSLog(@"_thumbFile.data() == %p, 4096 aligned = %lu\n", _thumbFile.data(), ((uintptr_t)_thumbFile.data() % 4096));
    
//    uint32_t thumbBufLen = (uint32_t)_thumbFile.byteLen();
//    for (;;) {
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//        _thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:thumbBufLen options:BufOpts deallocator:nil];
//        if (_thumbBuf) break;
//        usleep(1000);
//        NSLog(@"trying again...");
////        thumbBufLen /= 2;
//    }
    
//    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//    _thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:_thumbFile.byteLen() options:BufOpts deallocator:nil];
//    assert(_thumbBuf);
//    
//    _thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:_thumbFile.byteLen() options:BufOpts deallocator:nil];
//    _thumbBuf = [_device newBufferWithBytesNoCopy:_thumbFile.data() length:4096 options:BufOpts deallocator:nil];
//    assert(_thumbBuf);
//    [NSTimer scheduledTimerWithTimeInterval:2 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSLog(@"Creating _thumbBuf...");
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//        self->_thumbBuf = [self->_device newBufferWithBytesNoCopy:self->_thumbFile.data() length:(240000/1)*4096 options:BufOpts deallocator:nil];
//        NSLog(@"_thumbBuf: %p", self->_thumbBuf);
//    }];
    
    const uint32_t shadowExcess = (uint32_t)([_shadowTexture width]-[_maskTexture width]);
    _cellWidth = _ThumbWidth+shadowExcess;
    _cellHeight = _ThumbHeight+shadowExcess;
    
    _grid.setBorderSize({
        .left   = (int32_t)_cellWidth/5,
        .right  = (int32_t)_cellWidth/5,
        .top    = (int32_t)_cellHeight/5,
        .bottom = (int32_t)_cellHeight/5,
    });
    
    _grid.setCellSize({(int32_t)_cellWidth, (int32_t)_cellHeight});
    _grid.setCellSpacing({(int32_t)_cellWidth/10, (int32_t)_cellHeight/10});
    
    return self;
}

- (Grid&)grid {
    return _grid;
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self setNeedsDisplay];
}

- (MTLRenderPassDepthAttachmentDescriptor*)_depthAttachmentForDrawableTexture:(id<MTLTexture>)drawableTexture {
    NSParameterAssert(drawableTexture);
    
    const size_t width = [drawableTexture width];
    const size_t height = [drawableTexture height];
    if (!_depthTexture || width!=[_depthTexture width] || height!=[_depthTexture height]) {
        // The _depthTexture doesn't exist or our size changed, so re-create the depth texture
        MTLTextureDescriptor* desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
            width:width height:height mipmapped:false];
        [desc setTextureType:MTLTextureType2D];
        [desc setSampleCount:1];
        [desc setUsage:MTLTextureUsageUnknown];
        [desc setStorageMode:MTLStorageModePrivate];
        
        _depthTexture = [_device newTextureWithDescriptor:desc];
        [_depthAttachment setTexture:_depthTexture];
    }
    
    return _depthAttachment;
}

static Grid::Rect _GridRectForCGRect(CGRect rect, CGFloat scale) {
    const CGRect irect = CGRectIntegral({
        rect.origin.x*scale,
        rect.origin.y*scale,
        rect.size.width*scale,
        rect.size.height*scale,
    });
    
    return Grid::Rect{
        .point = {(int32_t)irect.origin.x, (int32_t)irect.origin.y},
        .size = {(int32_t)irect.size.width, (int32_t)irect.size.height},
    };
}

static uintptr_t _FloorToPageSize(uintptr_t x) {
    const uintptr_t s = getpagesize();
    return (x/s)*s;
}

static uintptr_t _CeilToPageSize(uintptr_t x) {
    const uintptr_t s = getpagesize();
    return ((x+s-1)/s)*s;
}

//template <typename T>
//static T _Distance(T a, T b) {
//    if (a > b) return a-b;
//    return b-a;
//}
//
//struct RangeMem {
//    uintptr_t start = 0;
//    uintptr_t end = 0;
//    size_t len = 0;
//    struct {
//        uintptr_t start = 0;
//        uintptr_t end = 0;
//        size_t len = 0;
//    } aligned;
//};
//
//// _RangeMemCalc(): returns the span of memory that `range` references,
//// both page-aligned and non-page-aligned
//static RangeMem _RangeMemCalc(const ImageLibrary& ic, const ImageLibrary::Range& range) {
//    if (!range.len) return {};
//    const uintptr_t start = (uintptr_t)ic.getImage(range.idx);
//    const uintptr_t end = (uintptr_t)ic.getImage(range.idx+range.len-1)+ImgSize;
//    const uintptr_t alignedStart = _FloorToPageSize(start);
//    const uintptr_t alignedEnd = _CeilToPageSize(end);
//    const size_t alignedLen = alignedEnd-alignedStart;
//    return {
//        .start = start,
//        .end = end,
//        .aligned = {
//            .start = alignedStart,
//            .end = alignedEnd,
//            .len = alignedLen,
//        },
//    };
//}
//
//// _RangeHalve(): splits `range` into 2 subranges, such that both subranges
//// span equally-sized regions in `_imagesMmap` (as equal as possible, that is).
////
//// To expand: `range` references indexes in _imageRefs, while the values in
//// _imageRefs serve as indexes into _imagesMmap. So we're not halving `range`
//// in the naive way, but rather halving it by considering the length that the
//// two subranges represent in _imagesMmap, and getting those two lengths as
//// equal as possible.
////
//// For example, with these values:
////     _imageRefs = [1,10,13,14,15,16,17,18,19]
////     range      = [0,9]
//// _RangeHalve() returns:
////     ([0,2], [2,7])
//// Note that the span of the first region is 10 images (10-1+1),
//// and the span of the second region is 7 images (19-13+1).
//std::tuple<ImageLibrary::Range,ImageLibrary::Range> _RangeHalve(const ImageLibrary& ic, const ImageLibrary::Range& range) {
//    if (!range.len) return std::make_tuple(ImageLibrary::Range{}, ImageLibrary::Range{});
//    const ImageLibrary::ImageRef first = ic.getImageRef(range.idx);
//    const ImageLibrary::ImageRef last  = ic.getImageRef(range.idx+range.len-1);
//    
//    size_t left = range.idx;
//    size_t right = range.idx+range.len; // Exclusive
//    size_t best = 0;
//    size_t bestDist = SIZE_MAX;
//    while (left < right) {
//        const size_t mid = (left+right)/2;
//        const size_t leftLen = (mid>range.idx ? ic.getImageRef(mid-1)-first+1 : 0);
//        const size_t rightLen = last-ic.getImageRef(mid)+1;
//        const size_t dist = _Distance(leftLen, rightLen);
//        if (dist < bestDist) {
//            best = mid;
//            bestDist = dist;
//        }
//        
//        // Continue with left chunk
//        if (leftLen > rightLen) right = mid;
//        // Continue with right chunk
//        else left = mid+1;
//    }
//    
//    return ImageLibrary::Split(range, best);
//}
//
//// _RangeSubdivide(): recursively divides `ranges[idx]` until all resulting subranges
//// reference <= T_MaxBufLen bytes in _imagesMmap
//template <size_t T_MaxBufLen>
//void _RangeSubdivide(const ImageLibrary& ic, std::vector<ImageLibrary::Range>& ranges, size_t idx) {
//    const ImageLibrary::Range& range = ranges[idx];
//    assert(range.len > 0);
//    
//    // Short-circuit if subdivision isn't necessary
//    if (_RangeMemCalc(ic, range).aligned.len <= T_MaxBufLen) return;
//    
//    // If the region is larger than `T_MaxBufLen`, halve it
//    const auto [l, r] = _RangeHalve(ic, range);
//    ranges.insert(ranges.begin()+idx, range);
//    ranges[idx+1] = r;
//    ranges[idx] = l;
//    
//    _RangeSubdivide<T_MaxBufLen>(ic, ranges, idx+1); // Higher indexes must happen first, to preserve lower indexes
//    _RangeSubdivide<T_MaxBufLen>(ic, ranges, idx);
//}
//
//// _RangeSegments(): segments the input range such that every returned range spans no more
//// than `T_MaxBufLen` bytes within the images buffer
//template <size_t T_MaxBufLen>
//std::vector<ImageLibrary::Range> _RangeSegments(const ImageLibrary& ic, const ImageLibrary::Range& range) {
//    if (!range.len) return {};
//    std::vector<ImageLibrary::Range> ranges;
//    
//    // Conditionally split `range` into 2 parts, in case the ImageRefs that it references wraps
//    // around to the beginning of `_imagesMmap`
//    const auto [l,r] = ic.splitRangeMonotonic(range);
//    ranges.push_back(l);
//    if (r.len) ranges.push_back(r);
//    
//    // Subdivide each range (recursively) so that none of them are larger than `T_MaxBufLen`
//    // This is done backwards so that the next element in `ranges` isn't affected by the
//    // splitting of the current element.
//    for (size_t i=ranges.size(); i; i--) {
//        _RangeSubdivide<T_MaxBufLen>(ic, ranges, i-1);
//    }
//    
//    return ranges;
//}



- (void)display {
    auto startTime = std::chrono::steady_clock::now();
    
    if (!_imgLib) return;
    auto il = _imgLib->vend();
    
//    _grid.setElementCount((int32_t)il.imageCount);
    _grid.setElementCount((int32_t)il->recordCount());
    _grid.recompute();
    
    // Update our drawable size
    const CGRect frame = [self frame];
    [self setDrawableSize:{frame.size.width*_contentsScale, frame.size.height*_contentsScale}];
    
    // Get our drawable and its texture
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    
    id<MTLTexture> drawableTexture = [drawable texture];
    assert(drawableTexture);
    
    // Get/update our depth attachment
    MTLRenderPassDepthAttachmentDescriptor* depthAttachment = [self _depthAttachmentForDrawableTexture:drawableTexture];
    assert(depthAttachment);
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [renderPassDescriptor setDepthAttachment:depthAttachment];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,0}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthStencilState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        [renderEncoder endEncoding];
    }
    
    const Grid::IndexRange indexRange = _grid.indexRangeForIndexRect(_grid.indexRectForRect(_GridRectForCGRect(frame, _contentsScale)));
    if (indexRange.count) {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [renderPassDescriptor setDepthAttachment:depthAttachment];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,0}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        // rasterFromUnityMatrix: converts unity coordinates [-1,1] -> rasterized coordinates [0,pixel width/height]
        const matrix_float4x4 rasterFromUnityMatrix = matrix_multiply(matrix_multiply(
            _Scale(.5*frame.size.width*_contentsScale, .5*frame.size.height*_contentsScale, 1), // Divide by 2, multiply by view width/height
            _Translate(1, 1, 0)),                                                               // Add 1
            _Scale(1, -1, 1)                                                                    // Flip Y
        );
        
        // unityFromRasterMatrix: converts rasterized coordinates -> unity coordinates
        const matrix_float4x4 unityFromRasterMatrix = matrix_invert(rasterFromUnityMatrix);
        
//        constexpr size_t MaxBufLen = 1024*1024*1024; // 1 GB
//        const std::vector<ImageLibrary::Range> ranges = _RangeSegments<MaxBufLen>(ic, {(size_t)indexRange.start, (size_t)indexRange.count});
        
        const int32_t offsetX = -round(frame.origin.x*_contentsScale);
        const int32_t offsetY = -round(frame.origin.y*_contentsScale);
        
        const uintptr_t imageRefsBegin = (uintptr_t)&*il->begin();
        const uintptr_t imageRefsEnd = (uintptr_t)&*il->end();
        id<MTLBuffer> imageRefs = [_device newBufferWithBytes:(void*)imageRefsBegin
            length:imageRefsEnd-imageRefsBegin options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeManaged];
        
//        printf("Range count: %zu\n", ranges.size());
        
        const auto imageRefFirst = il->begin()+indexRange.start;
        const auto imageRefLast = il->begin()+indexRange.start+indexRange.count-1;
        
        const auto imageRefBegin = imageRefFirst;
        const auto imageRefEnd = std::next(imageRefLast);
        
//        const auto chunkFirst = imageRefFirst->chunk;
//        const auto chunkLast = imageRefLast->chunk;
//        
//        const auto chunkBegin = chunkFirst;
//        const auto chunkEnd = std::next(chunkLast);
        for (auto it=imageRefBegin; it<imageRefEnd;) {
            const auto& chunk = *(it->chunk);
            const auto nextChunkStart = ImageLibrary::FindNextChunk(it, il->end());
            
            const auto chunkImageRefBegin = it;
            const auto chunkImageRefEnd = std::min(imageRefEnd, nextChunkStart);
            
            const auto chunkImageRefFirst = chunkImageRefBegin;
            const auto chunkImageRefLast = std::prev(chunkImageRefEnd);
            
//            const auto& chunk = *it;
//            
//            const auto imageRefFirst = ic.imageRefsBegin()+indexRange.start;
//            const auto imageRefLast = ic.imageRefsBegin()+indexRange.start+indexRange.count-1;
            
//            printf("Chunk count: %ju\n", std::distance(chunkStart, chunkEnd));
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            [renderEncoder setRenderPipelineState:_pipelineState];
            [renderEncoder setDepthStencilState:_depthStencilState];
            [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [renderEncoder setCullMode:MTLCullModeNone];
            
//            uintptr_t offBegin = 0;
//            uintptr_t offEnd = chunk.mmap.alignedLen();
//            if (it == chunkFirst) {
//                offBegin = sizeof(Img)*imageRefFirst.idx;
//            }
//            
//            if (it == chunkLast) {
//                offEnd = sizeof(Img)*(imageRefLast.idx+1);
//            }
//            printf("AAA\n");
            const uintptr_t addrBegin = (uintptr_t)(chunk.mmap.data()+(sizeof(ImageRef)*chunkImageRefFirst->idx));
            const uintptr_t addrEnd = (uintptr_t)(chunk.mmap.data()+(sizeof(ImageRef)*(chunkImageRefLast->idx+1)));
            
            const uintptr_t addrAlignedBegin = _FloorToPageSize(addrBegin);
            const uintptr_t addrAlignedEnd = _CeilToPageSize(addrEnd);
            
//            const RangeMem mem = _RangeMemCalc(ic, range);
            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
            id<MTLBuffer> imageBuf = [_device newBufferWithBytesNoCopy:(void*)addrAlignedBegin
                length:(addrAlignedEnd-addrAlignedBegin) options:BufOpts deallocator:nil];
            
//            printf("length: %zu\n", addrAlignedEnd-addrAlignedBegin);
            
            if (imageBuf) {
                assert(imageBuf);
                
//                static_assert(sizeof(it)==9);
            //    NSLog(@"%@", NSStringFromRect(frame));
            //    NSLog(@"Offset: %d", lround(frame.origin.y)-cell0Rect.point.y);
            //    NSLog(@"indexRange: [%d %d]", indexRange.start, indexRange.start+indexRange.count-1);
                ImageGridLayerTypes::RenderContext ctx = {
                    .grid = _grid,
//                    .chunk = ImageGridLayerTypes::UInt2FromType(it),
                    .idxOff = (uint32_t)(chunkImageRefFirst-il->begin()),
                    .imagesOff = (uint32_t)(addrBegin-addrAlignedBegin),
//                    .imageRefOff = (uint32_t)ic.getImageRef(range.idx),
                    .imageSize = (uint32_t)sizeof(ImageRef),
                    .viewOffset = {offsetX, offsetY},
                    .viewMatrix = unityFromRasterMatrix,
                    .thumb = {
                        .width  = ImageRef::ThumbWidth,
                        .height = ImageRef::ThumbHeight,
                        .pxSize = ImageRef::ThumbPixelSize,
                        .off    = (uint32_t)(offsetof(ImageRef, thumbData)),
                    },
                    .cellWidth = _cellWidth,
                    .cellHeight = _cellHeight,
                };
                
                [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
                [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
                
                [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
                [renderEncoder setFragmentBuffer:imageBuf offset:0 atIndex:1];
                [renderEncoder setFragmentTexture:_maskTexture atIndex:0];
                [renderEncoder setFragmentTexture:_outlineTexture atIndex:1];
                [renderEncoder setFragmentTexture:_shadowTexture atIndex:2];
                
            //    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1];
                
            //    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectForCGRect(frame));
                const size_t chunkImageCount = chunkImageRefEnd-chunkImageRefBegin;
//                printf("chunkImageCount: %zu\n", chunkImageCount);
                [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:chunkImageCount];
            }
            
            [renderEncoder endEncoding];
            
            it = chunkImageRefEnd;
            
//            break;
        }
    }
    
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted]; // Necessary to prevent artifacts when resizing window
    
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Took %ju ms\n", (uintmax_t)durationMs);
}

- (void)setContentsScale:(CGFloat)scale {
    _contentsScale = scale;
    [super setContentsScale:scale];
    // We need to redraw ourself when our scale changes
    // Assume we're on the main thread so we don't need to use -setNeedsDisplayAsync
    [self setNeedsDisplay];
}

- (void)setImageLibrary:(ImageLibraryPtr)imgLib {
    _imgLib = imgLib;
    [self setNeedsDisplay];
}

- (void)setContainerWidth:(CGFloat)width {
    _grid.setContainerWidth((int32_t)lround(width*_contentsScale));
    [self setNeedsDisplay];
}

- (CGFloat)containerHeight {
    _grid.recompute();
    return _grid.containerHeight() / _contentsScale;
}

@end












//constexpr size_t SublayerCount = 500000;
//
//@interface ImageGridLayer : CALayer
//@end
//
//@implementation ImageGridLayer {
//@public
//    Grid grid;
//@private
//    CGRect _visibleRect;
//    Grid::IndexRange _indexRangePrev;
////    Grid::Indexes _visibleIndexes;
////    CALayer* overlay;
//    
//@private
//    std::vector<CellLayer*> _layers;
//    std::vector<CellLayer*> _layersPool;
//}
//
//- (CellLayer*)_createLayerForIdx:(size_t)idx {
//    CellLayer* layer = _layers[idx];
//    if (layer) return layer;
//    
//    if (!_layersPool.empty()) {
//        layer = _layersPool.back();
//        _layersPool.pop_back();
//    } else {
//        layer = [CellLayer new];
//        
////        const uint32_t pixelFormat = 'BGRA';
////        IOSurface* surface = [[IOSurface alloc] initWithProperties:@{
////            IOSurfacePropertyKeyWidth: @(256),
////            IOSurfacePropertyKeyHeight: @(256),
////            IOSurfacePropertyKeyBytesPerElement: @(4),
////            IOSurfacePropertyKeyPixelFormat: @(pixelFormat),
////            (id)kIOSurfaceIsGlobal: @YES,
////        }];
////        
////        [surface lockWithOptions:0 seed:nullptr];
////        const size_t allocSize = [surface allocationSize];
////        uint32_t* data = (uint32_t*)[surface baseAddress];
////        for (size_t i=0; i<allocSize/sizeof(*data); i++) {
////            data[i] = rand() % RAND_MAX;
////        }
////        [surface unlockWithOptions:0 seed:nullptr];
////        
////        [surface lockWithOptions:0 seed:nullptr];
////        memset([surface baseAddress], 0, [surface allocationSize]);
////        [surface unlockWithOptions:0 seed:nullptr];
////        
////        [layer setContents:surface];
//    }
//    
//    _layers[idx] = layer;
//    [self addSublayer:layer];
//    return layer;
//}
//
//- (void)_destroyLayerForIdx:(size_t)idx {
//    CellLayer* layer = _layers[idx];
//    if (!layer) return; // Short-circuit if there's no layer for the given index
//    
//    [layer removeFromSuperlayer];
//    _layers[idx] = nil;
//    _layersPool.push_back(layer);
//}
//
//- (instancetype)init {
//    _LoadImages();
//    
//    if (!(self = [super init])) return nil;
////    [self setBackgroundColor:[[NSColor blackColor] CGColor]];
//    [self setActions:LayerNullActions];
////    [self setGeometryFlipped:true];
//    
////    for (size_t i=0; i<SublayerCount; i++) {
////        CellLayer* layer = [CellLayer new];
//////        [self addSublayer:layer];
////        _layers.push_back(layer);
////    }
//    
//    _layers.resize(SublayerCount);
//    
//    grid.border = {
//        .left   = 20,
//        .right  = 20,
//        .top    = 20,
//        .bottom = 20,
//    };
//    
//    grid.cell.size      = { 32, 32 };
//    grid.cell.spacing   = { 10, 10 };
//    grid.elementCount = SublayerCount;
//    
////    overlay = [CALayer new];
////    [overlay setBackgroundColor:[[NSColor redColor] CGColor]];
////    [self addSublayer:overlay];
////    [overlay setFrame:{0,0,100,100}];
////    [overlay setActions:LayerNullActions];
//    
//    return self;
//}
//
//static Grid::Rect _GridRectForCGRect(CGRect rect) {
//    return {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
//}
//
//- (void)setVisibleRect:(CGRect)rect {
////    NSLog(@"setVisibleRect: %@", NSStringFromRect(rect));
//    
////    const CGRect bounds = [self bounds];
//    
//    _visibleRect = rect;
////    grid.containerWidth = bounds.size.width;
////    grid.recompute();
////    
////    NSLog(@"setVisibleRect: %@ (bounds:%@)", NSStringFromRect(rect), NSStringFromRect(bounds));
////    
////    _visibleIndexes = grid.indexesForRect(_GridRectForCGRect(rect));
////    
////    [self setSublayers:@[]];
////    
////    for (size_t y=_visibleIndexes.y.start; y<_visibleIndexes.y.start+_visibleIndexes.y.count; y++) {
////        for (size_t x=_visibleIndexes.x.start; x<_visibleIndexes.x.start+_visibleIndexes.x.count; x++) {
////            const size_t idx = y*grid.computed.columnCount + x;
////            [self addSublayer:_layers[idx]];
////        }
////    }
//    
//    [self setNeedsLayout];
//}
//
//struct IndexRangeDiff {
//    Grid::IndexRange oldRange[2];
//    Grid::IndexRange newRange[2];
//};
//
//static IndexRangeDiff _Diff(const Grid::IndexRange& oldRange, const Grid::IndexRange& newRange) {
//    const size_t overlapStart = std::max(oldRange.start, newRange.start);
//    const size_t overlapEnd = std::min(oldRange.start+oldRange.count, newRange.start+newRange.count);
//    
//    if (overlapEnd > overlapStart) {
//        const size_t old0Start = oldRange.start;
//        const size_t old0End = overlapStart;
//        
//        const size_t new0Start = newRange.start;
//        const size_t new0End = overlapStart;
//        
//        const size_t new1Start = overlapEnd;
//        const size_t new1End = newRange.start+newRange.count;
//        
//        const size_t old1Start = overlapEnd;
//        const size_t old1End = oldRange.start+oldRange.count;
//        
//        IndexRangeDiff r;
//        if (old0End > old0Start) {
//            r.oldRange[0].start = old0Start;
//            r.oldRange[0].count = old0End-old0Start;
//        }
//        
//        if (new0End > new0Start) {
//            r.newRange[0].start = new0Start;
//            r.newRange[0].count = new0End-new0Start;
//        }
//        
//        if (old1End > old1Start) {
//            r.oldRange[1].start = old1Start;
//            r.oldRange[1].count = old1End-old1Start;
//        }
//        
//        if (new1End > new1Start) {
//            r.newRange[1].start = new1Start;
//            r.newRange[1].count = new1End-new1Start;
//        }
//        
//        return r;
//    }
//    
//    // If we get here, there's no overlap between `oldRange` and `newRange`
//    return IndexRangeDiff{
//        .oldRange = {oldRange},
//        .newRange = {newRange},
//    };
//    
//    
////    const Grid::IndexRange overlap = {
////        .start = overlapMin,
////        .count = ,
////    };
////    
////    const size_t oldMin = oldRange.start;
////    const size_t oldMax = oldRange.start+oldRange.count-1; // TODO: handle count==0
////    
////    const size_t newMin = newRange.start;
////    const size_t newMax = newRange.start+newRange.count-1; // TODO: handle count==0
////    
////    IndexRangeDiff r;
////    
////    if (oldMin < newMin) {
////        r.oldRange[0].start = oldMin;
////        r.oldRange[0].count = newMin-oldMin;
////    } else if (oldMin > newMin) {
////        r.newRange[0].start = newMin;
////        r.newRange[0].count = oldMin-newMin;
////    }
////    
////    if (oldMax < newMax) {
////        r.oldRange[1].start = oldMax;
////        r.oldRange[1].count = newMax-oldMax;
////    } else if (oldMax > newMax) {
////        r.newRange[1].start = newMax;
////        r.newRange[1].count = oldMax-newMax;
////    }
////    
////    return r;
//}
//
//- (void)layoutSublayers {
////    NSLog(@"layoutSublayers");
//    const CGRect bounds = [self bounds];
//    
////    NSLog(@"layoutSublayers: %@", NSStringFromRect(bounds));
//    
//    grid.containerWidth = bounds.size.width;
//    grid.recompute();
//    
//    const Grid::IndexRange indexRange = grid.indexRangeForIndexRect(grid.indexRectForRect(_GridRectForCGRect(_visibleRect)));
//    const IndexRangeDiff diff = _Diff(_indexRangePrev, indexRange);
//    
////    if (diff.oldRange[0].count) {
////        NSLog(@"oldRange[0]: [%zu,%zu]", diff.oldRange[0].start, diff.oldRange[0].start+diff.oldRange[0].count-1);
////    }
////    
////    if (diff.oldRange[1].count) {
////        NSLog(@"oldRange[1]: [%zu,%zu]", diff.oldRange[1].start, diff.oldRange[1].start+diff.oldRange[1].count-1);
////    }
////    
////    if (diff.newRange[0].count) {
////        NSLog(@"newRange[0]: [%zu,%zu]", diff.newRange[0].start, diff.newRange[0].start+diff.newRange[0].count-1);
////    }
////    
////    if (diff.newRange[1].count) {
////        NSLog(@"newRange[1]: [%zu,%zu]", diff.newRange[1].start, diff.newRange[1].start+diff.newRange[1].count-1);
////    }
//    
////    const Grid::IndexRange oldRange;
////    const Grid::IndexRange oldRange2;
////    
////    const Grid::IndexRange newRange;
////    const Grid::IndexRange newRange2;
////    
////    if () {
////        
////    }
//    
//    
////    const Grid::IndexRect indexRect = grid.indexesForRect(_GridRectForCGRect(_visibleRect));
//    
//    for (const Grid::IndexRange& oldRange : diff.oldRange) {
//        if (oldRange.count) {
////            NSLog(@"Destroying %zu layers", oldRange.count);
//        }
//        for (size_t i=oldRange.start; i<oldRange.start+oldRange.count; i++) {
//            [self _destroyLayerForIdx:i];
//        }
//    }
//    
//    for (const Grid::IndexRange& newRange : diff.newRange) {
//        if (newRange.count) {
////            NSLog(@"Adding %zu layers", newRange.count);
//        }
//        for (size_t i=newRange.start; i<newRange.start+newRange.count; i++) {
//            CellLayer*const layer = [self _createLayerForIdx:i];
//            
////            uint32_t color = ((uint32_t)rand()) << 8;
////            color |= 0xFF;
////            
////            IOSurface* surface = layer->surface;
////            [surface lockWithOptions:0 seed:nullptr];
////            const size_t allocSize = [surface allocationSize];
////            uint32_t* data = (uint32_t*)[surface baseAddress];
////            memset(data, color, allocSize);
////            [surface unlockWithOptions:0 seed:nullptr];
//            
//            
////            NSLog(@"SET LAYER CONTENTS: %@", _Images[i%_Images.size()]);
//            [layer setContents:_Images[i%_Images.size()]];
////            [layer setContents:[NSNull null]];
//        }
//    }
//    
//    for (size_t i=indexRange.start; i<indexRange.start+indexRange.count; i++) {
//        CellLayer*const layer = _layers[i];
//        assert(layer); // Logic error if it doesn't exist
//        const Grid::Rect rect = grid.rectForCellIndex(i);
//        [layer setFrame:{
//            rect.point.x,
//            rect.point.y,
//            rect.size.x,
//            rect.size.y,
//        }];
//    }
//    
////    NSLog(@"%@", @([[self sublayers] count]));
//    
//    
////    [self setSublayers:@[]];
////    
////    for (size_t i=indexRange.start; i<indexRange.start+indexRange.count; i++) {
////        CALayer*const layer = _layers[i];
////        const Grid::Rect rect = grid.rectForCellIndex(i);
////        [self addSublayer:layer];
////        [layer setFrame:{
////            rect.point.x,
////            rect.point.y,
////            rect.size.x,
////            rect.size.y,
////        }];
////        
////        [layer setContents:_Images[i%_Images.size()]];
////    }
//    
////    for (size_t y=indexRange.y.start; y<indexRange.y.start+indexRange.y.count; y++) {
////        for (size_t x=indexRange.x.start; x<indexRange.x.start+indexRange.x.count; x++) {
////            const size_t idx = y*grid.computed.columnCount + x;
////            CALayer*const layer = _layers[idx];
////            const Grid::Rect rect = grid.rectForCellIndex(idx);
////            [self addSublayer:layer];
////            [layer setFrame:{
////                rect.point.x,
////                rect.point.y,
////                rect.size.x,
////                rect.size.y,
////            }];
////            
////            [layer setContents:_Images[idx%_Images.size()]];
////        }
////    }
//    
//    _indexRangePrev = indexRange;
//    
////    for (size_t y=_visibleIndexes.y.start; y<_visibleIndexes.y.start+_visibleIndexes.y.count; y++) {
////        for (size_t x=_visibleIndexes.x.start; x<_visibleIndexes.x.start+_visibleIndexes.x.count; x++) {
////            const size_t idx = y*grid.computed.columnCount + x;
////            auto rect = grid.rectForCellIndex(idx);
////            CALayer*const layer = _layers[idx];
////            [layer setFrame:{
////                rect.point.x,
////                rect.point.y,
////                rect.size.x,
////                rect.size.y,
////            }];
////        }
////    }
//    
//    
//    
//    
////    for (size_t i=0; i<SublayerCount; i++) {
////        if (i >= _layers.size()) break;
////        auto rect = grid.rectForCellIndex(i);
////        CALayer*const layer = _layers[i];
////        [layer setFrame:{
////            rect.point.x,
////            rect.point.y,
////            rect.size.x,
////            rect.size.y,
////        }];
////    }
//}
//
//@end

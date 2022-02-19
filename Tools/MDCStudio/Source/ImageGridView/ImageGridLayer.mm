#import "ImageGridLayer.h"
#import <simd/simd.h>
#import <filesystem>
#import <MetalKit/MetalKit.h>
#import "ImageGridLayerTypes.h"
#import "Toastbox/Mmap.h"
#import "RecordStore.h"
#import "Util.h"
#import "Grid.h"
using namespace MDCStudio;
namespace fs = std::filesystem;

static constexpr auto _ThumbWidth = ImageThumb::ThumbWidth;
static constexpr auto _ThumbHeight = ImageThumb::ThumbHeight;

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
    id<MTLTexture> _selectionTexture;
    MTLRenderPassDepthAttachmentDescriptor* _depthAttachment;
    
    CGFloat _contentsScale;
    
    Grid _grid;
    uint32_t _cellWidth;
    uint32_t _cellHeight;
    ImageLibraryPtr _imgLib;
    
    struct {
        ImageGridLayerImageIds imageIds;
        MDCStudio::ImageId first = 0;
//        size_t first = 0;
        size_t count = 0;
        id<MTLBuffer> buf;
    } _selection;
    
//    uint32_t _thumbInset;
}

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imgLib {
//    extern void CreateThumbBuf();
//    CreateThumbBuf();
    NSParameterAssert(imgLib);
    
    if (!(self = [super init])) return nil;
    
    _imgLib = imgLib;
    _contentsScale = 1;
    
    [self setOpaque:true];
    [self setActions:LayerNullActions];
    [self setNeedsDisplayOnBoundsChange:true];
    
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
    
    _shadowTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"Shadow"] options:nil error:nil];
    assert(_shadowTexture);
    
    _selectionTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"Selection"] options:nil error:nil];
    assert(_selectionTexture);
    
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
    
//static float4 blendOverPremul(float4 a, float4 b) {
//    const float oa = (1.0)*a.a + (1-a.a)*b.a;
//    const float3 oc = (1.0)*a.rgb + (1-a.a)*b.rgb;
//    return float4(oc, oa);
//}
    
//    [[pipelineDescriptor colorAttachments][0] setAlphaBlendOperation:MTLBlendOperationAdd];
//    [[pipelineDescriptor colorAttachments][0] setSourceAlphaBlendFactor:MTLBlendFactorOne];
//    [[pipelineDescriptor colorAttachments][0] setDestinationAlphaBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
//    
//    [[pipelineDescriptor colorAttachments][0] setRgbBlendOperation:MTLBlendOperationAdd];
//    [[pipelineDescriptor colorAttachments][0] setSourceRGBBlendFactor:MTLBlendFactorOne];
//    [[pipelineDescriptor colorAttachments][0] setDestinationRGBBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
    
//static float4 blendOver(float4 a, float4 b) {
//    const float oa = a.a + b.a*(1-a.a);
//    const float3 oc = (a.rgb*a.a + b.rgb*b.a*(1-a.a)) / oa;
//    return float4(oc, oa);
//}
    
    [[pipelineDescriptor colorAttachments][0] setAlphaBlendOperation:MTLBlendOperationAdd];
    [[pipelineDescriptor colorAttachments][0] setSourceAlphaBlendFactor:MTLBlendFactorSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setDestinationAlphaBlendFactor:MTLBlendFactorOneMinusSourceAlpha];

    [[pipelineDescriptor colorAttachments][0] setRgbBlendOperation:MTLBlendOperationAdd];
    [[pipelineDescriptor colorAttachments][0] setSourceRGBBlendFactor:MTLBlendFactorSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setDestinationRGBBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
    
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
    
    const uint32_t excess = (uint32_t)([_shadowTexture width]-[_maskTexture width]);
    _cellWidth = _ThumbWidth+excess;
    _cellHeight = _ThumbHeight+excess;
    
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

- (void)setContainerWidth:(CGFloat)width {
    _grid.setContainerWidth((int32_t)lround(width*_contentsScale));
}

- (CGFloat)containerHeight {
    return _grid.containerHeight() / _contentsScale;
}

- (size_t)columnCount {
    return _grid.columnCount();
}

- (void)recomputeGrid {
    auto lock = std::unique_lock(*_imgLib);
    _grid.setElementCount((int32_t)_imgLib->recordCount());
    _grid.recompute();
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

static Grid::Rect _GridRectFromCGRect(CGRect rect, CGFloat scale) {
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

static CGRect _CGRectFromGridRect(Grid::Rect rect, CGFloat scale) {
    return CGRect{
        .origin = {rect.point.x / scale, rect.point.y / scale},
        .size = {rect.size.x / scale, rect.size.y / scale},
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

- (void)display {
    auto startTime = std::chrono::steady_clock::now();
    
    // Bail if we have zero width/height; the Metal drawable APIs will fail below
    // if we don't short-circuit here.
    const CGRect frame = [self frame];
    if (CGRectIsEmpty(frame)) return;
    
    auto lock = std::unique_lock(*_imgLib);
    
    // Update our drawable size
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
        [[renderPassDescriptor colorAttachments][0] setClearColor:{WindowBackgroundColor.lsrgb[0], WindowBackgroundColor.lsrgb[1], WindowBackgroundColor.lsrgb[2], 1}];
//        [[renderPassDescriptor colorAttachments][0] setClearColor:{0.118, 0.122, 0.129, 1}];
//        [[renderPassDescriptor colorAttachments][0] setClearColor:{1,1,1,1}];
//        [[renderPassDescriptor colorAttachments][0] setClearColor:{0,0,0,0}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthStencilState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        [renderEncoder endEncoding];
    }
    
    const Grid::IndexRange indexRange = _grid.indexRangeForIndexRect(_grid.indexRectForRect(_GridRectFromCGRect(frame, _contentsScale)));
    if (indexRange.count) {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [renderPassDescriptor setDepthAttachment:depthAttachment];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
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
        
        const uintptr_t imageRefsBegin = (uintptr_t)&*_imgLib->begin();
        const uintptr_t imageRefsEnd = (uintptr_t)&*_imgLib->end();
        id<MTLBuffer> imageRefs = [_device newBufferWithBytes:(void*)imageRefsBegin
            length:imageRefsEnd-imageRefsBegin options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared];
        
//        printf("Range count: %zu\n", ranges.size());
        
        const auto imageRefFirst = _imgLib->begin()+indexRange.start;
        const auto imageRefLast = _imgLib->begin()+indexRange.start+indexRange.count-1;
        
        const auto imageRefBegin = imageRefFirst;
        const auto imageRefEnd = std::next(imageRefLast);
        
//        const auto chunkFirst = imageRefFirst->chunk;
//        const auto chunkLast = imageRefLast->chunk;
//        
//        const auto chunkBegin = chunkFirst;
//        const auto chunkEnd = std::next(chunkLast);
        for (auto it=imageRefBegin; it<imageRefEnd;) {
            const auto& chunk = *(it->chunk);
            const auto nextChunkStart = ImageLibrary::FindNextChunk(it, _imgLib->end());
            
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
            
            const uintptr_t addrBegin = (uintptr_t)(chunk.mmap.data()+(sizeof(ImageLibrary::Record)*chunkImageRefFirst->idx));
            const uintptr_t addrEnd = (uintptr_t)(chunk.mmap.data()+(sizeof(ImageLibrary::Record)*(chunkImageRefLast->idx+1)));
            
            const uintptr_t addrAlignedBegin = _FloorToPageSize(addrBegin);
            const uintptr_t addrAlignedEnd = _CeilToPageSize(addrEnd);
            
//            const RangeMem mem = _RangeMemCalc(ic, range);
            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
            id<MTLBuffer> imageBuf = [_device newBufferWithBytesNoCopy:(void*)addrAlignedBegin
                length:(addrAlignedEnd-addrAlignedBegin) options:BufOpts deallocator:nil];
            
//            printf("length: %zu\n", addrAlignedEnd-addrAlignedBegin);
            
            if (imageBuf) {
                assert(imageBuf);
                assert(_selection.first <= UINT32_MAX);
                assert(_selection.count <= UINT32_MAX);
                
                // Make sure _selection.buf != nil
                if (!_selection.buf) {
                    _selection.buf = [_device newBufferWithLength:1 options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModePrivate];
                }
                
//                static_assert(sizeof(it)==9);
            //    NSLog(@"%@", NSStringFromRect(frame));
            //    NSLog(@"Offset: %d", lround(frame.origin.y)-cell0Rect.point.y);
            //    NSLog(@"indexRange: [%d %d]", indexRange.start, indexRange.start+indexRange.count-1);
                ImageGridLayerTypes::RenderContext ctx = {
                    .grid = _grid,
//                    .chunk = ImageGridLayerTypes::UInt2FromType(it),
                    .idxOff = (uint32_t)(chunkImageRefFirst-_imgLib->begin()),
                    .imagesOff = (uint32_t)(addrBegin-addrAlignedBegin),
//                    .imageRefOff = (uint32_t)ic.getImageRef(range.idx),
                    .imageSize = (uint32_t)sizeof(ImageLibrary::Record),
                    .viewOffset = {offsetX, offsetY},
                    .viewMatrix = unityFromRasterMatrix,
                    .off = {
                        .id         = (uint32_t)(offsetof(ImageThumb, ref.id)),
                        .thumbData  = (uint32_t)(offsetof(ImageThumb, thumb)),
                    },
                    .thumb = {
                        .width  = ImageThumb::ThumbWidth,
                        .height = ImageThumb::ThumbHeight,
                        .pxSize = ImageThumb::ThumbPixelSize,
                    },
                    .selection = {
                        .first = (uint32_t)_selection.first,
//                        .first = (uint32_t)_selection.first,
                        .count = (uint32_t)_selection.count,
                    },
                    .cellWidth = _cellWidth,
                    .cellHeight = _cellHeight,
                };
                
                [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
                [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
                
                [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
                [renderEncoder setFragmentBuffer:imageBuf offset:0 atIndex:1];
                [renderEncoder setFragmentBuffer:_selection.buf offset:0 atIndex:2];
                [renderEncoder setFragmentTexture:_maskTexture atIndex:0];
                [renderEncoder setFragmentTexture:_outlineTexture atIndex:1];
                [renderEncoder setFragmentTexture:_shadowTexture atIndex:2];
                [renderEncoder setFragmentTexture:_selectionTexture atIndex:4];
                
            //    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1];
                
            //    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(frame));
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
    [self setNeedsDisplay];
}

//- (void)setImageLibrary:(ImageLibraryPtr)imgLib {
//    _imgLib = imgLib;
//    [self setNeedsDisplay];
//}

- (void)setResizingUnderway:(bool)resizing {
    NSLog(@"setResizingUnderway: %d", resizing);
    // We need PresentsWithTransaction=1 while window is resizing (to prevent artifacts),
    // and PresentsWithTransaction=0 while scrolling (to prevent stutters)
    [self setPresentsWithTransaction:resizing];
}

- (ImageGridLayerImageIds)imageIdsForRect:(CGRect)rect {
    auto lock = std::unique_lock(*_imgLib);
    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(rect, _contentsScale));
    ImageGridLayerImageIds imageIds;
    for (int32_t y=indexRect.y.start; y<(indexRect.y.start+indexRect.y.count); y++) {
        for (int32_t x=indexRect.x.start; x<(indexRect.x.start+indexRect.x.count); x++) {
            const int32_t idx = _grid.columnCount()*y + x;
            if (idx >= _imgLib->recordCount()) goto done;
            const ImageRef& imageRef = _imgLib->recordGet(_imgLib->begin()+idx)->ref;
            imageIds.insert(imageRef.id);
        }
    }
done:
    return imageIds;
}

- (CGRect)rectForImageAtIndex:(size_t)idx {
    return _CGRectFromGridRect(_grid.rectForCellIndex((int32_t)idx), _contentsScale);
}

- (const ImageGridLayerImageIds&)selectedImageIds {
    return _selection.imageIds;
}

- (void)setSelectedImageIds:(const ImageGridLayerImageIds&)imageIds {
    if (!imageIds.empty()) {
        _selection.imageIds = imageIds;
        _selection.first = *imageIds.begin();
        _selection.count = *std::prev(imageIds.end())-*imageIds.begin()+1;
        
        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
        _selection.buf = [_device newBufferWithLength:_selection.count options:BufOpts];
        bool* bools = (bool*)[_selection.buf contents];
        for (ImageId imageId : imageIds) {
            bools[imageId-_selection.first] = true;
        }
    
    } else {
        _selection = {};
    }
    
    [self setNeedsDisplay];
}

//- (ImageGridLayerIndexes)indexesForRect:(CGRect)rect {
//    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(rect, _contentsScale));
//    ImageGridLayerIndexes indexes;
//    for (int32_t y=indexRect.y.start; y<(indexRect.y.start+indexRect.y.count); y++) {
//        for (int32_t x=indexRect.x.start; x<(indexRect.x.start+indexRect.x.count); x++) {
//            const size_t idx = _grid.columnCount()*y + x;
//            indexes.insert(idx);
//        }
//    }
//    return indexes;
//}
//
//- (void)setSelectedIndexes:(const ImageGridLayerIndexes&)indexes {
//    if (!indexes.empty()) {
//        _selection.first = *indexes.begin();
//        _selection.count = *std::prev(indexes.end())-*indexes.begin()+1;
//        
//        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
//        _selection.buf = [_device newBufferWithLength:_selection.count options:BufOpts];
//        bool* bools = (bool*)[_selection.buf contents];
//        for (size_t idx : indexes) {
//            bools[idx-_selection.first] = true;
//        }
//    
//    } else {
//        _selection = {};
//    }
//    
//    [self setNeedsDisplay];
//}

@end

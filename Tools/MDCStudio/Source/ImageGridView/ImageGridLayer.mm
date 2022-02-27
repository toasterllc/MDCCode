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

using ThumbFile = Mmap;

@implementation ImageGridLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLTexture> _outlineTexture;
    id<MTLTexture> _maskTexture;
    id<MTLTexture> _shadowTexture;
    id<MTLTexture> _selectionTexture;
    
    Grid _grid;
    uint32_t _cellWidth;
    uint32_t _cellHeight;
    ImageLibraryPtr _imageLibrary;
    
    struct {
        ImageGridLayerImageIds imageIds;
        MDCStudio::ImageId first = 0;
//        size_t first = 0;
        size_t count = 0;
        id<MTLBuffer> buf;
    } _selection;
    
//    uint32_t _thumbInset;
}

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imageLibrary {
//    extern void CreateThumbBuf();
//    CreateThumbBuf();
    NSParameterAssert(imageLibrary);
    
    if (!(self = [super init])) return nil;
    
    _imageLibrary = imageLibrary;
    
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

//- (CGSize)preferredFrameSize {
//    const CGFloat w = _grid.containerWidth() / [self contentsScale];
//    const CGFloat h = _grid.containerHeight() / [self contentsScale];
//    return {w,h};
//}

//- (CGSize)preferredFrameSize {
//    const CGFloat w = [[self superlayer] bounds].size.width;
//    const CGFloat contentsScale = [self contentsScale];
//    Grid grid = _grid;
//    grid.setContainerWidth(w * contentsScale);
//    grid.recompute();
//    const CGFloat h = grid.containerHeight()/contentsScale;
//    return {w, h};
//}

- (void)setContainerWidth:(CGFloat)width {
    _grid.setContainerWidth((int32_t)lround(width*[self contentsScale]));
}

- (CGFloat)containerHeight {
    return _grid.containerHeight() / [self contentsScale];
}

- (size_t)columnCount {
    return _grid.columnCount();
}

- (void)recomputeGrid {
    auto lock = std::unique_lock(*_imageLibrary);
    _grid.setElementCount((int32_t)_imageLibrary->recordCount());
    _grid.recompute();
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
    [super display];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    const CGRect frame = [self frame];
    const CGFloat contentsScale = [self contentsScale];
    const CGSize superlayerSize = [[self superlayer] bounds].size;
    const CGSize viewSize = {superlayerSize.width*contentsScale, superlayerSize.height*contentsScale};
    
    auto lock = std::unique_lock(*_imageLibrary);
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{WindowBackgroundColor.lsrgb[0], WindowBackgroundColor.lsrgb[1], WindowBackgroundColor.lsrgb[2], 1}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        [renderEncoder endEncoding];
    }
    
    const Grid::IndexRange indexRange = _grid.indexRangeForIndexRect(_grid.indexRectForRect(_GridRectFromCGRect(frame, contentsScale)));
    if (indexRange.count) {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        const uintptr_t imageRefsBegin = (uintptr_t)&*_imageLibrary->begin();
        const uintptr_t imageRefsEnd = (uintptr_t)&*_imageLibrary->end();
        id<MTLBuffer> imageRefs = [_device newBufferWithBytes:(void*)imageRefsBegin
            length:imageRefsEnd-imageRefsBegin options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared];
        
        const auto imageRefFirst = _imageLibrary->begin()+indexRange.start;
        const auto imageRefLast = _imageLibrary->begin()+indexRange.start+indexRange.count-1;
        
        const auto imageRefBegin = imageRefFirst;
        const auto imageRefEnd = std::next(imageRefLast);
        
        for (auto it=imageRefBegin; it<imageRefEnd;) {
            const auto& chunk = *(it->chunk);
            const auto nextChunkStart = ImageLibrary::FindNextChunk(it, _imageLibrary->end());
            
            const auto chunkImageRefBegin = it;
            const auto chunkImageRefEnd = std::min(imageRefEnd, nextChunkStart);
            
            const auto chunkImageRefFirst = chunkImageRefBegin;
            const auto chunkImageRefLast = std::prev(chunkImageRefEnd);
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            [renderEncoder setRenderPipelineState:_pipelineState];
            [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [renderEncoder setCullMode:MTLCullModeNone];
            
            const uintptr_t addrBegin = (uintptr_t)(chunk.mmap.data()+(sizeof(ImageLibrary::Record)*chunkImageRefFirst->idx));
            const uintptr_t addrEnd = (uintptr_t)(chunk.mmap.data()+(sizeof(ImageLibrary::Record)*(chunkImageRefLast->idx+1)));
            
            const uintptr_t addrAlignedBegin = _FloorToPageSize(addrBegin);
            const uintptr_t addrAlignedEnd = _CeilToPageSize(addrEnd);
            
            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
            id<MTLBuffer> imageBuf = [_device newBufferWithBytesNoCopy:(void*)addrAlignedBegin
                length:(addrAlignedEnd-addrAlignedBegin) options:BufOpts deallocator:nil];
            
            if (imageBuf) {
                assert(imageBuf);
                assert(_selection.first <= UINT32_MAX);
                assert(_selection.count <= UINT32_MAX);
                
                // Make sure _selection.buf != nil
                if (!_selection.buf) {
                    _selection.buf = [_device newBufferWithLength:1 options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModePrivate];
                }
                
                ImageGridLayerTypes::RenderContext ctx = {
                    .grid = _grid,
                    .idxOff = (uint32_t)(chunkImageRefFirst-_imageLibrary->begin()),
                    .imagesOff = (uint32_t)(addrBegin-addrAlignedBegin),
                    .imageSize = (uint32_t)sizeof(ImageLibrary::Record),
                    .viewSize = {(float)viewSize.width, (float)viewSize.height},
                    .transform = [self transform],
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
                
                const size_t chunkImageCount = chunkImageRefEnd-chunkImageRefBegin;
                [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:chunkImageCount];
            }
            
            [renderEncoder endEncoding];
            
            it = chunkImageRefEnd;
            
//            break;
        }
    }
    
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted]; // Necessary to prevent artifacts when resizing window
    [drawable present];
    
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Took %ju ms\n", (uintmax_t)durationMs);
}

- (void)setResizingUnderway:(bool)resizing {
    NSLog(@"setResizingUnderway: %d", resizing);
    // We need PresentsWithTransaction=1 while window is resizing (to prevent artifacts),
    // and PresentsWithTransaction=0 while scrolling (to prevent stutters)
    [self setPresentsWithTransaction:resizing];
}

- (ImageGridLayerImageIds)imageIdsForRect:(CGRect)rect {
    auto lock = std::unique_lock(*_imageLibrary);
    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(rect, [self contentsScale]));
    ImageGridLayerImageIds imageIds;
    for (int32_t y=indexRect.y.start; y<(indexRect.y.start+indexRect.y.count); y++) {
        for (int32_t x=indexRect.x.start; x<(indexRect.x.start+indexRect.x.count); x++) {
            const int32_t idx = _grid.columnCount()*y + x;
            if (idx >= _imageLibrary->recordCount()) goto done;
            const ImageRef& imageRef = _imageLibrary->recordGet(_imageLibrary->begin()+idx)->ref;
            imageIds.insert(imageRef.id);
        }
    }
done:
    return imageIds;
}

- (CGRect)rectForImageAtIndex:(size_t)idx {
    return _CGRectFromGridRect(_grid.rectForCellIndex((int32_t)idx), [self contentsScale]);
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

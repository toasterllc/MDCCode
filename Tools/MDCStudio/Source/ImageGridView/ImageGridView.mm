#import "ImageGridView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
#import "ImageGridLayerTypes.h"
#import "Util.h"
#import "Grid.h"
#import "ImageThumb.h"
#import "Code/Shared/Img.h"
#import "Code/Lib/AnchoredScrollView/AnchoredMetalDocumentLayer.h"
#import "Toastbox/LRU.h"
#import "Toastbox/IterAny.h"
#import "Toastbox/Signal.h"
#import "Toastbox/Mac/Util.h"
using namespace MDCStudio;

static constexpr auto _ThumbWidth = ImageThumb::ThumbWidth;
static constexpr auto _ThumbHeight = ImageThumb::ThumbHeight;

// _PixelFormat == RGBA8Unorm with -setColorspace:LinearSRGB appears to be the correct
// combination such that we supply color data in the linear SRGB colorspace and the
// system handles conversion into SRGB.
// (Without calling -setColorspace:, CAMetalLayers don't perform color matching!)
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatRGBA8Unorm;

@interface ImageGridLayer : AnchoredMetalDocumentLayer

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource
    selection:(ImageSelectionPtr)selection;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;
- (size_t)columnCount;
- (void)updateGridElementCount;

- (ImageSet)imagesForRect:(CGRect)rect;
//- (CGRect)rectForImageAtIndex:(size_t)idx;

@end

struct _ChunkTexture {
    static constexpr size_t SliceCount = ImageLibrary::ChunkRecordCap;
    id<MTLTexture> txt = nil;
    uint32_t loadCounts[SliceCount] = {};
};

static constexpr size_t _ChunkTexturesCacheCapacity = 4;
using _ChunkTextures = Toastbox::LRU<ImageLibrary::ChunkStrongRef,_ChunkTexture,_ChunkTexturesCacheCapacity>;

// MARK: - ImageGridLayer

@implementation ImageGridLayer {
    ImageSourcePtr _imageSource;
    ImageLibraryPtr _imageLibrary;
    ImageSelectionPtr _selection;
    Object::ObserverPtr _selectionOb;
    uint32_t _cellWidth;
    uint32_t _cellHeight;
    Grid _grid;
    bool _sortNewestFirst;
    CGFloat _containerWidth;
    NSEdgeInsets _contentInsets;
    
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLTexture> _placeholderTexture;
    
    _ChunkTextures _chunkTxts;
    
    struct {
        size_t base = 0;
        size_t count = 0;
        id<MTLBuffer> buf;
    } _selectionDraw;
}

static CGColorSpaceRef _LinearSRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    return cs;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource
selection:(MDCStudio::ImageSelectionPtr)selection {
    
    NSParameterAssert(imageSource);
    NSParameterAssert(selection);
    
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    _imageLibrary = imageSource->imageLibrary();
    _selection = selection;
    
    __weak auto selfWeak = self;
    _selectionOb = _selection->observerAdd([=] (auto, const Object::Event& ev) {
        [selfWeak _handleSelectionEvent:ev];
    });
    
    _cellWidth = _ThumbWidth;
    _cellHeight = _ThumbHeight;
    
    // Init our grid border
    [self setContentInsets:{}];
    
    _grid.setCellSize({(int32_t)_cellWidth, (int32_t)_cellHeight});
    _grid.setCellSpacing({6, 6});
//    _grid.setCellSpacing({(int32_t)_cellWidth/10, (int32_t)_cellHeight/10});
    
    _sortNewestFirst = true;
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    [self setColorspace:_LinearSRGBColorSpace()]; // See comment for _PixelFormat
    
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:_device];
    // TODO: supply scaleFactor properly
    
    _placeholderTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"ImageGrid-ImagePlaceholder"] options:nil error:nil];
    assert(_placeholderTexture);
    assert([_placeholderTexture width] == _cellWidth);
    assert([_placeholderTexture height] == _cellHeight);
    
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
    
    [[pipelineDescriptor colorAttachments][0] setAlphaBlendOperation:MTLBlendOperationAdd];
    [[pipelineDescriptor colorAttachments][0] setSourceAlphaBlendFactor:MTLBlendFactorSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setDestinationAlphaBlendFactor:MTLBlendFactorOneMinusSourceAlpha];

    [[pipelineDescriptor colorAttachments][0] setRgbBlendOperation:MTLBlendOperationAdd];
    [[pipelineDescriptor colorAttachments][0] setSourceRGBBlendFactor:MTLBlendFactorSourceAlpha];
    [[pipelineDescriptor colorAttachments][0] setDestinationRGBBlendFactor:MTLBlendFactorOneMinusSourceAlpha];
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    assert(_pipelineState);
    
    // Make our layer transparent against the layer's background
    [self setOpaque:false];
    
//    NSColorPanel* colorPanel = [NSColorPanel sharedColorPanel];
//    [colorPanel makeKeyAndOrderFront:nil];
//    [NSTimer scheduledTimerWithTimeInterval:.1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        [self setNeedsDisplay];
//    }];
    return self;
}

- (void)dealloc {
    printf("~ImageGridLayer\n");
}

- (Grid&)grid {
    return _grid;
}

- (void)setContainerWidth:(CGFloat)x {
//    NSLog(@"-[ImageGridLayer setContainerWidth:]");
    _containerWidth = x;
    _grid.setContainerWidth((int32_t)lround(_containerWidth * [self contentsScale]));
}

- (CGFloat)containerHeight {
    return _grid.containerHeight() / [self contentsScale];
}

- (size_t)columnCount {
    return _grid.columnCount();
}

- (void)setContentsScale:(CGFloat)x {
//    NSLog(@"-[ImageGridLayer setContentsScale:]");
    [super setContentsScale:x];
    [self setContainerWidth:_containerWidth];
    [self setContentInsets:_contentInsets];
}

- (void)setContentInsets:(NSEdgeInsets)contentInsets {
    const CGFloat k = [self contentsScale];
    _contentInsets = contentInsets;
    _grid.setBorderSize({
        .left   = 6+(int32_t)lround(k*_contentInsets.left),
        .right  = 6+(int32_t)lround(k*_contentInsets.right),
        .top    = 6+(int32_t)lround(k*_contentInsets.top),
        .bottom = 6+(int32_t)lround(k*_contentInsets.bottom),
    });
}

- (void)updateGridElementCount {
    auto lock = std::unique_lock(*_imageLibrary);
    _grid.setElementCount((int32_t)_imageLibrary->recordCount());
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

// _ChunkTextureUpdateSlice: if _ChunkTexture's slice for an ImageRecord is stale, reloads the compressed
// thumbnail data from the ImageRecord into the slice
static void _ChunkTextureUpdateSlice(_ChunkTexture& ct, const ImageLibrary::RecordRef& ref) {
    const uint32_t loadCount = ref->status.loadCount;
    if (loadCount != ct.loadCounts[ref.idx]) {
//        printf("Update slice\n");
        const uint8_t* b = ref.chunk->mmap.data() + ref.idx*sizeof(ImageRecord) + offsetof(ImageRecord, thumb.data);
        [ct.txt replaceRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0
            slice:ref.idx withBytes:b bytesPerRow:ImageThumb::ThumbWidth*4 bytesPerImage:0];
        
        ct.loadCounts[ref.idx] = loadCount;
    }
}

static MTLTextureDescriptor* _TextureDescriptor() {
    MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
    [desc setTextureType:MTLTextureType2DArray];
    [desc setPixelFormat:ImageThumb::PixelFormat];
    [desc setWidth:ImageThumb::ThumbWidth];
    [desc setHeight:ImageThumb::ThumbHeight];
    [desc setArrayLength:_ChunkTexture::SliceCount];
    return desc;
}

#warning TODO: throw out the oldest textures from _chunkTxts after it hits a high-water mark
// _getChunkTexture: returns a _ChunkTexture& containing all thumbnails for a given chunk
// ImageLibrary must be locked!
- (_ChunkTexture&)_getChunkTexture:(ImageRecordIterAny)iter {
    // If we already have a _ChunkTexture for the iter's chunk, return it.
    // Otherwise we need to create it.
    const ImageLibrary::ChunkStrongRef chunk = iter->chunkRef();
    const auto it = _chunkTxts.find(chunk);
    if (it != _chunkTxts.end()) {
        return it->val;
    }
    
    const auto chunkBegin = ImageLibrary::FindChunkBegin(ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst), iter);
    const auto chunkEnd = ImageLibrary::FindChunkEnd(ImageLibrary::EndSorted(*_imageLibrary, _sortNewestFirst), iter);
    assert(chunkBegin != chunkEnd);
    
    auto startTime = std::chrono::steady_clock::now();
    
    static MTLTextureDescriptor* txtDesc = _TextureDescriptor();
    id<MTLTexture> txt = [_device newTextureWithDescriptor:txtDesc];
    assert(txt);
    
    _ChunkTexture& ct = _chunkTxts[chunk];
    ct.txt = txt;
    
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Texture creation took %ju ms\n", (uintmax_t)durationMs);
    
    return ct;
}

// ImageLibrary must be locked!
- (void)_display:(id<MTLTexture>)drawableTxt commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    const CGRect frame = [self frame];
    const CGFloat contentsScale = [self contentsScale];
    const CGSize superlayerSize = [[self superlayer] bounds].size;
    const CGSize viewSize = {superlayerSize.width*contentsScale, superlayerSize.height*contentsScale};
    const Grid::IndexRange visibleIndexRange = _VisibleIndexRange(_grid, frame, contentsScale);
    if (!visibleIndexRange.count) return;
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [[renderPassDescriptor colorAttachments][0] setTexture:drawableTxt];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionLoad];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    
    // Recreate _selection properties
    if (!_selectionDraw.buf) {
        const ImageSet& selectionImages = _selection->images();
        const auto itBegin = (!selectionImages.empty() ?
            _imageLibrary->find(*selectionImages.begin()) : _imageLibrary->end());
        const auto itLast = (!selectionImages.empty() ?
            _imageLibrary->find(*std::prev(selectionImages.end())) : _imageLibrary->end());
        const auto itEnd = (itLast!=_imageLibrary->end() ? std::next(itLast) : _imageLibrary->end());
        
        if (itBegin!=_imageLibrary->end() && itLast!=_imageLibrary->end()) {
            _selectionDraw.base = itBegin-_imageLibrary->begin();
            _selectionDraw.count = itEnd-itBegin;
            
            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
            _selectionDraw.buf = [_device newBufferWithLength:_selectionDraw.count options:BufOpts];
            bool* bools = (bool*)[_selectionDraw.buf contents];
            
            size_t i = 0;
            for (auto it=itBegin; it!=itEnd; it++) {
                if (selectionImages.find(*it) != selectionImages.end()) {
                    bools[i] = true;
                }
                i++;
            }
        
        } else {
            _selectionDraw.buf = [_device newBufferWithLength:1 options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModePrivate];
        }
        
        assert(_selectionDraw.buf);
    }
    
    const uintptr_t imageRefsBegin = (uintptr_t)&*_imageLibrary->begin();
    const uintptr_t imageRefsEnd = (uintptr_t)&*_imageLibrary->end();
    id<MTLBuffer> imageRefs = [_device newBufferWithBytes:(void*)imageRefsBegin
        length:imageRefsEnd-imageRefsBegin options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared];
    
    const auto begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
    const auto [visibleBegin, visibleEnd] = _VisibleRange(visibleIndexRange, *_imageLibrary, _sortNewestFirst);
    
//    NSColor* color = [[NSColorPanel sharedColorPanel] color];
//    simd::float3 selectionColor;
//    if ([color numberOfComponents] >= 3) {
//        selectionColor = {
//            (float)[color redComponent],
//            (float)[color greenComponent],
//            (float)[color blueComponent],
//        };
//    }
    
    for (auto it=visibleBegin; it!=visibleEnd;) {
        // Update stale _ChunkTexture slices from the ImageRecord's thumbnail data, if needed. (We know whether a
        // _ChunkTexture slice is stale by using ImageRecord's loadCount.)
        const auto chunkBegin = it;
        _ChunkTexture& ct = [self _getChunkTexture:it];
        for (; it!=visibleEnd && it->chunk==chunkBegin->chunk; it++) {
            _ChunkTextureUpdateSlice(ct, *it);
        }
        const auto chunkEnd = it;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        
        assert(_selectionDraw.base <= UINT32_MAX);
        assert(_selectionDraw.count <= UINT32_MAX);
        
        const ImageGridLayerTypes::RenderContext ctx = {
            .grid = _grid,
            .idx = (uint32_t)(chunkBegin-begin),
            .sortNewestFirst = _sortNewestFirst,
            .viewSize = {(float)viewSize.width, (float)viewSize.height},
            .transform = [self anchoredTransform],
            .selection = {
                .base = (uint32_t)_selectionDraw.base,
                .count = (uint32_t)_selectionDraw.count,
            },
        };
        
        [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
        [renderEncoder setVertexBuffer:_selectionDraw.buf offset:0 atIndex:2];
        
        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setFragmentBytes:&ct.loadCounts length:sizeof(ct.loadCounts) atIndex:1];
        [renderEncoder setFragmentTexture:ct.txt atIndex:0];
        [renderEncoder setFragmentTexture:_placeholderTexture atIndex:1];
        
        const size_t chunkImageCount = chunkEnd-chunkBegin;
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:chunkImageCount];
        [renderEncoder endEncoding];
    }
    
    // Re-render the visible thumbnails that are marked dirty
    _ThumbRenderIfNeeded(_imageSource, { visibleBegin, visibleEnd });
}

- (void)display {
//    printf("[ImageGridView] display\n");
    
//    auto startTime = std::chrono::steady_clock::now();
    [super display];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    auto lock = std::unique_lock(*_imageLibrary);
    
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawableTxt];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        [renderEncoder endEncoding];
    }
    
    [self _display:drawableTxt commandBuffer:commandBuffer];
    
    [commandBuffer commit];
    // -waitUntilCompleted necessary because we're rendering directly from the image library, while the lock is held.
    [commandBuffer waitUntilCompleted];
    [drawable present];
}

- (ImageSet)imagesForRect:(CGRect)rect {
    auto lock = std::unique_lock(*_imageLibrary);
    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(rect, [self contentsScale]));
    ImageSet images;
    auto begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
    for (int32_t y=indexRect.y.start; y<(indexRect.y.start+indexRect.y.count); y++) {
        for (int32_t x=indexRect.x.start; x<(indexRect.x.start+indexRect.x.count); x++) {
            const int32_t idx = _grid.columnCount()*y + x;
            if (idx >= _imageLibrary->recordCount()) goto done;
            images.insert(*(begin+idx));
        }
    }
done:
    return images;
}

- (void)_selectionUpdate {
    // Set the entire _selection struct so that _display recreates the buffer
    _selectionDraw = {};
    [self setNeedsDisplay];
}

- (void)setSortNewestFirst:(bool)x {
    _sortNewestFirst = x;
    // Trigger selection update (_selection buffer needs to be cleared)
    [self _selectionUpdate];
}

struct SelectionDelta {
    int x = 0;
    int y = 0;
};

- (CGRect)rectForImageIndex:(size_t)idx {
    return _CGRectFromGridRect(_grid.rectForCellIndex((int32_t)idx), [self contentsScale]);
}

- (std::optional<CGRect>)rectForImageRecord:(ImageRecordPtr)rec {
    auto lock = std::unique_lock(*_imageLibrary);
    auto begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
    auto end = ImageLibrary::EndSorted(*_imageLibrary, _sortNewestFirst);
    const auto it = ImageLibrary::Find(begin, end, rec);
    if (it == end) return std::nullopt;
    const size_t idx = it-begin;
    return [self rectForImageIndex:idx];
}

- (std::optional<CGRect>)moveSelection:(SelectionDelta)delta extend:(bool)extend {
    ssize_t newIdx = 0;
    ImageRecordPtr newImg;
    ImageSet selection = _selection->images();
    {
        auto lock = std::unique_lock(*_imageLibrary);
        
        auto begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
        auto end = ImageLibrary::EndSorted(*_imageLibrary, _sortNewestFirst);
        const size_t imgCount = _imageLibrary->recordCount();
        if (!imgCount) return std::nullopt;
        
        if (!selection.empty()) {
            const auto it = ImageLibrary::Find(begin, end, *std::prev(selection.end()));
            if (it == end) {
                NSLog(@"Image no longer in library");
                return std::nullopt;
            }
            
            const size_t idx = it-begin;
            const size_t colCount = _grid.columnCount();
            const size_t rem = (imgCount % colCount);
            const size_t lastRowCount = (rem ? rem : colCount);
            const bool firstRow = (idx < colCount);
            const bool lastRow = (idx >= (imgCount-lastRowCount));
            const bool firstCol = !(idx % colCount);
            const bool lastCol = ((idx % colCount) == (colCount-1));
            const bool lastElm = (idx == (imgCount-1));
            
            newIdx = idx;
            if (delta.x > 0) {
                // Right
                if (lastCol || lastElm) return std::nullopt;
                newIdx += 1;
            
            } else if (delta.x < 0) {
                // Left
                if (firstCol) return std::nullopt;
                newIdx -= 1;
            
            } else if (delta.y > 0) {
                // Down
                if (lastRow) return std::nullopt;
                newIdx += colCount;
            
            } else if (delta.y < 0) {
                // Up
                if (firstRow) return std::nullopt;
                newIdx -= colCount;
            }
            
            newIdx = std::clamp(newIdx, (ssize_t)0, (ssize_t)imgCount-1);
        
        } else {
            if (delta.x>0 || delta.y>0) {
                // Select first element
                newIdx = 0;
            } else if (delta.x<0 || delta.y<0) {
                // Select last element
                newIdx = imgCount-1;
            } else {
                return std::nullopt;
            }
        }
        
    //    const size_t newIdx = std::min(imgCount-1, idx+[_imageGridLayer columnCount]);
        newImg = *(begin+newIdx);
    }
    
    if (!extend) selection.clear();
    selection.insert(newImg);
    _selection->images(std::move(selection));
    return [self rectForImageIndex:newIdx];
}

// MARK: - ImageSelection Observer

- (void)_handleSelectionEvent:(const Object::Event&)ev {
    // Selection changes must only occur on the main thread!
    assert([NSThread isMainThread]);
    [self _selectionUpdate];
}

// MARK: - AnchoredScrollViewDocument
- (bool)anchoredFlipped {
    return true;
}

// MARK: - Thumb Render

using _IterRange = std::pair<ImageRecordIterAny,ImageRecordIterAny>;

static Grid::IndexRange _VisibleIndexRange(Grid& grid, CGRect frame, CGFloat scale) {
    return grid.indexRangeForIndexRect(grid.indexRectForRect(_GridRectFromCGRect(frame, scale)));
}

static _IterRange _VisibleRange(Grid::IndexRange ir, const ImageLibrary& il, bool sortNewestFirst) {
    ImageRecordIterAny begin = ImageLibrary::BeginSorted(il, sortNewestFirst);
    
    // It's possible for the grid element count to be out of sync with the image library
    // element count, particularly if we display before a pending layout. In that case
    // `ir` could extend beyond the image library, so protect against that and just
    // return an empty range.
    if (ir.start+ir.count > il.recordCount()) {
        return std::make_pair(begin, begin);
    }
    
    const auto visibleBegin = begin+ir.start;
    const auto visibleEnd = begin+ir.start+ir.count;
    return std::make_pair(visibleBegin, visibleEnd);
}

static void _ThumbRenderIfNeeded(ImageSourcePtr is, _IterRange range) {
    std::set<ImageRecordPtr> recs;
    for (auto it=range.first; it!=range.second; it++) {
        if ((*it)->options.thumb.render) {
            recs.insert(*it);
        }
    }
    is->renderThumbs(recs);
}

// _imageLibrary must be locked!
- (void)_thumbRenderVisibleIfNeeded {
    const auto vir = _VisibleIndexRange(_grid, [self frame], [self contentsScale]);
    const auto vr = _VisibleRange(vir, *_imageLibrary, _sortNewestFirst);
    _ThumbRenderIfNeeded(_imageSource, vr);
}

// _imageLibrary must be locked!
- (bool)_recordsIntersectVisibleRange:(const ImageSet&)changed {
    if (changed.empty()) return false;
    const auto visibleRange = _VisibleRange(_VisibleIndexRange(_grid, [self frame], [self contentsScale]),
        *_imageLibrary, _sortNewestFirst);
    if (visibleRange.first == visibleRange.second) return false;
    
    ImageRecordPtr vl = *visibleRange.first;
    ImageRecordPtr vr = *std::prev(visibleRange.second);
    ImageRecordPtr cl = *changed.begin();
    ImageRecordPtr cr = *std::prev(changed.end());
    
    if (vr < vl) std::swap(vl, vr);
    if (cr < cl) std::swap(cl, cr);
    if (vr < cl) return false;
    if (cr < vl) return false;
    return true;
}

@end




















// MARK: - ImageGridView
@implementation ImageGridView {
    ImageGridLayer* _imageGridLayer;
    CALayer* _selectionRectLayer;
    ImageSourcePtr _imageSource;
    ImageSelectionPtr _selection;
    ImageLibraryPtr _imageLibrary;
    Object::ObserverPtr _imageLibraryOb;
    NSLayoutConstraint* _docHeight;
//    id _widthChangedObserver;
}

// MARK: - Creation

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource selection:(ImageSelectionPtr)selection {
    // Create ImageGridLayer
    ImageGridLayer* imageGridLayer = [[ImageGridLayer alloc] initWithImageSource:imageSource
        selection:selection];
    if (!(self = [super initWithAnchoredLayer:imageGridLayer])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _imageSource = imageSource;
    _selection = selection;
    _imageLibrary = _imageSource->imageLibrary();
    
    __weak auto selfWeak = self;
    // We observe the ImageLibrary with ImageGridView, and not with ImageGridLayer,
    // because when images are added/removed, we need to schedule layout+redraw,
    // and we want both to be apart of the same runloop iteration to avoid
    // flickering. By observing the ImageLibrary with ImageGridView, we can
    // do:
    //     [[self enclosingScrollView] setNeedsLayout:true];
    //     [_imageGridLayer _selectionUpdate];
    // to schedule both the view layout and layer redraw in the same runloop iteration.
    _imageLibraryOb = _imageLibrary->observerAdd([=] (auto, const Object::Event& ev) {
        [selfWeak _handleImageLibraryEvent:static_cast<const ImageLibrary::Event&>(ev)];
    });
    
    _imageGridLayer = imageGridLayer;
    
    // Create _selectionRectLayer
    {
        _selectionRectLayer = [CALayer new];
        [_selectionRectLayer setActions:Toastbox::LayerNullActions];
        [_selectionRectLayer setBackgroundColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:.2] CGColor]];
        [_selectionRectLayer setBorderColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] CGColor]];
        [_selectionRectLayer setHidden:true];
        [_selectionRectLayer setBorderWidth:1];
        [_imageGridLayer addSublayer:_selectionRectLayer];
    }
    
    return self;
}

- (void)dealloc {
    printf("~ImageGridView\n");
}

- (ImageSourcePtr)imageSource {
    return _imageSource;
}

- (void)setSortNewestFirst:(bool)x {
    [_imageGridLayer setSortNewestFirst:x];
}

- (CGRect)rectForImageIndex:(size_t)idx {
    return [_imageGridLayer rectForImageIndex:idx];
}

- (std::optional<CGRect>)rectForImageRecord:(ImageRecordPtr)rec {
    return [_imageGridLayer rectForImageRecord:rec];
}

- (void)scrollToImageRect:(CGRect)rect center:(bool)center {
    if (center) {
        const CGFloat height = [self bounds].size.height;
        const CGFloat delta = height - rect.size.height;
        rect.origin.y -= delta/2;
        rect.size.height = height;
        [self scrollRectToVisible:[self convertRect:rect fromView:[self superview]]];
    } else {
        [self scrollRectToVisible:[self convertRect:rect fromView:[self superview]]];
    }
}

- (void)_moveSelection:(SelectionDelta)delta extend:(bool)extend {
    std::optional<CGRect> rect = [_imageGridLayer moveSelection:delta extend:extend];
    if (!rect) return;
    [self scrollToImageRect:*rect center:false];
}

- (void)_updateDocumentHeight {
    [_imageGridLayer setContainerWidth:[[self enclosingScrollView] bounds].size.width];
    [_imageGridLayer updateGridElementCount];
    [_docHeight setConstant:[_imageGridLayer containerHeight]];
}





// MARK: - ImageLibrary Observer

// _handleImageLibraryEvent: called on whatever thread where the modification happened,
// and with the ImageLibrary lock held!
- (void)_handleImageLibraryEvent:(const ImageLibrary::Event&)ev {
    // Trampoline the event to our main thread, if we're not on the main thread
    if (![NSThread isMainThread]) {
        ImageLibrary::Event evCopy = ev;
        dispatch_async(dispatch_get_main_queue(), ^{
            auto lock = std::unique_lock(*self->_imageLibrary);
            [self _handleImageLibraryEvent:evCopy];
        });
        return;
    }
    
    switch (ev.type) {
    case ImageLibrary::Event::Type::Add:
    case ImageLibrary::Event::Type::Remove:
    case ImageLibrary::Event::Type::Clear:
        [[self enclosingScrollView] setNeedsLayout:true];
        [_imageGridLayer _selectionUpdate];
        break;
    
    case ImageLibrary::Event::Type::ChangeProperty:
        if ([_imageGridLayer _recordsIntersectVisibleRange:ev.records]) {
            // Re-render visible thumbs that are dirty
            // We don't check if any of `ev` intersect the visible range, because _thumbRenderVisibleIfNeeded
            // should be cheap and reduces to a no-op if none of the visible thumbs are dirty.
            [_imageGridLayer _thumbRenderVisibleIfNeeded];
        }
        break;
    case ImageLibrary::Event::Type::ChangeThumbnail:
        if ([_imageGridLayer _recordsIntersectVisibleRange:ev.records]) {
            [_imageGridLayer setNeedsDisplay];
        }
        break;
    default:
        break;
    }
}




// MARK: - Event Handling

//static CGPoint _ConvertPoint(CALayer* dst, NSView* src, CGPoint x) {
//    CALayer* srcLayer = [src layer];
//    x = [src convertPointToLayer:x];
//    return [dst convertPoint:x fromLayer:srcLayer];
//}

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
    
    NSView* superview = [self superview];
    NSWindow* win = [mouseDownEvent window];
//    const CGPoint startPoint = _ConvertPoint(_imageGridLayer, _documentView,
//        [_documentView convertPoint:[mouseDownEvent locationInWindow] fromView:nil]);
    const CGPoint startPoint = [superview convertPoint:[mouseDownEvent locationInWindow] fromView:nil];
    [_selectionRectLayer setHidden:false];
    
    const bool extend = [[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    const ImageSet oldSelection = _selection->images();
    Toastbox::TrackMouse(win, mouseDownEvent, [=] (NSEvent* event, bool done) {
//        const CGPoint curPoint = _ConvertPoint(_imageGridLayer, _documentView, [_documentView convertPoint:[event locationInWindow] fromView:nil]);
        const CGPoint curPoint = [superview convertPoint:[event locationInWindow] fromView:nil];
        const CGRect rect = CGRectStandardize(CGRect{startPoint.x, startPoint.y, curPoint.x-startPoint.x, curPoint.y-startPoint.y});
        ImageSet newSelection = [_imageGridLayer imagesForRect:rect];
        if (extend) {
            _selection->images(ImageSetsXOR(oldSelection, newSelection));
        } else {
            _selection->images(std::move(newSelection));
        }
        [_selectionRectLayer setFrame:[self convertRect:rect fromView:superview]];
        
        [self autoscroll:event];
//        NSLog(@"mouseDown:");
    });
    [_selectionRectLayer setHidden:true];
}

- (void)mouseUp:(NSEvent*)event {
    if ([event clickCount] == 2) {
        [[self window] tryToPerform:@selector(_showImage:) with:self];
    }
}

- (void)rightMouseDown:(NSEvent*)event {
    NSView* superview = [self superview];
    const CGRect rect = {
        [superview convertPoint:[event locationInWindow] fromView:nil],
        {1,1},
    };
    
    const ImageSet& selection = _selection->images();
    const ImageSet clickedImages = [_imageGridLayer imagesForRect:rect];
    const bool clickedImageWasAlreadySelected =
        clickedImages.size()==1 && selection.find(*clickedImages.begin())!=selection.end();
    if (!clickedImages.empty() && !clickedImageWasAlreadySelected) {
        _selection->images(clickedImages);
    }
    [super rightMouseDown:event];
}

- (void)moveDown:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{0,1} extend:extend];
}

- (void)moveUp:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{0,-1} extend:extend];
}

- (void)moveLeft:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{-1,0} extend:extend];
}

- (void)moveRight:(id)sender {
    const bool extend = false;//[[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    [self _moveSelection:{1,0} extend:extend];
}

- (void)selectAll:(id)sender {
    ImageSet selection;
    {
        auto lock = std::unique_lock(*_imageLibrary);
        for (auto it=_imageLibrary->begin(); it!=_imageLibrary->end(); it++) {
            selection.insert(*it);
        }
    }
    _selection->images(selection);
}

// MARK: - AnchoredScrollView

- (void)anchoredCreateConstraintsForContainer:(NSView*)container {
    NSView*const containerSuperview = [container superview];
    if (!containerSuperview) return;
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[container]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(container)]];
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[container]"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(container)]];
    
    NSLayoutConstraint* docHeightMin = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:containerSuperview attribute:NSLayoutAttributeHeight
        multiplier:1 constant:0];
    [docHeightMin setActive:true];
    
    _docHeight = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:1 constant:0];
    // _docHeight isn't Required because `docHeightMin` needs to override it
    // We're priority==Low instead of High, because using High affects our
    // window size for some reason.
    [_docHeight setPriority:NSLayoutPriorityDefaultLow];
    [_docHeight setActive:true];
}

@end


// MARK: - ImageGridScrollView

@implementation ImageGridScrollView {
    NSView* _headerView;
}

- (instancetype)initWithAnchoredDocument:(NSView<AnchoredScrollViewDocument>*)doc {
    if (!(self = [super initWithAnchoredDocument:doc])) return nil;
    [self setAllowsMagnification:false];
    // AnchoredScrollView's anchoring during resize doesn't work with our document because the document
    // resizes when its superviews resize (because its width needs to be the same as its superviews).
    // So disable that behavior.
    [self setAnchorDuringResize:false];
    return self;
}

- (NSView*)headerView {
    return _headerView;
}

- (void)setHeaderView:(NSView*)x {
    [_headerView removeFromSuperview];
    _headerView = x;
    
    // Add header view
    [[self floatingSubviewContainer] addSubview:_headerView];
    
    ImageGridLayer* layer = Toastbox::Cast<ImageGridLayer*>([[self document] layer]);
    [layer setContentInsets:{[_headerView intrinsicContentSize].height+10,0,0,0}];
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_headerView]"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_headerView)]];
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_headerView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_headerView)]];
}

- (void)layout {
    [super layout];
    ImageGridView*const gridView = (ImageGridView*)[self document];
    [gridView _updateDocumentHeight];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    if ([item action] == @selector(magnifyToActualSize:)) {
        return false;
    } else if ([item action] == @selector(magnifyToFit:)) {
        return false;
    } else if ([item action] == @selector(magnifyIncrease:)) {
        return false;
    } else if ([item action] == @selector(magnifyDecrease:)) {
        return false;
    }
    return true;
}

@end

#import "ImageGridView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
#import <simd/simd.h>
#import "ImageGridLayerTypes.h"
#import "Util.h"
#import "DragImage.h"
#import "Shared/ImageExporter/ImageExporter.h"
#import "Shared/Img.h"
#import "Shared/ImageThumb.h"
#import "Lib/AnchoredScrollView/AnchoredMetalDocumentLayer.h"
#import "Lib/Toastbox/Mac/Grid.h"
#import "Lib/Toastbox/LRU.h"
#import "Lib/Toastbox/IterAny.h"
#import "Lib/Toastbox/Signal.h"
#import "Lib/Toastbox/Mac/Util.h"
using namespace MDCStudio;

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
    static constexpr size_t SliceCountMax = 2048; // Metal feature set tables define this max layer count
    id<MTLTexture> txt = nil;
    uint32_t loadCounts[SliceCountMax] = {};
    // `loaded` is separate from `loadCounts` because `loadCounts` is too
    // large to pass as a uniform buffer
    uint8_t loaded[SliceCountMax] = {};
};

static constexpr size_t _ChunkTexturesCacheCapacity = 16;
using _ChunkTextures = Toastbox::LRU<ImageLibrary::ChunkStrongRef,_ChunkTexture,_ChunkTexturesCacheCapacity>;

// MARK: - ImageGridLayer

@implementation ImageGridLayer {
    ImageSourcePtr _imageSource;
    ImageLibraryPtr _imageLibrary;
    const ImageLibrary::Descriptor* _imageLibraryDesc;
    MTLTextureDescriptor* _txtDesc;
    
    ImageSelectionPtr _selection;
    Object::ObserverPtr _selectionOb;
    Toastbox::Grid _grid;
    
    CGFloat _magnification;
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

static MTLTextureDescriptor* _TextureDescriptor(const ImageLibrary::Descriptor& desc, size_t sliceCount) {
    MTLTextureDescriptor* r = [MTLTextureDescriptor new];
    [r setTextureType:MTLTextureType2DArray];
    [r setPixelFormat:ImageThumb::PixelFormat];
    [r setWidth:desc.thumbWidth];
    [r setHeight:desc.thumbHeight];
    [r setArrayLength:sliceCount];
    return r;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource selection:(MDCStudio::ImageSelectionPtr)selection {
    
    NSParameterAssert(imageSource);
    NSParameterAssert(selection);
    
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    _imageLibrary = imageSource->imageLibrary();
    _imageLibraryDesc = &_imageLibrary->descriptor();
    _txtDesc = _TextureDescriptor(*_imageLibraryDesc, _imageLibrary->config().chunkRecordCap);
    
    _selection = selection;
    
    __weak auto selfWeak = self;
    _selectionOb = _selection->observerAdd([=] (auto, const Object::Event& ev) {
        [selfWeak _handleSelectionEvent:ev];
    });
    
    // Init our grid border
    [self setContentInsets:{}];
    
    [self setMagnification:1];
    
    _sortNewestFirst = true;
    
    _device = [self preferredDevice];
    assert(_device);
    [self setDevice:_device];
    [self setColorspace:_LinearSRGBColorSpace()];
    [self setOpaque:false];
    
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:_device];
    // TODO: supply scaleFactor properly
    
    _placeholderTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"ImageGrid-ImagePlaceholder"] options:nil error:nil];
    assert(_placeholderTexture);
    
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
    
    [[pipelineDescriptor colorAttachments][0] setPixelFormat:[self pixelFormat]];
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    assert(_pipelineState);
    
    // Make our layer transparent against the layer's background
    [self setOpaque:false];
    return self;
}

- (void)dealloc {
    printf("~ImageGridLayer\n");
}

- (Toastbox::Grid&)grid {
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

- (CGFloat)magnification {
    return _magnification;
}

- (CGFloat)magnificationMin {
    constexpr CGFloat WidthMinPx = 64;
    return WidthMinPx / _imageLibraryDesc->thumbWidth;
}

- (CGFloat)magnificationMax {
    return 2;
}

- (bool)setMagnification:(CGFloat)x {
    if (_magnification == x) return false;
    
    _magnification = x;
    
    constexpr CGFloat Spacing = 6. / 512;
    const int32_t cellWidth = _magnification*_imageLibraryDesc->thumbWidth;
    const int32_t cellHeight = _magnification*_imageLibraryDesc->thumbHeight;
    const int32_t spacing = (Spacing*_imageLibraryDesc->thumbWidth)*_magnification;
    _grid.setCellSize({cellWidth, cellHeight});
    _grid.setCellSpacing({spacing, spacing});
    
    [self setNeedsDisplay];
    return true;
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

static Toastbox::Grid::Rect _GridRectFromCGRect(CGRect rect, CGFloat scale) {
    const CGRect irect = CGRectIntegral({
        rect.origin.x*scale,
        rect.origin.y*scale,
        rect.size.width*scale,
        rect.size.height*scale,
    });
    
    return Toastbox::Grid::Rect{
        .point = {(int32_t)irect.origin.x, (int32_t)irect.origin.y},
        .size = {(int32_t)irect.size.width, (int32_t)irect.size.height},
    };
}

static CGRect _CGRectFromGridRect(Toastbox::Grid::Rect rect, CGFloat scale) {
    return CGRect{
        .origin = {rect.point.x / scale, rect.point.y / scale},
        .size = {rect.size.x / scale, rect.size.y / scale},
    };
}

// _ChunkTextureUpdateSlice: if _ChunkTexture's slice for an ImageRecord is stale, reloads the compressed
// thumbnail data from the ImageRecord into the slice
static void _ChunkTextureUpdateSlice(const ImageLibrary::Descriptor& desc, _ChunkTexture& ct,
    const ImageLibrary::RecordRef& ref) {
    
    // Verify that the index is within the compile-time max slice count
    assert(ref.idx < _ChunkTexture::SliceCountMax);
    // Verify that the index is within the runtime max slice count
    assert(ref.idx < [ct.txt arrayLength]);
    
    const uint32_t loadCount = ref->status.loadCount;
    if (loadCount != ct.loadCounts[ref.idx]) {
//        printf("Update slice (%ju %u %u)\n", (uintmax_t)ref.idx, loadCount, ct.loadCounts[ref.idx]);
        
        const uint8_t* b = ref.chunk->mmap.data() + ref.idx*ref.recordSize + offsetof(ImageRecord, thumb.data);
        [ct.txt replaceRegion:MTLRegionMake2D(0,0,desc.thumbWidth,desc.thumbHeight) mipmapLevel:0
            slice:ref.idx withBytes:b bytesPerRow:desc.thumbWidth*4 bytesPerImage:0];
        
        ct.loadCounts[ref.idx] = loadCount;
        ct.loaded[ref.idx] = true;
    }
}

#warning TODO: throw out the oldest textures from _chunkTxts after it hits a high-water mark
// _getChunkTexture: returns a _ChunkTexture& containing all thumbnails for a given chunk
// ImageLibrary must be locked!
- (_ChunkTexture&)_getChunkTexture:(ImageRecordIterAny)iter {
    // If we already have a _ChunkTexture for the iter's chunk, return it.
    // Otherwise we need to create it.
    const ImageLibrary::ChunkStrongRef chunk = iter->chunkRef();
    
    // We've seen cases where ChunkStrongRef.chunk == nullptr; try to catch it here so we can debug!
    assert(chunk);
    
    const auto it = _chunkTxts.find(chunk);
    if (it != _chunkTxts.end()) {
        return it->val;
    }
    
//    auto startTime = std::chrono::steady_clock::now();
    
    id<MTLTexture> txt = [_device newTextureWithDescriptor:_txtDesc];
    assert(txt);
    
    _ChunkTexture& ct = _chunkTxts[chunk];
    ct.txt = txt;
    
//    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//    printf("Texture creation took %ju ms\n", (uintmax_t)durationMs);
    
    return ct;
}

// ImageLibrary must be locked!
- (void)_display:(id<MTLTexture>)drawableTxt commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    const CGRect frame = [self frame];
    const CGFloat contentsScale = [self contentsScale];
    const CGSize superlayerSize = [[self superlayer] bounds].size;
    const CGSize viewSize = {superlayerSize.width*contentsScale, superlayerSize.height*contentsScale};
    const Toastbox::Grid::IndexRange visibleIndexRange = _VisibleIndexRange(_grid, frame, contentsScale);
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
            _ChunkTextureUpdateSlice(*_imageLibraryDesc, ct, *it);
        }
        const auto chunkEnd = it;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        
        assert(_selectionDraw.base <= UINT32_MAX);
        assert(_selectionDraw.count <= UINT32_MAX);
        
        constexpr CGFloat SelectionBorderSizeDefault = 10. / 512;
        constexpr CGFloat SelectionBorderSizeMin = 5. / 512;
        
        const uint32_t selectionBorderSizeDefault =
            std::round(_magnification * _imageLibraryDesc->thumbWidth * SelectionBorderSizeDefault);
        const uint32_t selectionBorderSizeMin =
            std::round(SelectionBorderSizeMin*ImageLibrary::Descriptors::ExtraLarge.thumbWidth);
        const uint32_t selectionBorderSize = std::max(selectionBorderSizeMin, selectionBorderSizeDefault);
        
        const ImageGridLayerTypes::RenderContext ctx = {
            .grid = _grid,
            .idx = (uint32_t)(chunkBegin-begin),
            .sortNewestFirst = _sortNewestFirst,
            .viewSize = {(float)viewSize.width, (float)viewSize.height},
            .transform = [self anchoredTransform],
            .selection = {
                .base = (uint32_t)_selectionDraw.base,
                .count = (uint32_t)_selectionDraw.count,
                .borderSize = selectionBorderSize,
            },
        };
        
        [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
        [renderEncoder setVertexBuffer:_selectionDraw.buf offset:0 atIndex:2];
        
        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setFragmentBytes:&ct.loaded length:sizeof(ct.loaded) atIndex:1];
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
    const Toastbox::Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(rect, [self contentsScale]));
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

- (bool)sortNewestFirst {
    return _sortNewestFirst;
}

- (void)setSortNewestFirst:(bool)x {
    _sortNewestFirst = x;
    // Trigger selection update (_selection buffer needs to be cleared)
    [self _selectionUpdate];
}

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

static Toastbox::Grid::IndexRange _VisibleIndexRange(Toastbox::Grid& grid, CGRect frame, CGFloat scale) {
    return grid.indexRangeForIndexRect(grid.indexRectForRect(_GridRectFromCGRect(frame, scale)));
}

static _IterRange _VisibleRange(Toastbox::Grid::IndexRange ir, const ImageLibrary& il, bool sortNewestFirst) {
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
















//using SelectionVector = simd::int2;
//
//static int SelectionVectorAbs(SelectionVector a) {
//    return std::abs(a.x) + std::abs(a.y);
//}

//struct SelectionVector {
//    int x = 0;
//    int y = 0;
//    
//    int abs() const {
//        return std::abs(x)+std::abs(y);
//    }
//};

@interface ImageGridView () <NSDraggingSource>
@end

// MARK: - ImageGridView
@implementation ImageGridView {
    ImageGridLayer* _imageGridLayer;
    CALayer* _selectionRectLayer;
    ImageSourcePtr _imageSource;
    
    ImageSelectionPtr _selection;
    ImageRecordPtr _selectionHead;
    
    ImageLibraryPtr _imageLibrary;
    Object::ObserverPtr _imageLibraryOb;
    NSLayoutConstraint* _docHeight;
    
    struct {
        NSDraggingSession* session;
        NSMutableArray<DragImage*>* images;
    } _drag;
    
    struct {
        ImageRecordPtr anchor;
        CGFloat amount = 1;
    } _mag;
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

- (bool)sortNewestFirst {
    return [_imageGridLayer sortNewestFirst];
}

- (void)setSortNewestFirst:(bool)x {
    [_imageGridLayer setSortNewestFirst:x];
}

- (CGRect)rectForImageIndex:(size_t)idx {
//    CGRect r = [_imageGridLayer rectForImageIndex:idx];
//    const CGFloat height = [_imageGridLayer bounds].size.height;
//    r.origin.y = height - r.origin.y - r.size.height;
//    return r;
    
//    [_imageGridLayer bounds].size.height
    return [_imageGridLayer rectForImageIndex:idx];
}

- (std::optional<CGRect>)rectForImageRecord:(ImageRecordPtr)rec {
    return [_imageGridLayer rectForImageRecord:rec];
//    std::optional<CGRect> r = [_imageGridLayer rectForImageRecord:rec];
//    if (!r) return std::nullopt;
////    return [self convertRectFromLayer:*r];
//    
//    const CGFloat height = [_imageGridLayer bounds].size.height;
//    r->origin.y = height - r->origin.y - r->size.height - 22;
////    r->origin.y = (((height-12) - (r->origin.y-6)) - r->size.height) + 6;
//    return r;
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

- (void)_moveSelection:(simd::int2)delta extend:(bool)extend {
    assert(delta.x==0 || delta.y==0); // Prohibit diagonal changes
    
    if (_selection->images().empty()) {
        ImageLibrary::IterAny first;
        ImageLibrary::IterAny last;
        {
            auto lock = std::unique_lock(*_imageLibrary);
            assert(!_imageLibrary->empty());
            
            const ImageLibrary::IterAny end = ImageLibrary::EndSorted(*_imageLibrary, [_imageGridLayer sortNewestFirst]);
            first = ImageLibrary::BeginSorted(*_imageLibrary, [_imageGridLayer sortNewestFirst]);
            last = std::prev(end);
        }
        
        if (delta.x>0 || delta.y>0) {
            _selection->images({ *first });
            _selectionHead = *first;
        } else {
            _selection->images({ *last });
            _selectionHead = *last;
        }
    
    } else {
        if (!_selectionHead) {
            ImageRecordPtr first = *_selection->images().begin();
            ImageRecordPtr last = *std::prev(_selection->images().end());
            
            if (delta.x>0 || delta.y>0) {
                _selectionHead = ([_imageGridLayer sortNewestFirst] ? first : last);
            } else {
                _selectionHead = ([_imageGridLayer sortNewestFirst] ? last : first);
            }
        }
        
        ImageSet selection;
        const ImageSet oldSelection = _selection->images();
        {
            auto lock = std::unique_lock(*_imageLibrary);
            
            ImageRecordIterAny begin = ImageLibrary::BeginSorted(*_imageLibrary, [_imageGridLayer sortNewestFirst]);
            ImageRecordIterAny end = ImageLibrary::EndSorted(*_imageLibrary, [_imageGridLayer sortNewestFirst]);
            ImageRecordIterAny newSelectionFirst = ImageLibrary::Find(begin, end, _selectionHead);
            assert(newSelectionFirst != end);
            
            const ssize_t deltaCountMin = -(newSelectionFirst-begin);
            const ssize_t deltaCountMax = end-newSelectionFirst-1;
            ssize_t deltaCount = delta.y*[_imageGridLayer columnCount] + delta.x;
            
            // Short circuit if the delta is trying to extend beyond the valid bounds
            if (deltaCount<deltaCountMin || deltaCount>deltaCountMax) {
                return;
            }
            
            ImageRecordIterAny newSelectionLast = newSelectionFirst+deltaCount;
            _selectionHead = *newSelectionLast;
            
            if (extend) {
                if (newSelectionFirst > newSelectionLast) {
                    std::swap(newSelectionFirst, newSelectionLast);
                }
                
                ImageSet newSelection(newSelectionFirst, newSelectionLast+1);
                const bool headWasSelected = (oldSelection.find(_selectionHead) != oldSelection.end());
                if (headWasSelected) {
                    selection = ImageSetsSubtract(oldSelection, newSelection);
                } else {
                    selection = ImageSetsUnion(oldSelection, newSelection);
                }
                
                selection.insert(_selectionHead);
            
            } else {
                selection = { *newSelectionLast };
            }
        }
        
        _selection->images(selection);
    }
    
    std::optional<CGRect> rect = [_imageGridLayer rectForImageRecord:_selectionHead];
    if (rect) [self scrollToImageRect:*rect center:false];
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

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
    
    NSView* superview = [self superview];
    const CGPoint mouseDownPoint = [superview convertPoint:[mouseDownEvent locationInWindow] fromView:nil];
    const CGRect rect = {mouseDownPoint, {}};
    const ImageSet newSelection = [_imageGridLayer imagesForRect:rect];
    const ImageRecordPtr mouseDownImage = (!newSelection.empty() ? *newSelection.begin() : ImageRecordPtr{});
    const NSEventModifierFlags mouseDownFlags = [mouseDownEvent modifierFlags];
    const ImageSet mouseDownSelection = _selection->images();
    
    const bool mouseDownInUnselectedImage = !mouseDownImage ||
        mouseDownSelection.find(mouseDownImage) == mouseDownSelection.end();
    if (mouseDownInUnselectedImage) {
        _selection->images(std::move(newSelection));
    }
    
    NSWindow* win = [self window];
    bool drag = false;
    Toastbox::TrackMouse(win, mouseDownEvent, [&] (NSEvent* event, bool done) {
        constexpr CGFloat DragThreshold = 5;
        const CGPoint point = [superview convertPoint:[event locationInWindow] fromView:nil];
        const CGFloat dist = std::hypot(point.x-mouseDownPoint.x, point.y-mouseDownPoint.y);
        drag |= dist >= DragThreshold;
        
        const CGRect rect = CGRectStandardize({ point,
            { mouseDownPoint.x-point.x, mouseDownPoint.y-point.y } });
        const ImageSet newSelection = [_imageGridLayer imagesForRect:rect];
        
        bool updateSelectionRect = false;
        if (mouseDownFlags & NSEventModifierFlagShift) {
            ImageSet selection;
            {
                auto lock = std::unique_lock(*_imageLibrary);
                std::set<ImageLibrary::RecordRefConstIter> iters;
                if (!newSelection.empty()) {
                    iters.insert(_imageLibrary->find(*newSelection.begin()));
                    iters.insert(_imageLibrary->find(*std::prev(newSelection.end())));
                }
                
                if (!mouseDownSelection.empty()) {
                    iters.insert(_imageLibrary->find(*mouseDownSelection.begin()));
                    iters.insert(_imageLibrary->find(*std::prev(mouseDownSelection.end())));
                }
                
                if (!iters.empty()) {
                    auto begin = *iters.begin();
                    auto last = *std::prev(iters.end());
                    auto end = std::next(last);
                    selection = ImageSet(begin, end);
                }
            }
            
            _selection->images(selection);
            updateSelectionRect = true;
            
        } else if (mouseDownFlags & NSEventModifierFlagCommand) {
            _selection->images(ImageSetsXOR(mouseDownSelection, newSelection));
            updateSelectionRect = true;
        
        } else {
            if (drag) {
                if (mouseDownImage) {
                    ImageExportProgressDialog* progress =
                        [[ImageExportProgressDialog alloc] initWithParentWindow:[self window] imageCount:_selection->images().size()];
                    
                    _drag.images = [NSMutableArray new];
                    for (auto it=_selection->images().rbegin(); it!=_selection->images().rend(); it++) {
                        ImageRecordPtr rec = *it;
                        std::optional<CGRect> rect = [self rectForImageRecord:rec];
                        assert(rect);
                        
                        CGRect draggingRect = [self convertRect:*rect fromView:superview];
                        
                        DragImage* image = [[DragImage alloc] initWithImageSource:_imageSource
                            imageRecord:rec progressDialog:progress draggingFrame:draggingRect];
                        [_drag.images addObject:image];
                    }
                    
                    _drag.session = [self beginDraggingSessionWithItems:_drag.images event:event source:self];
                    [_drag.session setDraggingFormation:NSDraggingFormationPile];
                    
                    // Stop tracking mouse; this is apparently necessary becuase recursive mouse
                    // tracking isn't compatible with -beginDraggingSessionWithItems:.
                    return false;
                    
                } else {
                    updateSelectionRect = true;
                    _selection->images(std::move(newSelection));
                    [self autoscroll:event];
                }
            }
        }
        
        if (updateSelectionRect) {
            [_selectionRectLayer setHidden:false];
            [_selectionRectLayer setFrame:[self convertRect:rect fromView:superview]];
        }
        
        if (done) {
            _selectionHead = {};
            [_selectionRectLayer setHidden:true];
            if ([event clickCount] == 2) {
                [[self window] tryToPerform:@selector(_showImage:) with:self];
            }
        }
        
        return true;
    });
}

- (void)rightMouseDown:(NSEvent*)event {
    NSView* superview = [self superview];
    const CGRect rect = {
        [superview convertPoint:[event locationInWindow] fromView:nil],
        {},
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
    const bool extend = [[[self window] currentEvent] modifierFlags] & NSEventModifierFlagShift;
    [self _moveSelection:{0,1} extend:extend];
}

- (void)moveUp:(id)sender {
    const bool extend = [[[self window] currentEvent] modifierFlags] & NSEventModifierFlagShift;
    [self _moveSelection:{0,-1} extend:extend];
}

- (void)moveLeft:(id)sender {
    const bool extend = [[[self window] currentEvent] modifierFlags] & NSEventModifierFlagShift;
    [self _moveSelection:{-1,0} extend:extend];
}

- (void)moveRight:(id)sender {
    const bool extend = [[[self window] currentEvent] modifierFlags] & NSEventModifierFlagShift;
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

//- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent*)event {
//    return [event type] == NSEventTypeLeftMouseDown;
//}



//- (BOOL)acceptsFirstResponder {
//    NSLog(@"%@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
//    return true;
//}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
//    NSLog(@"%@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return true;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent*)event {
//    NSLog(@"%@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
//    return [event type] == NSEventTypeLeftMouseDown;
    return true;
}




// MARK: - Drag & Drop

- (NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    
    switch(context) {
    case NSDraggingContextOutsideApplication:   return NSDragOperationCopy;
    case NSDraggingContextWithinApplication:
    default:                                    return NSDragOperationNone;
    }
}

- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint {
    NSLog(@"%@", NSStringFromSelector(_cmd));
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    NSLog(@"%@", NSStringFromSelector(_cmd));
    // We can't clear _drag here because it's apparently the only thing that holds
    // on to the DragImage instances. If we clear _drag here, the DragImage instances
    // get destroyed and the drag-and-drop doesn't finish.
//    _drag = {};
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

// MARK: - Magnification

static CGFloat _NextMagnification(CGFloat min, CGFloat max, int direction, CGFloat mag) {
    // Thresh: if `mag` is within this threshold of the next magnification, we'll skip to the next-next magnification
    constexpr CGFloat Thresh = 0.25;
    if (direction > 0) {
        mag = std::pow(2, std::floor((std::ceil(std::log2(mag)/Thresh)*Thresh)+1));
    } else {
        mag = std::pow(2, std::ceil((std::floor(std::log2(mag)/Thresh)*Thresh)-1));
    }
    mag = std::clamp(mag, min, max);
    return mag;
}

- (ImageRecordPtr)_scrollAnchor {
    NSView* superview = [self superview];
    const CGRect rect = [superview convertRect:[self bounds] fromView:self];
    const ImageSet images = [_imageGridLayer imagesForRect:rect];
    if (!images.empty()) {
        size_t count = images.size()/2;
        auto it = images.begin();
        while (count--) it++;
        return *it;
    }
    return {};
}

- (void)_scrollToAnchor:(ImageRecordPtr)anchor {
    assert(anchor);
    std::optional<CGRect> rect = [_imageGridLayer rectForImageRecord:anchor];
    if (rect) [self scrollToImageRect:*rect center:true];
}

- (void)_setMagnification:(CGFloat)mag anchor:(ImageRecordPtr)anchor {
    const bool changed = [_imageGridLayer setMagnification:mag];
    if (changed) {
        [self _updateDocumentHeight];
        [[self window] layoutIfNeeded];
        if (anchor) [self _scrollToAnchor:anchor];
    }
}

- (void)magnifyIncrease:(id)sender {
    const CGFloat mag = _NextMagnification([_imageGridLayer magnificationMin],
        [_imageGridLayer magnificationMax], +1, [_imageGridLayer magnification]);
    [self _setMagnification:mag anchor:[self _scrollAnchor]];
}

- (void)magnifyDecrease:(id)sender {
    const CGFloat mag = _NextMagnification([_imageGridLayer magnificationMin],
        [_imageGridLayer magnificationMax], -1, [_imageGridLayer magnification]);
    [self _setMagnification:mag anchor:[self _scrollAnchor]];
}

- (void)magnifyWithEvent:(NSEvent*)event {
    if ([event phase] == NSEventPhaseBegan) {
        _mag = {
            .amount = [_imageGridLayer magnification],
            .anchor = [self _scrollAnchor],
        };
    }
    
    _mag.amount = std::clamp(_mag.amount+[event magnification],
        [_imageGridLayer magnificationMin], [_imageGridLayer magnificationMax]);
    [self _setMagnification:_mag.amount anchor:_mag.anchor];
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

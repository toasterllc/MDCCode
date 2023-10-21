#import "ImageGridView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
#import "FixedMetalDocumentLayer.h"
#import "ImageGridLayerTypes.h"
#import "Util.h"
#import "Grid.h"
#import "DeviceImageGridHeaderView/DeviceImageGridHeaderView.h"
#import "Code/Shared/Img.h"
#import "ImageExporter/ImageExporter.h"
#import "Toastbox/LRU.h"
#import "Toastbox/IterAny.h"
#import "Toastbox/Signal.h"
#import "Toastbox/Mac/Util.h"
using namespace MDCStudio;

static constexpr auto _ThumbWidth = ImageThumb::ThumbWidth;
static constexpr auto _ThumbHeight = ImageThumb::ThumbHeight;

// _PixelFormat == _sRGB with -setColorspace:SRGB appears to be the correct combination
// such that we supply color data in the linear SRGB colorspace and the system handles
// conversion into SRGB.
// (Without calling -setColorspace:, CAMetalLayers don't perform color matching!)
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

@interface ImageGridLayer : FixedMetalDocumentLayer

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;
- (size_t)columnCount;
- (void)updateGridElementCount;

- (ImageSet)imagesForRect:(CGRect)rect;
//- (CGRect)rectForImageAtIndex:(size_t)idx;

- (const ImageSet&)selection;
- (void)setSelection:(ImageSet)selection;

@end

struct _ChunkTexture {
    static constexpr size_t SliceCount = ImageLibrary::ChunkRecordCap;
    id<MTLTexture> txt = nil;
    uint32_t loadCounts[SliceCount] = {};
};

static constexpr size_t _ChunkTexturesCacheCapacity = 4;
using _ChunkTextures = Toastbox::LRU<ImageLibrary::ChunkStrongRef,_ChunkTexture,_ChunkTexturesCacheCapacity>;

struct _ThumbRenderThreadState {
    Toastbox::Signal signal; // Protects this struct
    ImageSourcePtr imageSource;
    std::set<ImageRecordPtr> recs;
};

// MARK: - ImageGridLayer

@implementation ImageGridLayer {
    ImageSourcePtr _imageSource;
    ImageLibraryPtr _imageLibrary;
    Object::ObserverPtr _imageLibraryOb;
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
    std::shared_ptr<_ThumbRenderThreadState> _thumbRender;
    
    struct {
        ImageSet images;
        size_t base = 0;
        size_t count = 0;
        id<MTLBuffer> buf;
    } _selection;
}

static CGColorSpaceRef _SRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return cs;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    NSParameterAssert(imageSource);
    
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    _imageLibrary = imageSource->imageLibrary();
    // Add ourself as an observer of the image library
    {
        __weak auto selfWeak = self;
        _imageLibraryOb = _imageLibrary->observerAdd([=] (auto, const Object::Event& ev) {
            [selfWeak _handleImageLibraryEvent:dynamic_cast<const ImageLibrary::Event&>(ev)];
        });
    }
    
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
    [self setColorspace:_SRGBColorSpace()]; // See comment for _PixelFormat
    
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
    
    // Start our _ThumbRenderThread
    auto thumbRender = std::make_shared<_ThumbRenderThreadState>();
    thumbRender->imageSource = _imageSource;
    std::thread([=] { _ThumbRenderThread(*thumbRender); }).detach();
    _thumbRender = thumbRender;
    
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
    // Signal our thread to exit
    _thumbRender->signal.stop();
}

- (Grid&)grid {
    return _grid;
}

- (void)setContainerWidth:(CGFloat)x {
//    NSLog(@"-[ImageGridLayer setContainerWidth:]");
    _containerWidth = x*[self contentsScale];
    _grid.setContainerWidth((int32_t)lround(_containerWidth));
}

- (CGFloat)containerHeight {
//    NSLog(@"-[ImageGridLayer containerHeight]");
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
    [desc setPixelFormat:MTLPixelFormatBC7_RGBAUnorm];
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
    if (!_selection.buf) {
        const auto itBegin = (!_selection.images.empty() ?
            _imageLibrary->find(*_selection.images.begin()) : _imageLibrary->end());
        const auto itLast = (!_selection.images.empty() ?
            _imageLibrary->find(*std::prev(_selection.images.end())) : _imageLibrary->end());
        const auto itEnd = (itLast!=_imageLibrary->end() ? std::next(itLast) : _imageLibrary->end());
        
        if (itBegin!=_imageLibrary->end() && itLast!=_imageLibrary->end()) {
            _selection.base = itBegin-_imageLibrary->begin();
            _selection.count = itEnd-itBegin;
            
            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
            _selection.buf = [_device newBufferWithLength:_selection.count options:BufOpts];
            bool* bools = (bool*)[_selection.buf contents];
            
            size_t i = 0;
            for (auto it=itBegin; it!=itEnd; it++) {
                if (_selection.images.find(*it) != _selection.images.end()) {
                    bools[i] = true;
                }
                i++;
            }
        
        } else {
            _selection.buf = [_device newBufferWithLength:1 options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModePrivate];
        }
        
        assert(_selection.buf);
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
        
        assert(_selection.base <= UINT32_MAX);
        assert(_selection.count <= UINT32_MAX);
        
        const ImageGridLayerTypes::RenderContext ctx = {
            .grid = _grid,
            .idx = (uint32_t)(chunkBegin-begin),
            .sortNewestFirst = _sortNewestFirst,
            .viewSize = {(float)viewSize.width, (float)viewSize.height},
            .transform = [self fixedTransform],
            .selection = {
                .base = (uint32_t)_selection.base,
                .count = (uint32_t)_selection.count,
            },
        };
        
        [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
        [renderEncoder setVertexBuffer:_selection.buf offset:0 atIndex:2];
        
        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setFragmentBytes:&ct.loadCounts length:sizeof(ct.loadCounts) atIndex:1];
        [renderEncoder setFragmentTexture:ct.txt atIndex:0];
        [renderEncoder setFragmentTexture:_placeholderTexture atIndex:1];
        
        const size_t chunkImageCount = chunkEnd-chunkBegin;
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:chunkImageCount];
        [renderEncoder endEncoding];
    }
    
    // Re-render the visible thumbnails that are marked dirty
    _ThumbRenderIfNeeded(*_thumbRender, { visibleBegin, visibleEnd });
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
//    [commandBuffer waitUntilCompleted]; // Necessary to prevent artifacts when resizing window
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

//- (CGRect)rectForImages:(ImageSet)images {
//    CGRect rect = {};
//    for (const ImageRecordPtr& rec : images) {
//        
//    }
//    return rect;
//}

//- (CGRect)rectForImageAtIndex:(size_t)idx {
//    return _CGRectFromGridRect(_grid.rectForCellIndex((int32_t)idx), [self contentsScale]);
//}

- (const ImageSet&)selection {
    return _selection.images;
}

- (void)setSelection:(ImageSet)images {
    // Remove images that aren't loaded
    // Ie, don't allow placeholder images to be selected
    for (auto it=images.begin(); it!=images.end();) {
        if (!(*it)->status.loadCount) {
            it = images.erase(it);
        } else {
            it++;
        }
    }
    
    // Set the entire _selection struct so that _display recreates the buffer
    _selection = { .images = std::move(images) };
    [self setNeedsDisplay];
}

- (void)setSortNewestFirst:(bool)x {
    _sortNewestFirst = x;
    // Trigger selection update (_selection buffer needs to be cleared)
    [self setSelection:std::move(_selection.images)];
}

struct SelectionDelta {
    int x = 0;
    int y = 0;
};

- (CGRect)rectForImageIndex:(size_t)idx {
    return _CGRectFromGridRect(_grid.rectForCellIndex((int32_t)idx), [self contentsScale]);
}

- (CGRect)rectForImageRecord:(ImageRecordPtr)rec {
    auto lock = std::unique_lock(*_imageLibrary);
    auto begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
    auto end = ImageLibrary::EndSorted(*_imageLibrary, _sortNewestFirst);
    const auto it = ImageLibrary::Find(begin, end, rec);
    if (it == end) return CGRectNull;
    const size_t idx = it-begin;
    return [self rectForImageIndex:idx];
}

- (std::optional<CGRect>)moveSelection:(SelectionDelta)delta extend:(bool)extend {
    ssize_t newIdx = 0;
    ImageRecordPtr newImg;
    ImageSet selection = _selection.images;
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
    [self setSelection:std::move(selection)];
    return [self rectForImageIndex:newIdx];
}

// MARK: - FixedScrollViewDocument
- (bool)fixedFlipped {
    return true;
}

// MARK: - Thumb Render

using _IterRange = std::pair<ImageRecordIterAny,ImageRecordIterAny>;

static Grid::IndexRange _VisibleIndexRange(Grid& grid, CGRect frame, CGFloat scale) {
    return grid.indexRangeForIndexRect(grid.indexRectForRect(_GridRectFromCGRect(frame, scale)));
}

static _IterRange _VisibleRange(const Grid::IndexRange& ir, const ImageLibrary& il, bool sortNewestFirst) {
    ImageRecordIterAny begin = ImageLibrary::BeginSorted(il, sortNewestFirst);
    const auto visibleBegin = begin+ir.start;
    const auto visibleEnd = begin+ir.start+ir.count;
    return std::make_pair(visibleBegin, visibleEnd);
}

static void _ThumbRenderIfNeeded(_ThumbRenderThreadState& thread, _IterRange range) {
    bool enqueued = false;
    {
        auto lock = thread.signal.lock();
        thread.recs.clear();
        for (auto it=range.first; it!=range.second; it++) {
            if ((*it)->options.thumb.render) {
                thread.recs.insert(*it);
                enqueued = true;
            }
        }
    }
    if (enqueued) thread.signal.signalOne();
}

static void _ThumbRenderThread(_ThumbRenderThreadState& state) {
    printf("[_ThumbRenderThread] Starting\n");
    try {
        for (;;) {
            std::set<ImageRecordPtr> recs;
            {
                auto lock = state.signal.wait([&] { return !state.recs.empty(); });
                recs = std::move(state.recs);
                // Update .thumb.render asap (ie before we've actually rendered) so that the
                // visibleThumbs() function on the main thread stops enqueuing work asap
                for (const ImageRecordPtr& rec : recs) {
                    rec->options.thumb.render = false;
                }
            }
            
            printf("[_ThumbRenderThread] Enqueueing %ju thumbnails for rendering\n", (uintmax_t)recs.size());
            state.imageSource->renderThumbs(ImageSource::Priority::High, recs);
            printf("[_ThumbRenderThread] Rendered %ju thumbnails\n", (uintmax_t)recs.size());
        }
    
    } catch (const Toastbox::Signal::Stop&) {
    }
    printf("[_ThumbRenderThread] Exiting\n");
}

// _imageLibrary must be locked!
- (void)_thumbRenderVisibleIfNeeded {
    const auto vir = _VisibleIndexRange(_grid, [self frame], [self contentsScale]);
    const auto vr = _VisibleRange(vir, *_imageLibrary, _sortNewestFirst);
    _ThumbRenderIfNeeded(*_thumbRender, vr);
}

//- (_IterRange)_visibleRange {
//    const Grid::IndexRange indexRange = _VisibleIndexRange(_grid, [self frame], [self contentsScale]);
//    ImageRecordIterAny begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
//    const auto visibleBegin = begin+indexRange.start;
//    const auto visibleEnd = begin+indexRange.start+indexRange.count;
//    return std::make_pair(visibleBegin, visibleEnd);
//}
//
//- (_IterRange)_visibleRange {
//    const CGRect frame = [self frame];
//    const CGFloat contentsScale = [self contentsScale];
//    const Grid::IndexRange indexRange = _grid.indexRangeForIndexRect(_grid.indexRectForRect(_GridRectFromCGRect(frame, contentsScale)));
//    ImageRecordIterAny begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
//    const auto visibleBegin = begin+indexRange.start;
//    const auto visibleEnd = begin+indexRange.start+indexRange.count;
//    return std::make_pair(visibleBegin, visibleEnd);
//}
//
//- (void)_updateVisibleThumbs {
//    bool enqueued = false;
//    {
////        auto lock = _thumbRender->signal.lock();
////        _thumbRender->recs.clear();
////        for (auto it=begin; it!=end; it++) {
////            ImageRecordPtr rec = *it;
////            if (rec->options.thumb.render) {
////                _thumbRender->recs.insert(rec);
////                enqueued = true;
////            }
////        }
//    }
//    if (enqueued) _thumbRender->signal.signalOne();
//}

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
        [self setNeedsDisplay];
        break;
    case ImageLibrary::Event::Type::Remove:
        [self setNeedsDisplay];
        break;
    case ImageLibrary::Event::Type::ChangeProperty:
        if ([self _recordsIntersectVisibleRange:ev.records]) {
            // Re-render visible thumbs that are dirty
            // We don't check if any of `ev` intersect the visible range, because _thumbRenderVisibleIfNeeded
            // should be cheap and reduces to a no-op if none of the visible thumbs are dirty.
            [self _thumbRenderVisibleIfNeeded];
        }
        break;
    case ImageLibrary::Event::Type::ChangeThumbnail:
        if ([self _recordsIntersectVisibleRange:ev.records]) {
            [self setNeedsDisplay];
        }
        break;
    }
}


// _imageLibrary must be locked!
- (bool)_recordsIntersectVisibleRange:(const std::set<ImageRecordPtr>&)changed {
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
    Object::ObserverPtr _imageLibraryOb;
    __weak id<ImageGridViewDelegate> _delegate;
    NSLayoutConstraint* _docHeight;
//    id _widthChangedObserver;
}

// MARK: - Creation

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    // Create ImageGridLayer
    ImageGridLayer* imageGridLayer = [[ImageGridLayer alloc] initWithImageSource:imageSource];
    
    if (!(self = [super initWithFixedLayer:imageGridLayer])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _imageSource = imageSource;
    _imageGridLayer = imageGridLayer;
    [self _handleImageLibraryChanged];
    
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
    
    // Observe image library changes so that we update the image grid
    {
        __weak auto selfWeak = self;
        _imageLibraryOb = _imageSource->imageLibrary()->observerAdd([=] (auto, const Object::Event& ev) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _handleImageLibraryChanged]; });
        });
    }
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSColor* c = [[self enclosingScrollView] backgroundColor];
////        NSColor* c = [[self window] backgroundColor];
//        NSColor* c2 = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
//        NSLog(@"backgroundColor: %f %f %f", [c2 redComponent], [c2 greenComponent], [c2 blueComponent]);
//    }];
    
    // Create our context menu
    {
        NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
        [menu addItemWithTitle:@"Export…" action:@selector(_export:) keyEquivalent:@""];
        [self setMenu:menu];
    }
    
    return self;
}

- (void)dealloc {
    printf("~ImageGridView\n");
}

- (void)setDelegate:(id<ImageGridViewDelegate>)delegate {
    _delegate = delegate;
}

- (ImageSourcePtr)imageSource {
    return _imageSource;
}

- (const ImageSet&)selection {
    return [_imageGridLayer selection];
}

- (void)setSelection:(MDCStudio::ImageSet)selection {
    [self _setSelection:std::move(selection) notify:false];
}

- (void)_setSelection:(ImageSet)selection notify:(bool)notify {
    [_imageGridLayer setSelection:std::move(selection)];
    if (notify) [_delegate imageGridViewSelectionChanged:self];
}

- (void)setSortNewestFirst:(bool)x {
    [_imageGridLayer setSortNewestFirst:x];
}

- (CGRect)rectForImageIndex:(size_t)idx {
    return [_imageGridLayer rectForImageIndex:idx];
}

- (CGRect)rectForImageRecord:(ImageRecordPtr)rec {
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
    [_delegate imageGridViewSelectionChanged:self];
}

- (void)_updateDocumentHeight {
    [_imageGridLayer setContainerWidth:[[self enclosingScrollView] bounds].size.width];
    [_imageGridLayer updateGridElementCount];
    [_docHeight setConstant:[_imageGridLayer containerHeight]];
}

- (void)_handleImageLibraryChanged {
    [[self enclosingScrollView] tile];
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
//    const CGPoint startPoint = [self convertPointToFixedDocument:[mouseDownEvent locationInWindow] fromView:nil];
    [_selectionRectLayer setHidden:false];
    
    const bool extend = [[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    const ImageSet oldSelection = [_imageGridLayer selection];
    Toastbox::TrackMouse(win, mouseDownEvent, [=] (NSEvent* event, bool done) {
//        const CGPoint curPoint = _ConvertPoint(_imageGridLayer, _documentView, [_documentView convertPoint:[event locationInWindow] fromView:nil]);
        const CGPoint curPoint = [superview convertPoint:[event locationInWindow] fromView:nil];
        const CGRect rect = CGRectStandardize(CGRect{startPoint.x, startPoint.y, curPoint.x-startPoint.x, curPoint.y-startPoint.y});
        ImageSet newSelection = [_imageGridLayer imagesForRect:rect];
        if (extend) {
            [self _setSelection:ImageSetsXOR(oldSelection, newSelection) notify:true];
        } else {
            [self _setSelection:std::move(newSelection) notify:true];
        }
        [_selectionRectLayer setFrame:[self convertRect:rect fromView:superview]];
        
        [self autoscroll:event];
//        NSLog(@"mouseDown:");
    });
    [_selectionRectLayer setHidden:true];
}

- (void)mouseUp:(NSEvent*)event {
    if ([event clickCount] == 2) {
        [_delegate imageGridViewOpenSelectedImage:self];
    }
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
        ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
        auto lock = std::unique_lock(*imageLibrary);
        for (auto it=imageLibrary->begin(); it!=imageLibrary->end(); it++) {
            selection.insert(*it);
        }
    }
    [self _setSelection:selection notify:true];
}

- (void)insertNewline:(id)sender {
    if ([self selection].size() == 1) {
        [_delegate imageGridViewOpenSelectedImage:self];
    }
}

- (void)keyDown:(NSEvent*)event {
    NSString* lf = @"\n";
    NSString* cr = @"\r";
    // -[NSResponder insertNewline:] doesn't get called when pressing return, so we manually trigger it
    if ([[event charactersIgnoringModifiers] isEqualToString:lf] ||
        [[event charactersIgnoringModifiers] isEqualToString:cr]) {
        return [self insertNewline:nil];
    }
    return [super keyDown:event];
}

- (void)fixedCreateConstraintsForContainer:(NSView*)container {
    NSView*const containerSuperview = [container superview];
    if (!containerSuperview) return;
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[container]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(container)]];
    
    NSLayoutConstraint* docHeightMin = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:containerSuperview attribute:NSLayoutAttributeHeight
        multiplier:1 constant:0];
    [docHeightMin setActive:true];
    
    _docHeight = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:1 constant:0];
    [_docHeight setActive:true];
}

// MARK: - Menu Actions

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if ([item action] == @selector(_export:)) {
        const size_t selectionCount = [self selection].size();
        NSString* title = nil;
        if (selectionCount > 1) {
            title = [NSString stringWithFormat:@"Export %ju Photos…", (uintmax_t)selectionCount];
        } else if (selectionCount == 1) {
            title = @"Export 1 Photo…";
        } else {
            title = @"Export…";
        }
        [item setTitle:title];
        return (bool)selectionCount;
    }
    return [super validateMenuItem:item];
}

- (IBAction)_export:(id)sender {
    printf("_export\n");
    ImageExporter::Export([self window], _imageSource, [self selection]);
}

@end


// MARK: - ImageGridScrollView

@implementation ImageGridScrollView {
    NSView* _headerView;
}

- (instancetype)initWithFixedDocument:(NSView<FixedScrollViewDocument>*)doc {
    if (!(self = [super initWithFixedDocument:doc])) return nil;
    [self setAllowsMagnification:false];
    // FixedScrollView's anchoring during resize doesn't work with our document because the document
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

- (void)tile {
    [super tile];
    ImageGridView*const gridView = (ImageGridView*)[self document];
    [gridView _updateDocumentHeight];
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if ([item action] == @selector(magnifyToActualSize:)) {
        return false;
    } else if ([item action] == @selector(magnifyToFit:)) {
        return false;
    } else if ([item action] == @selector(magnifyIncrease:)) {
        return false;
    } else if ([item action] == @selector(magnifyDecrease:)) {
        return false;
    }
    return [super validateMenuItem:item];
}

//- (BOOL)acceptsFirstResponder {
//    return true;
//}

//- (NSView*)initialFirstResponder {
//    return [self document];
//}

@end

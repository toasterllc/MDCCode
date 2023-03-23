#import "ImageGridView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "FixedMetalDocumentLayer.h"
#import "ImageGridLayerTypes.h"
#import "Util.h"
#import "Grid.h"
#import "Code/Shared/Img.h"
#import "Toastbox/LRU.h"
#import "Toastbox/IterAny.h"
#import "Toastbox/Signal.h"
#import "Toastbox/Mac/Util.h"
using namespace MDCStudio;

static constexpr auto _ThumbWidth = ImageThumb::ThumbWidth;
static constexpr auto _ThumbHeight = ImageThumb::ThumbHeight;

// _PixelFormat: Our pixels are in the linear RGB space (LSRGB), and need conversion to the display color space.
// To do so, we declare that our pixels are LSRGB (ie we _don't_ use the _sRGB MTLPixelFormat variant!),
// and we opt-in to color matching by setting the colorspace on our CAMetalLayer via -setColorspace:.
// (Without calling -setColorspace:, CAMetalLayers don't perform color matching!)
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm;

@interface ImageGridLayer : FixedMetalDocumentLayer

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;
- (size_t)columnCount;
- (void)recomputeGrid;

- (ImageSet)imagesForRect:(CGRect)rect;
//- (CGRect)rectForImageAtIndex:(size_t)idx;

- (const ImageSet&)selection;
- (void)setSelection:(ImageSet)selection;

@end

struct _ChunkTexture {
    static constexpr size_t SliceCount = ImageLibrary::ChunkRecordCap;
    id<MTLTexture> txt = nil;
    bool loaded[SliceCount] = {};
};

static constexpr size_t _ChunkTexturesCacheCapacity = 4;
using _ChunkTextures = Toastbox::LRU<ImageLibrary::ChunkStrongRef,_ChunkTexture,_ChunkTexturesCacheCapacity>;

struct _ThumbRenderThreadState {
    Toastbox::Signal signal; // Protects this struct
    ImageSourcePtr imageSource;
    ImageSource::LoadImagesState loadImages;
    std::set<ImageRecordPtr> recs;
};

@implementation ImageGridLayer {
    ImageSourcePtr _imageSource;
    ImageLibrary* _imageLibrary;
    uint32_t _cellWidth;
    uint32_t _cellHeight;
    Grid _grid;
    bool _sortNewestFirst;
    
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

static CGColorSpaceRef _LSRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    return cs;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    NSParameterAssert(imageSource);
    
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    _imageLibrary = &imageSource->imageLibrary();
    
    _cellWidth = _ThumbWidth;
    _cellHeight = _ThumbHeight;
    
    _grid.setBorderSize({
        .left   = 6,//(int32_t)_cellWidth/5,
        .right  = 6,//(int32_t)_cellWidth/5,
        .top    = 6,//(int32_t)_cellHeight/5,
        .bottom = 6,//(int32_t)_cellHeight/5,
    });
    
    _grid.setCellSize({(int32_t)_cellWidth, (int32_t)_cellHeight});
    _grid.setCellSpacing({6, 6});
//    _grid.setCellSpacing({(int32_t)_cellWidth/10, (int32_t)_cellHeight/10});
    
    _sortNewestFirst = true;
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    [self setColorspace:_LSRGBColorSpace()]; // See comment for _PixelFormat
    
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
    
    // Add ourself as an observer of the image library
    {
        auto lock = std::unique_lock(*_imageLibrary);
        __weak auto selfWeak = self;
        _imageLibrary->observerAdd([=](const ImageLibrary::Event& ev) {
            auto selfStrong = selfWeak;
            if (!selfStrong) return false;
            [selfStrong _handleImageLibraryEvent:ev];
            return true;
        });
    }
    
    // Start our _ThumbRenderThread
    _thumbRender = std::make_shared<_ThumbRenderThreadState>();
    _thumbRender->imageSource = _imageSource;
    std::thread([=] { _ThumbRenderThread(*_thumbRender); }).detach();
    
    return self;
}

- (void)dealloc {
    // Signal our thread to exit
    _thumbRender->signal.stop();
}

- (Grid&)grid {
    return _grid;
}

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

static void _ChunkTextureUpdateSlice(_ChunkTexture& ct, const ImageLibrary::RecordRef& ref) {
    const bool loaded = ref->info.flags & ImageFlags::Loaded;
    if (loaded) {
//        printf("Update slice\n");
        const uint8_t* b = ref.chunk->mmap.data() + ref.idx*sizeof(ImageRecord) + offsetof(ImageRecord, thumb.data);
        [ct.txt replaceRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0
            slice:ref.idx withBytes:b bytesPerRow:ImageThumb::ThumbWidth*4 bytesPerImage:0];
    }
    
    ct.loaded[ref.idx] = loaded;
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
    for (auto it=chunkBegin; it!=chunkEnd; it++) {
        _ChunkTextureUpdateSlice(ct, *it);
    }
    
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
    
    const ImageRecordIterAny begin = ImageLibrary::BeginSorted(*_imageLibrary, _sortNewestFirst);
    const ImageRecordIterAny end = ImageLibrary::EndSorted(*_imageLibrary, _sortNewestFirst);
    const auto [visibleBegin, visibleEnd] = _VisibleRange(visibleIndexRange, *_imageLibrary, _sortNewestFirst);
    
    for (auto it=visibleBegin; it!=visibleEnd;) {
        const auto nextChunkStart = ImageLibrary::FindChunkEnd(end, it);
        const auto chunkImageRefBegin = it;
        const auto chunkImageRefEnd = std::min(visibleEnd, nextChunkStart);
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        
        assert(_selection.base <= UINT32_MAX);
        assert(_selection.count <= UINT32_MAX);
        
        const ImageGridLayerTypes::RenderContext ctx = {
            .grid = _grid,
            .idx = (uint32_t)(chunkImageRefBegin-begin),
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
        
        _ChunkTexture& ct = [self _getChunkTexture:it];
        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setFragmentBytes:&ct.loaded length:sizeof(ct.loaded) atIndex:1];
        [renderEncoder setFragmentTexture:ct.txt atIndex:0];
        [renderEncoder setFragmentTexture:_placeholderTexture atIndex:1];
        
        const size_t chunkImageCount = chunkImageRefEnd-chunkImageRefBegin;
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:chunkImageCount];
        [renderEncoder endEncoding];
        
        it = chunkImageRefEnd;
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
//        [[renderPassDescriptor colorAttachments][0] setClearColor:{0, 0, 0, 1}];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{WindowBackgroundColor.lsrgb[0], WindowBackgroundColor.lsrgb[1], WindowBackgroundColor.lsrgb[2], 1}];
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
    // Trigger buffer regeneration
    _selection = {
        .images = std::move(images),
    };
    [self setNeedsDisplay];
}

- (void)setSortNewestFirst:(bool)x {
    _sortNewestFirst = x;
    // Trigger selection update
    [self setSelection:std::move(_selection.images)];
    [self setNeedsDisplay];
}

struct SelectionDelta {
    int x = 0;
    int y = 0;
};

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
    return _CGRectFromGridRect(_grid.rectForCellIndex((int32_t)newIdx), [self contentsScale]);
}

// MARK: - FixedScrollViewDocument
- (bool)fixedFlipped {
    return true;
}



//// MARK: - ImageLibrary Observer
//// _handleImageLibraryEvent: called on whatever thread where the modification happened,
//// and with the ImageLibraryPtr lock held!
//- (void)_handleImageLibraryEvent:(const ImageLibrary::Event&)ev {
//    // Trampoline the event to our main thread, if we're not on the main thread
//    if ([NSThread isMainThread]) {
//        ImageLibrary::Event evCopy = ev;
//        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
//            [self _handleImageLibraryEvent:evCopy];
//        });
//        return;
//    }
//    
//    if (ev.type == ImageLibrary::Event::Type::Change) {
//        // Erase textures for any of the changed records
//        for (const ImageRecordPtr& rec : ev.records) {
//            auto it = _chunkTxts.get(rec);
//            if (it == _chunkTxts.end()) continue;
//            id<MTLTexture> txt = it->val;
//            _ChunkTextureUpdateSlice(txt, rec);
//        }
//    }
//    
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [self setNeedsDisplay];
//    });
//}



// MARK: - Thumb Render

using _IterRange = std::pair<ImageRecordIterAny,ImageRecordIterAny>;

static Grid::IndexRange _VisibleIndexRange(const Grid& grid, CGRect frame, CGFloat scale) {
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
            
            state.imageSource->loadImages(state.loadImages, ImageSource::Priority::High, recs);
            printf("[_ThumbRenderThread] Rendered %ju thumbnails\n", (uintmax_t)recs.size());
        }
    
    } catch (const Toastbox::Signal::Stop&) {
        printf("[_ThumbRenderThread] Stopping\n");
    }
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
            [self __handleImageLibraryEvent:evCopy];
        });
        return;
    }
    
    [self __handleImageLibraryEvent:ev];
    
    
//    switch (ev.type) {
//    
//    }
//    
//    if (ev.type == ImageLibrary::Event::Type::Add) {
//        [self setNeedsDisplay];
//    
//    } else if (ev.type == ImageLibrary::Event::Type::ChangeProperty) {
////        // Re-render the visible thumbnails that are marked dirty
////        _imageSource->visibleThumbs(visibleBegin, visibleEnd);
//    } else {
//        
//    }
    
//    // If we added records or changed records, we need to update the relevent textures
//    if (ev.type==ImageLibrary::Event::Type::Add || ev.type==ImageLibrary::Event::Type::Change) {
//        for (const ImageRecordPtr& rec : ev.records) {
//            if (auto find=_chunkTxts.find(rec); find!=_chunkTxts.end()) {
////                printf("Update slice\n");
////                _chunkTxts.erase(find);
//                _ChunkTexture& ct = find->val;
//                _ChunkTextureUpdateSlice(ct, rec);
//            }
//        }
//    }
//    
//    [self setNeedsDisplay];
}


// _imageLibrary must be locked!
- (bool)_recordsIntersectVisibleRange:(const std::set<ImageRecordPtr>&)changed {
    if (changed.empty()) return false;
    const auto visibleRange = _VisibleRange(_VisibleIndexRange(_grid, [self frame], [self contentsScale]), *_imageLibrary, _sortNewestFirst);
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


// _imageLibrary must be locked!
- (void)__handleImageLibraryEvent:(const ImageLibrary::Event&)ev {
    assert([NSThread isMainThread]);
    
    switch (ev.type) {
    case ImageLibrary::Event::Type::Add:
        [self setNeedsDisplay];
        break;
    case ImageLibrary::Event::Type::Remove:
        [self setNeedsDisplay];
        break;
    case ImageLibrary::Event::Type::ChangeProperty:
        if ([self _recordsIntersectVisibleRange:ev.records]) {
            printf("_recordsIntersectVisibleRange: YES\n");
            // Re-render visible thumbs that are dirty
            // We don't check if any of `ev` intersect the visible range, because _thumbRenderVisibleIfNeeded
            // should be cheap and reduces to a no-op if none of the visible thumbs are dirty.
            [self _thumbRenderVisibleIfNeeded];
        } else {
            printf("_recordsIntersectVisibleRange: NO\n");
        }
        break;
    case ImageLibrary::Event::Type::ChangeThumbnail:
        if ([self _recordsIntersectVisibleRange:ev.records]) {
            printf("_recordsIntersectVisibleRange: YES\n");
            [self setNeedsDisplay];
        } else {
            printf("_recordsIntersectVisibleRange: NO\n");
        }
//        if (!ev.records.empty() && [self _meowmix:{ev.records.begin(),}])
//        if ([self _meowmix:{}])
//        for (const ImageRecordPtr& rec : ev.records) {
//            if (auto find=_chunkTxts.find(rec); find!=_chunkTxts.end()) {
////                printf("Update slice\n");
////                _chunkTxts.erase(find);
//                _ChunkTexture& ct = find->val;
//                _ChunkTextureUpdateSlice(ct, rec);
//            }
//        }
//        
//        
//        #warning TODO: only display if a changed thumbnail is visible
//        [self setNeedsDisplay];
        break;
    }
}

@end





















@implementation ImageGridView {
    ImageGridLayer* _imageGridLayer;
    CALayer* _selectionRectLayer;
    ImageSourcePtr _imageSource;
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
        ImageLibrary& imageLibrary = _imageSource->imageLibrary();
        auto lock = std::unique_lock(imageLibrary);
        imageLibrary.observerAdd([=] (const ImageLibrary::Event& ev) {
            auto selfStrong = selfWeak;
            if (!selfStrong) return false;
            dispatch_async(dispatch_get_main_queue(), ^{ [selfStrong _handleImageLibraryChanged]; });
            return true;
        });
    }
    
    return self;
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

- (void)setSortNewestFirst:(bool)x {
    [_imageGridLayer setSortNewestFirst:x];
}

- (void)_setSelection:(ImageSet)selection {
    [_imageGridLayer setSelection:std::move(selection)];
    [_delegate imageGridViewSelectionChanged:self];
}

- (void)_moveSelection:(SelectionDelta)delta extend:(bool)extend {
    std::optional<CGRect> rect = [_imageGridLayer moveSelection:delta extend:extend];
    if (!rect) return;
    [self scrollRectToVisible:[self convertRect:*rect fromView:[self superview]]];
    [_delegate imageGridViewSelectionChanged:self];
}

- (void)_updateDocumentHeight {
    [_imageGridLayer setContainerWidth:[self bounds].size.width];
    [_imageGridLayer recomputeGrid];
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
            [self _setSelection:ImageSetsXOR(oldSelection, newSelection)];
        } else {
            [self _setSelection:std::move(newSelection)];
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
        ImageLibrary& imgLib = _imageSource->imageLibrary();
        auto lock = std::unique_lock(imgLib);
        for (auto it=imgLib.begin(); it!=imgLib.end(); it++) {
            selection.insert(*it);
        }
    }
    [self _setSelection:selection];
}

- (void)fixedCreateConstraintsForContainer:(NSView*)container {
    NSView*const containerSuperview = [container superview];
    if (!containerSuperview) return;
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[container]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(container)]];
    
    NSLayoutConstraint* docHeightMin = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:containerSuperview attribute:NSLayoutAttributeHeight
        multiplier:1 constant:0];
    
    _docHeight = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:1 constant:0];
    [NSLayoutConstraint activateConstraints:@[docHeightMin, _docHeight]];
}

@end


@implementation ImageGridScrollView

- (instancetype)initWithFixedDocument:(NSView<FixedScrollViewDocument>*)doc {
    if (!(self = [super initWithFixedDocument:doc])) return nil;
    [self setAllowsMagnification:false];
    // FixedScrollView's anchoring during resize doesn't work with our document because the document
    // resizes when its superviews resize (because its width needs to be the same as its superviews).
    // So disable that behavior.
    [self setAnchorDuringResize:false];
    return self;
}

- (void)tile {
    [super tile];
    ImageGridView*const gridView = (ImageGridView*)[self document];
    [gridView _updateDocumentHeight];
}

//- (NSView*)initialFirstResponder {
//    return [self document];
//}

@end

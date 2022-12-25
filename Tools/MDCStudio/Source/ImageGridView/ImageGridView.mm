#import "ImageGridView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "FixedMetalDocumentLayer.h"
#import "ImageGridLayerTypes.h"
#import "Util.h"
#import "Grid.h"
#import "Code/Shared/Img.h"
using namespace MDCStudio;

static constexpr auto _ThumbWidth = ImageThumb::ThumbWidth;
static constexpr auto _ThumbHeight = ImageThumb::ThumbHeight;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

@interface ImageGridLayer : FixedMetalDocumentLayer

- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;
- (size_t)columnCount;
- (void)recomputeGrid;

- (ImageGridViewImageIds)imageIdsForRect:(CGRect)rect;
- (CGRect)rectForImageAtIndex:(size_t)idx;

- (const ImageGridViewImageIds&)selectedImageIds;
- (void)setSelectedImageIds:(const ImageGridViewImageIds&)imageIds;

@end

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
        ImageGridViewImageIds imageIds;
        Img::Id first = 0;
        size_t count = 0;
        id<MTLBuffer> buf;
    } _selection;
}

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imageLibrary {
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

//- (BOOL)isGeometryFlipped {
//    return true;
//}

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
                    .transform = [self fixedTransform],
                    .off = {
                        .id         = (uint32_t)(offsetof(ImageLibrary::Record, ref.id)),
                        .thumbData  = (uint32_t)(offsetof(ImageLibrary::Record, thumb)),
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
        }
    }
    
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted]; // Necessary to prevent artifacts when resizing window
    [drawable present];
    
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Took %ju ms\n", (uintmax_t)durationMs);
}

- (ImageGridViewImageIds)imageIdsForRect:(CGRect)rect {
    auto lock = std::unique_lock(*_imageLibrary);
    const Grid::IndexRect indexRect = _grid.indexRectForRect(_GridRectFromCGRect(rect, [self contentsScale]));
    ImageGridViewImageIds imageIds;
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

- (const ImageGridViewImageIds&)selectedImageIds {
    return _selection.imageIds;
}

- (void)setSelectedImageIds:(const ImageGridViewImageIds&)imageIds {
    if (!imageIds.empty()) {
        _selection.imageIds = imageIds;
        _selection.first = *imageIds.begin();
        _selection.count = *std::prev(imageIds.end())-*imageIds.begin()+1;
        
        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeShared;
        _selection.buf = [_device newBufferWithLength:_selection.count options:BufOpts];
        bool* bools = (bool*)[_selection.buf contents];
        for (Img::Id imageId : imageIds) {
            bools[imageId-_selection.first] = true;
        }
    
    } else {
        _selection = {};
    }
    
    [self setNeedsDisplay];
}

// MARK: - FixedScrollViewDocument
- (bool)fixedFlipped {
    return true;
}

@end





















@implementation ImageGridView {
    ImageGridLayer* _imageGridLayer;
    CALayer* _selectionRectLayer;
    ImageSourcePtr _imageSource;
    __weak id<ImageGridViewDelegate> _delegate;
    NSLayoutConstraint* _docHeight;
    id _superviewFrameChangedObserver;
}

// MARK: - Creation

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    // Create ImageGridLayer
    ImageGridLayer* imageGridLayer = [[ImageGridLayer alloc] initWithImageLibrary:imageSource->imageLibrary()];
    
    if (!(self = [super initWithFixedLayer:imageGridLayer])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _imageSource = imageSource;
    _imageGridLayer = imageGridLayer;
    [self _handleImageLibraryChanged];
    
    // Create _selectionRectLayer
    {
        _selectionRectLayer = [CALayer new];
        [_selectionRectLayer setActions:LayerNullActions];
        [_selectionRectLayer setBackgroundColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:.2] CGColor]];
        [_selectionRectLayer setBorderColor:[[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1] CGColor]];
        [_selectionRectLayer setHidden:true];
        [_selectionRectLayer setBorderWidth:1];
        [[_imageGridLayer superlayer] addSublayer:_selectionRectLayer];
    }
    
    // Observe image library changes so that we update the image grid
    {
        __weak auto weakSelf = self;
        ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
        auto lock = std::unique_lock(*imageLibrary);
        imageLibrary->addObserver([=] {
            auto strongSelf = weakSelf;
            if (!strongSelf) return false;
            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf _handleImageLibraryChanged]; });
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

- (const ImageGridViewImageIds&)selectedImageIds {
    return [_imageGridLayer selectedImageIds];
}

//- (NSView*)initialFirstResponder {
//    return [_scrollView documentView];
//}

//- (void)setFrame:(NSRect)frame {
//    
//    [_imageGridLayer setContainerWidth:frame.size.width];
//    [_imageGridLayer recomputeGrid];
//    [_docHeight setConstant:[_imageGridLayer containerHeight]];
//    
////    [self _updateDocumentHeight];
//    [super setFrame:frame];
//}

//- (void)setFrameSize:(NSSize)size {
//    [_imageGridLayer setContainerWidth:size.width];
//    [_imageGridLayer recomputeGrid];
//    const CGFloat height = [_imageGridLayer containerHeight];
//    [_docHeight setConstant:height];
//    [super setFrameSize:{size.width, [_imageGridLayer containerHeight]}];
////    [self _updateDocumentHeight];
//}

//- (void)updateConstraints {
//    [super updateConstraints];
//    [self _updateDocumentHeight];
//    NSLog(@"updateConstraints");
//}

- (void)_updateDocumentHeight {
    NSLog(@"_updateDocumentHeight");
    [_imageGridLayer setContainerWidth:[self bounds].size.width];
    [_imageGridLayer recomputeGrid];
//    [self setFrameSize:{[self bounds].size.width, 0}];
    [_docHeight setConstant:[_imageGridLayer containerHeight]];
}

- (void)_handleImageLibraryChanged {
    [self _updateDocumentHeight];
    [_imageGridLayer setNeedsDisplay];
}

// MARK: - NSView Overrides
//- (BOOL)isFlipped {
//    return true;
//}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    
    NSView*const superview = [self superview];
    if (!superview) return;
    
    NSView*const superSuperview = [superview superview];
    if (!superSuperview) return;
    
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[superview]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(superview)]];
    
//    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[superview]|"
//        options:0 metrics:nil views:NSDictionaryOfVariableBindings(superview)]];
    
//    NSLayoutConstraint* docHeightMin = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeHeight
//        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
//        multiplier:1 constant:100];
    
    
    NSLayoutConstraint* docHeightMin = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:superSuperview attribute:NSLayoutAttributeHeight
        multiplier:1 constant:0];
    
    _docHeight = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
        multiplier:1 constant:0];
    [NSLayoutConstraint activateConstraints:@[docHeightMin, _docHeight]];
    
    // Observe document frame changes so we can update our magnification if we're in magnify-to-fit mode
    __weak auto weakSelf = self;
    _superviewFrameChangedObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification
        object:superview queue:nil usingBlock:^(NSNotification*) {
        [weakSelf _superviewFrameChanged];
    }];
}

- (void)_superviewFrameChanged {
//    NSLog(@"_superviewFrameChanged");
    [self _updateDocumentHeight];
}

// MARK: - Event Handling

static ImageGridViewImageIds _XORImageIds(const ImageGridViewImageIds& a, const ImageGridViewImageIds& b) {
    ImageGridViewImageIds r;
    for (Img::Id x : a) {
        if (b.find(x) == b.end()) {
            r.insert(x);
        }
    }
    
    for (Img::Id x : b) {
        if (a.find(x) == a.end()) {
            r.insert(x);
        }
    }
    
    return r;
}

//static CGPoint _ConvertPoint(CALayer* dst, NSView* src, CGPoint x) {
//    CALayer* srcLayer = [src layer];
//    x = [src convertPointToLayer:x];
//    return [dst convertPoint:x fromLayer:srcLayer];
//}

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
    
    NSWindow* win = [mouseDownEvent window];
//    const CGPoint startPoint = _ConvertPoint(_imageGridLayer, _documentView,
//        [_documentView convertPoint:[mouseDownEvent locationInWindow] fromView:nil]);
    const CGPoint startPoint = [self convertPointToFixedDocument:[mouseDownEvent locationInWindow] fromView:nil];
    [_selectionRectLayer setHidden:false];
    
    const bool extend = [[[self window] currentEvent] modifierFlags] & (NSEventModifierFlagShift|NSEventModifierFlagCommand);
    const ImageGridViewImageIds oldSelection = [_imageGridLayer selectedImageIds];
    TrackMouse(win, mouseDownEvent, [=] (NSEvent* event, bool done) {
//        const CGPoint curPoint = _ConvertPoint(_imageGridLayer, _documentView, [_documentView convertPoint:[event locationInWindow] fromView:nil]);
        const CGPoint curPoint = [self convertPointToFixedDocument:[event locationInWindow] fromView:nil];
        const CGRect rect = CGRectStandardize(CGRect{startPoint.x, startPoint.y, curPoint.x-startPoint.x, curPoint.y-startPoint.y});
        const ImageGridViewImageIds newSelection = [_imageGridLayer imageIdsForRect:rect];
        if (extend) {
            [_imageGridLayer setSelectedImageIds:_XORImageIds(oldSelection, newSelection)];
        } else {
            [_imageGridLayer setSelectedImageIds:newSelection];
        }
        [_selectionRectLayer setFrame:rect];
        
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

struct SelectionDelta {
    int x = 0;
    int y = 0;
};

- (void)_moveSelection:(SelectionDelta)delta extend:(bool)extend {
    ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
    auto lock = std::unique_lock(*imageLibrary);
    
    const size_t imgCount = imageLibrary->recordCount();
    if (!imgCount) return;
    
    ImageGridViewImageIds selectedImageIds = [_imageGridLayer selectedImageIds];
    ssize_t newIdx = 0;
    if (!selectedImageIds.empty()) {
        const Img::Id lastSelectedImgId = *std::prev(selectedImageIds.end());
        const auto iter = imageLibrary->find(lastSelectedImgId);
        if (iter == imageLibrary->end()) {
            NSLog(@"Image no longer in library");
            return;
        }
        
        const size_t idx = std::distance(imageLibrary->begin(), iter);
        const size_t colCount = [_imageGridLayer columnCount];
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
            if (lastCol || lastElm) return;
            newIdx += 1;
        
        } else if (delta.x < 0) {
            // Left
            if (firstCol) return;
            newIdx -= 1;
        
        } else if (delta.y > 0) {
            // Down
            if (lastRow) return;
            newIdx += colCount;
        
        } else if (delta.y < 0) {
            // Up
            if (firstRow) return;
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
            return;
        }
    }
    
//    const size_t newIdx = std::min(imgCount-1, idx+[_imageGridLayer columnCount]);
    const Img::Id newImgId = imageLibrary->recordGet(imageLibrary->begin()+newIdx)->ref.id;
    [self scrollRectToVisible:[_imageGridLayer rectForImageAtIndex:newIdx]];
    
    if (!extend) selectedImageIds.clear();
    selectedImageIds.insert(newImgId);
    [_imageGridLayer setSelectedImageIds:selectedImageIds];
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
    ImageLibraryPtr imageLibrary = _imageSource->imageLibrary();
    auto lock = std::unique_lock(*imageLibrary);
    ImageGridViewImageIds ids;
    for (auto it=imageLibrary->begin(); it!=imageLibrary->end(); it++) {
        ids.insert(imageLibrary->recordGet(it)->ref.id);
    }
    [_imageGridLayer setSelectedImageIds:ids];
}

@end

#import "ImageLayer.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <chrono>
#import "Util.h"
using namespace MDCStudio;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthStencilState;
    id<MTLTexture> _depthTexture;
    MTLRenderPassDepthAttachmentDescriptor* _depthAttachment;
    
    CGFloat _contentsScale;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    _contentsScale = 1;
    
    [self setOpaque:true];
    [self setActions:LayerNullActions];
    [self setNeedsDisplayOnBoundsChange:true];
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    
    _commandQueue = [_device newCommandQueue];
    
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:
        [NSBundle bundleForClass:[self class]] error:nil];
    assert(library);
    
    id<MTLFunction> vertexShader = [library newFunctionWithName:@"MDCStudio::ImageLayerShader::VertexShader"];
    assert(vertexShader);
    
    id<MTLFunction> fragmentShader = [library newFunctionWithName:@"MDCStudio::ImageLayerShader::FragmentShader"];
    assert(fragmentShader);
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    
    [pipelineDescriptor setDepthAttachmentPixelFormat:MTLPixelFormatDepth32Float];
    [[pipelineDescriptor colorAttachments][0] setPixelFormat:_PixelFormat];
    
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
    
    return self;
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

- (void)display {
    auto startTime = std::chrono::steady_clock::now();
    
    // Bail if we have zero width/height; the Metal drawable APIs will fail below
    // if we don't short-circuit here.
    const CGRect frame = [self frame];
    if (CGRectIsEmpty(frame)) return;
    
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
    
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
    [renderPassDescriptor setDepthAttachment:depthAttachment];
    [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
    [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
    [[renderPassDescriptor colorAttachments][0] setClearColor:{WindowBackgroundColor.lsrgb[0], WindowBackgroundColor.lsrgb[1], WindowBackgroundColor.lsrgb[2], 1}];
    [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
    
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [renderEncoder setRenderPipelineState:_pipelineState];
    [renderEncoder setDepthStencilState:_depthStencilState];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeNone];
    
//    [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
//    [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
//    
//    [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
//    [renderEncoder setFragmentBuffer:imageBuf offset:0 atIndex:1];
//    [renderEncoder setFragmentBuffer:_selection.buf offset:0 atIndex:2];
//    [renderEncoder setFragmentTexture:_maskTexture atIndex:0];
//    [renderEncoder setFragmentTexture:_outlineTexture atIndex:1];
//    [renderEncoder setFragmentTexture:_shadowTexture atIndex:2];
//    [renderEncoder setFragmentTexture:_selectionTexture atIndex:4];
    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    
    [renderEncoder endEncoding];
    
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

@end

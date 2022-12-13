#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/Mat.h"
#import "RenderTypes.h"
#import "Tools/MDCStudio/Source/FixedScrollView.h"
#import "Tools/MDCStudio/Source/FixedDocumentView.h"
#import "Tools/MDCStudio/Source/FixedMetalDocumentLayer.h"
using namespace MDCTools;

static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

inline NSDictionary* LayerNullActions = @{
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

@interface MyFixedDocLayer : FixedMetalDocumentLayer
@end

@implementation MyFixedDocLayer {
@private
    id<MTLDevice> _device;
    id<MTLLibrary> _library;
    id<MTLCommandQueue> _commandQueue;
    id <MTLTexture> _imageTexture;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    [self setPresentsWithTransaction:true];
    
    _device = [self preferredDevice];
    assert(_device);
    
    [self setDevice:[self preferredDevice]];
    [self setPixelFormat:_PixelFormat];
    
    _library = [_device newDefaultLibrary];
    _commandQueue = [_device newCommandQueue];
    
    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:_device];
    _imageTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"TestImage"] options:nil error:nil];
    assert(_imageTexture);
    return self;
}

- (void)display {
    [super display];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    Renderer renderer(_device, _library, _commandQueue);
    renderer.clear(drawableTxt, {0,0,0,0});
    
    const simd_float4x4 transform = [self fixedTransform];
    renderer.render(drawableTxt, Renderer::BlendType::None,
        renderer.VertexShader("VertexShader", transform),
        renderer.FragmentShader("FragmentShader", _imageTexture)
    );
    
    renderer.commitAndWait();
    [drawable present];
}

//- (BOOL)isGeometryFlipped {
//    return true;
//}

@end


@interface MyClipView : NSClipView
@end

@implementation MyClipView

- (NSRect)constrainBoundsRect:(NSRect)bounds {
    bounds = [super constrainBoundsRect:bounds];
    
    const CGSize docSize = [[self documentView] frame].size;
    if (bounds.size.width >= docSize.width) {
        bounds.origin.x = (docSize.width-bounds.size.width)/2;
    }
    if (bounds.size.height >= docSize.height) {
        bounds.origin.y = (docSize.height-bounds.size.height)/2;
    }
    return bounds;
}

@end







@interface MyDocumentView : NSView
@end

@implementation MyDocumentView

static void _init(MyDocumentView* self) {
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addConstraint:[NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:640]];
    [self addConstraint:[NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:480]];
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _init(self);
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _init(self);
    return self;
}

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    const bool fit = [(FixedScrollView*)[self enclosingScrollView] magnifyToFit];
    if (fit) {
        return CGRectInset({point, {0,0}}, -20, -20);
    } else {
        return [self bounds];
    }
}

- (BOOL)isFlipped {
    return true;
}

@end









constexpr CGFloat ShadowCenterOffset = 45;

@interface MyScrollView : FixedScrollView
@end

@implementation MyScrollView {
    NSView* _shadowView;
    CALayer* _shadowLayer;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (void)initCommon {
    FixedDocumentView* fixedDocView = [[FixedDocumentView alloc] initWithFrame:{}];
    [fixedDocView setFixedLayer:[MyFixedDocLayer new]];
    [self setFixedDocument:fixedDocView];
    
    constexpr uint32_t BackgroundTileSize = 256;
    constexpr uint32_t BackgroundTileLen = BackgroundTileSize*BackgroundTileSize*3;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MDCTools::Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    auto backgroundTxt = renderer.textureCreate(MTLPixelFormatRGBA16Float, BackgroundTileSize, BackgroundTileSize);
    id<MTLBuffer> noiseDataBuf = [device newBufferWithLength:BackgroundTileLen options:MTLResourceCPUCacheModeDefaultCache|MTLResourceStorageModeManaged];
    uint8_t* noiseData = (uint8_t*)[noiseDataBuf contents];
    for (size_t i=0; i<BackgroundTileLen; i++) {
        noiseData[i] = rand() & 0xFF;
    }
    [noiseDataBuf didModifyRange:NSMakeRange(0, BackgroundTileLen)];
    
    renderer.clear(backgroundTxt, {0.0130468225, 0.0137825618, 0.015127142, 1});
    renderer.render(backgroundTxt, Renderer::BlendType::Over,
        renderer.FragmentShader("RenderNoise",
            // Buffer args
            BackgroundTileSize,
            noiseDataBuf
        )
    );
    renderer.commitAndWait();
    
    id image = renderer.imageCreate(backgroundTxt);
    assert(image);
    [self setBackgroundColor:[NSColor colorWithPatternImage:[[NSImage alloc] initWithCGImage:(__bridge CGImageRef)image size:{BackgroundTileSize/2, BackgroundTileSize/2}]]];

    
    
    
//    [self setBackgroundColor:[NSColor colorWithSRGBRed:.118 green:.122 blue:.129 alpha:1]];
}


- (void)tile {
    [super tile];
    if (!_shadowView) {
        _shadowLayer = [CALayer new];
        [_shadowLayer setActions:LayerNullActions];
        NSImage* shadow = [NSImage imageNamed:@"ImageView-Shadow"];
        assert(shadow);
        [_shadowLayer setContents:shadow];
        [_shadowLayer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
        
        CGSize shadowSize = [shadow size];
        CGRect center = { ShadowCenterOffset, ShadowCenterOffset, shadowSize.width-2*ShadowCenterOffset, shadowSize.height-2*ShadowCenterOffset };
        center.origin.x /= shadowSize.width;
        center.origin.y /= shadowSize.height;
        center.size.width /= shadowSize.width;
        center.size.height /= shadowSize.height;
        [_shadowLayer setContentsCenter:center];
        
        _shadowView = [[NSView alloc] initWithFrame:{}];
        [_shadowView setLayer:_shadowLayer];
        [_shadowView setWantsLayer:true];
        [self addSubview:_shadowView positioned:NSWindowBelow relativeTo:[self contentView]];
    }
    
    [self _updateShadowFrame];
}

- (void)_updateShadowFrame {
    NSView* docView = [self documentView];
    CGRect shadowFrame = [self convertRect:[docView visibleRect] fromView:docView];
    shadowFrame = CGRectInset(shadowFrame, -ShadowCenterOffset/[_shadowLayer contentsScale], -ShadowCenterOffset/[_shadowLayer contentsScale]);
    [_shadowView setFrame:shadowFrame];
}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    [self _updateShadowFrame];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_shadowLayer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

@end

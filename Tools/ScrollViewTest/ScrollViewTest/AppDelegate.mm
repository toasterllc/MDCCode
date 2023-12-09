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

@interface MyDocLayer : FixedMetalDocumentLayer
@end

static CGColorSpaceRef _SRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return cs;
}

@implementation MyDocLayer {
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
    [self setColorspace:_SRGBColorSpace()]; // See comment for _PixelFormat
    
    _library = [_device newDefaultLibrary];
    _commandQueue = [_device newCommandQueue];
    
    
    
    {
        constexpr size_t ThumbWidth = 512;
        constexpr size_t ThumbHeight = 288;
        
//        NSData* data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle]
//            pathForResource:@"thumb-astc-4x4" ofType:@"bin"]];
//        assert(data);
//        MTLPixelFormat fmt = MTLPixelFormatASTC_4x4_LDR;
        
        NSData* data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle]
            pathForResource:@"thumb-bc7" ofType:@"bin"]];
        assert(data);
        MTLPixelFormat fmt = MTLPixelFormatBC7_RGBAUnorm;
        
        MTLTextureDescriptor* desc = [MTLTextureDescriptor new];
        [desc setTextureType:MTLTextureType2D];
        [desc setPixelFormat:fmt];
        [desc setWidth:ThumbWidth];
        [desc setHeight:ThumbHeight];
        [desc setArrayLength:1];
        
        _imageTexture = [_device newTextureWithDescriptor:desc];
        assert(_imageTexture);
        
        [_imageTexture replaceRegion:MTLRegionMake2D(0,0,ThumbWidth,ThumbHeight) mipmapLevel:0
            slice:0 withBytes:[data bytes] bytesPerRow:ThumbWidth*4 bytesPerImage:0];
        
    }
    
    
    
//    MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:_device];
//    _imageTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForImageResource:@"TestImage"] options:nil error:nil];
    
//    _imageTexture = [loader newTextureWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"thumb-astc-4x4" withExtension:@".bin"] options:nil error:nil];
    
//    assert(_imageTexture);
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

//- (CGSize)fixedContentSize {
//    return {640, 480};
//}

//- (BOOL)isGeometryFlipped {
//    return true;
//}


- (bool)fixedFlipped {
    return true;
}

- (CGSize)preferredFrameSize {
    return {640, 480};
}

@end







@interface MyDocView : FixedDocumentView
@end

@implementation MyDocView

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    const bool fit = [(FixedScrollView*)[self enclosingScrollView] magnifyToFit];
    if (fit) {
        return CGRectInset({point, {0,0}}, -20, -20);
    } else {
        return [[self superview] bounds];
    }
}

//- (void)viewDidMoveToSuperview {
//    [super viewDidMoveToSuperview];
//    
//    NSView*const superview = [self superview];
//    if (!superview) return;
//    
//    NSLayoutConstraint* width = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeWidth
//        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
//        multiplier:1 constant:640];
//    
//    NSLayoutConstraint* height = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeHeight
//        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute
//        multiplier:1 constant:480];
//    
//    [NSLayoutConstraint activateConstraints:@[width, height]];
//}

@end









constexpr CGFloat ShadowCenterOffset = 45;

@interface MyScrollView : FixedScrollView
@end

@implementation MyScrollView {
    NSView* _shadowView;
    CALayer* _shadowLayer;
}

- (instancetype)init {
    FixedDocumentView* fixedDocView = [[MyDocView alloc] initWithFixedLayer:[MyDocLayer new]];
    
    if (!(self = [super initWithFixedDocument:fixedDocView])) return nil;
    
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
    
//    [self setContentInsets:{100,0,50,0}];
    
    return self;
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




//- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
//    NSLog(@"BBB rectForSmartMagnificationAtPoint");
//    return {};
//}


@end



@interface MainView : NSView
@end

@implementation MainView

- (void)initCommon {
    MyScrollView* sv = [MyScrollView new];
    [self addSubview:sv];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[sv]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(sv)]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[sv]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(sv)]];
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



@end

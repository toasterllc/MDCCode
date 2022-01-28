#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <IOSurface/IOSurface.h>
#import <IOSurface/IOSurfaceObjC.h>
#import <vector>
#import <filesystem>
#import "Grid.h"
#import "ImageGridLayer.h"
#import "ImageLibrary.h"
#import "MDCDevicesManager.h"
namespace fs = std::filesystem;

static std::vector<id> _Images;

//static bool _IsJPGFile(const fs::path& path) {
//    return fs::is_regular_file(path) && path.extension() == ".jpg";
//}
//
//static id _CGImageFromPath(const fs::path& path) {
////    id imageSource = CFBridgingRelease(CGImageSourceCreateWithData((__bridge CFDataRef)[NSData dataWithContentsOfFile:@(path.c_str())], nullptr));
////    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((__bridge CGImageSourceRef)imageSource, 0, nullptr));
////    CGImageCreateWithImageInRect(<#CGImageRef  _Nullable image#>, <#CGRect rect#>)
////    return image;
//    
//    id dataProvider = CFBridgingRelease(CGDataProviderCreateWithFilename(path.c_str()));
//    id img = CFBridgingRelease(CGImageCreateWithJPEGDataProvider((__bridge CGDataProviderRef)dataProvider, nullptr, false, kCGRenderingIntentDefault));
//    CGImageRef imgRef = (__bridge CGImageRef)img;
//    
//    const size_t w = CGImageGetWidth((__bridge CGImageRef)img);
//    const size_t h = CGImageGetHeight((__bridge CGImageRef)img);
//    
//    const id colorspace = CFBridgingRelease(CGColorSpaceCreateDeviceRGB());
//    CGColorSpaceRef colorspaceRef = (__bridge CGColorSpaceRef)colorspace;
//    
//    const CGContextRef ctx = CGBitmapContextCreate(nullptr, w, h, 8, w*4, colorspaceRef, kCGImageAlphaNoneSkipFirst);
//    CGContextDrawImage(ctx, {0,0,(CGFloat)w,(CGFloat)h}, imgRef);
//    
//    return CFBridgingRelease(CGBitmapContextCreateImage(ctx));
//    
//    
//    
//    
////    const size_t w = CGImageGetWidth((__bridge CGImageRef)image);
////    const size_t h = CGImageGetHeight((__bridge CGImageRef)image);
////    image = CFBridgingRelease(CGImageCreateWithImageInRect((__bridge CGImageRef)image, {1,1,(CGFloat)w,(CGFloat)h}));
//////    CGImageSourceCreateWithURL(<#CFURLRef  _Nonnull url#>, <#CFDictionaryRef  _Nullable options#>)
//////    CGImageGetWidth((__bridge CGImageRef)image);
//////    CGImageGetBitmapInfo((__bridge CGImageRef)image);
////    return image;
//}

//static void _LoadImages() {
//    id<MTLDevice> _MetalDevice = MTLCreateSystemDefaultDevice();
//    MTKTextureLoader* _TextureLoader = [[MTKTextureLoader alloc] initWithDevice:_MetalDevice];
//    
//    const fs::path ImagesDir = "/Users/dave/Desktop/TestImages";
//    
//    NSLog(@"Loading images START");
//    for (const fs::path& p : fs::directory_iterator(ImagesDir)) {
//        if (_IsJPGFile(p)) {
////            const uint32_t pixelFormat = 'BGRA';
////            IOSurface* image = [[IOSurface alloc] initWithProperties:@{
////                IOSurfacePropertyKeyWidth: @(32),
////                IOSurfacePropertyKeyHeight: @(32),
////                IOSurfacePropertyKeyBytesPerElement: @(4),
////                IOSurfacePropertyKeyPixelFormat: @(pixelFormat),
////            }];
////            if (image) _Images.push_back(image);
//            
//            
//            id image = _CGImageFromPath(p);
//            if (image) _Images.push_back(image);
//            
//            
////            id image = [_TextureLoader newTextureWithCGImage:(__bridge CGImageRef)_CGImageFromPath(p) options:nil error:nil];
////            if (image) _Images.push_back(image);
//            
////            MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:256 height:256 mipmapped:false];
////            id<MTLTexture> image = [_MetalDevice newTextureWithDescriptor:desc];
//////            id<MTLTexture> image = [_TextureLoader newTextureWithContentsOfURL:[NSURL fileURLWithPath:@(p.c_str())] options:nil error:nil];
////            if (image) _Images.push_back(image);
////            if (_Images.size() > 10) break;
//////            NSLog(@"%s", p.path().string().c_str());
//        }
//    }
//    NSLog(@"Loading images END");
//}

static NSDictionary* LayerNullActions = @{
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







@interface MainView : NSView
@end

@implementation MainView {
@public
    CALayer* _rootLayer;
    ImageGridLayer* _imageGridLayer;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self initCommon];
    return self;
}

- (void)initCommon {
    _rootLayer = [CALayer new];
    [self setLayer:_rootLayer];
    [self setWantsLayer:true];
    
    _imageGridLayer = [ImageGridLayer new];
    [_rootLayer addSublayer:_imageGridLayer];
    
    const char* ImageLibraryPath = "/Users/dave/Desktop/ImageStore-Chunk-5k";
//    const char* ImageLibraryPath = "/Users/dave/Desktop/ImageStore-Chunk-40k";
    auto imgLib = std::make_shared<ImageLibrary>(ImageLibraryPath);
    
//    printf("Reading every page START\n");
//    const size_t pageSize = getpagesize();
//    const auto chunkBegin = imgLib->getImageChunk(0);
//    const auto chunkEnd = std::next(imgLib->getImageChunk(imgLib->imageCount()-1));
//    for (auto it=chunkBegin; it!=chunkEnd; it++) {
//        const Mmap& mmap = it->mmap;
//        const volatile uint8_t* data = mmap.data<const volatile uint8_t>();
//        const size_t mmapLen = mmap.len();
//        for (size_t off=0; off<mmapLen; off+=pageSize) {
//            data[off];
//        }
//    }
//    printf("Reading every page END\n");
    
    [_imageGridLayer setImageLibrary:imgLib];
    
//    [_rootLayer addSublayer:_imageGridLayer];
//    [self setLayer:_imageGridLayer];
//    [self setWantsLayer:true];
}

//- (void)setFrameOrigin:(NSPoint)origin {
//    NSLog(@"setFrameOrigin: %@", NSStringFromPoint(origin));
//    [super setFrameOrigin:origin];
//}
//
//- (void)setBoundsOrigin:(NSPoint)origin {
//    NSLog(@"setBoundsOrigin: %@", NSStringFromPoint(origin));
//    [super setBoundsOrigin:origin];
//}
//
//- (void)setBounds:(NSRect)bounds {
//    NSLog(@"setBounds:");
//    [super setBounds:bounds];
//}

- (void)setFrame:(NSRect)frame {
    [_imageGridLayer setContainerWidth:frame.size.width];
    frame.size.height = [_imageGridLayer containerHeight];
//    NSLog(@"setFrame: %@", NSStringFromRect(frame));
    [super setFrame:frame];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_imageGridLayer setContentsScale:[[self window] backingScaleFactor]];
}

- (BOOL)isFlipped {
    return true;
}

//- (BOOL)isOpaque {
//    return true;
//}

@end









@interface MyScrollView : NSScrollView
@end

@implementation MyScrollView

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    
    const CGRect visibleRect = [self documentVisibleRect];
    ImageGridLayer*const imageGridLayer = ((MainView*)[self documentView])->_imageGridLayer;
    [imageGridLayer setFrame:visibleRect];
//    [gridLayer setFrame:CGRectInset(visibleRect, 10, 10)];
//    NSLog(@"%@", NSStringFromRect(visibleRect));
    
//    ImageGridLayer* gridLayer = ((MainView*)[self documentView])->_imageGridLayer;
//    const CGRect visibleRect = [self documentVisibleRect];
////    [gridLayer setVisibleRect:visibleRect];
//    NSLog(@"%@", NSStringFromRect(visibleRect));
    
//    NSLog(@"[MyScrollView] reflectScrolledClipView");
//    [super reflectScrolledClipView:clipView];
}

//- (void)scrollClipView:(NSClipView*)clipView toPoint:(NSPoint)point {
//    [super scrollClipView:clipView toPoint:point];
//    ImageGridLayer* gridLayer = ((MainView*)[self documentView])->_imageGridLayer;
//    
//    const CGRect visibleRect = [self documentVisibleRect];
//    [gridLayer setVisibleRect:visibleRect];
//    NSLog(@"%@", NSStringFromRect(visibleRect));
//    
////    CGRect frame = [self documentVisibleRect];
////    frame.origin.y = [gridLayer bounds].size.height-frame.origin.y-frame.size.height;
////    [gridLayer->overlay setFrame:frame];
////    NSLog(@"%@", NSStringFromRect(frame));
////    return;
////    NSLog(@"[MyScrollView] scrollClipView");
////    [super scrollClipView:clipView toPoint:point];
//}

//- (void)tile {
//    NSLog(@"[MyScrollView] tile");
//    [super tile];
//}

@end




@interface MyClipView : NSClipView
@end

@implementation MyClipView

//- (void)reflectScrolledClipView:(NSClipView*)clipView {
//    NSLog(@"[MyClipView] reflectScrolledClipView");
//    [super reflectScrolledClipView:clipView];
//}
//
//- (void)scrollClipView:(NSClipView*)clipView toPoint:(NSPoint)point {
//    NSLog(@"[MyClipView] scrollClipView");
//    [super scrollClipView:clipView toPoint:point];
//}
//
//- (void)scrollToPoint:(NSPoint)point {
//    NSLog(@"[MyClipView] scrollToPoint");
//    [super scrollToPoint:point];
//}

@end



@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@interface AppDelegate ()
@property(weak) IBOutlet NSWindow* window;
@end

@implementation AppDelegate

- (void)awakeFromNib {
    MDCDevicesManager::AddObserver([] {
        printf("Devices changed\n");
    });
    
    MDCDevicesManager::Start();
}

@end

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <mutex>
#import <vector>
#import "ImageLayer.h"
#import "Assert.h"
#import "Util.h"
#import "TimeInstant.h"
#import "ImagePipeline.h"
#import "ImagePipelineManager.h"
using namespace CFAViewer;
using namespace MetalUtil;
using namespace ImagePipeline;

@implementation ImageLayer {
    ImagePipelineManager* _ipm;
    
//    Histogram _inputHistogram __attribute__((aligned(4096)));
//    id<MTLBuffer> _inputHistogramBuf;
//    Histogram _outputHistogram __attribute__((aligned(4096)));
//    id<MTLBuffer> _outputHistogramBuf;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [self setActions:LayerNullActions()];
    return self;
}

- (void)setImagePipelineManager:(ImagePipelineManager*)ipm {
    _ipm = ipm;
    [self setDevice:_ipm->renderer.dev];
}

//- (void)setImage:(const CFAViewer::ImageLayerTypes::Image&)img {
//    // If we don't have pixel data, ensure that our image has 0 pixels
//    NSParameterAssert(img.pixels || (img.width*img.height)==0);
//    
//    auto lock = std::lock_guard(_state.lock);
//    
//    const size_t pixelCount = img.width*img.height;
//    
//    // Reset image size in case something fails
//    _state.img.width = 0;
//    _state.img.height = 0;
//    _state.img.cfaDesc = img.cfaDesc;
//    
//    const size_t len = pixelCount*sizeof(ImagePixel);
//    if (len) {
//        if (!_state.img.pixels || [_state.img.pixels length]<len) {
//            _state.img.pixels = _state.renderer.bufferCreate(len);
//            Assert(_state.img.pixels, return);
//        }
//        
//        // Copy the pixel data into the Metal buffer
//        memcpy([_state.img.pixels contents], img.pixels, len);
//        
//        // Set the image size now that we have image data
//        _state.img.width = img.width;
//        _state.img.height = img.height;
//    
//    } else {
//        _state.img.pixels = Renderer::Buf();
//    }
//    
//    const CGFloat scale = [self contentsScale];
//    [self setBounds:{0, 0, _state.img.width/scale, _state.img.height/scale}];
//    [self setNeedsDisplay];
//}
//
//
//- (void)setOptions:(const CFAViewer::ImageLayerTypes::Options&)opts {
//    auto lock = std::lock_guard(_state.lock);
//    _state.opts = opts;
//    [self setNeedsDisplay];
//}

//- (MetalUtil::Histogram)inputHistogram {
//    return _inputHistogram;
//}
//
//- (MetalUtil::Histogram)outputHistogram {
//    return _outputHistogram;
//}

//// Lock must be held
//- (void)_displayToTexture:(id<MTLTexture>)outTxt drawable:(id<CAMetalDrawable>)drawable {
//    ImagePipeline::Pipeline::Run(_state.renderer, _state.img,
//        _state.opts, _state.sampleOpts, outTxt);
//    
//    // If outTxt isn't framebuffer-only, then do a blit-sync, which is
//    // apparently required for [outTxt getBytes:] to work, which
//    // -CGImage uses.
//    if (![outTxt isFramebufferOnly]) {
//        _state.renderer.sync(outTxt);
//    }
//    
//    if (drawable) _state.renderer.present(drawable);
//    // Wait for the render to complete, since the lock needs to be
//    // held because the shader accesses _state
//    _state.renderer.commitAndWait();
//    
//    // Notify that our histogram changed
//    auto dataChangedHandler = _state.dataChangedHandler;
//    if (dataChangedHandler) {
//        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
//            dataChangedHandler(self);
//        });
//    }
//}

- (void)display {
    if (!_ipm) return;
    
    // Update our drawable size using our view size (in pixels)
    [self setDrawableSize:{(CGFloat)_ipm->rawImage.width, (CGFloat)_ipm->rawImage.height}];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    Assert(drawable, return);
    
    TimeInstant start;
    {
        [_ipm render];
        _ipm->renderer.copy(_ipm->result.txt, [drawable texture]);
        _ipm->renderer.present(drawable);
        _ipm->renderer.commit();
    }
    printf("Display took %f\n", start.durationMs()/1000.);
}

- (void)setContentsScale:(CGFloat)scale {
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

- (void)setNeedsDisplay {
    if ([NSThread isMainThread]) {
        // Update our bounds
        if (_ipm) {
            const CGFloat scale = [self contentsScale];
            [self setBounds:{0, 0, _ipm->rawImage.width/scale, _ipm->rawImage.height/scale}];
        }
        [super setNeedsDisplay];
    
    } else {
        // Call -setNeedsDisplay on the main thread, so that drawing is
        // sync'd with drawing triggered by the main thread.
        // Don't use dispatch_async here, because dispatch_async's don't get drained
        // while the runloop is run recursively, eg during mouse tracking.
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [self setNeedsDisplay];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

@end

#import <QuartzCore/QuartzCore.h>
#import "MetalUtil.h"
#import "Mat.h"
#import "Color.h"
#import "ImagePipelineTypes.h"
#import "ImagePipeline.h"
@class ImagePipelineManager;

@interface ImageLayer : CAMetalLayer

- (void)setImagePipelineManager:(ImagePipelineManager*)ipm;

//- (instancetype)initWithImagePipelineManager:(ImagePipelineManager*)ipm;

//- (void)setImage:(const CFAViewer::ImageLayerTypes::Image&)img;
//- (void)setOptions:(const CFAViewer::ImageLayerTypes::Options&)opts;
//
//- (void)setSampleRect:(CGRect)rect;
//// `handler` is called on a background queue when histograms/sample data changes
//- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler;
//
//- (CFAViewer::MetalUtil::Histogram)inputHistogram;
//- (CFAViewer::MetalUtil::Histogram)outputHistogram;
//
//- (Color<ColorSpace::Raw>)sampleRaw;
//- (Color<ColorSpace::XYZD50>)sampleXYZD50;
//- (Color<ColorSpace::SRGB>)sampleSRGB;
//
//- (id)CGImage;

@end

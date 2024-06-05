#import "PrintImages.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "ImagePipelineUtil.h"
using namespace MDCStudio;

@interface PrintImageView : NSImageView
- (instancetype)initWithImages:(std::vector<NSImage*>&&)images;
@end

static NSImage* _NSImageForImage(ImageSourcePtr imageSource, const ImageRecordPtr& rec) {
    using namespace Toastbox;
    using namespace MDCTools;
    using namespace ImagePipeline;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    Toastbox::Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    Image image = imageSource->getImage(ImageSource::Priority::High, rec);
    Pipeline::Options popts = PipelineOptionsForImage(*rec, image);
    
    Renderer::Txt txt = renderer.textureCreate(MTLPixelFormatRGBA16Float,
        rec->info.imageWidth, rec->info.imageHeight);
    
    Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
        image.width, image.height, (ImagePixel*)(image.data.get()));
    
    Pipeline::Run(renderer, popts, rawTxt, txt);
    
    return [[NSImage alloc] initWithCGImage:(__bridge CGImageRef)renderer.imageCreate(txt)
        size:NSZeroSize];
}

NSPrintOperation* PrintImages(NSDictionary<NSPrintInfoAttributeKey,id>* settings,
    ImageSourcePtr imageSource, const ImageSet& recs, bool order) {
    
    assert(!recs.empty());
    
    std::vector<NSImage*> images;
    
    using IterAny = Toastbox::IterAny<ImageSet::const_iterator>;
    IterAny recsBegin = (order ? IterAny(recs.begin()) : IterAny(recs.rbegin()));
    IterAny recsEnd = (order ? IterAny(recs.end()) : IterAny(recs.rend()));
    for (auto it=recsBegin; it!=recsEnd; it++) {
        images.push_back(_NSImageForImage(imageSource, *it));
    }
    
    PrintImageView* view = [[PrintImageView alloc] initWithImages:std::move(images)];
    
    NSPrintInfo* pi = [[NSPrintInfo alloc] initWithDictionary:settings];
    [pi setVerticalPagination:NSPrintingPaginationModeFit];
    [pi setHorizontalPagination:NSPrintingPaginationModeFit];
    [pi setOrientation:NSPaperOrientationLandscape];
    
    NSPrintOperation* pop = [NSPrintOperation printOperationWithView:view printInfo:pi];
    NSPrintPanel* pp = [pop printPanel];
    [pp setOptions:
        [pp options] |
        NSPrintPanelShowsOrientation |
        NSPrintPanelShowsScaling
    ];
    
    return pop;
}


@implementation PrintImageView {
    std::vector<NSImage*> _images;
}

- (instancetype)initWithImages:(std::vector<NSImage*>&&)images {
    if (!(self = [super initWithFrame:{}])) return nil;
    assert(!images.empty());
    _images = std::move(images);
    [self setImage:_images.at(0)];
    [self setFrame:{{}, [self intrinsicContentSize]}];
    return self;
}

- (NSRect)rectForPage:(NSInteger)page {
    [self setImage:_images.at(page-1)];
    NSPrintInfo* pi = [[NSPrintOperation currentOperation] printInfo];
    const NSRect pageBounds = [pi imageablePageBounds];
    const CGFloat scale = [pi scalingFactor];
    [self setFrame:{{}, {
        pageBounds.size.width*scale,
        pageBounds.size.height*scale
    }}];
    return [self bounds];
}

- (BOOL)knowsPageRange:(NSRangePointer)range {
    range->location = 1;
    range->length = _images.size();
    return true;
}

@end

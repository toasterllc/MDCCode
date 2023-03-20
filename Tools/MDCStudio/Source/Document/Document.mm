#import "Document.h"
#import <algorithm>
#import "Toastbox/Mac/ThreePartView.h"
#import "SourceListView/SourceListView.h"
#import "InspectorView/InspectorView.h"
#import "ImageGridView/ImageGridView.h"
#import "ImageView/ImageView.h"
#import "FixedScrollView.h"
#import "MockImageSource.h"

using namespace MDCStudio;

@interface Document () <NSSplitViewDelegate, SourceListViewDelegate, ImageGridViewDelegate, ImageViewDelegate>
@end

@implementation Document {
    IBOutlet NSSplitView* _splitView;
    SourceListView* _sourceListView;
    
    NSView* _centerContainerView;
    NSView* _centerView;
    
    NSView* _inspectorContainerView;
    InspectorView* _inspectorView;
}

+ (BOOL)autosavesInPlace {
    return false;
}

- (void)setCenterView:(NSView*)centerView {
    if (_centerView) [_centerView removeFromSuperview];
    _centerView = centerView;
    [_centerContainerView addSubview:_centerView];
    [_centerContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_centerView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_centerView)]];
    [_centerContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_centerView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_centerView)]];
}

- (void)setInspectorView:(InspectorView*)inspectorView {
    if (_inspectorView) [_inspectorView removeFromSuperview];
    _inspectorView = inspectorView;
    [_inspectorContainerView addSubview:_inspectorView];
    [_inspectorContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_inspectorView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_inspectorView)]];
    [_inspectorContainerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_inspectorView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_inspectorView)]];
}

- (void)awakeFromNib {
    _sourceListView = [[SourceListView alloc] initWithFrame:{}];
    [_sourceListView setDelegate:self];
    
    _centerContainerView = [[NSView alloc] initWithFrame:{}];
    [_centerContainerView setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _inspectorContainerView = [[NSView alloc] initWithFrame:{}];
    [_inspectorContainerView setTranslatesAutoresizingMaskIntoConstraints:false];
    
    [_splitView addArrangedSubview:_sourceListView];
    [_splitView addArrangedSubview:_centerContainerView];
    [_splitView addArrangedSubview:_inspectorContainerView];
    
    [_splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [_splitView setHoldingPriority:NSLayoutPriorityFittingSizeCompression forSubviewAtIndex:1];
    [_splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:2];
    
    // Handle whatever is first selected
    [self sourceListViewSelectionChanged:_sourceListView];
}

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if ([item action] == @selector(saveDocument:)) {
        return false;
    }
    return true;
}

- (NSString*)windowNibName {
    return @"Document";
}

- (NSString*)displayName {
    return @"MDCStudio";
}




//static void _addImages(ImageLibraryPtr imgLib, MDCTools::Renderer& renderer, const uint8_t* data, size_t imgCount, SD::Block block) {
//    using namespace MDCTools;
//    using namespace MDCTools::ImagePipeline;
//    
//    ImageId imageId = 0;
//    {
//        auto lock = std::unique_lock(*imgLib);
//        
//        // Reserve space for `imgCount` additional images
//        imgLib->reserve(imgCount);
//        
//        // Load `imageId` by looking at the last record's image id +1, and reserve space
//        if (imgLib->recordCount()) {
//            imageId = imgLib->recordGet(imgLib->back())->ref.id+1;
//        }
//    }
//    
//    Img::Id deviceImgIdLast = 0;
//    for (size_t idx=0; idx<imgCount; idx++) {
//        const uint8_t* imgData = data+idx*ImgSD::ImagePaddedLen;
//        const Img::Header& imgHeader = *(const Img::Header*)imgData;
//        // Accessing `imgLib` without a lock because we're the only entity using the image library's reserved space
//        const auto recordRefIter = imgLib->reservedBegin()+idx;
//        ImageThumb& imageThumb = *imgLib->recordGet(recordRefIter);
//        ImageRef& imageRef = imageThumb.ref; // Safe without a lock because we're the only entity using the image library's reserved space
//        
//        // Validate checksum
//        const uint32_t checksumExpected = ChecksumFletcher32(imgData, Img::ChecksumOffset);
//        uint32_t checksumGot = 0;
//        memcpy(&checksumGot, imgData+Img::ChecksumOffset, Img::ChecksumLen);
//        if (checksumGot != checksumExpected) {
//            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
//        } else {
//            printf("Checksum OK\n");
//        }
//        
//        // Populate ImageRef fields
//        {
//            imageRef.id = imageId;
//            
//            // If the image has an absolute time, use it
//            // If the image has a relative time (ie time since device boot), drop it
//            if (imgHeader.timestamp & MSP::TimeAbsoluteBase) {
//                imageRef.timestamp = MSP::UnixTimeFromTime(imgHeader.timestamp);
//            }
//            
//            imageRef.addr           = block;
//            
//            imageRef.imageWidth     = imgHeader.imageWidth;
//            imageRef.imageHeight    = imgHeader.imageHeight;
//            
//            imageRef.coarseIntTime  = imgHeader.coarseIntTime;
//            imageRef.analogGain     = imgHeader.analogGain;
//            
//            imageId++;
//            block += ImgSD::Full::ImageBlockCount;
//        }
//        
//        // Render the thumbnail into imageRef.thumbData
//        {
//            constexpr CFADesc _CFADesc = {
//                CFAColor::Green, CFAColor::Red,
//                CFAColor::Blue, CFAColor::Green,
//            };
//            
//            const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
//            
//            Pipeline::RawImage rawImage = {
//                .cfaDesc = _CFADesc,
//                .width = Img::PixelWidth,
//                .height = Img::PixelHeight,
//                .pixels = (ImagePixel*)(imgData+Img::PixelsOffset),
//            };
//            
//            const Pipeline::Options pipelineOpts = {
//                .reconstructHighlights  = { .en = true, },
//                .debayerLMMSE           = { .applyGamma = true, },
//            };
//            
//            Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
//            const size_t thumbDataOff = (uintptr_t)&imageThumb.thumb - (uintptr_t)chunk.mmap.data();
//            
//            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//            id<MTLBuffer> buf = [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data() length:chunk.mmap.len() options:BufOpts deallocator:nil];
//            
//            const RenderThumb::Options thumbOpts = {
//                .thumbWidth = ImageThumb::ThumbWidth,
//                .thumbHeight = ImageThumb::ThumbHeight,
//                .dataOff = thumbDataOff,
//            };
//            
//            RenderThumb::RGB3FromTexture(renderer, thumbOpts, renderResult.txt, buf);
//        }
//        
//        deviceImgIdLast = imgHeader.id;
//    }
//    
//    // Make sure all rendering is complete before adding the images to the library
//    renderer.commitAndWait();
//    
//    {
//        auto lock = std::unique_lock(*imgLib);
//        // Add the records that we previously reserved
//        imgLib->add();
//        // Update the device's image id 'end' == last image id that we've observed from the device +1
//        imgLib->deviceImgIdEnd(deviceImgIdLast+1);
//    }
//}







- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView {
    {
        auto imageSource = std::make_shared<MockImageSource>("/Users/dave/Desktop/ImageLibrary");
        
        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:imageSource];
        [imageGridView setDelegate:self];
        
        [self setCenterView:[[ImageGridScrollView alloc] initWithFixedDocument:imageGridView]];
        [self setInspectorView:[[InspectorView alloc] initWithImageSource:imageSource]];
        
        [[_splitView window] makeFirstResponder:imageGridView];
    }
    
    
    
    
    
    
    
    
//    ImageSourcePtr imageSource = [_sourceListView selection];
//    if (imageSource) {
//        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:imageSource];
//        [imageGridView setDelegate:self];
//        
//        [self setCenterView:[[ImageGridScrollView alloc] initWithFixedDocument:imageGridView]];
//        [self setInspectorView:[[InspectorView alloc] initWithImageSource:imageSource]];
//        
//        [[_splitView window] makeFirstResponder:imageGridView];
////        [_mainView setContentView:sv animation:MainViewAnimation::None];
//    
//    } else {
////        [_mainView setCenterView:nil];
//    }
}








//static constexpr MDCTools::CFADesc _CFADesc = {
//    MDCTools::CFAColor::Green, MDCTools::CFAColor::Red,
//    MDCTools::CFAColor::Blue, MDCTools::CFAColor::Green,
//};
//
//static bool _ChecksumValid(const void* data, Img::Size size) {
//    const size_t ChecksumOffset = (size==Img::Size::Full ? Img::Full::ChecksumOffset : Img::Thumb::ChecksumOffset);
//    // Validate thumbnail checksum
//    const uint32_t checksumExpected = ChecksumFletcher32(data, ChecksumOffset);
//    uint32_t checksumGot = 0;
//    memcpy(&checksumGot, (uint8_t*)data+ChecksumOffset, Img::ChecksumLen);
//    if (checksumGot != checksumExpected) {
//        printf("Checksum invalid (expected:0x%08x got:0x%08x)\n", checksumExpected, checksumGot);
//        return false;
//    }
//    return true;
//}
//
//
//
//static simd::float3 _SimdForMat(const Mat<double,3,1>& m) {
//    return {
//        simd::float3{(float)m[0], (float)m[1], (float)m[2]},
//    };
//}
//
//static simd::float3x3 _SimdForMat(const Mat<double,3,3>& m) {
//    return {
//        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
//        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
//        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
//    };
//}
//
//
//- (void)_addFakeImages:(ImageLibraryPtr)imgLib {
//    using namespace MDCTools;
//    using namespace MDCTools::ImagePipeline;
//    using namespace Toastbox;
//    
//    Mmap mmap("/Users/dave/Desktop/images.bin");
//    const uint8_t* data = mmap.data();
//    const size_t imgCount = 31;
//    
//    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
//    if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
//    Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
//    
//    // Reserve space for `imgCount` additional images
//    {
//        auto lock = std::unique_lock(*imgLib);
//        imgLib->reserve(imgCount);
//    }
//    
//    Img::Id deviceImgIdLast = 0;
//    std::vector<Renderer::Buf> bufs;
//    id<MTLBuffer> chunkBuf = nil;
//    
//    for (size_t idx=0; idx<imgCount; idx++) {
//        const uint8_t* imgData = data+idx*ImgSD::Thumb::ImagePaddedLen;
//        const Img::Header& imgHeader = *(const Img::Header*)imgData;
//        // Accessing `imgLib` without a lock because we're the only entity using the image library's reserved space
//        const auto recordRefIter = imgLib->reservedBegin()+idx;
//        ImageRecord& rec = **recordRefIter;
//        
//        rec.info.id = imgHeader.id;
//        
//        // Render the thumbnail into rec.thumb
//        {
//            const ImagePixel* rawImagePixels = (ImagePixel*)(imgData+Img::PixelsOffset);
//            
////            Renderer::Buf rawImagePixelsBuf = renderer.bufferCreate(rawImagePixels, Img::Thumb::PixelLen);
//            
////        const size_t w = [txt width];
////        const size_t h = [txt height];
////        const size_t len = w*h*samplesPerPixel*sizeof(T);
////        Renderer::Buf buf = bufferCreate(len);
////        memcpy([buf contents], samples, len);
////        textureWrite(txt, buf, samplesPerPixel, bytesPerSample, maxValue);
////            
////            
////            [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data() length:Mmap::PageCeil(chunk.mmap.len()) options:BufOpts deallocator:nil];
//            
//            Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, Img::Thumb::PixelWidth, Img::Thumb::PixelHeight);
////            renderer.textureWrite(rgb, rawImagePixelsBuf, 1, sizeof(*rawImagePixels), ImagePixelMax);
//            
//            renderer.textureWrite(rgb, rawImagePixels, 1, sizeof(*rawImagePixels), ImagePixelMax);
//            
//            const ImageLibrary::Chunk& chunk = *recordRefIter->chunk;
//            const size_t thumbDataOff = (uintptr_t)&rec.thumb - (uintptr_t)chunk.mmap.data();
//            constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//            
//            if (!chunkBuf) {
//                chunkBuf = [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data() length:Mmap::PageCeil(chunk.mmap.len()) options:BufOpts deallocator:nil];
//            }
//            
//            renderer.render(ImageThumb::ThumbWidth, ImageThumb::ThumbHeight,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "RenderThumb::RGB3FromTexture",
//                    // Buffer args
//                    (uint32_t)thumbDataOff,
//                    (uint32_t)ImageThumb::ThumbWidth,
//                    chunkBuf,
//                    // Texture args
//                    rgb
//                )
//            );
//            
////            NSLog(@"%@", @([renderer.cmdBuf() retainedReferences]));
////            [renderer.cmdBuf() enqueue];
////            renderer.commit();
////            txts.push_back(std::move(raw));
////            bufs.push_back(std::move(rawImagePixelsBuf));
//            
//            // Add non-determinism
//            usleep(arc4random_uniform(1000));
//        }
//        
//        deviceImgIdLast = imgHeader.id;
//    }
//    
//    // Make sure all rendering is complete before adding the images to the library
//    renderer.commitAndWait();
//    
//    {
//        auto lock = std::unique_lock(*imgLib);
//        // Add the records that we previously reserved
//        imgLib->add();
//    }
//}










// _openImage: open a particular image id, or an image offset from a particular image id
- (bool)_openImage:(ImageRecordPtr)rec delta:(ssize_t)delta {
    ImageSourcePtr imageSource = [_sourceListView selection];
    if (!imageSource) return false;
    
    ImageLibrary& imageLibrary = imageSource->imageLibrary();
    {
        ImageRecordPtr imageRecord;
        {
            auto lock = std::unique_lock(imageLibrary);
            if (imageLibrary.empty()) return false;
            
            const auto find = imageLibrary.find(rec);
            if (find == imageLibrary.end()) return false;
            
            const ssize_t deltaMin = std::distance(find, imageLibrary.begin());
            const ssize_t deltaMax = std::distance(find, std::prev(imageLibrary.end()));
            if (delta<deltaMin || delta>deltaMax) return false;
            
            imageRecord = *(find+delta);
        }
        
        ImageView* imageView = [[ImageView alloc] initWithImageRecord:imageRecord imageSource:imageSource];
        [imageView setDelegate:self];
        
        ImageScrollView* sv = [[ImageScrollView alloc] initWithFixedDocument:imageView];
        [sv setMagnifyToFit:true animate:false];
        
//        if (delta) {
//            [_mainView setContentView:imageView animation:(delta>0 ? MainViewAnimation::SlideToLeft : MainViewAnimation::SlideToRight)];
//        } else {
//            [_mainView setContentView:imageView animation:MainViewAnimation::None];
//        }
        
        [self setCenterView:sv];
        [[_splitView window] makeFirstResponder:[sv document]];
        
        ImageSet selection;
        selection.insert(imageRecord);
        [_inspectorView setSelection:selection];
        
        printf("Showing image id %ju\n", (uintmax_t)imageRecord->info.id);
        
        return true;
    }
}

// MARK: - ImageGridViewDelegate

- (void)imageGridViewSelectionChanged:(ImageGridView*)imageGridView {
    [_inspectorView setSelection:[imageGridView selection]];
}

- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView {
    const ImageSet selection = [imageGridView selection];
    if (selection.empty()) return;
    const ImageRecordPtr rec = *selection.begin();
    [self _openImage:rec delta:0];
}

// MARK: - ImageViewDelegate

- (void)imageViewPreviousImage:(ImageView*)imageView {
    const bool ok = [self _openImage:[imageView imageRecord] delta:-1];
    if (!ok) NSBeep();
}

- (void)imageViewNextImage:(ImageView*)imageView {
    const bool ok = [self _openImage:[imageView imageRecord] delta:1];
    if (!ok) NSBeep();
}

// MARK: - NSSplitViewDelegate

- (BOOL)splitView:(NSSplitView*)splitView canCollapseSubview:(NSView*)subview {
    return true;
}

@end

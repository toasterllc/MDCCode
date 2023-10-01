#import "DeviceImageGridHeaderView.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    MDCStudio::MDCDevicePtr _device;
    ImageLibrary* _imageLibrary;
    __weak id<DeviceImageGridHeaderViewDelegate> _delegate;
    IBOutlet NSView* _nibView;
    IBOutlet NSLayoutConstraint* _height;
    IBOutlet NSTextField* _statusLabel;
    IBOutlet NSView* _loadPhotosContainerView;
    IBOutlet NSTextField* _loadPhotosCountLabel;
}

- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _device = device;
    _imageLibrary = &_device->imageLibrary();
    
    __weak auto selfWeak = self;
    {
        _device->observerAdd([=] {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _update]; });
            return true;
        });
    }
    
    // Add ourself as an observer of the image library
    {
        auto lock = std::unique_lock(*_imageLibrary);
        _imageLibrary->observerAdd([=](const ImageLibrary::Event& ev) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _update]; });
            return true;
        });
    }
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_nibView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    
    [self _update];
    return self;
}

- (NSSize)intrinsicContentSize {
    return { NSViewNoIntrinsicMetric, [_height constant] };
}

- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

- (void)_update {
    [self _updateStatus];
    [self _updateLoadCount];
}

static NSString* _ImageLibraryStatus(ImageLibrary& imgLib) {
    auto lock = std::unique_lock(imgLib);
    if (imgLib.empty()) return @"No photos";
    
    auto front = imgLib.front();
    auto back = imgLib.back();
    
//    auto tbegin = Time::Clock::to_sys(Time::Clock::TimePointFromTimeInstant(front->info.timestamp));
//    auto tend = Time::Clock::to_sys(Time::Clock::TimePointFromTimeInstant(back->info.timestamp));
    
    
    
    
    
    return [NSString stringWithFormat:@"%ju photos", (uintmax_t)imgLib.recordCount()];
}

- (void)_updateStatus {
    [_statusLabel setStringValue:_ImageLibraryStatus(*_imageLibrary)];
}

- (void)_updateLoadCount {
    const size_t loadCount = _LoadCount(_device);
    if (loadCount) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)loadCount]];
        [_loadPhotosContainerView setHidden:false];
    } else {
        [_loadPhotosContainerView setHidden:true];
    }
}

static size_t _LoadCount(const MDCDevice::Status& status, ImageLibrary& imgLib) {
    auto lock = std::unique_lock(imgLib);
    const Img::Id libImgIdEnd = (!imgLib.empty() ? imgLib.back()->info.id+1 : 0);
    
    // Calculate how many images to add to the end of the library: device has, lib doesn't
    if (libImgIdEnd > status.imgIdEnd) {
        #warning TODO: how do we properly handle this situation?
        throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, status.imgIdEnd: %ju)",
            (uintmax_t)libImgIdEnd,
            (uintmax_t)status.imgIdEnd
        );
    }
    
    return status.imgIdEnd - std::max(status.imgIdBegin, libImgIdEnd);
}

static size_t _LoadCount(MDCDevicePtr device) {
    return _LoadCount(device->status(), device->imageLibrary());
}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end

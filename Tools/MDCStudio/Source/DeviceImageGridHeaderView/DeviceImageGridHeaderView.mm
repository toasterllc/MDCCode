#import "DeviceImageGridHeaderView.h"
#import "date/date.h"
#import "date/tz.h"
#import "Calendar.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    MDCStudio::MDCDevicePtr _device;
    ImageLibrary* _imageLibrary;
    __weak id<DeviceImageGridHeaderViewDelegate> _delegate;
    IBOutlet NSView* _nibView;
    IBOutlet NSLayoutConstraint* _heightConstraint;
    IBOutlet NSLayoutConstraint* _hideLoadPhotosConstraint;
    IBOutlet NSTextField* _statusLabel;
    IBOutlet NSTextField* _loadPhotosCountLabel;
    IBOutlet NSProgressIndicator* _progressIndicator;
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
    return { NSViewNoIntrinsicMetric, [_heightConstraint constant] };
}

- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

static auto _FirstLoaded(ImageLibrary& imgLib) {
    for (auto it=imgLib.begin(); it!=imgLib.end(); it++) {
        if ((*it)->status.loadCount) return it;
    }
    return imgLib.end();
}

static auto _LastLoaded(ImageLibrary& imgLib) {
    for (auto it=imgLib.rbegin(); it!=imgLib.rend(); it++) {
        if ((*it)->status.loadCount) return it;
    }
    return imgLib.rend();
}


static NSString* _ImageLibraryStatus(ImageLibrary& imgLib) {
    using namespace std::chrono;
    
    auto lock = std::unique_lock(imgLib);
    if (imgLib.empty()) return @"No photos";
    
    // itFirst: first loaded record
    auto itFirst = _FirstLoaded(imgLib);
    // No loaded photos yet
    if (itFirst == imgLib.end()) return @"No photos";
    
    // itLast: last loaded record
    auto itLast = _LastLoaded(imgLib);
    
    const auto tFirst = Time::Clock::TimePointFromTimeInstant((*itFirst)->info.timestamp);
    const auto tLast = Time::Clock::TimePointFromTimeInstant((*itLast)->info.timestamp);
    
    const std::string strFirst = Calendar::MonthYearString(tFirst);
    const std::string strLast = Calendar::MonthYearString(tLast);
    const std::string dateDesc = strFirst + (strFirst == strLast ? "" : " – " + strLast);
    return [NSString stringWithFormat:@"%ju photos from %s", (uintmax_t)imgLib.recordCount(), dateDesc.c_str()];
}

static std::optional<size_t> _LoadCount(const MDCDevice::Status& status, ImageLibrary& imgLib) {
    // Short-circut if syncing is in progress.
    // In that case, we don't want to show the 'Load' button in the header
    if (status.sync) return std::nullopt;
    
    {
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
}

//static std::optional<size_t> _LoadCount(const MDCDevice::Status& status MDCDevicePtr device) {
//    return _LoadCount(device->status(), device->imageLibrary());
//}

- (void)_update {
    const MDCDevice::Status status = _device->status();
    
    // Update status
    {
        [_statusLabel setStringValue:_ImageLibraryStatus(*_imageLibrary)];
    }
    
    // Update unloaded photo count
    {
        const std::optional<size_t> loadCount = _LoadCount(status, *_imageLibrary);
        if (loadCount && *loadCount) {
            [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)*loadCount]];
            [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityDefaultLow];
        } else {
            [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityRequired];
        }
    }
    
    // Upload load progress
    {
        const float progress = (status.sync ? status.sync->progress : 0);
        [_progressIndicator setDoubleValue:progress];
    }
}

//- (void)_updateStatus {
//    [_statusLabel setStringValue:_ImageLibraryStatus(*_imageLibrary)];
//}
//
//- (void)_updateLoadCount {
//    const std::optional<size_t> loadCount = _LoadCount(_device);
//    if (loadCount && *loadCount) {
//        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)*loadCount]];
//        [_loadPhotosContainerView setHidden:false];
//    } else {
//        [_loadPhotosContainerView setHidden:true];
//    }
//}
//
//- (void)_updateLoadProgress {
//    [_progressIndicator setDoubleValue:];
//}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end

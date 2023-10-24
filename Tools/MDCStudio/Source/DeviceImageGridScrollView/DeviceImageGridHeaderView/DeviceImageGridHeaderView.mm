#import "DeviceImageGridHeaderView.h"
#import "date/date.h"
#import "date/tz.h"
#import "Calendar.h"
#import "ImageLibraryStatus.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSTextField* _statusLabel;
    IBOutlet NSLayoutConstraint* _hideLoadPhotosConstraint;
    IBOutlet NSTextField* _loadPhotosCountLabel;
    IBOutlet NSProgressIndicator* _progressIndicator;
    IBOutlet NSLayoutConstraint* _heightConstraint;
    MDCDevicePtr _device;
    Object::ObserverPtr _deviceOb;
    Object::ObserverPtr _imageLibraryOb;
}

- (instancetype)initWithDevice:(MDCDevicePtr)device {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    NibViewInit(self, _nibView);
    _device = device;
    
    __weak auto selfWeak = self;
    _deviceOb = _device->observerAdd([=] (const Object::Event& ev) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _update]; });
    });
    
    _imageLibraryOb = _device->imageLibrary()->observerAdd([=] (const Object::Event& ev) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _update]; });
    });
    
    [self _update];
    return self;
}

static std::optional<size_t> _LoadCount(const MDCDevice::Status& status, ImageLibraryPtr imageLibrary) {
    // Short-circut if syncing is in progress.
    // In that case, we don't want to show the 'Load' button in the header
    if (status.syncProgress) return std::nullopt;
    
    {
        auto lock = std::unique_lock(*imageLibrary);
        const Img::Id libImgIdEnd = (!imageLibrary->empty() ? imageLibrary->back()->info.id+1 : 0);
        
        // Calculate how many images to add to the end of the library: device has, lib doesn't
        if (libImgIdEnd > status.imageRange.end) {
            #warning TODO: how do we properly handle this situation?
            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, status.imgIdEnd: %ju)",
                (uintmax_t)libImgIdEnd,
                (uintmax_t)status.imageRange.end
            );
        }
        
        return status.imageRange.end - std::max(status.imageRange.begin, libImgIdEnd);
    }
}

- (void)_update {
    ImageLibraryPtr imageLibrary = _device->imageLibrary();
    const MDCDevice::Status status = _device->status();
    const ImageSet& selection = _device->selection();
    
    // Update status
    if (selection.empty()) {
        [_statusLabel setStringValue:@(ImageLibraryStatus(imageLibrary).c_str())];
    
    } else {
        const Time::Instant first = (*selection.begin())->info.timestamp;
        const Time::Instant last = (*std::prev(selection.end()))->info.timestamp;
        const std::string status = ImageLibraryStatus(selection.size(), first, last,
            "photo selected", "photos selected");
        [_statusLabel setStringValue:@(status.c_str())];
    }
    
    // Update unloaded photo count
    {
        const std::optional<size_t> loadCount = _LoadCount(status, imageLibrary);
        [self _setLoadCount:loadCount.value_or(0)];
    }
    
    // Upload load progress
    {
        const float progress = status.syncProgress.value_or(0);
        [_progressIndicator setDoubleValue:progress];
    }
}

- (size_t)loadCount {
    return _loadCount;
}

- (void)_setLoadCount:(size_t)x {
    if (x) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)x]];
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityDefaultLow];
    } else {
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityRequired];
    }
}

- (IBAction)load:(id)sender {
    _device->sync();
}

- (NSSize)intrinsicContentSize {
    return { NSViewNoIntrinsicMetric, [_heightConstraint constant] };
}

@end

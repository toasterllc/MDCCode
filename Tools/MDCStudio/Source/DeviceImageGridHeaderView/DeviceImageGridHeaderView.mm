#import "DeviceImageGridHeaderView.h"
#import "date/date.h"
#import "date/tz.h"
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
    NSCalendar* cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateFormatter* monthYearFormatter = [[NSDateFormatter alloc] init];
    [monthYearFormatter setLocale:[NSLocale autoupdatingCurrentLocale]];
    [monthYearFormatter setCalendar:cal];
    [monthYearFormatter setTimeZone:[cal timeZone]];
    [monthYearFormatter setLocalizedDateFormatFromTemplate:@"MMMYYYY"];
    [monthYearFormatter setLenient:true];
    
    auto lock = std::unique_lock(imgLib);
    if (imgLib.empty()) return @"No photos";
    
    // itFirst: first loaded record
    auto itFirst = _FirstLoaded(imgLib);
    // No loaded photos yet
    if (itFirst == imgLib.end()) return @"No photos";
    
    // itLast: last loaded record
    auto itLast = _LastLoaded(imgLib);
    
    auto refFirst = *itFirst;
    auto refLast = *itLast;
    
    auto tFirst = date::clock_cast<system_clock>(Time::Clock::TimePointFromTimeInstant(refFirst->info.timestamp));
    auto tLast = date::clock_cast<system_clock>(Time::Clock::TimePointFromTimeInstant(refLast->info.timestamp));
    
    const milliseconds msFirst = duration_cast<milliseconds>(tFirst.time_since_epoch());
    const milliseconds msLast = duration_cast<milliseconds>(tLast.time_since_epoch());
    
    NSDate* dateFirst = [NSDate dateWithTimeIntervalSince1970:(double)msFirst.count()/1000.];
    NSDate* dateLast = [NSDate dateWithTimeIntervalSince1970:(double)msLast.count()/1000.];
    
    NSString* strFirst = [monthYearFormatter stringFromDate:dateFirst];
    NSString* strLast = [monthYearFormatter stringFromDate:dateLast];
    
    NSString* dateDesc = nil;
    
    if ([strFirst isEqualToString:strLast]) {
        // Same month and year
        dateDesc = strFirst;
    } else {
        // Different month/year
        dateDesc = [NSString stringWithFormat:@"%@ – %@", strFirst, strLast];
    }
    
    return [NSString stringWithFormat:@"%ju photos from %@", (uintmax_t)imgLib.recordCount(), dateDesc];
}

static std::optional<size_t> _LoadCount(const MDCDevice::Status& status, ImageLibrary& imgLib) {
    if (status.syncing) return std::nullopt;
    
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

static std::optional<size_t> _LoadCount(MDCDevicePtr device) {
    return _LoadCount(device->status(), device->imageLibrary());
}

- (void)_updateStatus {
    [_statusLabel setStringValue:_ImageLibraryStatus(*_imageLibrary)];
}

- (void)_updateLoadCount {
    const std::optional<size_t> loadCount = _LoadCount(_device);
    if (loadCount && *loadCount) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)*loadCount]];
        [_loadPhotosContainerView setHidden:false];
    } else {
        [_loadPhotosContainerView setHidden:true];
    }
}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end

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
    
//    auto front = imgLib.front();
//    auto back = imgLib.back();
    
    auto itBegin = std::upper_bound(imgLib.begin(), imgLib.end(), 0,
        [&](auto, const auto& x) -> bool {
            return x->status.loadCount > 0;
        });
    
    auto itEnd = std::lower_bound(imgLib.begin(), imgLib.end(), 0,
        [&](const auto& x, auto) -> bool {
            return x->status.loadCount > 0;
        });
    
    auto refBegin = *itBegin;
    auto refEnd = *std::prev(itEnd);
    
    auto tbegin = Time::Clock::to_sys(Time::Clock::TimePointFromTimeInstant(refBegin->info.timestamp));
    auto tend = Time::Clock::to_sys(Time::Clock::TimePointFromTimeInstant(refEnd->info.timestamp));
    
    auto ymdBegin = date::year_month_day(std::chrono::floor<date::days>(tbegin));
    auto ymdEnd = date::year_month_day(std::chrono::floor<date::days>(tend));
    
    const milliseconds msBegin = duration_cast<milliseconds>(tbegin.time_since_epoch());
    const milliseconds msEnd = duration_cast<milliseconds>(tend.time_since_epoch());
    
    NSDate* dateBegin = [NSDate dateWithTimeIntervalSince1970:(double)msBegin.count()/1000.];
    NSDate* dateEnd = [NSDate dateWithTimeIntervalSince1970:(double)msEnd.count()/1000.];
    
    NSString* strBegin = [monthYearFormatter stringFromDate:dateBegin];
    NSString* strEnd = [monthYearFormatter stringFromDate:dateEnd];
    
    NSString* dateDesc = nil;
    if (ymdBegin.year()==ymdEnd.year() && ymdBegin.month()==ymdEnd.month()) {
        // Same month and year
        dateDesc = strBegin;
    } else {
        // Different month/year
        dateDesc = [NSString stringWithFormat:@"%@ – %@", strBegin, strEnd];
    }
    
    return [NSString stringWithFormat:@"%ju photos from %@", (uintmax_t)imgLib.recordCount(), dateDesc];
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

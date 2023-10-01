#import "DeviceImageGridHeaderView.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    MDCStudio::MDCDevicePtr _device;
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
    __weak auto selfWeak = self;
    _device->observerAdd([=] {
        auto selfStrong = selfWeak;
        if (!selfStrong) return false;
        dispatch_async(dispatch_get_main_queue(), ^{ [selfStrong deviceChanged]; });
        return true;
    });
    
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_nibView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    
    [self setLoadCount:0];
    return self;
}

- (NSSize)intrinsicContentSize {
    return { NSViewNoIntrinsicMetric, [_height constant] };
}

- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

- (void)setLoadCount:(NSUInteger)x {
    if (x) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%@", @(x)]];
        [_loadPhotosContainerView setHidden:false];
    } else {
        [_loadPhotosContainerView setHidden:true];
    }
}

- (void)setStatus:(NSString*)status {
    [_statusLabel setStringValue:status];
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

- (void)deviceChanged {
    [self setLoadCount:_LoadCount(_device)];
    printf("DeviceImageGridHeaderView: deviceChanged\n");
}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end

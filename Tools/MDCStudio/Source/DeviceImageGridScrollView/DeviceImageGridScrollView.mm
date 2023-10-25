#import "DeviceImageGridScrollView.h"
#import "DeviceImageGridHeaderView/DeviceImageGridHeaderView.h"
#import "ImageLibraryStatus.h"
#import "date/date.h"
#import "date/tz.h"
#import "Calendar.h"
using namespace MDCStudio;

@implementation DeviceImageGridScrollView {
    IBOutlet NSView* _noPhotosView;
    IBOutlet NSButton* _configureDeviceButton;
    
    MDCDevicePtr _device;
    ImageSelectionPtr _selection;
    
    Object::ObserverPtr _deviceOb;
    Object::ObserverPtr _imageLibraryOb;
    Object::ObserverPtr _selectionOb;
    
    ImageGridView* _imageGridView;
    DeviceImageGridHeaderView* _headerView;
}

- (instancetype)initWithDevice:(MDCDevicePtr)device selection:(ImageSelectionPtr)selection {
    _imageGridView = [[ImageGridView alloc] initWithImageSource:device selection:selection];
    if (!(self = [super initWithFixedDocument:_imageGridView])) return nil;
    
    _device = device;
    _selection = selection;
    
    __weak auto selfWeak = self;
    _deviceOb = _device->observerAdd([=] (auto, const Object::Event& ev) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _refresh]; });
    });
    
    _imageLibraryOb = _device->imageLibrary()->observerAdd([=] (auto, const Object::Event& ev) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _refresh]; });
    });
    
    _selectionOb = _selection->observerAdd([=] (auto, const Object::Event& ev) {
        assert([NSThread isMainThread]);
        [selfWeak _refresh];
    });
    
    _headerView = [[DeviceImageGridHeaderView alloc] initWithFrame:{}];
    [[_headerView loadButton] setTarget:self];
    [[_headerView loadButton] setAction:@selector(_load:)];
    [self setHeaderView:_headerView];
    
    {
        bool br = [[[NSNib alloc] initWithNibNamed:@"DeviceImageGridNoPhotosView" bundle:nil]
            instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        [[self floatingSubviewContainer] addSubview:_noPhotosView];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_noPhotosView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_noPhotosView)]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_noPhotosView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_noPhotosView)]];
    }
    
    [self _refresh];
    return self;
}

// _update is a private method used by NSScrollView!
// We're naming this _refresh instead...
- (void)_refresh {
    ImageLibraryPtr imageLibrary = _device->imageLibrary();
    const MDCDevice::Status status = _device->status();
    const ImageSet& selection = _selection->images();
    
    // Update status
    if (selection.empty()) {
        [_headerView setStatus:@(ImageLibraryStatus(imageLibrary).c_str())];
    
    } else {
        const Time::Instant first = (*selection.begin())->info.timestamp;
        const Time::Instant last = (*std::prev(selection.end()))->info.timestamp;
        const std::string status = ImageLibraryStatus(selection.size(), first, last,
            "photo selected", "photos selected");
        [_headerView setStatus:@(status.c_str())];
    }
    
    // Update unloaded photo count
    const size_t loadCount = (!status.syncProgress ? status.loadImageCount : 0);
    {
        [_headerView setLoadCount:loadCount];
    }
    
    // Upload load progress
    {
        [_headerView setProgress:status.syncProgress.value_or(0)];
    }
    
    // Update our 'no photos' state
    {
        auto lock = std::unique_lock(*_device->imageLibrary());
        const bool noPhotos = _device->imageLibrary()->empty();
        [_headerView setHidden:noPhotos];
        [_noPhotosView setHidden:!noPhotos];
    }
}

// MARK: - UI Actions

- (IBAction)_load:(id)sender {
    _device->sync();
}

- (NSButton*)configureDeviceButton {
    return _configureDeviceButton;
}

@end

#import "DeviceImageGridScrollView.h"
#import "DeviceImageGridHeaderView/DeviceImageGridHeaderView.h"
using namespace MDCStudio;

@implementation DeviceImageGridScrollView {
    IBOutlet NSView* _noPhotosView;
    
    MDCDevicePtr _device;
    Object::ObserverPtr _imageLibraryOb;
    
    ImageGridView* _imageGridView;
    DeviceImageGridHeaderView* _headerView;
}

- (instancetype)initWithDevice:(MDCDevicePtr)device {
    _imageGridView = [[ImageGridView alloc] initWithImageSource:device];
    if (!(self = [super initWithFixedDocument:_imageGridView])) return nil;
    
    _device = device;
    
    __weak auto selfWeak = self;
    _imageLibraryOb = _device->imageLibrary()->observerAdd([=] (const Object::Event& ev) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _updateNoPhotosState]; });
    });
    
    _headerView = [[DeviceImageGridHeaderView alloc] initWithDevice:_device];
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
    
    [self _updateNoPhotosState];
    return self;
}

- (void)_updateNoPhotosState {
    const bool noPhotos = _device->imageLibrary()->empty() && ;
    auto lock = std::unique_lock(*_device->imageLibrary());
    [_headerView setHidden:_device->imageLibrary()->empty()];
    [_noPhotosView setHidden:!_device->imageLibrary()->empty()];
}

- (IBAction)_configureDevice:(id)sender {
    
}

@end

#import "DeviceImageGridScrollView.h"
#import "DeviceImageGridHeaderView/DeviceImageGridHeaderView.h"

@implementation DeviceImageGridScrollView {
    IBOutlet NSView* _noPhotosView;
    
    ImageGridView* _imageGridView;
    DeviceImageGridHeaderView* _headerView;
}

- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device {
    _imageGridView = [[ImageGridView alloc] initWithImageSource:device];
    if (!(self = [super initWithFixedDocument:_imageGridView])) return nil;
    
    _headerView = [[DeviceImageGridHeaderView alloc] initWithFrame:{}];
    [self setHeaderView:_headerView];
    
    {
        bool br = [[[NSNib alloc] initWithNibNamed:@"DeviceImageGridNoPhotosView" bundle:nil]
            instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        [self addSubview:_noPhotosView];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[_noPhotosView]"
            options:NSLayoutFormatAlignAllCenterX metrics:nil views:NSDictionaryOfVariableBindings(_noPhotosView)]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[_noPhotosView]"
            options:NSLayoutFormatAlignAllCenterY metrics:nil views:NSDictionaryOfVariableBindings(_noPhotosView)]];
    }
    
    return self;
}

- (IBAction)_configureDevice:(id)sender {
    
}

@end

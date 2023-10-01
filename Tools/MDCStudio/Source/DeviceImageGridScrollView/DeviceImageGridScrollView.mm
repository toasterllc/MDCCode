#import "DeviceImageGridScrollView.h"
#import "DeviceImageGridHeaderView/DeviceImageGridHeaderView.h"

@implementation DeviceImageGridScrollView {
    ImageGridView* _imageGridView;
    DeviceImageGridHeaderView* _headerView;
}

- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device {
    _imageGridView = [[ImageGridView alloc] initWithImageSource:device];
    
    if (!(self = [super initWithFixedDocument:_imageGridView])) return nil;
    
    _headerView = [[DeviceImageGridHeaderView alloc] initWithDevice:device];
    [self setHeaderView:_headerView];
    
    return self;
}

- (ImageGridView*)imageGridView {
    return _imageGridView;
}

- (DeviceImageGridHeaderView*)headerView {
    return _headerView;
}

@end

#import "DeviceImageGridHeaderView.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSTextField* _statusLabel;
    IBOutlet NSLayoutConstraint* _hideLoadPhotosConstraint;
    IBOutlet NSTextField* _loadPhotosCountLabel;
    IBOutlet NSButton* _loadButton;
    IBOutlet NSProgressIndicator* _progressIndicator;
    IBOutlet NSLayoutConstraint* _heightConstraint;
//    MDCDevicePtr _device;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
//    _device = device;
    return self;
}

//- (IBAction)load:(id)sender {
//    _device->sync();
//}

- (NSSize)intrinsicContentSize {
    return { NSViewNoIntrinsicMetric, [_heightConstraint constant] };
}

- (void)setStatus:(NSString*)x {
    [_statusLabel setStringValue:x];
}

- (void)setLoadCount:(size_t)x {
    if (x) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)x]];
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityDefaultLow];
    } else {
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityRequired];
    }
}

- (NSButton*)loadButton {
    return _loadButton;
}

- (void)setProgress:(float)x {
    [_progressIndicator setDoubleValue:x];
}

@end

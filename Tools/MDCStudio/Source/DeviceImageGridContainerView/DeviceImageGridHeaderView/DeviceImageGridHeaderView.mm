#import "DeviceImageGridHeaderView.h"
#import "NibViewInit.h"
#import "ProgressBar.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSTextField* _statusLabel;
    IBOutlet NSLayoutConstraint* _hideLoadPhotosConstraint;
    IBOutlet NSTextField* _loadPhotosCountLabel;
    IBOutlet NSButton* _loadButton;
    IBOutlet ProgressBar* _progressBar;
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

- (void)mouseDown:(NSEvent*)event {
    [[self window] performWindowDragWithEvent:event];
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
    [_progressBar setProgress:x];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSView* contentView = [[self window] contentView];
    if (!contentView) return;
    NSLayoutConstraint* windowLeftMin = [NSLayoutConstraint constraintWithItem:_statusLabel
        attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationGreaterThanOrEqual
        toItem:contentView attribute:NSLayoutAttributeLeft multiplier:1 constant:75];
    [windowLeftMin setActive:true];
}

@end

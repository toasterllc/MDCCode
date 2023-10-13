#import "DeviceImageGridHeaderView.h"
#import "date/date.h"
#import "date/tz.h"
#import "Calendar.h"
#import "ImageLibraryStatus.h"
using namespace MDCStudio;

@implementation DeviceImageGridHeaderView {
    __weak id<DeviceImageGridHeaderViewDelegate> _delegate;
    IBOutlet NSLayoutConstraint* _hideLoadPhotosConstraint;
    IBOutlet NSTextField* _loadPhotosCountLabel;
    IBOutlet NSProgressIndicator* _progressIndicator;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setLoadCount:0];
    return self;
}

- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

- (void)setLoadCount:(size_t)x {
    if (x) {
        [_loadPhotosCountLabel setStringValue:[NSString stringWithFormat:@"%ju", (uintmax_t)x]];
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityDefaultLow];
    } else {
        [_hideLoadPhotosConstraint setPriority:NSLayoutPriorityRequired];
    }
}

- (void)setProgress:(float)x {
    [_progressIndicator setDoubleValue:x];
}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end

#import "ImageExportProgressDialog.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation ImageExportProgressDialog {
    IBOutlet NSWindow* _window;
    IBOutlet NSTextField* _message;
    IBOutlet NSProgressIndicator* _progressBar;
    std::atomic<bool> _canceled;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [self setProgress:0];
    
    return self;
}

- (NSWindow*)window {
    return _window;
}

- (void)setImageCount:(size_t)x {
    [_message setStringValue:[NSString stringWithFormat:@"Exporting %ju photos…", (uintmax_t)x]];
}

- (void)setProgress:(float)x {
    [_progressBar setDoubleValue:x];
}

- (IBAction)_cancel:(id)sender {
    [[_window sheetParent] endSheet:_window returnCode:NSModalResponseCancel];
    _canceled = true;
}

- (const std::atomic<bool>&)canceled {
    return _canceled;
}

@end

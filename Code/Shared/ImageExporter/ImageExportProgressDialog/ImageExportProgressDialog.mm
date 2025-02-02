#import "ImageExportProgressDialog.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation ImageExportProgressDialog {
    IBOutlet NSWindow* _window;
    IBOutlet NSTextField* _message;
    IBOutlet NSProgressIndicator* _progressBar;
    __weak NSWindow* _parentWindow;
    size_t _imageCountTotal;
    size_t _imageCountProgress;
    std::atomic<bool> _shown;
    std::atomic<bool> _canceled;
}

- (instancetype)initWithParentWindow:(NSWindow*)parentWindow imageCount:(size_t)imageCount {
    if (imageCount < 4) return nil;
    if (!(self = [super init])) return nil;
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    _parentWindow = parentWindow;
    _imageCountTotal = imageCount;
    [_message setStringValue:[NSString stringWithFormat:@"Exporting %ju photos…", (uintmax_t)_imageCountTotal]];
    [self _setProgress:0];
    return self;
}

- (NSWindow*)window {
    return _window;
}

- (void)showIfNeeded {
    if (_shown) return;
    
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showIfNeeded]; });
        return;
    }
    
    _shown = true;
    [_parentWindow beginSheet:_window completionHandler:nil];
}

- (void)incrementProgress {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self incrementProgress]; });
        return;
    }
    
    assert(_imageCountProgress < _imageCountTotal);
    _imageCountProgress++;
    [self _setProgress:(float)_imageCountProgress/_imageCountTotal];
    if (_imageCountProgress == _imageCountTotal) {
        [[_window sheetParent] endSheet:_window];
    }
}

- (void)_setProgress:(float)x {
    [_progressBar setDoubleValue:x];
}

- (IBAction)_cancel:(id)sender {
    [self cancel];
}

- (void)cancel {
    if (_canceled) return;
    
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancel]; });
        return;
    }
    
    [[_window sheetParent] endSheet:_window returnCode:NSModalResponseCancel];
    _canceled = true;
}

- (bool)canceled {
    return _canceled;
}

@end

#import "ImageExportDialog.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@interface ImageExportDialogFileTypesView : NSView
@end

@implementation ImageExportDialogFileTypesView {
    IBOutlet NSView* _nibView;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
    return self;
}

@end

@implementation ImageExportDialog

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask
    backing:(NSBackingStoreType)backing defer:(BOOL)defer {
    
    if (!(self = [super initWithContentRect:contentRect styleMask:styleMask backing:backing defer:defer])) {
        return nil;
    }
    
    [self setAllowedFileTypes:@[@"jpg", @"png"]];
    return self;
}

- (void)show:(NSWindow*)window {
    __weak auto selfWeak = self;
    [self beginSheetModalForWindow:window completionHandler:^(NSInteger result) {
        if (result != NSModalResponseOK) return;
        [selfWeak _export];
    }];
}

- (void)_export {
    NSString* path = [[self URL] path];
    NSLog(@"Export to: %@", path);
}

@end

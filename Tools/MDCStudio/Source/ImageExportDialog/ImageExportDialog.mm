#import "ImageExportDialog.h"
#import "NibViewInit.h"
#import "Prefs.h"
using namespace MDCStudio;

@interface ImageExportDialogFileTypesView : NSView
@end

@implementation ImageExportDialogFileTypesView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSPopUpButton* _formatMenu;
    __weak id _dialog;
}

struct _Format {
    const char* name;
    const char* extension;
};

static _Format _Formats[] = {
    { "JPEG", "jpg" },
    { "PNG",  "png" },
};

static const char* ImageExportFormatKey = "ImageExportFormat";

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
    [_formatMenu removeAllItems];
    for (const _Format& fmt : _Formats) {
        [_formatMenu addItemWithTitle:@(fmt.name)];
    }
    [_formatMenu selectItemWithTitle:@(PrefsGlobal()->get(ImageExportFormatKey, _Formats[0].name))];
    return self;
}

- (size_t)formatIndex {
    return [_formatMenu indexOfSelectedItem];
}

- (IBAction)_formatChanged:(id)sender {
    PrefsGlobal()->set(ImageExportFormatKey, _Formats[[self formatIndex]].name);
    [_dialog _formatChanged:sender];
}

@end

@implementation ImageExportDialog {
    ImageExportDialogFileTypesView* _formatsView;
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask
    backing:(NSBackingStoreType)backing defer:(BOOL)defer {
    
    if (!(self = [super initWithContentRect:contentRect styleMask:styleMask backing:backing defer:defer])) {
        return nil;
    }
    
    _formatsView = [[ImageExportDialogFileTypesView alloc] initWithFrame:{}];
    _formatsView->_dialog = self;
    [self setAccessoryView:_formatsView];
    [self _updateFormat];
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
    
}

- (void)_updateFormat {
    const _Format& format = _Formats[[_formatsView formatIndex]];
    [self setAllowedFileTypes:@[@(format.extension)]];
}

- (IBAction)_formatChanged:(id)sender {
    [self _updateFormat];
}

@end

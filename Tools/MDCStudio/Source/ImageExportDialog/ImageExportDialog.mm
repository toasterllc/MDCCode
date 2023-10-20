#import "ImageExportDialog.h"
#import "NibViewInit.h"
#import "Prefs.h"
#import "ImageExporter/ImageExporter.h"
using namespace MDCStudio;

@interface ImageExportDialogFileTypesView : NSView
@end

using _FormatChangedHandler = void(^)();

@implementation ImageExportDialogFileTypesView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSPopUpButton* _formatMenu;
    __weak NSSavePanel* _panel;
}

static const char* ImageExportFormatKey = "ImageExportFormat";

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
    [_formatMenu removeAllItems];
    for (const ImageExporter::Format* fmt : ImageExporter::Formats) {
        [_formatMenu addItemWithTitle:@(fmt->name)];
    }
    [_formatMenu selectItemWithTitle:@(PrefsGlobal()->get(ImageExportFormatKey, ImageExporter::FormatJPEG.name))];
    return self;
}

- (const ImageExporter::Format*)_format {
    return ImageExporter::Formats[[_formatMenu indexOfSelectedItem]];
}

- (void)_updateFormat {
    if (![_panel isKindOfClass:[NSOpenPanel class]]) {
        [_panel setAllowedFileTypes:@[@([self _format]->extension)]];
    }
}

- (IBAction)_formatChanged:(id)sender {
    PrefsGlobal()->set(ImageExportFormatKey, [self _format]->name);
    [self _updateFormat];
}

@end

//@implementation ImageExportDialog {
//    NSSavePanel* _panel;
//    ImageExportDialogFileTypesView* _formatsView;
//}
//
////- (instancetype)init {
////    if (!(self = [super init])) return nil;
////    _panel = [NSSavePanel new];
////    
////    _formatsView = [[ImageExportDialogFileTypesView alloc] initWithFrame:{}];
////    _formatsView->_dialog = self;
////    [_panel setAccessoryView:_formatsView];
////    [_panel _updateFormat];
////    
////    return self;
////}
//
//- (void)show:(NSWindow*)window batch:(bool)batch handler:(ImageExportDialogHandler)handler {
//    
//    _panel = [NSSavePanel new];
//    
//    _formatsView = [[ImageExportDialogFileTypesView alloc] initWithFrame:{}];
//    _formatsView->_formatChangedHandler = {
//        
//    };
//    
//    
//    _formatsView->_dialog = self;
//    [_panel setAccessoryView:_formatsView];
//    [_panel _updateFormat];
//    
//    
//    [self setAllowedFileTypes:@[]];
//    __weak auto selfWeak = self;
//    [self beginSheetModalForWindow:window completionHandler:^(NSInteger result) {
//        if (result != NSModalResponseOK) return;
//        [selfWeak _export];
//    }];
//    
//    
//}
//
//- (void)_export {
//    NSString* path = [[self URL] path];
//    
//}
//
//- (void)_updateFormat {
//    const _Format& format = _Formats[[_formatsView formatIndex]];
//    [self setAllowedFileTypes:@[@(format.extension)]];
//}
//
//- (IBAction)_formatChanged:(id)sender {
//    [self _updateFormat];
//}
//
//@end

namespace MDCStudio::ImageExportDialog {

std::optional<Result> Run(NSWindow* window, bool batch, NSString* filename) {
    NSSavePanel* panel = nil;
    if (batch) {
        panel = [NSOpenPanel new];
    } else {
        panel = [NSSavePanel new];
    }
    
    ImageExportDialogFileTypesView* formatsView = [[ImageExportDialogFileTypesView alloc] initWithFrame:{}];
    formatsView->_panel = panel;
    [formatsView _updateFormat];
    [panel setAccessoryView:formatsView];
    [panel setCanCreateDirectories:true];
    
    if (batch) {
        NSOpenPanel* openPanel = (NSOpenPanel*)panel;
        [openPanel setAccessoryViewDisclosed:true];
        [openPanel setCanChooseDirectories:true];
        [openPanel setCanChooseFiles:false];
        [openPanel setPrompt:@"Choose"];
        [openPanel setMessage:@"Choose the directory to contain the exported images."];
    } else {
        [panel setNameFieldStringValue:filename];
    }
    
//    __weak auto panelWeak = panel;
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        [NSApp stopModalWithCode:result];
    }];
    
    const NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) return std::nullopt;
    return Result{
        .format = [formatsView _format],
        .path = [[panel URL] path],
    };
}


} // namespace MDCStudio::ImageExportDialog

#import "ImageExportSaveDialog.h"
#import "NibViewInit.h"
#import "Shared/ImageExporter/ImageExporter.h"
#import "Shared/PrefsUtil.h"
using namespace MDCStudio;

@interface ImageExportSaveDialogFileTypesView : NSView
@end

using _FormatChangedHandler = void(^)();

@implementation ImageExportSaveDialogFileTypesView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSPopUpButton* _formatMenu;
    __weak NSSavePanel* _panel;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
    [_formatMenu removeAllItems];
    for (const ImageExporter::Format* fmt : ImageExporter::Formats::All) {
        [_formatMenu addItemWithTitle:@(fmt->name)];
    }
    [_formatMenu selectItemWithTitle:@(PrefsUtil::PreviousImageExportFormat())];
    return self;
}

- (const ImageExporter::Format*)_format {
    return ImageExporter::Formats::All[[_formatMenu indexOfSelectedItem]];
}

- (void)_updateFormat {
    if (![_panel isKindOfClass:[NSOpenPanel class]]) {
        [_panel setAllowedFileTypes:@[@([self _format]->extension)]];
    }
}

- (IBAction)_formatChanged:(id)sender {
    PrefsUtil::PreviousImageExportFormat([self _format]->name);
    [self _updateFormat];
}

@end

namespace MDCStudio::ImageExportSaveDialog {

void Show(NSWindow* window, bool batch, NSString* filename, Handler handler) {
    NSSavePanel* panel = nil;
    if (batch) {
        panel = [NSOpenPanel new];
    } else {
        panel = [NSSavePanel new];
    }
    
    ImageExportSaveDialogFileTypesView* formatsView = [[ImageExportSaveDialogFileTypesView alloc] initWithFrame:{}];
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
    
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        handler({
            .format = [formatsView _format],
            .path = [[panel URL] path],
        });
    }];
}


} // namespace MDCStudio::ImageExportSaveDialog

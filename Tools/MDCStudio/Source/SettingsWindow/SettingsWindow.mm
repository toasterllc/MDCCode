#import "SettingsWindow.h"
#import "NibViewInit.h"
#import "ImageCorner/ImageCornerButton.h"
#import "PrefsUtil.h"

using namespace MDCStudio;

@implementation SettingsWindow {
    // General
    IBOutlet ImageCornerButton* _timestampCornerButton;
    
    // Drag and Drop
    IBOutlet NSPopUpButton* _dragAndDropExportFormatMenu;
}

- (instancetype)init {
    NSArray* objects = nil;
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:nil topLevelObjects:&objects];
    assert(br);
    for (id obj : objects) {
        if ([obj isKindOfClass:[self class]]) return obj;
    }
    abort();
}

- (void)awakeFromNib {
    [_dragAndDropExportFormatMenu removeAllItems];
    for (const ImageExporter::Format* fmt : ImageExporter::Formats::All) {
        [_dragAndDropExportFormatMenu addItemWithTitle:@(fmt->name)];
    }
    
    [_timestampCornerButton setCorner:PrefsUtil::Timestamp::Corner()];
    [_dragAndDropExportFormatMenu selectItemWithTitle:@(PrefsUtil::DragAndDrop::ExportFormat()->name)];
}

- (IBAction)action_timestampCorner:(id)sender {
    PrefsUtil::Timestamp::Corner([_timestampCornerButton corner]);
}

- (IBAction)action_dragAndDrop_exportFormatMenu:(id)sender {
    const ImageExporter::Format* fmt = ImageExporter::Formats::FormatForName(
        [[_dragAndDropExportFormatMenu titleOfSelectedItem] UTF8String]);
    PrefsUtil::DragAndDrop::ExportFormat(fmt);
}

@end

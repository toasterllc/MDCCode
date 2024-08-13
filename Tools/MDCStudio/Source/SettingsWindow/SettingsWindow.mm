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
    IBOutlet NSButton* _includeTimestampCheckbox;
}

- (instancetype)init {
    NSArray* objects = nil;
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:nil topLevelObjects:&objects];
    assert(br);
    for (id obj : objects) {
        if ([obj isKindOfClass:[self class]]) {
            [obj _load];
            return obj;
        }
    }
    abort();
}

- (void)_load {
    [_dragAndDropExportFormatMenu removeAllItems];
    for (const ImageExporter::Format* fmt : ImageExporter::Formats::All) {
        [_dragAndDropExportFormatMenu addItemWithTitle:@(fmt->name)];
    }
    
    [_timestampCornerButton setCorner:PrefsUtil::TimestampImageCorner()];
    [_dragAndDropExportFormatMenu selectItemWithTitle:@(PrefsUtil::DragAndDropExportFormat())];
    [_includeTimestampCheckbox setState:(PrefsUtil::DragAndDropIncludeTimestamp() ? NSControlStateValueOn : NSControlStateValueOff)];
}

- (IBAction)action_timestampCorner:(id)sender {
    PrefsUtil::TimestampImageCorner([_timestampCornerButton corner]);
}

- (IBAction)action_dragAndDropExportFormatMenu:(id)sender {
    PrefsUtil::DragAndDropExportFormat([[_dragAndDropExportFormatMenu titleOfSelectedItem] UTF8String]);
}

- (IBAction)action_includeTimestamp:(id)sender {
    PrefsUtil::DragAndDropIncludeTimestamp([_includeTimestampCheckbox state]==NSControlStateValueOn);
}

@end

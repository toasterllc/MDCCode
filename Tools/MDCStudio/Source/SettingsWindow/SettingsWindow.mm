#import "SettingsWindow.h"
#import "Shared/ImageCorner/ImageCornerButton.h"
#import "Shared/PrefsUtil.h"

using namespace MDCStudio;

@implementation SettingsWindow {
    // General
    IBOutlet ImageCornerButton* _timestampCornerButton;
    IBOutlet NSPopUpButton* _dragAndDropExportFormatMenu;
    
    // Advanced
    IBOutlet NSPopUpButton* _cachedImageSizeMenu;
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

static NSString* _StringForDescriptor(const ImageLibrary::Descriptor& desc) {
    constexpr size_t ImageLibraryRecordCount = 20197;
    const size_t bytes = ImageLibrary::RecordSizeForDescriptor(desc) * ImageLibraryRecordCount;
    const size_t mb = bytes / (1024*1024);
//    return [NSString stringWithFormat:@"%s (%ju x %ju, %ju MB)",
//        desc.name, (uintmax_t)desc.thumbWidth, (uintmax_t)desc.thumbHeight, (uintmax_t)mb];
    
    return [NSString stringWithFormat:@"%s (%ju MB)", desc.name, (uintmax_t)mb];
}

- (void)_cachedImageSizeMenuUpdate {
    [_cachedImageSizeMenu selectItemWithTag:PrefsUtil::ImageLibraryDescriptor().thumbWidth];
}

- (void)awakeFromNib {
    // _timestampCornerButton
    {
        [_timestampCornerButton setCorner:PrefsUtil::Timestamp::Corner()];
    }
    
    // _dragAndDropExportFormatMenu
    {
        [_dragAndDropExportFormatMenu removeAllItems];
        for (const ImageExporter::Format* fmt : ImageExporter::Formats::All) {
            [_dragAndDropExportFormatMenu addItemWithTitle:@(fmt->name)];
        }
        [_dragAndDropExportFormatMenu selectItemWithTitle:@(PrefsUtil::DragAndDrop::ExportFormat().name)];
    }
    
    // _cachedImageSizeMenu
    {
        [_cachedImageSizeMenu removeAllItems];
        for (const ImageLibrary::Descriptor* desc : ImageLibrary::Descriptors::All) {
            [_cachedImageSizeMenu addItemWithTitle:_StringForDescriptor(*desc)];
            [[_cachedImageSizeMenu lastItem] setTag:desc->thumbWidth];
        }
        [self _cachedImageSizeMenuUpdate];
    }
}

- (IBAction)action_timestampCorner:(id)sender {
    PrefsUtil::Timestamp::Corner([_timestampCornerButton corner]);
}

- (IBAction)action_dragAndDropFormatMenu:(id)sender {
    const ImageExporter::Format& fmt = ImageExporter::Formats::FormatForName(
        [[_dragAndDropExportFormatMenu titleOfSelectedItem] UTF8String]);
    PrefsUtil::DragAndDrop::ExportFormat(fmt);
}

- (IBAction)action_cachedImageSizeMenu:(id)sender {
    NSAlert* alert = [NSAlert new];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert setMessageText:@"Photo adjustments will be lost"];
    
    [alert setInformativeText:@"This will cause your photo library to be rebuilt.\n\nAll photos will revert to their default appearance; any modifications (such as exposure or contrast adjustments) will be lost!"];
    
    {
        NSButton* button = [alert addButtonWithTitle:@"Cancel"];
        [button setTag:NSModalResponseCancel];
        [button setKeyEquivalent:@"\r"];
    }
    
    {
        NSButton* button = [alert addButtonWithTitle:@"Continue"];
        [button setTag:NSModalResponseOK];
    }
    
    [alert beginSheetModalForWindow:self completionHandler:^(NSModalResponse r) {
        [self _cachedImageSizeAlertFinished:r];
    }];
}

- (void)_cachedImageSizeAlertFinished:(NSModalResponse)resp {
    switch (resp) {
    case NSModalResponseOK: {
        const ImageLibrary::Descriptor& desc = ImageLibrary::DescriptorFromThumbWidth([[_cachedImageSizeMenu selectedItem] tag]);
        PrefsUtil::ImageLibraryDescriptor(desc);
        break;
    }
    
    case NSModalResponseCancel: {
        break;
    }
    
    default: abort();
    }
    
    [self _cachedImageSizeMenuUpdate];
}

@end

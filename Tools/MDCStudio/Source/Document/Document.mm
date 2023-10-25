#import "Document.h"
#import <algorithm>
#import "Toastbox/Cast.h"
#import "SourceListView/SourceListView.h"
#import "InspectorView/InspectorView.h"
#import "ImageGridView/ImageGridView.h"
#import "FullSizeImageView/FullSizeImageView.h"
#import "FixedScrollView.h"
#import "MockImageSource.h"
#import "Prefs.h"
#import "ImageLibraryStatus.h"
#import "DeviceSettings/DeviceSettingsView.h"
#import "DeviceImageGridScrollView/DeviceImageGridScrollView.h"
#import "FactoryResetConfirmationAlert/FactoryResetConfirmationAlert.h"
#import "ImageExporter/ImageExporter.h"
#import "MDCDevicesManager.h"

using namespace MDCStudio;

@interface Document () <NSSplitViewDelegate, SourceListViewDelegate, DeviceSettingsViewDelegate>
@end

@implementation Document {
    IBOutlet NSSplitView* _splitView;
    IBOutlet NSView* _noDevicesView;
    NSWindow* _window;
    Object::ObserverPtr _devicesOb;
    Object::ObserverPtr _prefsOb;
    
    SourceListView* _sourceListView;
    
    struct {
        NSView* containerView;
        NSView* view;
    } _left;
    
    struct {
        NSView* containerView;
        NSView* view;
    } _center;
    
    struct {
        NSView* containerView;
        NSView* view;
    } _right;
    
    struct {
        ImageSourcePtr imageSource;
        ImageLibraryPtr imageLibrary;
        ImageSelectionPtr selection;
        
        Object::ObserverPtr deviceOb;
        Object::ObserverPtr imageLibraryOb;
        
        ImageGridScrollView* imageGridScrollView;
        ImageGridView* imageGridView;
        FullSizeImageView* fullSizeImageView;
        
        InspectorView* inspectorView;
    } _active;
    
    struct {
        MDCDevicePtr device;
        DeviceSettingsView* view;
    } _deviceSettings;
}

static NSMenu* _ContextMenuCreate() {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItemWithTitle:@"Export…" action:@selector(_export:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Delete…" action:@selector(_delete:) keyEquivalent:@""];
    return menu;
}

+ (BOOL)autosavesInPlace {
    return false;
}

template<typename T>
static void _SetView(T& x, NSView* y) {
    if (x.view) [x.view removeFromSuperview];
    x.view = y;
    if (x.view) {
        [x.containerView addSubview:x.view];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[v]|"
            options:0 metrics:nil views:@{@"v":x.view}]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[v]|"
            options:0 metrics:nil views:@{@"v":x.view}]];
        // setNeedsLayout: is necessary to ensure the grid view is sized properly,
        // when showing the grid view.
        [y setNeedsLayout:true];
    }
}

- (void)awakeFromNib {
    _window = [_splitView window];
//    [_window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
    
    _left.containerView = [[NSView alloc] initWithFrame:{}];
    [_left.containerView setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _center.containerView = [[NSView alloc] initWithFrame:{}];
    [_center.containerView setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _right.containerView = [[NSView alloc] initWithFrame:{}];
    [_right.containerView setTranslatesAutoresizingMaskIntoConstraints:false];
    
    [_splitView addArrangedSubview:_left.containerView];
    [_splitView addArrangedSubview:_center.containerView];
    [_splitView addArrangedSubview:_right.containerView];
    
    [_splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [_splitView setHoldingPriority:NSLayoutPriorityFittingSizeCompression forSubviewAtIndex:1];
    [_splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:2];
    
    _sourceListView = [[SourceListView alloc] initWithFrame:{}];
    [_sourceListView setDelegate:self];
    _SetView(_left, _sourceListView);
    
    // Handle whatever is first selected
    [self sourceListViewSelectionChanged:_sourceListView];
    
    {
        __weak auto selfWeak = self;
        _prefsOb = PrefsGlobal()->observerAdd([=] (auto, auto) { [selfWeak _prefsChanged]; });
    }
    
    // Observe devices connecting/disconnecting
    {
        __weak auto selfWeak = self;
        _devicesOb = MDCDevicesManagerGlobal()->observerAdd([=] (auto, auto) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _updateDevices]; });
        });
    }
    
    [self _updateDevices];
}

- (NSView*)_devicesContainerView {
    return [_splitView arrangedSubviews][0];
}

- (NSView*)_inspectorContainerView {
    return [_splitView arrangedSubviews][2];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    NSLog(@"[Document] validateUserInterfaceItem: %@\n", item);
    NSMenuItem* mitem = Toastbox::CastOrNull<NSMenuItem*>(item);
    
    // Save
    if ([item action] == @selector(saveDocument:)) {
        return false;
    } else if ([item action] == @selector(saveDocumentAs:)) {
        return false;
    
    // Sort
    } else if ([item action] == @selector(_sortNewestFirst:)) {
        [mitem setState:(_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
        return true;
    
    } else if ([item action] == @selector(_sortOldestFirst:)) {
        [mitem setState:(!_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
        return true;
    
    // Toggle panels
    } else if ([item action] == @selector(_toggleDevices:)) {
        [mitem setTitle:([[self _devicesContainerView] isHidden] ? @"Show Devices" : @"Hide Devices")];
        return true;
    
    } else if ([item action] == @selector(_toggleInspector:)) {
        [mitem setTitle:([[self _inspectorContainerView] isHidden] ? @"Show Inspector" : @"Hide Inspector")];
        return true;
    
    // Navigation
    } else if ([item action] == @selector(_showImage:)) {
        if (_center.view != _active.imageGridScrollView) return false;
        if (_active.selection->images().size() != 1) return false;
        return true;
    
    } else if ([item action] == @selector(_nextImage:)) {
        return _center.view == _active.fullSizeImageView;
    
    } else if ([item action] == @selector(_previousImage:)) {
        return _center.view == _active.fullSizeImageView;
    
    } else if ([item action] == @selector(_backToImages:)) {
        return _center.view == _active.fullSizeImageView;
    
    // Export
    } else if ([item action] == @selector(_export:)) {
        const size_t selectionCount = _active.selection->images().size();
        NSString* title = nil;
        if (selectionCount > 1) {
            title = [NSString stringWithFormat:@"Export %ju Photos…", (uintmax_t)selectionCount];
        } else if (selectionCount == 1) {
            title = @"Export 1 Photo…";
        } else {
            title = @"Export…";
        }
        [mitem setTitle:title];
        return (bool)selectionCount;
    
    // Delete
    } else if ([item action] == @selector(_delete:)) {
        const size_t selectionCount = _active.selection->images().size();
        NSString* title = nil;
        if (selectionCount > 1) {
            title = [NSString stringWithFormat:@"Delete %ju Photos…", (uintmax_t)selectionCount];
        } else if (selectionCount == 1) {
            title = @"Delete 1 Photo…";
        } else {
            title = @"Delete…";
        }
        [mitem setTitle:title];
        return (bool)selectionCount;
    }
    
    return true;
//    return [super validateMenuItem:item];
}





- (NSString*)windowNibName {
    return @"Document";
}

- (NSString*)displayName {
    return @"MDCStudio";
}

static void _UpdateImageGridViewFromPrefs(PrefsPtr prefs, ImageGridView* view) {
    [view setSortNewestFirst:_SortNewestFirst()];
}

- (void)_prefsChanged {
    NSLog(@"prefs changed");
    if (_active.imageGridScrollView) {
        auto v = Toastbox::Cast<ImageGridView*>([_active.imageGridScrollView document]);
        _UpdateImageGridViewFromPrefs(PrefsGlobal(), v);
    }
}

// _openImage: open a particular image id, or an image offset from a particular image id
- (bool)_openImage:(ImageRecordPtr)rec delta:(ssize_t)delta {
    const bool sortNewestFirst = _SortNewestFirst();
    
    ImageLibraryPtr imageLibrary = _active.imageLibrary;
    assert(imageLibrary);
    
    ImageRecordPtr imageRecord;
    {
        auto lock = std::unique_lock(*imageLibrary);
        if (imageLibrary->empty()) return false;
        
        const auto begin = ImageLibrary::BeginSorted(*imageLibrary, sortNewestFirst);
        const auto end = ImageLibrary::EndSorted(*imageLibrary, sortNewestFirst);
        const auto find = ImageLibrary::Find(begin, end, rec);
        if (find == end) return false;
        
        const ssize_t deltaMin = begin-find;
        const ssize_t deltaMax = std::prev(end)-find;
        if (delta<deltaMin || delta>deltaMax) return false;
        
        imageRecord = *(find+delta);
    }
    
    [_active.fullSizeImageView setImageRecord:imageRecord];
    
    if (_center.view != _active.fullSizeImageView) {
        _SetView(_center, _active.fullSizeImageView);
        [_active.fullSizeImageView magnifyToFit];
        [_window makeFirstResponder:_active.fullSizeImageView];
    }
    
    _active.selection->images({ imageRecord });
    printf("Showing image id %ju\n", (uintmax_t)imageRecord->info.id);
    
    return true;
}

- (void)_setActiveImageSource:(ImageSourcePtr)imageSource {
    // Short-circuit if nothing changed
    if (_active.imageSource == imageSource) return;
    
    // First reset our state
    _active = {};
    _SetView(_center, nil);
    _SetView(_right, nil);
    [_window makeFirstResponder:_sourceListView];
    
    // Short-circuit (after resetting _active) if there's no selection
    if (!imageSource) return;
    
    MDCDevicePtr device = Toastbox::CastOrNull<MDCDevicePtr>(imageSource);
    assert(device);
    
    // Update _active
    {
        _active.imageSource = imageSource;
        _active.imageLibrary = _active.imageSource->imageLibrary();
        _active.selection = Object::Create<ImageSelection>(_active.imageLibrary);
        
        __weak auto selfWeak = self;
        
        // Observe image library
        _active.deviceOb = device->observerAdd([=] (auto, const Object::Event& ev) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _activeDeviceChanged]; });
        });
        
        // Observe image library
        _active.imageLibraryOb = _active.imageLibrary->observerAdd([=] (auto, const Object::Event& ev) {
            const auto type = static_cast<const ImageLibrary::Event&>(ev).type;
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _handleImageLibraryEventType:type]; });
        });
        
        DeviceImageGridScrollView* imageGridScrollView = [[DeviceImageGridScrollView alloc] initWithDevice:device
            selection:_active.selection];
        
        [[imageGridScrollView configureDeviceButton] setTarget:self];
        [[imageGridScrollView configureDeviceButton] setAction:@selector(_showSettingsForActiveDevice:)];
        _active.imageGridScrollView = imageGridScrollView;
        
        _active.imageGridView = Toastbox::Cast<ImageGridView*>([_active.imageGridScrollView document]);
        _UpdateImageGridViewFromPrefs(PrefsGlobal(), _active.imageGridView);
        [_active.imageGridView setMenu:_ContextMenuCreate()];
        
        _active.fullSizeImageView = [[FullSizeImageView alloc] initWithImageSource:device];
        [_active.fullSizeImageView setMenu:_ContextMenuCreate()];
        
        _active.inspectorView = [[InspectorView alloc] initWithImageSource:device selection:_active.selection];
    }
    
    _SetView(_center, _active.imageGridScrollView);
    _SetView(_right, _active.inspectorView);
    
    [_window makeFirstResponder:_active.imageGridView];
}

// MARK: - Source List
- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView {
    assert(sourceListView == _sourceListView);
    [self _setActiveImageSource:[_sourceListView selection]];
}

- (void)sourceListView:(SourceListView*)sourceListView showSettingsForDevice:(MDCDevicePtr)device {
    assert(sourceListView == _sourceListView);
    [self _showSettingsForDevice:device];
}

- (void)sourceListView:(SourceListView*)sourceListView factoryResetDevice:(MDCStudio::MDCDevicePtr)device {
    NSLog(@"sourceListView:factoryResetDevice:");
    
    FactoryResetConfirmationAlert* alert = [FactoryResetConfirmationAlert new];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK) return;
        NSLog(@"FACTORY RESET");
        device->factoryReset();
    }];
}

- (void)_updateDevices {
    std::vector<MDCDevicePtr> devices = MDCDevicesManagerGlobal()->devices();
    std::set<ImageSourcePtr> imageSources;
    for (MDCDevicePtr device : devices) {
        imageSources.insert(device);
    }
    [_sourceListView setImageSources:imageSources];
    [self sourceListViewSelectionChanged:_sourceListView];
    
    const bool haveDevices = !imageSources.empty();
    [_splitView setHidden:!haveDevices];
    [_noDevicesView setHidden:haveDevices];
}

// MARK: - Device Observer
- (void)_activeDeviceChanged {
    MDCDevicePtr device = Toastbox::Cast<MDCDevicePtr>(_active.imageSource);
    
    bool libraryEmpty = false;
    {
        ImageLibraryPtr imageLibrary = device->imageLibrary();
        auto lock = std::unique_lock(*imageLibrary);
        libraryEmpty = imageLibrary->empty();
    }
    
    // Perform an initial load the first time our image library doesn't have photos, but the device does.
    // This is a simple UX affordance for a nicer 'out of box' experience.
    if (libraryEmpty && device->status().loadImageCount) {
        device->sync();
    }
}

// MARK: - ImageLibrary Observer
- (void)_handleImageLibraryEventType:(ImageLibrary::Event::Type)type {
    switch (type) {
    case ImageLibrary::Event::Type::Clear:
        // When the image library is cleared, return to the grid view
        _SetView(_center, _active.imageGridScrollView);
        _active.selection->images({});
        break;
    default:
        break;
    }
}

// MARK: - Split View

- (BOOL)splitView:(NSSplitView*)splitView canCollapseSubview:(NSView*)subview {
    return true;
}

// MARK: - Menu Actions
static bool _SortNewestFirst() {
    return PrefsGlobal()->get("SortNewestFirst", true);
}

static void _SortNewestFirst(bool x) {
    return PrefsGlobal()->set("SortNewestFirst", x);
}

- (IBAction)_sortNewestFirst:(id)sender {
    NSLog(@"_sortNewestFirst");
    _SortNewestFirst(true);
}

- (IBAction)_sortOldestFirst:(id)sender {
    NSLog(@"_sortOldestFirst");
    _SortNewestFirst(false);
}

- (IBAction)_toggleDevices:(id)sender {
    NSView* view = [self _devicesContainerView];
    const bool shown = [view isHidden];
    [view setHidden:!shown];
}

- (IBAction)_toggleInspector:(id)sender {
    NSView* view = [self _inspectorContainerView];
    const bool shown = [view isHidden];
    [view setHidden:!shown];
}

- (IBAction)_showSettingsForActiveDevice:(id)sender {
    MDCDevicePtr device = Toastbox::Cast<MDCDevicePtr>(_active.imageSource);
    [self _showSettingsForDevice:device];
}

- (IBAction)_showImage:(id)sender {
    printf("[Document] _showImage:\n");
    const ImageSet& selection = _active.selection->images();
    // Bail if there are multiple images selected
    if (selection.size() != 1) return;
    const ImageRecordPtr rec = *selection.begin();
    [self _openImage:rec delta:0];
}

- (IBAction)_nextImage:(id)sender {
    assert(_center.view == _active.fullSizeImageView);
    const bool ok = [self _openImage:[_active.fullSizeImageView imageRecord] delta:1];
    if (!ok) NSBeep();
}

- (IBAction)_previousImage:(id)sender {
    assert(_center.view == _active.fullSizeImageView);
    const bool ok = [self _openImage:[_active.fullSizeImageView imageRecord] delta:-1];
    if (!ok) NSBeep();
}

- (IBAction)_backToImages:(id)sender {
    assert(_center.view == _active.fullSizeImageView);
    _SetView(_center, _active.imageGridScrollView);
    
    // -layoutIfNeeded is necessary on the window so that we can scroll the grid
    // view to a particular spot immediately, instead of having to wait until
    // the next layout pass (eg using NSTimer).
    [_window layoutIfNeeded];
    
    ImageRecordPtr rec = [_active.fullSizeImageView imageRecord];
    _active.selection->images({ rec });
    [_window makeFirstResponder:_active.imageGridView];
    
    const std::optional<CGRect> rect = [_active.imageGridView rectForImageRecord:rec];
    if (rect) [_active.imageGridView scrollToImageRect:*rect center:true];
}

- (IBAction)_export:(id)sender {
    printf("[Document] _export:\n");
    ImageExporter::Export(_window, _active.imageSource, _active.selection->images());
}

- (void)_deleteSelection {
    using ImageSetIterAny = Toastbox::IterAny<ImageSet::const_iterator>;
    
    ImageSet selection = _active.selection->images();
    ImageSet newSelection;
    if (selection.empty()) {
        NSBeep();
        return;
    }
    
    // Delete the images from the library
    {
        auto lock = std::unique_lock(*_active.imageLibrary);
        
        // Determine the record to select after deletion
        const bool sortNewestFirst = _SortNewestFirst();
        auto begin = ImageLibrary::BeginSorted(*_active.imageLibrary, sortNewestFirst);
        auto end = ImageLibrary::EndSorted(*_active.imageLibrary, sortNewestFirst);
        auto selectionBegin = (sortNewestFirst ? ImageSetIterAny(selection.rbegin()) : ImageSetIterAny(selection.begin()));
        auto selectionEnd = (sortNewestFirst ? ImageSetIterAny(selection.rend()) : ImageSetIterAny(selection.end()));
        ImageRecordPtr selectionFront = *selectionBegin;
        ImageRecordPtr selectionBack = *std::prev(selectionEnd);
        const auto selectionFrontIt = ImageLibrary::Find(begin, end, selectionFront);
        assert(selectionFrontIt != end);
        const auto selectionBackIt = ImageLibrary::Find(begin, end, selectionBack);
        assert(selectionBackIt != end);
        const size_t selectionIdx = selectionFrontIt - begin;
        
        // Perform the removal
        _active.imageLibrary->remove(selection);
        
        // Construct `newSelection`
        {
            if (!_active.imageLibrary->empty()) {
                const size_t idx = std::min(_active.imageLibrary->recordCount()-1, selectionIdx);
                auto begin = ImageLibrary::BeginSorted(*_active.imageLibrary, sortNewestFirst);
                newSelection = { *(begin + idx) };
            }
        }
    }
    
    // Set the new selection
    // Don't hold the ImageLibrary lock because this calls out!
    _active.selection->images(newSelection);
}

- (IBAction)_delete:(id)sender {
    const uintmax_t imageCount = _active.selection->images().size();
    NSAlert* alert = [NSAlert new];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert setMessageText:[NSString stringWithFormat:@"Delete %ju %s",
        imageCount, (imageCount>1 ? "Photos" : "Photo")]];
    
    [alert setInformativeText:[NSString stringWithFormat:@"Are you sure you want to delete %ju %s?\n\nOnce deleted, these photos will be unrecoverable, and this action cannot be undone.",
        imageCount, (imageCount>1 ? "photos" : "photo")]];
    
    {
        [alert addButtonWithTitle:@"Delete"];
        NSButton* button = [[alert buttons] lastObject];
        [button setTag:NSModalResponseOK];
        [button setKeyEquivalent:@"\x7f"];
        [button setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    }
    
    {
        [alert addButtonWithTitle:@"Cancel"];
        NSButton* button = [[alert buttons] lastObject];
        [button setTag:NSModalResponseCancel];
        [button setKeyEquivalent:@"\r"];
    }
    
    {
        [alert addButtonWithTitle:@"CancelHidden"];
        NSButton* button = [[alert buttons] lastObject];
        [button setTag:NSModalResponseCancel];
        [button setKeyEquivalent:@"\x1b"];
        // Make button invisible, in case other versions of macOS break our -setFrame: technique
        [button setAlphaValue:0];
        [alert layout];
        [button setFrame:{}];
    }
    
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK) return;
        [self _deleteSelection];
    }];
}

// MARK: - Device Settings
- (void)_showSettingsForDevice:(MDCDevicePtr)device {
    _deviceSettings = {
        .device = device,
        .view = [[DeviceSettingsView alloc] initWithSettings:device->settings() delegate:self],
    };
    
    NSWindow* sheetWindow = [[NSWindow alloc] initWithContentRect:{}
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:false];
    NSView* contentView = [sheetWindow contentView];
    [contentView addSubview:_deviceSettings.view];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|"
        options:0 metrics:nil views:@{@"view":_deviceSettings.view}]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|"
        options:0 metrics:nil views:@{@"view":_deviceSettings.view}]];
    
    [_window beginSheet:sheetWindow completionHandler:^(NSModalResponse returnCode) {
        NSLog(@"sheet complete");
    }];
}

- (void)deviceSettingsView:(DeviceSettingsView*)view dismiss:(bool)save {
    assert(view == _deviceSettings.view);
    
    // Save settings to device if user so desires
    if (save) {
        try {
            const MSP::Settings settings = [_deviceSettings.view settings];
            _deviceSettings.device->settings(settings);
        
        } catch (const std::exception& e) {
            NSAlert* alert = [NSAlert new];
            [alert setAlertStyle:NSAlertStyleCritical];
            [alert setMessageText:@"An error occurred when trying to save these settings"];
            [alert setInformativeText:[NSString stringWithFormat:@"Error: %s", e.what()]];
            [alert beginSheetModalForWindow:[view window] completionHandler:nil];
            return;
        }
    }
    
    [_window endSheet:[_deviceSettings.view window]];
    _deviceSettings = {};
}

@end

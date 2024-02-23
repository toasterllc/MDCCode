#import "Document.h"
#import <algorithm>
#import "Toastbox/Cast.h"
#import "SourceListView/SourceListView.h"
#import "InspectorView/InspectorView.h"
#import "ImageGridView/ImageGridView.h"
#import "FullSizeImageView/FullSizeImageView.h"
#import "FixedScrollView.h"
#import "Prefs.h"
#import "ImageLibraryStatus.h"
#import "DeviceSettings/DeviceSettingsView.h"
#import "DeviceSettings/DeviceSettingsSheet.h"
#import "DeviceImageGridContainerView/DeviceImageGridContainerView.h"
#import "FactoryResetConfirmationAlert/FactoryResetConfirmationAlert.h"
#import "ImageExporter/ImageExporter.h"
#import "MDCDevicesManager.h"
#import "PrintImages.h"
#import "MDCDeviceDemo.h"
#import "CenterContentView.h"

using namespace MDCStudio;

@interface NoDevicesView : NSView <CenterContentView>
@end

@implementation NoDevicesView

- (bool)sourceListAllowed {
    return false;
}

- (bool)inspectorAllowed {
    return false;
}

@end

@interface Document () <NSSplitViewDelegate, SourceListViewDelegate, DeviceSettingsViewDelegate>
@end

@implementation Document {
    IBOutlet NSWindow* _window;
    IBOutlet NSSplitView* _splitView;
    IBOutlet NSView<CenterContentView>* _noDevicesView;
    
    id _contentViewChangedOb;
    bool _sourceListVisible;
    bool _inspectorVisible;
    
    Object::ObserverPtr _devicesOb;
    Object::ObserverPtr _prefsOb;
    
    SourceListView* _sourceListView;
    
    struct {
        NSView* containerView;
        NSView* view;
    } _left;
    
    struct {
        NSView* containerView;
        NSView<CenterContentView>* view;
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
        
        ImageGridContainerView* imageGridContainerView;
        
        FullSizeImageView* fullSizeImageView;
        
        InspectorView* inspectorView;
    } _active;
    
    struct {
        MDCDevicePtr device;
        DeviceSettingsView* view;
    } _deviceSettings;
    
    MDCDeviceDemoPtr _demoDevice;
}

static NSMenu* _ContextMenuCreate() {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItemWithTitle:@"Export…" action:@selector(_export:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Delete…" action:@selector(_delete:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Print…" action:@selector(printDocument:) keyEquivalent:@""];
    return menu;
}

+ (BOOL)autosavesInPlace {
    return false;
}

template<typename T>
static void _SetView(T& x, NSView* y) {
    if (x.view) [x.view removeFromSuperview];
    x.view = (id)y;
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
    __weak auto selfWeak = self;
    
    _contentViewChangedOb = [[NSNotificationCenter defaultCenter] addObserverForName:@(CenterContentViewTypes::ChangedNotification)
        object:nil queue:nil usingBlock:^(NSNotification* note) {
        [selfWeak _updateAccessoryViewVisibility];
    }];
    
    _sourceListVisible = true;
    _inspectorVisible = true;
    
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
        _prefsOb = PrefsGlobal()->observerAdd([=] (auto, auto) { [selfWeak _prefsChanged]; });
    }
    
    // Observe devices connecting/disconnecting
    {
        _devicesOb = MDCDevicesManagerGlobal()->observerAdd([=] (auto, auto) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _updateDevices]; });
        });
    }
    
    [self _updateDevices];
    [self _updateAccessoryViewVisibility];
}

- (void)_updateAccessoryViewVisibility {
    const bool sourceListVisible = _sourceListVisible && [self _sourceListAllowed];
    const bool inspectorVisible = _inspectorVisible && [self _inspectorAllowed];
    
    [[self _sourceListContainerView] setHidden:!sourceListVisible];
    [[self _inspectorContainerView] setHidden:!inspectorVisible];
}

- (bool)_sourceListAllowed {
    if ([_center.view respondsToSelector:@selector(sourceListAllowed)]) {
        return [_center.view sourceListAllowed];
    }
    return true;
}

- (bool)_inspectorAllowed {
    if ([_center.view respondsToSelector:@selector(inspectorAllowed)]) {
        return [_center.view inspectorAllowed];
    }
    return true;
}

- (NSView*)_sourceListContainerView {
    return [_splitView arrangedSubviews][0];
}

- (NSView*)_inspectorContainerView {
    return [_splitView arrangedSubviews][2];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    NSLog(@"[Document] validateUserInterfaceItem: %@\n", item);
    NSMenuItem* mitem = Toastbox::CastOrNull<NSMenuItem*>(item);
    
    // Disable all menu items if we're not displaying anything
    // This is necessary to protect the code below from looking at _active.selection,
    // which will be nullptr in this case.
    if (!_center.view) return false;
    
    // Save
    if ([item action] == @selector(saveDocument:)) {
        return false;
    } else if ([item action] == @selector(saveDocumentAs:)) {
        return false;
    } else if ([item action] == @selector(revertDocumentToSaved:)) {
        return false;
    
    // Printing
    } else if ([item action] == @selector(printDocument:)) {
        const size_t selectionCount = _active.selection->images().size();
        NSString* title = nil;
        if (selectionCount > 1) {
            title = [NSString stringWithFormat:@"Print %ju Photos…", (uintmax_t)selectionCount];
        } else {
            title = @"Print Photo…";
        }
        [mitem setTitle:title];
        return !_active.selection->images().empty();
    
    // Sort
    } else if ([item action] == @selector(_sortNewestFirst:)) {
        [mitem setState:(_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
        return true;
    
    } else if ([item action] == @selector(_sortOldestFirst:)) {
        [mitem setState:(!_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
        return true;
    
    // Toggle panels
    } else if ([item action] == @selector(_toggleSourceList:)) {
        [mitem setState:(_sourceListVisible ? NSControlStateValueOn : NSControlStateValueOff)];
        return [self _sourceListAllowed];
    
    } else if ([item action] == @selector(_toggleInspector:)) {
        [mitem setState:(_inspectorVisible ? NSControlStateValueOn : NSControlStateValueOff)];
        return [self _inspectorAllowed];
    
    // Navigation
    } else if ([item action] == @selector(_showImage:)) {
        if (_center.view != _active.imageGridContainerView) return false;
        if (_active.selection->images().size() != 1) return false;
        return true;
    
    } else if ([item action] == @selector(_nextImage:)) {
        return _active.fullSizeImageView && _center.view==_active.fullSizeImageView;
    
    } else if ([item action] == @selector(_previousImage:)) {
        return _active.fullSizeImageView && _center.view==_active.fullSizeImageView;
    
    } else if ([item action] == @selector(_backToImages:)) {
        return _active.fullSizeImageView && _center.view==_active.fullSizeImageView;
    
    // Export
    } else if ([item action] == @selector(_export:)) {
        const size_t selectionCount = _active.selection->images().size();
        NSString* title = nil;
        if (selectionCount > 1) {
            title = [NSString stringWithFormat:@"Export %ju Photos…", (uintmax_t)selectionCount];
        } else if (selectionCount == 1) {
            title = @"Export Photo…";
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
            title = @"Delete Photo…";
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
    return @"Photon Transfer";
}

static void _UpdateImageGridViewFromPrefs(PrefsPtr prefs, ImageGridView* view) {
    [view setSortNewestFirst:_SortNewestFirst()];
}

- (void)_prefsChanged {
    NSLog(@"prefs changed");
    if (_active.imageGridContainerView) {
        auto cv = Toastbox::Cast<DeviceImageGridContainerView*>(_active.imageGridContainerView);
        auto doc = Toastbox::Cast<ImageGridView*>([[cv imageGridScrollView] document]);
        _UpdateImageGridViewFromPrefs(PrefsGlobal(), doc);
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
        [self _setCenterView:_active.fullSizeImageView];
        [_active.fullSizeImageView magnifyToFit];
//        [_window makeFirstResponder:_active.fullSizeImageView];
    }
    
    _active.selection->images({ imageRecord });
    printf("Showing image id %ju\n", (uintmax_t)imageRecord->info.id);
    
    return true;
}

- (void)_setActiveImageSource:(ImageSourcePtr)imageSource {
    // Short-circuit if nothing changed
//    if (_active.imageSource == imageSource) return;
    
    // First reset our state
    _active = {};
    _SetView(_center, nil);
    _SetView(_right, nil);
    [_window makeFirstResponder:_sourceListView];
    
    if (imageSource) {
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
            
            DeviceImageGridContainerView* imageGridContainerView = [[DeviceImageGridContainerView alloc] initWithDevice:device
                selection:_active.selection];
            
            [[imageGridContainerView configureDeviceButton] setTarget:self];
            [[imageGridContainerView configureDeviceButton] setAction:@selector(_showSettingsForActiveDevice:)];
            _active.imageGridContainerView = imageGridContainerView;
            
    //        _active.imageGridView = Toastbox::Cast<ImageGridView*>([[imageGridContainerView imageGridScrollView] document]);
            _UpdateImageGridViewFromPrefs(PrefsGlobal(), [_active.imageGridContainerView imageGridView]);
            [[_active.imageGridContainerView imageGridView] setMenu:_ContextMenuCreate()];
            
            _active.fullSizeImageView = [[FullSizeImageView alloc] initWithImageSource:device];
            [_active.fullSizeImageView setMenu:_ContextMenuCreate()];
            
            _active.inspectorView = [[InspectorView alloc] initWithImageSource:device selection:_active.selection];
        }
        
        [self _setCenterView:_active.imageGridContainerView];
        _SetView(_right, _active.inspectorView);
    
    } else {
        [self _setCenterView:_noDevicesView];
    }
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
    __weak auto alertWeak = alert;
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse r) {
        NSLog(@"FACTORY RESET");
        if (r == NSModalResponseOK) {
            [alertWeak setSpinnerVisible:true];
            
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                std::exception_ptr esaved;
                try {
                    device->factoryReset();
                } catch (...) {
                    esaved = std::current_exception();
                }
                
                // Dismiss the alert on the main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    [alertWeak dismiss];
                    
                    // Show an error dialog if an error occurred
                    if (esaved) {
                        try {
                            std::rethrow_exception(esaved);
                        } catch (const std::exception& e) {
                            NSAlert* alert = [NSAlert new];
                            [alert setAlertStyle:NSAlertStyleCritical];
                            [alert setMessageText:@"Factory Reset Failed"];
                            [alert setInformativeText:[NSString stringWithFormat:@"Error: %s", e.what()]];
                            [alert beginSheetModalForWindow:self->_window completionHandler:nil];
                        }
                    }
                });
            });
        } else {
            [alertWeak dismiss];
        }
    }];
}

- (void)_updateDevices {
    std::set<ImageSourcePtr> imageSources;
    std::vector<MDCDeviceRealPtr> devices = MDCDevicesManagerGlobal()->devices();
    for (MDCDeviceRealPtr device : devices) {
        imageSources.insert(device);
    }
    
    if (_demoDevice) {
        imageSources.insert(_demoDevice);
    }
    
    [_sourceListView setImageSources:imageSources];
    [self sourceListViewSelectionChanged:_sourceListView];
    
//    const bool haveDevices = !imageSources.empty();
//    if (!haveDevices) {
//        [self _setCenterView:_noDevicesView];
//    }
}

- (void)_setCenterView:(NSView<CenterContentView>*)view {
    _SetView(_center, view);
    [self _updateAccessoryViewVisibility];
    
    NSView* fr = view;
    if ([view respondsToSelector:@selector(initialFirstResponder)]) {
        fr = [view initialFirstResponder];
    }
    [_window makeFirstResponder:fr];
}

// MARK: - Device Observer
- (void)_activeDeviceChanged {
    if (!_active.imageSource) return;
    
    MDCDevicePtr device = Toastbox::Cast<MDCDevicePtr>(_active.imageSource);
    
    bool libraryEmpty = false;
    {
        ImageLibraryPtr imageLibrary = device->imageLibrary();
        auto lock = std::unique_lock(*imageLibrary);
        libraryEmpty = imageLibrary->empty();
    }
    
    // Perform an initial load the first time our image library doesn't have photos, but the device does.
    // This is a simple UX affordance for a nicer 'out of box' experience.
    {
        auto status = device->status();
        if (status) {
            if (libraryEmpty && status->loadImageCount) {
                device->sync();
            }
        }
    }
}

// MARK: - ImageLibrary Observer
- (void)_handleImageLibraryEventType:(ImageLibrary::Event::Type)type {
    switch (type) {
    case ImageLibrary::Event::Type::Remove:
        // Go back to the grid view if the currently-displayed full-size image is deleted
        if (_active.fullSizeImageView && _center.view==_active.fullSizeImageView) {
            auto lock = std::unique_lock(*_active.imageLibrary);
            const bool deleted = _active.imageLibrary->find([_active.fullSizeImageView imageRecord]) == _active.imageLibrary->end();
            if (deleted) {
                [self _setCenterView:_active.imageGridContainerView];
            }
        }
        break;
    case ImageLibrary::Event::Type::Clear:
        // When the image library is cleared, return to the grid view
        [self _setCenterView:_active.imageGridContainerView];
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

- (IBAction)_toggleSourceList:(id)sender {
    _sourceListVisible = !_sourceListVisible;
    [self _updateAccessoryViewVisibility];
}

- (IBAction)_toggleInspector:(id)sender {
    _inspectorVisible = !_inspectorVisible;
    [self _updateAccessoryViewVisibility];
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
    assert(_active.fullSizeImageView && _center.view==_active.fullSizeImageView);
    const bool ok = [self _openImage:[_active.fullSizeImageView imageRecord] delta:1];
    if (!ok) NSBeep();
}

- (IBAction)_previousImage:(id)sender {
    assert(_active.fullSizeImageView && _center.view==_active.fullSizeImageView);
    const bool ok = [self _openImage:[_active.fullSizeImageView imageRecord] delta:-1];
    if (!ok) NSBeep();
}

- (IBAction)_backToImages:(id)sender {
    assert(_active.fullSizeImageView && _center.view==_active.fullSizeImageView);
    [self _setCenterView:_active.imageGridContainerView];
    
    // -layoutIfNeeded is necessary on the window so that we can scroll the grid
    // view to a particular spot immediately, instead of having to wait until
    // the next layout pass (eg using NSTimer).
    [_window layoutIfNeeded];
    
    ImageRecordPtr rec = [_active.fullSizeImageView imageRecord];
    _active.selection->images({ rec });
    
    ImageGridView* igv = [_active.imageGridContainerView imageGridView];
//    [_window makeFirstResponder:igv];
    
    const std::optional<CGRect> rect = [igv rectForImageRecord:rec];
    if (rect) [igv scrollToImageRect:*rect center:true];
}

- (IBAction)_export:(id)sender {
    printf("[Document] _export:\n");
    ImageExporter::Export(_window, _active.imageSource, _active.selection->images());
}

- (void)_deleteSelection {
    using ImageSetIterAny = Toastbox::IterAny<ImageSet::const_iterator>;
    
    const bool sortNewestFirst = _SortNewestFirst();
    const ImageSet selection = _active.selection->images();
    ImageSet newSelection;
    if (selection.empty()) {
        NSBeep();
        return;
    }
    
    // Find the index of the selection so we can restore it after the deletion
    size_t selectionIdx = 0;
    {
        auto lock = std::unique_lock(*_active.imageLibrary);
        auto begin = ImageLibrary::BeginSorted(*_active.imageLibrary, sortNewestFirst);
        auto end = ImageLibrary::EndSorted(*_active.imageLibrary, sortNewestFirst);
        auto selectionBegin = (sortNewestFirst ? ImageSetIterAny(selection.rbegin()) : ImageSetIterAny(selection.begin()));
        ImageRecordPtr selectionFront = *selectionBegin;
        const auto selectionFrontIt = ImageLibrary::Find(begin, end, selectionFront);
        assert(selectionFrontIt != end);
        selectionIdx = selectionFrontIt - begin;
    }
    
    // Perform the deletion
    _active.imageSource->deleteImages(selection);
        
    // Construct `newSelection` using `selectionIdx`
    {
        auto lock = std::unique_lock(*_active.imageLibrary);
        if (!_active.imageLibrary->empty()) {
            const size_t idx = std::min(_active.imageLibrary->recordCount()-1, selectionIdx);
            auto begin = ImageLibrary::BeginSorted(*_active.imageLibrary, sortNewestFirst);
            newSelection = { *(begin + idx) };
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
    
    [alert setInformativeText:[NSString stringWithFormat:
        @"Are you sure you want to delete %ju %s?\n\nOnce deleted, %s will be unrecoverable.",
        imageCount,
        (imageCount>1 ? "photos" : "photo"),
        (imageCount>1 ? "these photos" : "this photo")
    ]];
    
    {
        NSButton* button = [alert addButtonWithTitle:@"Delete"];
        [button setTag:NSModalResponseOK];
        [button setKeyEquivalent:@"\x7f"];
        [button setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    }
    
    {
        NSButton* button = [alert addButtonWithTitle:@"Cancel"];
        [button setTag:NSModalResponseCancel];
        [button setKeyEquivalent:@"\r"];
    }
    
//    {
//        NSButton* button = [alert addButtonWithTitle:@"CancelHidden"];
//        [button setTag:NSModalResponseCancel];
//        [button setKeyEquivalent:@"\x1b"];
//        // Make button invisible, in case other versions of macOS break our -setFrame: technique
//        [button setAlphaValue:0];
//        [alert layout];
//        [button setFrame:{}];
//    }
    
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
    
    DeviceSettingsSheet* sheet = [[DeviceSettingsSheet alloc] initWithView:_deviceSettings.view];
    [_window beginSheet:sheet completionHandler:^(NSModalResponse returnCode) {
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
            [alert setMessageText:@"Save Settings Failed"];
            [alert setInformativeText:[NSString stringWithFormat:@"Error: %s", e.what()]];
            [alert beginSheetModalForWindow:[view window] completionHandler:nil];
            return;
        }
    }
    
    [_window endSheet:[_deviceSettings.view window]];
    _deviceSettings = {};
}

// MARK: - Printing

- (NSPrintOperation*)printOperationWithSettings:(NSDictionary<NSPrintInfoAttributeKey,id>*)settings error:(NSError**)error {
    return PrintImages(settings, _active.imageSource, _active.selection->images(), !_SortNewestFirst());
}

// MARK: - Demo

- (IBAction)_tryDemo:(id)sender {
    _demoDevice = Object::Create<MDCDeviceDemo>();
    [self _updateDevices];
}

@end

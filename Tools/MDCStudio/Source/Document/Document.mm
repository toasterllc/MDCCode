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
#import "DeviceImageGridHeaderView/DeviceImageGridHeaderView.h"
#import "FactoryResetConfirmationAlert/FactoryResetConfirmationAlert.h"
#import "MDCDevicesManager.h"

using namespace MDCStudio;

@interface Document () <NSSplitViewDelegate, SourceListViewDelegate, ImageGridViewDelegate, FullSizeImageViewDelegate, DeviceSettingsViewDelegate, DeviceImageGridHeaderViewDelegate>
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
        
        Object::ObserverPtr deviceOb;
        Object::ObserverPtr imageLibraryOb;
        
        ImageGridScrollView* imageGridScrollView;
        ImageGridView* imageGridView;
        ImageGridHeaderView* imageGridHeaderView;
        
        FullSizeImageView* fullSizeImageView;
        
        InspectorView* inspectorView;
    } _active;
    
    struct {
        MDCDevicePtr device;
        DeviceSettingsView* view;
    } _deviceSettings;
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
    if ([item action] == @selector(saveDocument:)) {
        return false;
    } else if ([item action] == @selector(saveDocumentAs:)) {
        return false;
    
    } else if ([item action] == @selector(_sortNewestFirst:)) {
        [mitem setState:(_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
    } else if ([item action] == @selector(_sortOldestFirst:)) {
        [mitem setState:(!_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
    
    } else if ([item action] == @selector(_toggleDevices:)) {
        [mitem setTitle:([[self _devicesContainerView] isHidden] ? @"Show Devices" : @"Hide Devices")];
    } else if ([item action] == @selector(_toggleInspector:)) {
        [mitem setTitle:([[self _inspectorContainerView] isHidden] ? @"Show Inspector" : @"Hide Inspector")];
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
    
    ImageSet selection;
    selection.insert(imageRecord);
    [_active.inspectorView setSelection:selection];
    
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
        
        __weak auto selfWeak = self;
        // Observe device
        _active.deviceOb = device->observerAdd([=] (auto, auto) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _deviceChanged]; });
        });
        
        // Observe image library
        _active.imageLibraryOb = _active.imageLibrary->observerAdd([=] (auto, const Object::Event& ev) {
            const auto type = dynamic_cast<const ImageLibrary::Event&>(ev).type;
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _handleImageLibraryEvent:type]; });
        });
        
        _active.imageGridView = [[ImageGridView alloc] initWithImageSource:device];
        [_active.imageGridView setDelegate:self];
        _UpdateImageGridViewFromPrefs(PrefsGlobal(), _active.imageGridView);
        
        DeviceImageGridHeaderView* headerView = [[DeviceImageGridHeaderView alloc] initWithFrame:{}];
        [headerView setDelegate:self];
        _active.imageGridHeaderView = headerView;
        
        _active.imageGridScrollView = [[ImageGridScrollView alloc] initWithFixedDocument:_active.imageGridView];
        [_active.imageGridScrollView setHeaderView:_active.imageGridHeaderView];
        
        _active.fullSizeImageView = [[FullSizeImageView alloc] initWithImageSource:device];
        [_active.fullSizeImageView setDelegate:self];
        
        _active.inspectorView = [[InspectorView alloc] initWithImageSource:device];
    }
    
    _SetView(_center, _active.imageGridScrollView);
    _SetView(_right, _active.inspectorView);
    [self _updateImageGridHeader];
    
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

static std::optional<size_t> _LoadCount(const MDCDevice::Status& status, ImageLibraryPtr imageLibrary) {
    // Short-circut if syncing is in progress.
    // In that case, we don't want to show the 'Load' button in the header
    if (status.syncProgress) return std::nullopt;
    
    {
        auto lock = std::unique_lock(*imageLibrary);
        const Img::Id libImgIdEnd = (!imageLibrary->empty() ? imageLibrary->back()->info.id+1 : 0);
        
        // Calculate how many images to add to the end of the library: device has, lib doesn't
        if (libImgIdEnd > status.imageRange.end) {
            #warning TODO: how do we properly handle this situation?
            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, status.imgIdEnd: %ju)",
                (uintmax_t)libImgIdEnd,
                (uintmax_t)status.imageRange.end
            );
        }
        
        return status.imageRange.end - std::max(status.imageRange.begin, libImgIdEnd);
    }
}

- (void)_updateImageGridHeader {
    MDCDevicePtr device = Toastbox::CastOrNull<MDCDevicePtr>(_active.imageSource);
    if (!device) return;
    
    ImageLibraryPtr imageLibrary = device->imageLibrary();
    DeviceImageGridHeaderView* deviceHeader = Toastbox::Cast<DeviceImageGridHeaderView*>(_active.imageGridHeaderView);
    const MDCDevice::Status status = device->status();
    const ImageSet& selection = [_active.imageGridView selection];
    
    // Update status
    if (selection.empty()) {
        [_active.imageGridHeaderView setStatus:@(ImageLibraryStatus(imageLibrary).c_str())];
    
    } else {
        const Time::Instant first = (*selection.begin())->info.timestamp;
        const Time::Instant last = (*std::prev(selection.end()))->info.timestamp;
        const std::string status = ImageLibraryStatus(selection.size(), first, last,
            "photo selected", "photos selected");
        [_active.imageGridHeaderView setStatus:@(status.c_str())];
    }
    
    // Update unloaded photo count
    {
        const std::optional<size_t> loadCount = _LoadCount(status, imageLibrary);
        [deviceHeader setLoadCount:loadCount.value_or(0)];
    }
    
    // Upload load progress
    {
        const float progress = status.syncProgress.value_or(0);
        [deviceHeader setProgress:progress];
    }
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

- (void)_deviceChanged {
    [self _updateImageGridHeader];
}

// MARK: - ImageLibrary Observer
// _handleImageLibraryEvent: called on whatever thread where the modification happened,
// and with the ImageLibrary lock held!
- (void)_handleImageLibraryEvent:(ImageLibrary::Event::Type)type {
    switch (type) {
    case ImageLibrary::Event::Type::Add:
    case ImageLibrary::Event::Type::Remove:
    case ImageLibrary::Event::Type::ChangeProperty:
    case ImageLibrary::Event::Type::ChangeThumbnail:
        break;
    case ImageLibrary::Event::Type::Clear:
        _SetView(_center, _active.imageGridScrollView);
        [_active.imageGridView setSelection:{}];
        [_active.inspectorView setSelection:{}];
        break;
    }
    
    [self _updateImageGridHeader];
}

// MARK: - Image Grid

- (void)imageGridViewSelectionChanged:(ImageGridView*)imageGridView {
    assert(imageGridView == _active.imageGridView);
    [_active.inspectorView setSelection:[_active.imageGridView selection]];
    [self _updateImageGridHeader];
}

- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView {
    assert(imageGridView == _active.imageGridView);
    const ImageSet selection = [_active.imageGridView selection];
    if (selection.empty()) return;
    const ImageRecordPtr rec = *selection.begin();
    [self _openImage:rec delta:0];
}

// MARK: - Full Size Image View

- (void)fullSizeImageViewBack:(FullSizeImageView*)x {
    assert(x == _active.fullSizeImageView);
    _SetView(_center, _active.imageGridScrollView);
    
    // -layoutIfNeeded is necessary on the window so that we can scroll the grid
    // view to a particular spot immediately, instead of having to wait until
    // the next layout pass (eg using NSTimer).
    [_window layoutIfNeeded];
    
    ImageRecordPtr rec = [_active.fullSizeImageView imageRecord];
    [_active.imageGridView setSelection:{ rec }];
    [_window makeFirstResponder:_active.imageGridView];
    [_active.imageGridView scrollToImageRect:[_active.imageGridView rectForImageRecord:rec] center:true];
//    [NSTimer scheduledTimerWithTimeInterval:0 repeats:false block:^(NSTimer* timer) {
//        [_active.imageGridView scrollToImageRect:[_active.imageGridView rectForImageRecord:rec] center:true];
//    }];
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer* timer) {
//        [_active.imageGridView scrollToImageRect:[_active.imageGridView rectForImageRecord:[_active.fullSizeImageView imageRecord]]];
//    }];
    
//    ImageGridView* imageGridView = Toastbox::Cast<ImageGridView*>([imageGridScrollView document]);
//    
//    [_active.imageGridScrollView imageGridView];
}

- (void)fullSizeImageViewPreviousImage:(FullSizeImageView*)x {
    assert(x == _active.fullSizeImageView);
    const bool ok = [self _openImage:[_active.fullSizeImageView imageRecord] delta:-1];
    if (!ok) NSBeep();
}

- (void)fullSizeImageViewNextImage:(FullSizeImageView*)x {
    assert(x == _active.fullSizeImageView);
    const bool ok = [self _openImage:[_active.fullSizeImageView imageRecord] delta:1];
    if (!ok) NSBeep();
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

// MARK: - DeviceImageGridHeaderViewDelegate

- (void)deviceImageGridHeaderViewLoad:(DeviceImageGridHeaderView*)x {
    MDCDevicePtr device = Toastbox::Cast<MDCDevicePtr>(_active.imageSource);
    device->sync();
}

@end

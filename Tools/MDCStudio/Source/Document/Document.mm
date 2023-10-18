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
    
    NSView* _rightContainerView;
    NSView* _rightView;
    
    SourceListView* _sourceListView;
    
    ImageGridScrollView* _imageGridScrollView;
    ImageGridView* _imageGridView;
    ImageGridHeaderView* _imageGridHeaderView;
    
    FullSizeImageView* _fullSizeImageView;
    
    InspectorView* _inspectorView;
    
    Object::ObserverPtr _deviceOb;
    Object::ObserverPtr _imageLibraryOb;
    
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
    [x.containerView addSubview:x.view];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[v]|"
        options:0 metrics:nil views:@{@"v":x.view}]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[v]|"
        options:0 metrics:nil views:@{@"v":x.view}]];
    // setNeedsLayout: is necessary to ensure the grid view is sized properly,
    // when showing the grid view.
    [y setNeedsLayout:true];
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

- (BOOL)validateMenuItem:(NSMenuItem*)item {
    NSLog(@"[Document] validateMenuItem: %@\n", [item title]);
    
    if ([item action] == @selector(saveDocument:)) {
        return false;
    } else if ([item action] == @selector(saveDocumentAs:)) {
        return false;
    
    } else if ([item action] == @selector(_sortNewestFirst:)) {
        [item setState:(_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
    } else if ([item action] == @selector(_sortOldestFirst:)) {
        [item setState:(!_SortNewestFirst() ? NSControlStateValueOn : NSControlStateValueOff)];
    
    } else if ([item action] == @selector(_toggleDevices:)) {
        [item setTitle:([[self _devicesContainerView] isHidden] ? @"Show Devices" : @"Hide Devices")];
    } else if ([item action] == @selector(_toggleInspector:)) {
        [item setTitle:([[self _inspectorContainerView] isHidden] ? @"Show Inspector" : @"Hide Inspector")];
    
    } else if ([item action] == @selector(_export:)) {
        if (_center.view == _fullSizeImageView) {
            return true;
        } else if (_center.view == _imageGridScrollView) {
            return ![_imageGridView selection].empty();
        } else {
            abort();
        }
    }
    
    return [super validateMenuItem:item];
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
    if (_imageGridScrollView) {
        auto v = Toastbox::Cast<ImageGridView*>([_imageGridScrollView document]);
        _UpdateImageGridViewFromPrefs(PrefsGlobal(), v);
    }
}

// _openImage: open a particular image id, or an image offset from a particular image id
- (bool)_openImage:(ImageRecordPtr)rec delta:(ssize_t)delta {
    const bool sortNewestFirst = _SortNewestFirst();
    
    ImageSourcePtr imageSource = [_sourceListView selection];
    if (!imageSource) return false;
    
    ImageLibraryPtr imageLibrary = imageSource->imageLibrary();
    {
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
        
        [_fullSizeImageView setImageRecord:imageRecord];
        
        if (_center.view != _fullSizeImageView) {
            _SetView(_center, _fullSizeImageView);
            [_fullSizeImageView magnifyToFit];
            [_window makeFirstResponder:_fullSizeImageView];
        }
        
        ImageSet selection;
        selection.insert(imageRecord);
        [_inspectorView setSelection:selection];
        
        printf("Showing image id %ju\n", (uintmax_t)imageRecord->info.id);
        
        return true;
    }
}

// MARK: - Source List
- (void)sourceListViewSelectionChanged:(SourceListView*)sourceListView {
//    {
//        auto imageSource = std::make_shared<MockImageSource>("/Users/dave/Desktop/ImageLibrary");
//        
//        ImageGridView* imageGridView = [[ImageGridView alloc] initWithImageSource:imageSource];
//        [imageGridView setDelegate:self];
//        
//        [self setCenterView:[[ImageGridScrollView alloc] initWithFixedDocument:imageGridView]];
//        [self setInspectorView:[[InspectorView alloc] initWithImageSource:imageSource]];
//        
//        [[_splitView window] makeFirstResponder:imageGridView];
//    }
    
    assert(sourceListView == _sourceListView);
    MDCDevicePtr device = Toastbox::CastOrNull<MDCDevicePtr>([_sourceListView selection]);
    if (device) {
        {
            _imageGridView = [[ImageGridView alloc] initWithImageSource:device];
            [_imageGridView setDelegate:self];
            _UpdateImageGridViewFromPrefs(PrefsGlobal(), _imageGridView);
            
            DeviceImageGridHeaderView* headerView = [[DeviceImageGridHeaderView alloc] initWithFrame:{}];
            [headerView setDelegate:self];
            _imageGridHeaderView = headerView;
            
            _imageGridScrollView = [[ImageGridScrollView alloc] initWithFixedDocument:_imageGridView];
            [_imageGridScrollView setHeaderView:_imageGridHeaderView];
        }
        
        {
            _fullSizeImageView = [[FullSizeImageView alloc] initWithImageSource:device];
            [_fullSizeImageView setDelegate:self];
        }
        
        {
            _inspectorView = [[InspectorView alloc] initWithImageSource:device];
        }
        
        _SetView(_center, _imageGridScrollView);
        _SetView(_right, _inspectorView);
        [_window makeFirstResponder:_imageGridView];
        
        __weak auto selfWeak = self;
        // Observe device
        _deviceOb = device->observerAdd([=] (auto, auto) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _deviceChanged]; });
        });
        
        // Observe image library
        _imageLibraryOb = device->imageLibrary()->observerAdd([=] (auto, auto) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _imageLibraryChanged]; });
        });
        
        [self _updateImageGridHeader];
        
//        [_mainView setContentView:sv animation:MainViewAnimation::None];
    
    } else {
//        [_mainView setCenterView:nil];
    }
}

- (void)sourceListView:(SourceListView*)sourceListView showDeviceSettings:(MDCDevicePtr)device {
    assert(sourceListView == _sourceListView);
    [self _showDeviceSettings:device];
}

static std::optional<size_t> _LoadCount(const MDCDevice::Status& status, ImageLibraryPtr imageLibrary) {
    // Short-circut if syncing is in progress.
    // In that case, we don't want to show the 'Load' button in the header
    if (status.sync) return std::nullopt;
    
    {
        auto lock = std::unique_lock(*imageLibrary);
        const Img::Id libImgIdEnd = (!imageLibrary->empty() ? imageLibrary->back()->info.id+1 : 0);
        
        // Calculate how many images to add to the end of the library: device has, lib doesn't
        if (libImgIdEnd > status.imgIdEnd) {
            #warning TODO: how do we properly handle this situation?
            throw Toastbox::RuntimeError("image library claims to have newer images than the device (libImgIdEnd: %ju, status.imgIdEnd: %ju)",
                (uintmax_t)libImgIdEnd,
                (uintmax_t)status.imgIdEnd
            );
        }
        
        return status.imgIdEnd - std::max(status.imgIdBegin, libImgIdEnd);
    }
}

- (void)_updateImageGridHeader {
    MDCDevicePtr device = Toastbox::CastOrNull<MDCDevicePtr>([_sourceListView selection]);
    if (!device) return;
    
    ImageLibraryPtr imageLibrary = device->imageLibrary();
    DeviceImageGridHeaderView* deviceHeader = Toastbox::Cast<DeviceImageGridHeaderView*>(_imageGridHeaderView);
    const MDCDevice::Status status = device->status();
    const ImageSet& selection = [_imageGridView selection];
    
    // Update status
    if (selection.empty()) {
        [_imageGridHeaderView setStatus:@(ImageLibraryStatus(imageLibrary, "No photos").c_str())];
    
    } else {
        const Time::Instant first = (*selection.begin())->info.timestamp;
        const Time::Instant last = (*std::prev(selection.end()))->info.timestamp;
        const std::string status = ImageLibraryStatus(selection.size(), first, last,
            "photo selected", "photos selected");
        [_imageGridHeaderView setStatus:@(status.c_str())];
    }
    
    // Update unloaded photo count
    {
        const std::optional<size_t> loadCount = _LoadCount(status, imageLibrary);
        [deviceHeader setLoadCount:loadCount.value_or(0)];
    }
    
    // Upload load progress
    {
        const float progress = (status.sync ? status.sync->progress : 0);
        [deviceHeader setProgress:progress];
    }
}

- (void)_updateDevices {
    std::set<ImageSourcePtr> imageSources;
    std::vector<MDCDevicePtr> devices = MDCDevicesManagerGlobal()->devices();
    for (MDCDevicePtr device : devices) {
        imageSources.insert(device);
    }
    [_sourceListView setImageSources:imageSources];
    
    const bool haveDevices = !imageSources.empty();
    [_splitView setHidden:!haveDevices];
    [_noDevicesView setHidden:haveDevices];
}

- (void)_deviceChanged {
    [self _updateImageGridHeader];
}

- (void)_imageLibraryChanged {
    [self _updateImageGridHeader];
}

// MARK: - Image Grid

- (void)imageGridViewSelectionChanged:(ImageGridView*)imageGridView {
    assert(imageGridView == _imageGridView);
    [_inspectorView setSelection:[_imageGridView selection]];
    [self _updateImageGridHeader];
}

- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView {
    assert(imageGridView == _imageGridView);
    const ImageSet selection = [_imageGridView selection];
    if (selection.empty()) return;
    const ImageRecordPtr rec = *selection.begin();
    [self _openImage:rec delta:0];
}

// MARK: - Full Size Image View

- (void)fullSizeImageViewBack:(FullSizeImageView*)x {
    assert(x == _fullSizeImageView);
    _SetView(_center, _imageGridScrollView);
    
    // -layoutIfNeeded is necessary on the window so that we can scroll the grid
    // view to a particular spot immediately, instead of having to wait until
    // the next layout pass (eg using NSTimer).
    [_window layoutIfNeeded];
    
    ImageRecordPtr rec = [_fullSizeImageView imageRecord];
    [_imageGridView setSelection:{ rec }];
    [_window makeFirstResponder:_imageGridView];
    [_imageGridView scrollToImageRect:[_imageGridView rectForImageRecord:rec] center:true];
//    [NSTimer scheduledTimerWithTimeInterval:0 repeats:false block:^(NSTimer* timer) {
//        [_imageGridView scrollToImageRect:[_imageGridView rectForImageRecord:rec] center:true];
//    }];
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer* timer) {
//        [_imageGridView scrollToImageRect:[_imageGridView rectForImageRecord:[_fullSizeImageView imageRecord]]];
//    }];
    
//    ImageGridView* imageGridView = Toastbox::Cast<ImageGridView*>([imageGridScrollView document]);
//    
//    [_imageGridScrollView imageGridView];
}

- (void)fullSizeImageViewPreviousImage:(FullSizeImageView*)x {
    assert(x == _fullSizeImageView);
    const bool ok = [self _openImage:[_fullSizeImageView imageRecord] delta:-1];
    if (!ok) NSBeep();
}

- (void)fullSizeImageViewNextImage:(FullSizeImageView*)x {
    assert(x == _fullSizeImageView);
    const bool ok = [self _openImage:[_fullSizeImageView imageRecord] delta:1];
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

- (IBAction)_export:(id)sender {
    printf("_export\n");
}

// MARK: - Device Settings
- (void)_showDeviceSettings:(MDCDevicePtr)device {
//    ImageSourcePtr source = [_sourceListView selection];
//    MDCDevicePtr device = Toastbox::CastOrNull<MDCDevicePtr>(source);
//    if (!device) return;
    
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
    MDCDevicePtr device = Toastbox::Cast<MDCDevicePtr>([_sourceListView selection]);
    device->sync();
}

@end

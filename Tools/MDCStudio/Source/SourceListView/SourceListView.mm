#import "SourceListView.h"
#import <vector>
#import "Util.h"
#import "MDCDevicesManager.h"
#import "Toastbox/Mac/Util.h"
#import "ImageLibraryStatus.h"
#import "NibViewInit.h"
@class SourceListView;
using namespace MDCStudio;

//static NSMenu* _DeviceContextMenuCreate() {
//    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
//    [menu addItemWithTitle:@"Settings…" action:@selector(_settings:) keyEquivalent:@""];
//    [menu addItemWithTitle:@"Factory Reset…" action:@selector(_factoryReset:) keyEquivalent:@""];
//    return menu;
//}

@interface SourceListView ()
- (void)_showSettingsForDevice:(MDCDevicePtr)device;
@end

// MARK: - Outline View Items

@interface SourceListView_Item : NSTableCellView
@end

@implementation SourceListView_Item {
@public
    NSString* name;
    __weak SourceListView* sourceListView;
    IBOutlet NSLayoutConstraint* _height;
    ImageSourcePtr _imageSource;
    Object::ObserverPtr _imageLibraryOb;
}

- (NSString*)name { return name; }
- (bool)selectable { return true; }
- (CGFloat)height { return 74; }

- (ImageSourcePtr)imageSource {
    return _imageSource;
}

- (void)setImageSource:(ImageSourcePtr)x {
    _imageSource = x;
    __weak auto selfWeak = self;
    _imageLibraryOb = _imageSource->imageLibrary()->observerAdd([=] (auto, auto) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak update]; });
    });
}

- (void)update {
    [_height setConstant:[self height]];
    if (![[self textField] currentEditor]) {
        [[self textField] setStringValue:[self name]];
    }
}

@end



















@interface SourceListView_Device : SourceListView_Item
@end

@implementation SourceListView_Device {
@public
    IBOutlet NSImageView* _batteryImageView;
    IBOutlet NSTextField* _descriptionLabel;
    Object::ObserverPtr _deviceOb;
}

- (MDCDevicePtr)device {
    return Toastbox::Cast<MDCDevicePtr>(_imageSource);
}

- (NSString*)name { return @([self device]->name().c_str()); }

- (void)setImageSource:(ImageSourcePtr)x {
    [super setImageSource:x];
    
    __weak auto selfWeak = self;
    _deviceOb = [self device]->observerAdd([=] (auto, auto) {
        dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak update]; });
    });
}

static NSString* _BatteryLevelImage(float level) {
    if (level == 1) {
        return @"SourceList-Battery-Charged";
    } else if (level == 0) {
        return @"SourceList-Battery-Error";
    } else {
        const int levelInt = ((int)(level*10))*10;
        return [NSString stringWithFormat:@"SourceList-Battery-Charging-%d", levelInt];
    }
}

- (void)update {
    [super update];
    [_batteryImageView setImage:[NSImage imageNamed:_BatteryLevelImage([self device]->status().batteryLevel)]];
    [_descriptionLabel setStringValue:@(ImageLibraryStatus([self device]->imageLibrary()).c_str())];
}

- (IBAction)_textFieldChanged:(id)sender {
    [self device]->name([[[self textField] stringValue] UTF8String]);
}

- (IBAction)_settings:(id)sender {
    [sourceListView _showSettingsForDevice:[self device]];
}

@end

@interface SourceListView_RowView : NSTableRowView
@end

@implementation SourceListView_RowView
- (BOOL)isEmphasized { return false; }
@end

#define Item            SourceListView_Item
#define Device          SourceListView_Device
#define RowView         SourceListView_RowView

// MARK: - SourceListView

@implementation SourceListView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSOutlineView* _outlineView;
    
    std::vector<Item*> _items;
    
    __weak id<SourceListViewDelegate> _delegate;
}

// MARK: - Creation

static void _Init(SourceListView* self) {
    NibViewInit(self, self->_nibView);
    {
        NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
        [menu addItemWithTitle:@"Settings…" action:@selector(_settings:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Factory Reset…" action:@selector(_factoryReset:) keyEquivalent:@""];
        [self->_outlineView setMenu:menu];
    }
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _Init(self);
    return self;
}

// MARK: - Methods

- (void)setImageSources:(const std::set<ImageSourcePtr>&)x {
    ImageSourcePtr selectedImageSource;
    Item* selectedItem = nil;
    const NSInteger selectedRow = [_outlineView selectedRow];
    if (selectedRow >= 0) {
        selectedImageSource = [Toastbox::Cast<Item*>(_items.at(selectedRow)) imageSource];
    }
    
    _items.clear();
    for (ImageSourcePtr imageSource : x) {
        Item* it = [self _createItemForImageSource:imageSource];
        _items.push_back(it);
        if (imageSource == selectedImageSource) {
            selectedItem = it;
        }
    }
    
    // Sort items
    std::sort(_items.begin(), _items.end(), [](Item* a, Item* b) {
        return [Toastbox::Cast<Item*>(a)->name compare:Toastbox::Cast<Item*>(b)->name] == NSOrderedDescending;
    });
    
    [_outlineView reloadData];
    for (auto item : _items) {
        [_outlineView expandItem:item];
    }
    
    // Restore selection
    if (selectedItem) {
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[_outlineView rowForItem:selectedItem]]
            byExtendingSelection:false];
    }
    
//    // Collect the old and new device sets
//    std::set<MDCDevicePtr> oldDevices;
//    std::set<MDCDevicePtr> newDevices;
//    {
//        for (Item* it : _items) {
//            oldDevices.insert(Toastbox::Cast<Device*>(it)->device);
//        }
//        
//        std::vector<MDCDevicePtr> newDevicesVec = MDCDevicesManager::Devices();
//        newDevices.insert(newDevicesVec.begin(), newDevicesVec.end());
//    }
//    
//    // Remove disconnected devices
//    for (auto it=_items.begin(); it!=_items.end();) {
//        MDCDevicePtr dev = Toastbox::Cast<Device*>(*it)->device;
//        if (newDevices.find(dev) == newDevices.end()) {
//            it = _items.erase(it);
//        } else {
//            it++;
//        }
//    }
//    
//    // Add connected devices
//    for (const MDCDevicePtr& dev : newDevices) {
//        if (oldDevices.find(dev) == oldDevices.end()) {
//            Device* item = [self _createItemWithClass:[Device class]];
//            [item setDevice:dev];
//            _items.push_back(item);
//        }
//    }
//    
//    // Sort devices
//    std::sort(_items.begin(), _items.end(), [](Item* a, Item* b) {
//        return [Toastbox::Cast<Device*>(a)->name compare:Toastbox::Cast<Device*>(b)->name] == NSOrderedDescending;
//    });
}

- (void)setDelegate:(id<SourceListViewDelegate>)delegate {
    _delegate = delegate;
}

- (ImageSourcePtr)selection {
    const NSInteger selectedRow = [_outlineView selectedRow];
    if (selectedRow < 0) return nullptr;
    return [Toastbox::Cast<Item*>(_items.at(selectedRow)) imageSource];
}

- (Item*)_createItemForImageSource:(ImageSourcePtr)imageSource {
    NSParameterAssert(imageSource);
    Item* view = nil;
    if (auto it = Toastbox::CastOrNull<MDCDevicePtr>(imageSource)) {
        view = Toastbox::Cast<Device*>([_outlineView makeViewWithIdentifier:NSStringFromClass([Device class]) owner:nil]);
        assert(view);
    }
    
    view->sourceListView = self;
    [view setImageSource:imageSource];
    return view;
}

//- (void)_updateDevices {
//    // Collect the old and new device sets
//    std::set<MDCDevicePtr> oldDevices;
//    std::set<MDCDevicePtr> newDevices;
//    {
//        for (Item* it : _items) {
//            oldDevices.insert(Toastbox::Cast<Device*>(it)->device);
//        }
//        
//        std::vector<MDCDevicePtr> newDevicesVec = MDCDevicesManager::Devices();
//        newDevices.insert(newDevicesVec.begin(), newDevicesVec.end());
//    }
//    
//    // Remove disconnected devices
//    for (auto it=_items.begin(); it!=_items.end();) {
//        MDCDevicePtr dev = Toastbox::Cast<Device*>(*it)->device;
//        if (newDevices.find(dev) == newDevices.end()) {
//            it = _items.erase(it);
//        } else {
//            it++;
//        }
//    }
//    
//    // Add connected devices
//    for (const MDCDevicePtr& dev : newDevices) {
//        if (oldDevices.find(dev) == oldDevices.end()) {
//            Device* item = [self _createItemWithClass:[Device class]];
//            [item setDevice:dev];
//            _items.push_back(item);
//        }
//    }
//    
//    // Sort devices
//    std::sort(_items.begin(), _items.end(), [](Item* a, Item* b) {
//        return [Toastbox::Cast<Device*>(a)->name compare:Toastbox::Cast<Device*>(b)->name] == NSOrderedDescending;
//    });
//}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    // Fix intermittent issue where our sole column can be sized a few points too large,
    // causing the enclosing scroll view to be able to scroll horizontally (which
    // we don't want)
    CGFloat usableWidth = [self bounds].size.width-4;
    [[_outlineView tableColumns][0] setWidth:usableWidth];
}

// MARK: - Menu Actions

- (MDCDevicePtr)_clickedDevice {
    const NSInteger clickedRow = [_outlineView clickedRow];
    if (clickedRow < 0) return nullptr;
    return [Toastbox::Cast<Device*>(_items.at(clickedRow)) device];
}

- (IBAction)_settings:(id)sender {
    if (MDCDevicePtr device = [self _clickedDevice]) {
        [_delegate sourceListView:self showSettingsForDevice:device];
    }
}

- (IBAction)_factoryReset:(id)sender {
    if (MDCDevicePtr device = [self _clickedDevice]) {
        [_delegate sourceListView:self factoryResetDevice:device];
    }
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    MDCDevicePtr clickedDevice = [self _clickedDevice];
    if ([item action] == @selector(_settings:)) {
        return (bool)clickedDevice;
    } else if ([item action] == @selector(_factoryReset:)) {
        return (bool)clickedDevice;
    }
    return true;
}

- (void)_showSettingsForDevice:(MDCDevicePtr)device {
    [_delegate sourceListView:self showSettingsForDevice:device];
}

- (void)_factoryResetDevice:(MDCDevicePtr)device {
    [_delegate sourceListView:self factoryResetDevice:device];
}

// MARK: - Outline View Data Source / Delegate

- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nullptr) {
        return _items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        return _items[index];
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldSelectItem:(id)item {
    if (auto it = Toastbox::CastOrNull<Item*>(item)) {
        return [it selectable];
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldShowOutlineCellForItem:(id)item {
    return false;
}

- (NSTableRowView*)outlineView:(NSOutlineView*)outlineView rowViewForItem:(id)item {
    return [_outlineView makeViewWithIdentifier:NSStringFromClass([RowView class]) owner:nil];
}

- (NSView*)outlineView:(NSOutlineView*)outlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item {
    Item* it = Toastbox::Cast<Item*>(item);
    [it update];
    return item;
}

//- (void)outlineView:(NSOutlineView*)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)tableColumn item:(id)item {
//    NSLog(@"AAA %@", NSStringFromSelector(_cmd));
//}

- (void)outlineViewSelectionDidChange:(NSNotification*)note {
    [_delegate sourceListViewSelectionChanged:self];
}

@end

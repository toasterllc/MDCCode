#import "SourceListView.h"
#import <vector>
#import "Util.h"
#import "MDCDevicesManager.h"
#import "Toastbox/Mac/Util.h"
@class SourceListView;
using namespace MDCStudio;

@interface SourceListView ()
- (void)_showDeviceSettings:(MDCDevicePtr)device;
@end

// MARK: - Outline View Items

@interface SourceListView_Item : NSTableCellView
@end

@implementation SourceListView_Item {
@public
    SourceListView* sourceListView;
@protected
//    IBOutlet NSLayoutConstraint* _indent;
    IBOutlet NSLayoutConstraint* _height;
}

- (NSString*)name { abort(); }
- (bool)selectable { abort(); }
- (CGFloat)height { return 20; }
//- (CGFloat)indent { return 0; }

- (void)update {
//    [_indent setConstant:[self indent]];
    [_height setConstant:[self height]];
    [[self textField] setStringValue:[self name]];
}

@end

@interface SourceListView_Section : SourceListView_Item
@end

@implementation SourceListView_Section {
@public
    NSString* name;
    std::vector<SourceListView_Item*> items;
}

- (NSString*)name { return [name uppercaseString]; }
- (bool)selectable { return false; }
- (CGFloat)height { return 20; }

- (void)update {
    [super update];
    for (SourceListView_Item* it : items) {
        [it update];
    }
}

@end

@interface SourceListView_SectionItem : SourceListView_Item
@end

@implementation SourceListView_SectionItem {
@public
    NSString* name;
}
- (NSString*)name { return name; }
- (bool)selectable { return true; }
- (CGFloat)height { return 74; }
//- (CGFloat)indent { return [super indent]+5; }
@end

@interface SourceListView_Library : SourceListView_SectionItem
@end

@implementation SourceListView_Library
@end

@interface SourceListView_Device : SourceListView_SectionItem
@end

@implementation SourceListView_Device {
@public
    IBOutlet NSImageView* _batteryImageView;
    MDCDevicePtr device;
}

- (NSString*)name { return @(device->name().c_str()); }

- (void)setDevice:(MDCDevicePtr)dev {
    assert(!device); // We're one-time use since MDCDevice observers can't be removed
    device = dev;
    __weak auto selfWeak = self;
    device->observerAdd([=] {
        auto selfStrong = selfWeak;
        if (!selfStrong) return false;
        dispatch_async(dispatch_get_main_queue(), ^{ [selfStrong update]; });
        return true;
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
    [_batteryImageView setImage:[NSImage imageNamed:_BatteryLevelImage(device->batteryLevel())]];
}

- (IBAction)textFieldAction:(id)sender {
    device->name([[[self textField] stringValue] UTF8String]);
}

- (IBAction)settingsAction:(id)sender {
    [sourceListView _showDeviceSettings:device];
}

@end

@interface SourceListView_Spacer : SourceListView_Item
@end

@implementation SourceListView_Spacer {
@public
    CGFloat height;
}
- (NSString*)name { return @""; }
- (bool)selectable { return false; }
- (CGFloat)height { return height; }
@end

@interface SourceListView_RowView : NSTableRowView
@end

@implementation SourceListView_RowView
- (BOOL)isEmphasized { return false; }
@end

#define Device          SourceListView_Device
#define Item            SourceListView_Item
#define Library         SourceListView_Library
#define RowView         SourceListView_RowView
#define Section         SourceListView_Section
#define SectionItem     SourceListView_SectionItem
#define Spacer          SourceListView_Spacer

// MARK: - SourceListView

@implementation SourceListView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSOutlineView* _outlineView;
    
    Section* _devicesSection;
    Section* _librariesSection;
    std::vector<Item*> _outlineItems;
    
    __weak id<SourceListViewDelegate> _delegate;
}

// MARK: - Creation

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self initCommon];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self initCommon];
    return self;
}

- (void)initCommon {
    // Load view from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:_nibView];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    }
    
    // Observe devices connecting/disconnecting
    {
        __weak auto selfWeak = self;
        MDCDevicesManager::AddObserver([=] {
            auto selfStrong = selfWeak;
            if (!selfStrong) return false;
            dispatch_async(dispatch_get_main_queue(), ^{
                [selfStrong _updateDevices];
                [selfStrong->_outlineView reloadData];
            });
            return true;
        });
    }
    
    // Populate NSOutlineView
    {
        Spacer* spacer1 = [self _createItemWithClass:[Spacer class]];
        spacer1->height = 3;
        
        _devicesSection = [self _createItemWithClass:[Section class]];
        _devicesSection->name = @"Devices";
        
        Spacer* spacer2 = [self _createItemWithClass:[Spacer class]];
        spacer2->height = 10;
        
        _librariesSection = [self _createItemWithClass:[Section class]];
        _librariesSection->name = @"Libraries";
        
    //    Device* device = [self _createItemWithClass:[Device class]];
    //    device->name = @"MDC Device 123456";
    //    _devicesSection->items.push_back(device);
        
//        Library* library = [self _createItemWithClass:[Library class]];
//        library->name = @"New Library";
//        _librariesSection->items.push_back(library);
        
        _outlineItems = {
//            spacer1,
            _devicesSection,
//            spacer2,
//            _librariesSection,
        };
        
        [self _updateDevices];
        [_outlineView reloadData];
        
        for (auto item : _outlineItems) {
            [_outlineView expandItem:item];
        }
        
        // Select first device by default
        const NSInteger selectedRow = [_outlineView selectedRow];
        if (selectedRow<0 && !_devicesSection->items.empty()) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[_outlineView rowForItem:_devicesSection->items.at(0)]] byExtendingSelection:false];
        }
    }
}

// MARK: - Methods

- (void)setDelegate:(id<SourceListViewDelegate>)delegate {
    _delegate = delegate;
}

- (ImageSourcePtr)selection {
    const NSInteger selectedRow = [_outlineView selectedRow];
    if (selectedRow < 0) return {};
    
    if (Device* dev = Toastbox::CastOrNull<Device*>([_outlineView itemAtRow:selectedRow])) {
        return dev->device;
    }
    
    return {};
}

- (id)_createItemWithClass:(Class)itemClass {
    NSParameterAssert(itemClass);
    Item* view = Toastbox::Cast<Item*>([_outlineView makeViewWithIdentifier:NSStringFromClass(itemClass) owner:nil]);
    assert(view);
    view->sourceListView = self;
    return view;
}

- (void)_updateDevices {
    // Collect the old and new device sets
    std::set<MDCDevicePtr> oldDevices;
    std::set<MDCDevicePtr> newDevices;
    {
        for (Item* it : _devicesSection->items) {
            oldDevices.insert(Toastbox::Cast<Device*>(it)->device);
        }
        
        std::vector<MDCDevicePtr> newDevicesVec = MDCDevicesManager::Devices();
        newDevices.insert(newDevicesVec.begin(), newDevicesVec.end());
    }
    
    // Remove disconnected devices
    for (auto it=_devicesSection->items.begin(); it!=_devicesSection->items.end();) {
        MDCDevicePtr dev = Toastbox::Cast<Device*>(*it)->device;
        if (newDevices.find(dev) == newDevices.end()) {
            it = _devicesSection->items.erase(it);
        } else {
            it++;
        }
    }
    
    // Add connected devices
    for (const MDCDevicePtr& dev : newDevices) {
        if (oldDevices.find(dev) == oldDevices.end()) {
            Device* item = [self _createItemWithClass:[Device class]];
            [item setDevice:dev];
            _devicesSection->items.push_back(item);
        }
    }
    
    // Sort devices
    std::sort(_devicesSection->items.begin(), _devicesSection->items.end(), [](Item* a, Item* b) {
        return [Toastbox::Cast<Device*>(a)->name compare:Toastbox::Cast<Device*>(b)->name] == NSOrderedDescending;
    });
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    // Fix intermittent issue where our sole column can be sized a few points too large,
    // causing the enclosing scroll view to be able to scroll horizontally (which
    // we don't want)
    CGFloat usableWidth = [self bounds].size.width-4;
    [[_outlineView tableColumns][0] setWidth:usableWidth];
}

- (void)_showDeviceSettings:(MDCDevicePtr)device {
    [_delegate sourceListView:self showDeviceSettings:device];
}

//- (void)_handleDevicesChanged {
//    std::set<MDCDevicePtr> connected;
//    std::set<MDCDevicePtr> disconnected;
//    
//    // Determine which devices were connected/disconnected
//    {
//        std::set<MDCDevicePtr> oldDevices;
//        for (Item* it : _devicesSection->items) {
//            oldDevices.insert(Cast<Device>(it)->device);
//        }
//        
//        std::vector<MDCDevicePtr> newDevicesVec = MDCDevicesManager::Devices();
//        std::set<MDCDevicePtr> newDevices(newDevicesVec.begin(), newDevicesVec.end());
//        
//        for (const MDCDevicePtr& dev : newDevices) {
//            if (oldDevices.find(dev) == oldDevices.end()) {
//                connected.insert(dev);
//            }
//        }
//        
//        for (const MDCDevicePtr& dev : oldDevices) {
//            if (newDevices.find(dev) == newDevices.end()) {
//                disconnected.insert(dev);
//            }
//        }
//    }
//    
//    // Handle disconnected devices
//    for (auto it=_devicesSection->items.rend(); it!=_devicesSection->items.rbegin(); it++) {
//        
//    }
//    
//    for (Item* it : _devicesSection->items) {
//        oldDevices.insert(Cast<Device>(it)->device);
//    }
//    
//    for (const MDCDevicePtr& dev : disconnected) {
//        
//    }
//    
//    // Handle connected devices
//    for (const MDCDevicePtr& dev : connected) {
//        
//    }
//}

// MARK: - Outline View Data Source / Delegate

- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nullptr) {
        return _outlineItems.size();
    
    } else if (auto it = Toastbox::CastOrNull<Section*>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        return _outlineItems[index];
    
    } else if (auto section = Toastbox::CastOrNull<Section*>(item)) {
        return section->items.at(index);
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    if (auto it = Toastbox::CastOrNull<Section*>(item)) {
        return true;
    }
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
    [Toastbox::Cast<Item*>(item) update];
    return item;
}

//- (void)outlineView:(NSOutlineView*)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)tableColumn item:(id)item {
//    NSLog(@"AAA %@", NSStringFromSelector(_cmd));
//}

- (void)outlineViewSelectionDidChange:(NSNotification*)note {
    [_delegate sourceListViewSelectionChanged:self];
}

@end

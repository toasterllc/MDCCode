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
    NSString* name;
    __weak SourceListView* sourceListView;
@protected
//    IBOutlet NSLayoutConstraint* _indent;
    IBOutlet NSLayoutConstraint* _height;
}

- (NSString*)name { return name; }
- (bool)selectable { return true; }
- (CGFloat)height { return 74; }
//- (CGFloat)indent { return 0; }

- (void)update {
//    [_indent setConstant:[self indent]];
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

@interface SourceListView_RowView : NSTableRowView
@end

@implementation SourceListView_RowView
- (BOOL)isEmphasized { return false; }
@end

#define Device          SourceListView_Device
#define Item            SourceListView_Item
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
        _items = {};
        
        [self _updateDevices];
        [_outlineView reloadData];
        
        for (auto item : _items) {
            [_outlineView expandItem:item];
        }
        
        // Select first device by default
        const NSInteger selectedRow = [_outlineView selectedRow];
        if (selectedRow<0 && !_items.empty()) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[_outlineView rowForItem:_items.at(0)]] byExtendingSelection:false];
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
        for (Item* it : _items) {
            oldDevices.insert(Toastbox::Cast<Device*>(it)->device);
        }
        
        std::vector<MDCDevicePtr> newDevicesVec = MDCDevicesManager::Devices();
        newDevices.insert(newDevicesVec.begin(), newDevicesVec.end());
    }
    
    // Remove disconnected devices
    for (auto it=_items.begin(); it!=_items.end();) {
        MDCDevicePtr dev = Toastbox::Cast<Device*>(*it)->device;
        if (newDevices.find(dev) == newDevices.end()) {
            it = _items.erase(it);
        } else {
            it++;
        }
    }
    
    // Add connected devices
    for (const MDCDevicePtr& dev : newDevices) {
        if (oldDevices.find(dev) == oldDevices.end()) {
            Device* item = [self _createItemWithClass:[Device class]];
            [item setDevice:dev];
            _items.push_back(item);
        }
    }
    
    // Sort devices
    std::sort(_items.begin(), _items.end(), [](Item* a, Item* b) {
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

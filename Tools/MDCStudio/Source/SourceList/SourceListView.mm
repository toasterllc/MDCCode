#import "SourceListView.h"
#import <vector>
#import "Util.h"
#import "MDCDevicesManager.h"
using namespace MDCStudio;

// MARK: - Outline View Items

#define Device          SourceListView_Device
#define Item            SourceListView_Item
#define Library         SourceListView_Library
#define RowView         SourceListView_RowView
#define Section         SourceListView_Section
#define SectionItem     SourceListView_SectionItem
#define Spacer          SourceListView_Spacer

@interface Item : NSTableCellView
@end

@implementation Item {
    IBOutlet NSLayoutConstraint* _indent;
    IBOutlet NSLayoutConstraint* _height;
}

- (NSString*)name { abort(); }
- (bool)selectable { abort(); }
- (CGFloat)height { return 20; }
- (CGFloat)indent { return 12; }

- (void)update {
    [_indent setConstant:[self indent]];
    [_height setConstant:[self height]];
    [[self textField] setStringValue:[self name]];
}

@end

@interface Section : Item
@end

@implementation Section {
@public
    NSString* name;
    std::vector<Item*> items;
}

- (NSString*)name { return [name uppercaseString]; }
- (bool)selectable { return false; }
- (CGFloat)height { return 20; }

- (void)update {
    [super update];
    for (Item* it : items) {
        [it update];
    }
}

@end




@interface SectionItem : Item
@end

@implementation SectionItem {
@public
    NSString* name;
}
- (NSString*)name { return name; }
- (bool)selectable { return true; }
- (CGFloat)height { return 25; }
- (CGFloat)indent { return [super indent]+5; }
@end



@interface Library : SectionItem
@end

@implementation Library
@end

@interface Device : SectionItem
@end

@implementation Device {
@public
    MDCDevicePtr device;
}

- (NSString*)name { return [NSString stringWithFormat:@"MDC Device %s", device->serial().c_str()]; }

@end






@interface Spacer : Item
@end

@implementation Spacer {
@public
    CGFloat height;
}
- (NSString*)name { return @""; }
- (bool)selectable { return false; }
- (CGFloat)height { return height; }
@end



@interface RowView : NSTableRowView
@end

@implementation RowView
- (BOOL)isEmphasized { return false; }
@end

// MARK: - SourceListView

@implementation SourceListView {
    IBOutlet NSView* _nibView;
    IBOutlet NSOutlineView* _outlineView;
    Section* _devicesSection;
    Section* _librariesSection;
    
    std::vector<Item*> _outlineItems;
}

// MARK: - Creation

- (instancetype)initWithCoder:(NSCoder*)coder {
    abort();
    return [super initWithCoder:coder]; // Silence warning
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    
    // Load view from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:_nibView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    }
    
    // Observe device connecting/disconnecting
    {
        __weak auto weakSelf = self;
        MDCDevicesManager::AddObserver([=] {
            auto strongSelf = weakSelf;
            if (!strongSelf) return false;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf _updateDevices];
                [strongSelf->_outlineView reloadData];
            });
            return true;
        });
    }
    
    // Create sections
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
    //    
    //    Library* library = [self _createItemWithClass:[Library class]];
    //    library->name = @"New Library";
    //    _librariesSection->items.push_back(library);
        
        _outlineItems = {
            spacer1,
            _devicesSection,
            spacer2,
            _librariesSection,
        };
    }
    
    [self _updateDevices];
    [_outlineView reloadData];
    
    for (auto item : _outlineItems) {
        [_outlineView expandItem:item];
    }
    
    return self;
}

// MARK: - Methods

- (id)_createItemWithClass:(Class)itemClass {
    NSParameterAssert(itemClass);
    Item* view = Cast<Item>([_outlineView makeViewWithIdentifier:NSStringFromClass(itemClass) owner:nil]);
    assert(view);
    return view;
}


- (void)_updateDevices {
    // Collect the old and new device sets
    std::set<MDCDevicePtr> oldDevices;
    std::set<MDCDevicePtr> newDevices;
    {
        for (Item* it : _devicesSection->items) {
            oldDevices.insert(Cast<Device>(it)->device);
        }
        
        std::vector<MDCDevicePtr> newDevicesVec = MDCDevicesManager::Devices();
        newDevices.insert(newDevicesVec.begin(), newDevicesVec.end());
    }
    
    // Remove disconnected devices
    for (auto it=_devicesSection->items.begin(); it!=_devicesSection->items.end();) {
        MDCDevicePtr dev = Cast<Device>(*it)->device;
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
            item->device = dev;
            _devicesSection->items.push_back(item);
        }
    }
    
    // Sort devices
    std::sort(_devicesSection->items.begin(), _devicesSection->items.end(), [](Item* a, Item* b) {
        return [Cast<Device>(a)->name compare:Cast<Device>(b)->name] == NSOrderedDescending;
    });
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
    
    } else if (auto it = CastOrNil<Section>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        return _outlineItems[index];
    
    } else if (auto section = CastOrNil<Section>(item)) {
        return section->items.at(index);
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    if (auto it = CastOrNil<Section>(item)) {
        return true;
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldSelectItem:(id)item {
    if (auto it = CastOrNil<Item>(item)) {
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
    [Cast<Item>(item) update];
    return item;
}

//- (void)outlineView:(NSOutlineView*)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)tableColumn item:(id)item {
//    NSLog(@"AAA %@", NSStringFromSelector(_cmd));
//}

@end

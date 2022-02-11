#import "SourceListView.h"
#import "Util.h"
#import <vector>
using namespace MDCStudio;

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

@implementation Device
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



@implementation SourceListView {
    IBOutlet NSScrollView* _scrollView;
    IBOutlet NSOutlineView* _outlineView;
    std::vector<Item*> _outlineItems;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    abort();
    return [super initWithCoder:coder]; // Silence warning
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [_scrollView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_scrollView];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_scrollView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
    
    return self;
}

- (id)_itemForClass:(Class)itemClass {
    NSParameterAssert(itemClass);
    Item* view = DynamicCast<Item>([_outlineView makeViewWithIdentifier:NSStringFromClass(itemClass) owner:nil]);
    assert(view);
    return view;
}

- (void)_load {
    Spacer* spacer1 = [self _itemForClass:[Spacer class]];
    spacer1->height = 3;
    
    Device* device = [self _itemForClass:[Device class]];
    device->name = @"MDC Device 123457";
    
    Section* devicesSection = [self _itemForClass:[Section class]];
    devicesSection->name = @"Devices";
    devicesSection->items = { device };
    
    Spacer* spacer2 = [self _itemForClass:[Spacer class]];
    spacer2->height = 10;
    
    Library* library = [self _itemForClass:[Library class]];
    library->name = @"New Library";
    
    Section* librariesSection = [self _itemForClass:[Section class]];
    librariesSection->name = @"Libraries";
    librariesSection->items = { library };
    
    _outlineItems = {
        spacer1,
        devicesSection,
        spacer2,
        librariesSection,
    };
    
    for (Item* it : _outlineItems) {
        [it update];
    }
    
    [_outlineView reloadData];
}

- (void)awakeFromNib {
    [self _load];
    
    for (auto item : _outlineItems) {
        [_outlineView expandItem:item];
    }
}

- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nullptr) {
        return _outlineItems.size();
    
    } else if (auto it = DynamicCast<Section>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        return _outlineItems[index];
    
    } else if (auto section = DynamicCast<Section>(item)) {
        return section->items.at(index);
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    if (auto it = DynamicCast<Section>(item)) {
        return true;
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldSelectItem:(id)item {
    if (auto it = DynamicCast<Item>(item)) {
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
    return item;
}

@end

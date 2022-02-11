#import "SourceListView.h"
#import "Util.h"
#import <vector>
using namespace MDCStudio;

#define X(x) SourceListView_##x

@interface SourceListView_Item : NSTableCellView
@end

@implementation SourceListView_Item {
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
- (CGFloat)height { return 25; }
- (CGFloat)indent { return [super indent]+5; }
@end



@interface SourceListView_Library : SourceListView_SectionItem
@end

@implementation SourceListView_Library
@end

@interface SourceListView_Device : SourceListView_SectionItem
@end

@implementation SourceListView_Device
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



@implementation SourceListView {
    IBOutlet NSScrollView* _scrollView;
    IBOutlet NSOutlineView* _outlineView;
    std::vector<SourceListView_Item*> _outlineItems;
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
    SourceListView_Item* view = DynamicCast<SourceListView_Item>([_outlineView makeViewWithIdentifier:NSStringFromClass(itemClass) owner:nil]);
    assert(view);
    return view;
}

- (void)_load {
    SourceListView_Spacer* spacer1 = [self _itemForClass:[SourceListView_Spacer class]];
    spacer1->height = 3;
    
    SourceListView_Device* device = [self _itemForClass:[SourceListView_Device class]];
    device->name = @"MDC Device 123457";
    
    SourceListView_Section* devicesSection = [self _itemForClass:[SourceListView_Section class]];
    devicesSection->name = @"Devices";
    devicesSection->items = { device };
    
    SourceListView_Spacer* spacer2 = [self _itemForClass:[SourceListView_Spacer class]];
    spacer2->height = 10;
    
    SourceListView_Library* library = [self _itemForClass:[SourceListView_Library class]];
    library->name = @"New Library";
    
    SourceListView_Section* librariesSection = [self _itemForClass:[SourceListView_Section class]];
    librariesSection->name = @"Libraries";
    librariesSection->items = { library };
    
    _outlineItems = {
        spacer1,
        devicesSection,
        spacer2,
        librariesSection,
    };
    
    for (SourceListView_Item* it : _outlineItems) {
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
    
    } else if (auto it = DynamicCast<SourceListView_Section>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        return _outlineItems[index];
    
    } else if (auto section = DynamicCast<SourceListView_Section>(item)) {
        return section->items.at(index);
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    if (auto it = DynamicCast<SourceListView_Section>(item)) {
        return true;
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldSelectItem:(id)item {
    if (auto it = DynamicCast<SourceListView_Item>(item)) {
        return [it selectable];
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldShowOutlineCellForItem:(id)item {
    return false;
}

- (NSTableRowView*)outlineView:(NSOutlineView*)outlineView rowViewForItem:(id)item {
    return [_outlineView makeViewWithIdentifier:NSStringFromClass([SourceListView_RowView class]) owner:nil];
}

- (NSView*)outlineView:(NSOutlineView*)outlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item {
    return item;
}

@end

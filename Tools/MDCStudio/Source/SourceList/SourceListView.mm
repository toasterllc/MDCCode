#import "SourceListView.h"
#import "Util.h"
#import <vector>
using namespace MDCStudio;

@interface SourceListItem : NSTableCellView
@end

@implementation SourceListItem {
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

@interface SourceListSection : SourceListItem
@end

@implementation SourceListSection {
@public
    NSString* name;
    std::vector<SourceListItem*> items;
}

- (NSString*)name { return [name uppercaseString]; }
- (bool)selectable { return false; }
- (CGFloat)height { return 20; }

- (void)update {
    [super update];
    for (SourceListItem* it : items) {
        [it update];
    }
}

@end




@interface SourceListSectionItem : SourceListItem
@end

@implementation SourceListSectionItem {
@public
    NSString* name;
}
- (NSString*)name { return name; }
- (bool)selectable { return true; }
- (CGFloat)height { return 25; }
- (CGFloat)indent { return [super indent]+5; }
@end



@interface SourceListLibrary : SourceListSectionItem
@end

@implementation SourceListLibrary
@end

@interface SourceListDevice : SourceListSectionItem
@end

@implementation SourceListDevice
@end






@interface SourceListSpacer : SourceListItem
@end

@implementation SourceListSpacer {
@public
    CGFloat height;
}
- (NSString*)name { return @""; }
- (bool)selectable { return false; }
- (CGFloat)height { return height; }
@end



@interface SourceListRowView : NSTableRowView
@end

@implementation SourceListRowView
- (BOOL)isEmphasized { return false; }
@end



@implementation SourceListView {
    IBOutlet NSScrollView* _scrollView;
    IBOutlet NSOutlineView* _outlineView;
    std::vector<SourceListItem*> _outlineItems;
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
    SourceListItem* view = DynamicCast<SourceListItem>([_outlineView makeViewWithIdentifier:NSStringFromClass(itemClass) owner:nil]);
    assert(view);
    return view;
}

- (void)_load {
    SourceListSpacer* spacer1 = [self _itemForClass:[SourceListSpacer class]];
    spacer1->height = 3;
    
    SourceListDevice* device = [self _itemForClass:[SourceListDevice class]];
    device->name = @"MDC Device 123457";
    
    SourceListSection* devicesSection = [self _itemForClass:[SourceListSection class]];
    devicesSection->name = @"Devices";
    devicesSection->items = { device };
    
    SourceListSpacer* spacer2 = [self _itemForClass:[SourceListSpacer class]];
    spacer2->height = 10;
    
    SourceListLibrary* library = [self _itemForClass:[SourceListLibrary class]];
    library->name = @"New Library";
    
    SourceListSection* librariesSection = [self _itemForClass:[SourceListSection class]];
    librariesSection->name = @"Libraries";
    librariesSection->items = { library };
    
    _outlineItems = {
        spacer1,
        devicesSection,
        spacer2,
        librariesSection,
    };
    
    for (SourceListItem* it : _outlineItems) {
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
    
    } else if (auto it = DynamicCast<SourceListSection>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        return _outlineItems[index];
    
    } else if (auto section = DynamicCast<SourceListSection>(item)) {
        return section->items.at(index);
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    if (auto it = DynamicCast<SourceListSection>(item)) {
        return true;
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldSelectItem:(id)item {
    if (auto it = DynamicCast<SourceListItem>(item)) {
        return [it selectable];
    }
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldShowOutlineCellForItem:(id)item {
    return false;
}

- (NSTableRowView*)outlineView:(NSOutlineView*)outlineView rowViewForItem:(id)item {
    return [_outlineView makeViewWithIdentifier:@"Row" owner:nil];
}

- (NSView*)outlineView:(NSOutlineView*)outlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item {
    return item;
}

@end

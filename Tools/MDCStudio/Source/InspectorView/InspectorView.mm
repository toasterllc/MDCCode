#import "InspectorView.h"
#import <vector>
#import "Util.h"
using namespace MDCStudio;

// MARK: - Outline View Items

@interface InspectorView_Item : NSTableCellView
@end

@implementation InspectorView_Item {
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

@interface InspectorView_Section : InspectorView_Item
@end

@implementation InspectorView_Section {
@public
    NSString* name;
    std::vector<InspectorView_Item*> items;
}

- (NSString*)name { return [name uppercaseString]; }
- (bool)selectable { return false; }
- (CGFloat)height { return 20; }

- (void)update {
    [super update];
    for (InspectorView_Item* it : items) {
        [it update];
    }
}

@end

@interface InspectorView_Spacer : InspectorView_Item
@end

@implementation InspectorView_Spacer {
@public
    CGFloat height;
}
- (NSString*)name { return @""; }
- (bool)selectable { return false; }
- (CGFloat)height { return height; }
@end







@interface InspectorView_Slider : InspectorView_Item
@end

@implementation InspectorView_Slider {
@public
    IBOutlet NSImageView* iconLeft;
    IBOutlet NSImageView* iconRight;
    IBOutlet NSSlider* slider;
}
- (NSString*)name { return @""; }
- (bool)selectable { return false; }
@end







@interface InspectorView_Checkbox : InspectorView_Item
@end

@implementation InspectorView_Checkbox {
@public
    IBOutlet NSButton* checkbox;
    NSString* name;
}

- (NSString*)name { return @""; }
- (bool)selectable { return false; }

- (void)update {
    [super update];
    [checkbox setTitle:name];
}

@end






@interface InspectorView_RowView : NSTableRowView
@end

@implementation InspectorView_RowView
- (BOOL)isEmphasized { return false; }
@end

#define Item            InspectorView_Item
#define RowView         InspectorView_RowView
#define Section         InspectorView_Section
#define SectionItem     InspectorView_SectionItem
#define Spacer          InspectorView_Spacer
#define Slider          InspectorView_Slider
#define Checkbox        InspectorView_Checkbox

// MARK: - InspectorView

@implementation InspectorView {
    IBOutlet NSView* _nibView;
    IBOutlet NSOutlineView* _outlineView;
    
    std::vector<Item*> _outlineItems;
}

// MARK: - Creation

//static void _Init(InspectorView* self) {
//    
//}

//- (instancetype)initWithCoder:(NSCoder*)coder {
//    if (!(self = [super initWithCoder:coder])) return nil;
//    _Init(self);
//    return self;
//}

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
    
//    // Add a divider line
//    {
//        NSView* dividerLine = [[NSView alloc] initWithFrame:{}];
//        [dividerLine setTranslatesAutoresizingMaskIntoConstraints:false];
//        [dividerLine setWantsLayer:true];
//        [[dividerLine layer] setBackgroundColor:[[NSColor colorWithWhite:0 alpha:1] CGColor]];
//        [self addSubview:dividerLine];
//        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[dividerLine(==1)]|"
//            options:0 metrics:nil views:NSDictionaryOfVariableBindings(dividerLine)]];
//        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[dividerLine]|"
//            options:0 metrics:nil views:NSDictionaryOfVariableBindings(dividerLine)]];
//    }
    
    // Populate NSOutlineView
    {
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 3;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"White Balance";
            section->items = { [self _createItemWithClass:[Slider class]] };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 8;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Exposure";
            section->items = { [self _createItemWithClass:[Slider class]] };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 8;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Brightness";
            section->items = { [self _createItemWithClass:[Slider class]] };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 8;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Contrast";
            section->items = { [self _createItemWithClass:[Slider class]] };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 8;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Saturation";
            section->items = { [self _createItemWithClass:[Slider class]] };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 8;
            _outlineItems.push_back(spacer);
        }
        
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Processing";
            
            Checkbox* checkbox1 = [self _createItemWithClass:[Checkbox class]];
            checkbox1->name = @"Defringe";
            
            Checkbox* checkbox2 = [self _createItemWithClass:[Checkbox class]];
            checkbox2->name = @"Reconstruct Highlights Hello";
            
            section->items = { checkbox1, checkbox2 };
            _outlineItems.push_back(section);
        }
        
        
        
//        Spacer* spacer2 = [self _createItemWithClass:[Spacer class]];
//        spacer2->height = 10;
        
//        Slider* slider = [self _createItemWithClass:[Slider class]];
        
//        _librariesSection = [self _createItemWithClass:[Section class]];
//        _librariesSection->name = @"Libraries";
        
    //    Device* device = [self _createItemWithClass:[Device class]];
    //    device->name = @"MDC Device 123456";
    //    _devicesSection->items.push_back(device);
        
//        Library* library = [self _createItemWithClass:[Library class]];
//        library->name = @"New Library";
//        _librariesSection->items.push_back(library);
        
//        _outlineItems = {
//            spacer1,
//            section,
//            spacer2
//        };
        
        [_outlineView reloadData];
        
        for (auto item : _outlineItems) {
            [_outlineView expandItem:item];
        }
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

//- (void)setFrameSize:(NSSize)size {
//    [super setFrameSize:size];
//    // Fix intermittent issue where our sole column can be sized a few points too large,
//    // causing the enclosing scroll view to be able to scroll horizontally (which
//    // we don't want)
//    CGFloat usableWidth = [self bounds].size.width-4;
//    [[_outlineView tableColumns][0] setWidth:usableWidth];
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

//- (void)outlineViewSelectionDidChange:(NSNotification*)note {
//    [_delegate sourceListViewSelectionChanged:self];
//}

@end

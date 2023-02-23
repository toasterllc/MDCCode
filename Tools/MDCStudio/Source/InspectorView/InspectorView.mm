#import "InspectorView.h"
#import <vector>
#import "Util.h"
using namespace MDCStudio;

// MARK: - Outline View Items

@interface InspectorView_Item : NSTableCellView
@end

@implementation InspectorView_Item {
@private
    IBOutlet NSLayoutConstraint* _indent;
    IBOutlet NSLayoutConstraint* _height;
@public
    bool darkBackground;
}

- (NSString*)name { abort(); }
- (CGFloat)height { return 20; }
- (CGFloat)indent { return 12; }

- (void)update {
    [_indent setConstant:[self indent]];
    [_height setConstant:[self height]];
    [[self textField] setStringValue:[self name]];
}

//- (void)drawRect:(NSRect)rect {
//    [[NSColor redColor] set];
//    NSRectFill(rect);
//}

@end

@interface InspectorView_Section : InspectorView_Item
@end

@implementation InspectorView_Section {
@public
    NSString* name;
    std::vector<InspectorView_Item*> items;
}

- (NSString*)name { return [name uppercaseString]; }
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
- (CGFloat)height { return height; }
@end







@interface InspectorView_SliderIcon : InspectorView_Item
@end

@implementation InspectorView_SliderIcon {
@private
    IBOutlet NSButton* _buttonMin;
    IBOutlet NSButton* _buttonMax;
    IBOutlet NSSlider* _slider;
@public
    NSString* icon;
}
- (NSString*)name { return @""; }

- (void)update {
    [super update];
    [_buttonMin setImage:[NSImage imageNamed:[NSString stringWithFormat:@"%@-Min", icon]]];
    [_buttonMax setImage:[NSImage imageNamed:[NSString stringWithFormat:@"%@-Max", icon]]];
}

@end






@interface InspectorView_SliderLabel : InspectorView_Item
@end

@implementation InspectorView_SliderLabel {
@public
    IBOutlet NSTextField* label;
    IBOutlet NSSlider* slider;
    NSString* name;
}
- (NSString*)name { return name; }

- (void)update {
    [super update];
    [label setStringValue:name];
}

@end






@interface InspectorView_Checkbox : InspectorView_Item
@end

@implementation InspectorView_Checkbox {
@public
    IBOutlet NSButton* checkbox;
    NSString* name;
}

- (NSString*)name { return name; }

- (void)update {
    [super update];
    [checkbox setTitle:name];
}

@end





@interface InspectorView_Menu : InspectorView_Item
@end

@implementation InspectorView_Menu {
@public
    IBOutlet NSPopUpButton* button;
}

- (NSString*)name { return @""; }

@end




@interface InspectorView_Timestamp : InspectorView_Item
@end

@implementation InspectorView_Timestamp {
@public
    IBOutlet NSPopUpButton* button;
    IBOutlet NSButton* imageCornerButton;
}

- (NSString*)name { return @""; }

@end




@interface InspectorView_Rotation : InspectorView_Item
@end

@implementation InspectorView_Rotation {
@private
    IBOutlet NSButton* _button;
@public
    NSString* icon;
}

- (NSString*)name { return @""; }

//- (void)update {
//    [super update];
//    [_button setImage:[NSImage imageNamed:icon]];
//}

@end




@interface InspectorView_Stat : InspectorView_Item
@end

@implementation InspectorView_Stat {
@private
    IBOutlet NSTextField* _nameLabel;
    IBOutlet NSTextField* _valueLabel;
    IBOutlet NSLayoutConstraint* _valueIndentConstraint;
@public
    NSString* name;
    NSString* value;
    CGFloat valueIndent;
}

- (NSString*)name { return @""; }

- (void)update {
    [super update];
    [_nameLabel setStringValue:name];
    [_valueLabel setStringValue:value];
    [_valueIndentConstraint setConstant:valueIndent];
}

@end






@interface InspectorView_DarkRowView : NSTableRowView
@end

@implementation InspectorView_DarkRowView

- (NSBackgroundStyle)interiorBackgroundStyle {
    return NSBackgroundStyleEmphasized;
}

- (NSColor*)backgroundColor {
    return [[NSColor blackColor] colorWithAlphaComponent:.25];
}

@end





#define Item            InspectorView_Item
#define DarkRowView     InspectorView_DarkRowView
#define Section         InspectorView_Section
#define SectionItem     InspectorView_SectionItem
#define Spacer          InspectorView_Spacer
#define SliderIcon      InspectorView_SliderIcon
#define SliderLabel     InspectorView_SliderLabel
#define Checkbox        InspectorView_Checkbox
#define Menu            InspectorView_Menu
#define Timestamp       InspectorView_Timestamp
#define Rotation        InspectorView_Rotation
#define Stat            InspectorView_Stat

// MARK: - InspectorView

@interface InspectorView () <NSOutlineViewDelegate>
@end

@implementation InspectorView {
    IBOutlet NSView* _nibView;
    IBOutlet NSOutlineView* _outlineView;
    
    std::vector<Item*> _outlineItems;
}

// MARK: - Creation

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
    
    // Populate NSOutlineView
    {
        static constexpr CGFloat SpacerSize = 20;
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 3;
            spacer->darkBackground = true;
            _outlineItems.push_back(spacer);
            
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Stats";
            section->darkBackground = true;
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Image ID";
                stat->value = @"7553";
                stat->valueIndent = 75;
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Date";
                stat->value = @"Feb 18, 2023";
                stat->valueIndent = 75;
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Time";
                stat->value = @"8:43 PM";
                stat->valueIndent = 75;
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Exposure";
                stat->value = @"555";
                stat->valueIndent = 75;
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Gain";
                stat->value = @"1023";
                stat->valueIndent = 75;
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Spacer* spacer = [self _createItemWithClass:[Spacer class]];
                spacer->height = SpacerSize/2;
                spacer->darkBackground = true;
                section->items.push_back(spacer);
            }
            
            
            
//            Stat* stat1 = [self _createItemWithClass:[Stat class]];
//            stat1->name = "Date";
            
//            section->items = { [self _createItemWithClass:[SliderIcon class]] };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize/2;
            _outlineItems.push_back(spacer);
        }
        
        
        
        
        
        
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"White Balance";
            
            SliderIcon* slider = [self _createItemWithClass:[SliderIcon class]];
            slider->icon = @"Inspector-WhiteBalance";
            section->items = { slider };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Exposure";
            SliderIcon* slider = [self _createItemWithClass:[SliderIcon class]];
            slider->icon = @"Inspector-Exposure";
            section->items = { slider };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Saturation";
            SliderIcon* slider = [self _createItemWithClass:[SliderIcon class]];
            slider->icon = @"Inspector-Saturation";
            section->items = { slider };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Brightness";
            SliderIcon* slider = [self _createItemWithClass:[SliderIcon class]];
            slider->icon = @"Inspector-Brightness";
            section->items = { slider };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Contrast";
            SliderIcon* slider = [self _createItemWithClass:[SliderIcon class]];
            slider->icon = @"Inspector-Contrast";
            section->items = { slider };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Local Constrast";
            
            SliderLabel* slider1 = [self _createItemWithClass:[SliderLabel class]];
            slider1->name = @"Amount";
            
            SliderLabel* slider2 = [self _createItemWithClass:[SliderLabel class]];
            slider2->name = @"Radius";
            
            section->items = { slider1, slider2 };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Rotation";
            Rotation* rotation = [self _createItemWithClass:[Rotation class]];
            rotation->icon = @"Rotation";
            section->items = { rotation };
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Other";
            
            {
                Checkbox* checkbox = [self _createItemWithClass:[Checkbox class]];
                checkbox->name = @"Defringe";
                section->items.push_back(checkbox);
            }
            
//            {
//                Spacer* spacer = [self _createItemWithClass:[Spacer class]];
//                spacer->height = 4;
//                section->items.push_back(spacer);
//            }
            
            {
                Checkbox* checkbox = [self _createItemWithClass:[Checkbox class]];
                checkbox->name = @"Reconstruct highlights";
                section->items.push_back(checkbox);
            }
            
//            {
//                Spacer* spacer = [self _createItemWithClass:[Spacer class]];
//                spacer->height = 4;
//                section->items.push_back(spacer);
//            }
            
            {
                Timestamp* timestamp = [self _createItemWithClass:[Timestamp class]];
                section->items.push_back(timestamp);
            }
            
            _outlineItems.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
        }
        
        
//        {
//            Section* section = [self _createItemWithClass:[Section class]];
//            section->name = @"Timestamp";
//            section->items = { [self _createItemWithClass:[Timestamp class]] };
//            _outlineItems.push_back(section);
//        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _outlineItems.push_back(spacer);
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
    return false;
}

- (BOOL)outlineView:(NSOutlineView*)outlineView shouldShowOutlineCellForItem:(id)item {
    return false;
}

- (NSTableRowView*)outlineView:(NSOutlineView*)outlineView rowViewForItem:(id)item {
    auto it = CastOrNil<Item>(item);
    if (it->darkBackground) {
        return [_outlineView makeViewWithIdentifier:NSStringFromClass([DarkRowView class]) owner:nil];
    }
    return nil;
}

- (NSView*)outlineView:(NSOutlineView*)outlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item {
    [Cast<Item>(item) update];
    return item;
}

@end


@interface InspectorOutlineView : NSOutlineView
@end


@implementation InspectorOutlineView

- (BOOL)validateProposedFirstResponder:(NSResponder*)responder forEvent:(NSEvent*)event {
    // Allow labels in our outline view to be selected
    return true;
}

@end

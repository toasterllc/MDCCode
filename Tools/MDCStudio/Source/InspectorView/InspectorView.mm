#import "InspectorView.h"
#import <vector>
#import "Util.h"
#import "ImageCornerButton/ImageCornerButton.h"
using namespace MDCStudio;

struct _ModelData {
    enum class Type {
        Normal,
        Mixed,
    };
    
    Type type = Type::Normal;
    id data = nil;
};

@class InspectorView_Item;
using _ModelGetter = _ModelData(^)(InspectorView_Item*);
using _ModelSetter = void(^)(InspectorView_Item*, id);

// MARK: - Outline View Items

@interface InspectorView_Item : NSTableCellView
@end

@implementation InspectorView_Item {
@private
    IBOutlet NSLayoutConstraint* _indent;
    IBOutlet NSLayoutConstraint* _height;
@public
    _ModelGetter modelGetter;
    _ModelSetter modelSetter;
    bool darkBackground;
}

- (NSString*)name { return @""; }
- (CGFloat)height { return 20; }
- (CGFloat)indent { return 12; }

- (void)updateView {
    [_indent setConstant:[self indent]];
    [_height setConstant:[self height]];
    [[self textField] setStringValue:[self name]];
}

//- (void)updateModel {
//    if (updateModel) {
//        updateModel(self);
//    }
//}

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

- (void)updateView {
    [super updateView];
    for (InspectorView_Item* it : items) {
        [it updateView];
    }
}

@end

@interface InspectorView_Spacer : InspectorView_Item
@end

@implementation InspectorView_Spacer {
@public
    CGFloat height;
}
- (CGFloat)height { return height; }
@end







@interface InspectorView_SliderWithIcon : InspectorView_Item
@end

@implementation InspectorView_SliderWithIcon {
@private
    IBOutlet NSButton* _buttonMin;
    IBOutlet NSButton* _buttonMax;
    IBOutlet NSSlider* _slider;
@public
    NSString* icon;
}

- (void)updateView {
    [super updateView];
    [_buttonMin setImage:[NSImage imageNamed:[NSString stringWithFormat:@"%@-Min", icon]]];
    [_buttonMax setImage:[NSImage imageNamed:[NSString stringWithFormat:@"%@-Max", icon]]];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        [_slider setObjectValue:data.data];
        break;
    case _ModelData::Type::Mixed:
        [_slider setObjectValue:@(0)];
        break;
    }
}

@end






@interface InspectorView_SliderWithLabel : InspectorView_Item
@end

@implementation InspectorView_SliderWithLabel {
@private
    IBOutlet NSTextField* _label;
    IBOutlet NSSlider* _slider;
@public
    NSString* name;
}
- (NSString*)name { return name; }

- (void)updateView {
    [super updateView];
    [_label setStringValue:name];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        [_slider setObjectValue:data.data];
        break;
    case _ModelData::Type::Mixed:
        [_slider setObjectValue:@(0)];
        break;
    }
}

@end






@interface InspectorView_Checkbox : InspectorView_Item
@end

@implementation InspectorView_Checkbox {
@private
    IBOutlet NSButton* _checkbox;
@public
    NSString* name;
}

- (NSString*)name { return name; }

- (void)updateView {
    [super updateView];
    [_checkbox setTitle:name];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        [_checkbox setState:([data.data boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
        break;
    case _ModelData::Type::Mixed:
        [_checkbox setState:NSControlStateValueMixed];
        break;
    }
}

@end





@interface InspectorView_Menu : InspectorView_Item
@end

@implementation InspectorView_Menu {
@private
    IBOutlet NSPopUpButton* _button;
}
@end




@interface InspectorView_Timestamp : InspectorView_Item
@end

@implementation InspectorView_Timestamp {
@private
    IBOutlet NSButton* _checkbox;
    IBOutlet ImageCornerButton* _cornerButton;
@public
    _ModelGetter cornerModelGetter;
    _ModelSetter cornerModelSetter;
}

- (void)updateView {
    [super updateView];
    
    {
        const _ModelData data = modelGetter(self);
        switch (data.type) {
        case _ModelData::Type::Normal:
            [_checkbox setState:([data.data boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
            break;
        case _ModelData::Type::Mixed:
            [_checkbox setState:NSControlStateValueMixed];
            break;
        }
    }
    
    {
        const _ModelData data = cornerModelGetter(self);
        switch (data.type) {
        case _ModelData::Type::Normal:
            [_cornerButton setCorner:(ImageCornerButtonTypes::Corner)[data.data intValue]];
            break;
        case _ModelData::Type::Mixed:
            [_cornerButton setCorner:ImageCornerButtonTypes::Corner::Mixed];
            break;
        }
    }
}

@end




@interface InspectorView_Rotation : InspectorView_Item
@end

@implementation InspectorView_Rotation {
@private
    IBOutlet NSButton* _button;
@public
    NSString* icon;
}

//- (void)updateView {
//    [super updateView];
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
    CGFloat valueIndent;
}

- (void)updateView {
    [super updateView];
    [_nameLabel setStringValue:name];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        [_valueLabel setObjectValue:data.data];
        [_valueLabel setTextColor:[NSColor labelColor]];
        break;
    case _ModelData::Type::Mixed:
        [_valueLabel setObjectValue:@"multiple"];
        [_valueLabel setTextColor:[NSColor placeholderTextColor]];
        break;
    }
    
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
#define SliderWithIcon  InspectorView_SliderWithIcon
#define SliderWithLabel InspectorView_SliderWithLabel
#define Checkbox        InspectorView_Checkbox
//#define Menu            InspectorView_Menu
#define Timestamp       InspectorView_Timestamp
#define Rotation        InspectorView_Rotation
#define Stat            InspectorView_Stat

// MARK: - InspectorView

@interface InspectorView () <NSOutlineViewDelegate>
@end

@implementation InspectorView {
    ImageLibraryPtr _imgLib;
    Section* _rootItem;
    std::set<Img::Id> _selection;
    
    IBOutlet NSView* _nibView;
    IBOutlet NSOutlineView* _outlineView;
}

// MARK: - Creation

static id _extract_id(const ImageThumb& thumb) {
    return @(thumb.id);
}

using _ModelExtractFn = id(*)(const ImageThumb&);

//static _ModelData _Getter(InspectorView* self, _ModelGetterFn fn) {
//    // first: holds the first non-nil value
//    id first = nil;
//    // mixed: tracks whether there are at least 2 differing values
//    bool mixed = false;
//    
//    auto lock = std::unique_lock(*self->_imgLib);
//    for (const Img::Id imgId : self->_selection) {
//        auto find = self->_imgLib->find(imgId);
//        if (find == self->_imgLib->end()) continue;
//        const id obj = fn(*self->_imgLib->recordGet(find));
//        if (!obj) continue;
//        if (!first) {
//            first = obj;
//        } else {
//            mixed |= ![first isEqual:obj];
//        }
//    }
//    
//    if (!mixed) {
//        return _ModelData{ .data = first };
//    }
//    
//    return _ModelData{ .type = _ModelData::Type::Mixed };
//}


- (_ModelData)_getter:(_ModelExtractFn)fn {
    // first: holds the first non-nil value
    id first = nil;
    // mixed: tracks whether there are at least 2 differing values
    bool mixed = false;
    
    auto lock = std::unique_lock(*_imgLib);
    for (const Img::Id imgId : _selection) {
        auto find = _imgLib->find(imgId);
        if (find == _imgLib->end()) continue;
        const id obj = fn(*_imgLib->recordGet(find));
        if (!obj) continue;
        if (!first) {
            first = obj;
        } else {
            mixed |= ![first isEqual:obj];
        }
    }
    
    if (!mixed) {
        return _ModelData{ .data = first };
    }
    
    return _ModelData{ .type = _ModelData::Type::Mixed };
}

static _ModelGetter _GetterCreate(InspectorView* self, _ModelExtractFn fn) {
    __weak const auto selfWeak = self;
    return ^_ModelData(InspectorView_Item*){
        const auto selfStrong = selfWeak;
        if (!selfStrong) return _ModelData{};
        return [selfStrong _getter:fn];
    };
}


- (_ModelData)_getter_id {
    if (_selection.size() != 1) {
        return _ModelData{ .type = _ModelData::Type::Mixed };
    }
    
    const Img::Id id = *_selection.begin();
    auto lock = std::unique_lock(*_imgLib);
    auto find = _imgLib->find(id);
    if (find == _imgLib->end()) return {};
    
    return _ModelData{ .data = @(_imgLib->recordGet(find)->id) };
}

- (_ModelData)_getter_date {
    return {};
}

- (_ModelData)_getter_time {
    return {};
}

- (_ModelData)_getter_integrationTime {
    return {};
//    if (_selection.size() != 1) {
//        return nil;
//    }
//    
//    const Img::Id id = *_selection.begin();
//    
//    auto lock = std::unique_lock(*_imgLib);
//    auto find = _imgLib->find(id);
//    if (find == _imgLib->end()) return nil;
//    return @(_imgLib->recordGet(find)->coarseIntTime);
}

- (_ModelData)_getter_analogGain {
    return {};
//    if (_selection.size() != 1) {
//        return nil;
//    }
//    
//    const Img::Id id = *_selection.begin();
//    
//    auto lock = std::unique_lock(*_imgLib);
//    auto find = _imgLib->find(id);
//    if (find == _imgLib->end()) return nil;
//    return @(_imgLib->recordGet(find)->analogGain);
}

- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _imgLib = imgLib;
    
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
    
    // Create NSOutlineView items
    {
        static constexpr CGFloat SpacerSize = 20;
        _rootItem = [self _createItemWithClass:[Section class]];
        _rootItem->name = @"";
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = 3;
            spacer->darkBackground = true;
            _rootItem->items.push_back(spacer);
            
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Stats";
            section->darkBackground = true;
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Image ID";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, _extract_id);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Date";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, @selector(_getter_date));
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Time";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, @selector(_getter_time));
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Integration Time";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, @selector(_getter_integrationTime));
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Analog Gain";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, @selector(_getter_analogGain));
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
            
//            section->items = { [self _createItemWithClass:[SliderWithIcon class]] };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize/2;
            _rootItem->items.push_back(spacer);
        }
        
        
        
        
        
        
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"White Balance";
            SliderWithIcon* slider = [self _createItemWithClass:[SliderWithIcon class]];
            slider->icon = @"Inspector-WhiteBalance";
            slider->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Exposure";
            SliderWithIcon* slider = [self _createItemWithClass:[SliderWithIcon class]];
            slider->icon = @"Inspector-Exposure";
            slider->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Saturation";
            SliderWithIcon* slider = [self _createItemWithClass:[SliderWithIcon class]];
            slider->icon = @"Inspector-Saturation";
            slider->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Brightness";
            SliderWithIcon* slider = [self _createItemWithClass:[SliderWithIcon class]];
            slider->icon = @"Inspector-Brightness";
            slider->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Contrast";
            SliderWithIcon* slider = [self _createItemWithClass:[SliderWithIcon class]];
            slider->icon = @"Inspector-Contrast";
            slider->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Local Constrast";
            
            SliderWithLabel* slider1 = [self _createItemWithClass:[SliderWithLabel class]];
            slider1->name = @"Amount";
            slider1->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            
            SliderWithLabel* slider2 = [self _createItemWithClass:[SliderWithLabel class]];
            slider2->name = @"Radius";
            slider2->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
            
            section->items = { slider1, slider2 };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Rotation";
            Rotation* rotation = [self _createItemWithClass:[Rotation class]];
            rotation->icon = @"Rotation";
            section->items = { rotation };
            _rootItem->items.push_back(section);
        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Section* section = [self _createItemWithClass:[Section class]];
            section->name = @"Other";
            
            {
                Checkbox* checkbox = [self _createItemWithClass:[Checkbox class]];
                checkbox->name = @"Defringe";
                checkbox->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
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
                checkbox->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
                section->items.push_back(checkbox);
            }
            
//            {
//                Spacer* spacer = [self _createItemWithClass:[Spacer class]];
//                spacer->height = 4;
//                section->items.push_back(spacer);
//            }
            
            {
                Timestamp* timestamp = [self _createItemWithClass:[Timestamp class]];
                timestamp->modelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
                timestamp->cornerModelGetter = ^(id){ return _ModelData{}; /*meowmix*/ };
                section->items.push_back(timestamp);
            }
            
            _rootItem->items.push_back(section);
        }
        
//        {
//            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
//            spacer->height = SpacerSize;
//            _rootItem->items.push_back(spacer);
//        }
//        
//        
//        {
//            Section* section = [self _createItemWithClass:[Section class]];
//            section->name = @"Timestamp";
//            section->items = { [self _createItemWithClass:[Timestamp class]] };
//            _rootItem->items.push_back(section);
//        }
        
        {
            Spacer* spacer = [self _createItemWithClass:[Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
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
    }
    
    [_outlineView reloadData];
    
    for (auto item : _rootItem->items) {
        [_outlineView expandItem:item];
    }
    return self;
}

// MARK: - Methods

static void _UpdateView(Item* it) {
    [it updateView];
    if (auto section = CastOrNil<Section>(it)) {
        for (auto it : section->items) {
            _UpdateView(it);
        }
    }
}

- (void)setSelection:(const std::set<Img::Id>&)selection {
    _selection = selection;
    _UpdateView(_rootItem);
}

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
        if (!_rootItem) return 0;
        return _rootItem->items.size();
    
    } else if (auto it = CastOrNil<Section>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        if (!_rootItem) return nil;
        return _rootItem->items[index];
    
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
    [Cast<Item>(item) updateView];
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

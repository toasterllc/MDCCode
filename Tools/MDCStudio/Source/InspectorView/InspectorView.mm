#import "InspectorView.h"
#import <vector>
#import "Util.h"
#import "ImageCornerButton/ImageCornerButton.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/TimeConvert.h"
#import "Toastbox/DurationString.h"
using namespace MDCStudio;

struct _ModelData {
    enum class Type {
        Normal,
        Mixed,
    };
    
    Type type = Type::Normal;
    id data = nil;
};

@class InspectorViewItem;
@class InspectorViewItem_Section;
using _ModelGetter = _ModelData(^)(InspectorViewItem*);
using _ModelSetter = void(^)(InspectorViewItem*, id);

@interface InspectorCheckboxCell : NSButtonCell
@end

@implementation InspectorCheckboxCell
- (NSInteger)nextState {
    NSInteger state = [self state];
    switch (state) {
    case NSControlStateValueMixed:  return NSControlStateValueOn;
    case NSControlStateValueOff:    return NSControlStateValueOn;
    case NSControlStateValueOn:     return NSControlStateValueOff;
    }
    return NSControlStateValueOff;
}
@end



// MARK: - Outline View Items

@interface InspectorViewItem : NSTableCellView
@end

@implementation InspectorViewItem {
@private
    IBOutlet NSLayoutConstraint* _indentLeft;
    IBOutlet NSLayoutConstraint* _indentRight;
@public
    _ModelGetter modelGetter;
    _ModelSetter modelSetter;
    bool darkBackground;
    __weak InspectorViewItem_Section* section;
}

- (CGFloat)indent { return 16; }

- (bool)updateView {
    [_indentLeft setConstant:[self indent]];
    [_indentRight setConstant:[self indent]];
    return false;
}

- (void)clear {}

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

@interface InspectorViewItem_Section : InspectorViewItem
@end

@implementation InspectorViewItem_Section {
@private
    IBOutlet NSTextField* _label;
    IBOutlet NSButton* _clearButton;
@public
    NSString* name;
    std::vector<InspectorViewItem*> items;
}

- (bool)updateView {
    bool modified = [super updateView];
    for (InspectorViewItem* it : items) {
        modified |= [it updateView];
    }
    [_label setStringValue:[name uppercaseString]];
    [_label setTextColor:(modified ? [NSColor labelColor] : [NSColor secondaryLabelColor])];
    [_clearButton setHidden:!modified];
    return modified;
}

- (IBAction)clear:(id)sender {
    for (InspectorViewItem* it : items) {
        [it clear];
    }
    [self updateView];
}

@end

@interface InspectorViewItem_Spacer : InspectorViewItem
@end

@implementation InspectorViewItem_Spacer {
@private
    IBOutlet NSLayoutConstraint* _height;
@public
    CGFloat height;
}

- (bool)updateView {
    const bool modified = [super updateView];
    [_height setConstant:height];
    return modified;
}

@end






@interface InspectorView_Slider : InspectorViewItem
@end

@implementation InspectorView_Slider {
@private
    IBOutlet NSSlider* _slider;
    IBOutlet NSTextField* _numberField;
    IBOutlet NSNumberFormatter* _numberFormatter;
@public
    float valueMin;
    float valueMax;
    float valueDefault;
}

- (bool)updateView {
    bool modified = [super updateView];
    
    [_slider setMinValue:valueMin];
    [_slider setMaxValue:valueMax];
    
    [_numberFormatter setMinimum:@(valueMin)];
    [_numberFormatter setMaximum:@(valueMax)];
    
    const _ModelData data = modelGetter(self);
    
    switch (data.type) {
    case _ModelData::Type::Normal:
        modified |= ![data.data isEqual:@(valueDefault)];
        [_slider setObjectValue:data.data];
        [_numberField setObjectValue:data.data];
        [_numberField setPlaceholderString:nil];
        [_numberField setHidden:!modified];
        break;
    case _ModelData::Type::Mixed:
        modified = true;
        [_slider setObjectValue:@(0)];
        [_numberField setObjectValue:nil];
        [_numberField setPlaceholderString:@"multiple"];
        [_numberField setHidden:false];
        break;
    }
    return modified;
}

- (void)clear {
    modelSetter(self, @(valueDefault));
}

//- (void)_updateSlider:(const _ModelData&)data {
//    switch (data.type) {
//    case _ModelData::Type::Normal:
//        [_slider setObjectValue:data.data];
//        [_numberField setObjectValue:data.data];
//        break;
//    case _ModelData::Type::Mixed:
//        [_slider setObjectValue:@(0)];
//        break;
//    }
//}
//
//- (void)_updateNumberField:(const _ModelData&)data {
//    switch (data.type) {
//    case _ModelData::Type::Normal:
//        [_numberField setObjectValue:data.data];
//        [_numberField setPlaceholderString:nil];
//        [_numberField setHidden:[data.data isEqual:@(valueDefault)]];
//        break;
//    case _ModelData::Type::Mixed:
//        [_numberField setObjectValue:nil];
//        [_numberField setPlaceholderString:@"multiple"];
//        break;
//    }
//}

- (IBAction)sliderAction:(id)sender {
    const id val = [_slider objectValue];
    modelSetter(self, val);
    [section updateView];
}

- (IBAction)numberFieldAction:(id)sender {
    const id val = [_numberField objectValue];
    // Don't set nil values, since they represent an empty text field
    if (val) {
        modelSetter(self, val);
    }
    [section updateView];
}

@end















@interface InspectorViewItem_SliderWithIcon : InspectorView_Slider
@end

@implementation InspectorViewItem_SliderWithIcon {
@private
    IBOutlet NSButton* _buttonMin;
    IBOutlet NSButton* _buttonMax;
@public
    NSString* icon;
}

- (bool)updateView {
    const bool modified = [super updateView];
    [_buttonMin setImage:[NSImage imageNamed:[NSString stringWithFormat:@"%@-Min", icon]]];
    [_buttonMax setImage:[NSImage imageNamed:[NSString stringWithFormat:@"%@-Max", icon]]];
    return modified;
}

@end






@interface InspectorViewItem_SliderWithLabel : InspectorView_Slider
@end

@implementation InspectorViewItem_SliderWithLabel {
@private
    IBOutlet NSTextField* _label;
@public
    NSString* name;
}

- (bool)updateView {
    const bool modified = [super updateView];
    [_label setStringValue:name];
    return modified;
}

@end






@interface InspectorViewItem_Checkbox : InspectorViewItem
@end

@implementation InspectorViewItem_Checkbox {
@protected
    IBOutlet NSButton* _checkbox;
@public
    NSString* name;
    bool valueDefault;
}

- (bool)updateView {
    bool modified = [super updateView];
    [_checkbox setTitle:name];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        modified |= ((bool)[data.data boolValue] != valueDefault);
        [_checkbox setState:([data.data boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
        break;
    case _ModelData::Type::Mixed:
        modified = true;
        [_checkbox setState:NSControlStateValueMixed];
        break;
    }
    return modified;
}

- (void)clear {
    modelSetter(self, @(valueDefault));
}

- (IBAction)checkboxAction:(id)sender {
    modelSetter(self, @([_checkbox state]!=NSControlStateValueOff));
    [section updateView];
}

@end





@interface InspectorView_Menu : InspectorViewItem
@end

@implementation InspectorView_Menu {
@private
    IBOutlet NSPopUpButton* _button;
}
@end




@interface InspectorViewItem_Timestamp : InspectorViewItem_Checkbox
@end

@implementation InspectorViewItem_Timestamp {
@private
    IBOutlet ImageCornerButton* _cornerButton;
@public
    ImageCornerButtonTypes::Corner cornerValueDefault;
    _ModelGetter cornerModelGetter;
    _ModelSetter cornerModelSetter;
}

- (bool)updateView {
    bool modified = [super updateView];
    
    {
        const _ModelData data = modelGetter(self);
        switch (data.type) {
        case _ModelData::Type::Normal:
            modified |= ((bool)[data.data boolValue] != valueDefault);
            [_checkbox setState:([data.data boolValue] ? NSControlStateValueOn : NSControlStateValueOff)];
            break;
        case _ModelData::Type::Mixed:
            modified = true;
            [_checkbox setState:NSControlStateValueMixed];
            break;
        }
    }
    
    {
        const _ModelData data = cornerModelGetter(self);
        switch (data.type) {
        case _ModelData::Type::Normal:
            modified |= ((ImageCornerButtonTypes::Corner)[data.data intValue] != cornerValueDefault);
            [_cornerButton setCorner:(ImageCornerButtonTypes::Corner)[data.data intValue]];
            break;
        case _ModelData::Type::Mixed:
            modified = true;
            [_cornerButton setCorner:ImageCornerButtonTypes::Corner::Mixed];
            break;
        }
    }
    return modified;
}

- (void)clear {
    [super clear];
    cornerModelSetter(self, @((int)cornerValueDefault));
}

- (IBAction)checkboxAction:(id)sender {
    modelSetter(self, @([_checkbox state]!=NSControlStateValueOff));
    [section updateView];
}

- (IBAction)cornerButtonAction:(id)sender {
    cornerModelSetter(self, @((int)[_cornerButton corner]));
    [section updateView];
}

@end




@interface InspectorViewItem_Rotation : InspectorViewItem
@end

@implementation InspectorViewItem_Rotation {
@private
    IBOutlet NSButton* _button;
@public
    ImageOptions::Rotation valueDefault;
}

static ImageOptions::Rotation _RotationNext(ImageOptions::Rotation x, int delta) {
    using R = ImageOptions::Rotation;
    if (delta >= 0) {
        switch (x) {
        case R::Clockwise0:    return R::Clockwise90;
        case R::Clockwise90:   return R::Clockwise180;
        case R::Clockwise180:  return R::Clockwise270;
        case R::Clockwise270:  return R::Clockwise0;
        }
    } else {
        switch (x) {
        case R::Clockwise0:    return R::Clockwise270;
        case R::Clockwise90:   return R::Clockwise0;
        case R::Clockwise180:  return R::Clockwise90;
        case R::Clockwise270:  return R::Clockwise180;
        }
    }
}

- (bool)updateView {
    bool modified = [super updateView];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        modified |= ((ImageOptions::Rotation)[data.data intValue] != valueDefault);
        break;
    case _ModelData::Type::Mixed:
        modified = true;
        break;
    }
    
    return modified;
}

- (void)clear {
    modelSetter(self, @((int)valueDefault));
}

- (IBAction)buttonAction:(id)sender {
    NSEvent*const ev = [NSApp currentEvent];
    const int delta = (([ev modifierFlags] & NSEventModifierFlagShift) ? -1 : 1);
    
    ImageOptions::Rotation rotationNext = ImageOptions::Rotation::Clockwise0;
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        rotationNext = _RotationNext((ImageOptions::Rotation)[data.data intValue], delta);
        break;
    case _ModelData::Type::Mixed:
        rotationNext = _RotationNext(rotationNext, delta);
        break;
    }
    
    modelSetter(self, @((int)rotationNext));
    [section updateView];
}

@end




@interface InspectorViewItem_Stat : InspectorViewItem
@end

@implementation InspectorViewItem_Stat {
@private
    IBOutlet NSTextField* _nameLabel;
    IBOutlet NSTextField* _valueLabel;
    IBOutlet NSLayoutConstraint* _valueIndentConstraint;
@public
    NSString* name;
    CGFloat valueIndent;
}

- (bool)updateView {
    const bool modified = [super updateView];
    [_nameLabel setStringValue:name];
    
    const _ModelData data = modelGetter(self);
    switch (data.type) {
    case _ModelData::Type::Normal:
        [_valueLabel setObjectValue:data.data];
//        [_valueLabel setTextColor:[NSColor secondaryLabelColor]];
        break;
    case _ModelData::Type::Mixed:
        [_valueLabel setObjectValue:@"multiple"];
//        [_valueLabel setTextColor:[NSColor placeholderTextColor]];
        break;
    }
//    [_valueLabel setBackgroundColor:[NSColor redColor]];
    
    [_valueIndentConstraint setConstant:valueIndent];
    return modified;
}

@end






@interface InspectorView_DarkRowView : NSTableRowView
@end

@implementation InspectorView_DarkRowView

//- (NSTableViewSelectionHighlightStyle)selectionHighlightStyle {
//    return NSTableViewSelectionHighlightStyleSourceList;
//}

//- (BOOL)isEmphasized {
//    return true;
//}

//- (BOOL)groupRowStyle {
//    return true;
//}

//- (BOOL)selected {
//    return false;
//}

//- (NSBackgroundStyle)interiorBackgroundStyle {
//    return NSBackgroundStyleEmphasized;
//}

- (NSColor*)backgroundColor {
//    return [NSColor blackColor];
    return [[NSColor blackColor] colorWithAlphaComponent:.25];
}

- (BOOL)isOpaque {
    return true;
}









@end





#define Item                    InspectorViewItem
#define Item_Section            InspectorViewItem_Section
#define Item_Spacer             InspectorViewItem_Spacer
#define Item_SliderWithIcon     InspectorViewItem_SliderWithIcon
#define Item_SliderWithLabel    InspectorViewItem_SliderWithLabel
#define Item_Checkbox           InspectorViewItem_Checkbox
#define Item_Timestamp          InspectorViewItem_Timestamp
#define Item_Rotation           InspectorViewItem_Rotation
#define Item_Stat               InspectorViewItem_Stat

// MARK: - InspectorView

@interface InspectorView () <NSOutlineViewDelegate>
@end

@implementation InspectorView {
    ImageLibraryPtr _imgLib;
    Item_Section* _rootItem;
    ImageSet _selection;
    bool _notifying;
    
    IBOutlet NSView* _nibView;
    IBOutlet NSTextField* _noSelectionLabel;
    IBOutlet NSView* _outlineContainerView;
    IBOutlet NSOutlineView* _outlineView;
}

// MARK: - Creation

- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _imgLib = imgLib;
    
    // Add ourself as an observer of the image library
    {
        auto lock = std::unique_lock(*_imgLib);
        __weak auto selfWeak = self;
        _imgLib->observerAdd([=](const ImageLibrary::Event& ev) {
            auto selfStrong = selfWeak;
            if (!selfStrong) return false;
            [self _handleImageLibraryEvent:ev];
            return true;
        });
    }
    
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
        static constexpr CGFloat SpacerSize = 8;
        _rootItem = [self _createItemWithClass:[Item_Section class]];
        _rootItem->name = @"";
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = 3;
            spacer->darkBackground = true;
            _rootItem->items.push_back(spacer);
            
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Stats";
            section->darkBackground = true;
            
            {
                Item_Stat* stat = [self _createItemWithClass:[Item_Stat class]];
                stat->name = @"Image ID";
                stat->valueIndent = 115;
                stat->modelGetter = _GetterCreate(self, _Get_id);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Item_Stat* stat = [self _createItemWithClass:[Item_Stat class]];
                stat->name = @"Timestamp";
                stat->valueIndent = 115;
                stat->modelGetter = _GetterCreate(self, _Get_timestamp);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Item_Stat* stat = [self _createItemWithClass:[Item_Stat class]];
                stat->name = @"Integration Time";
                stat->valueIndent = 115;
                stat->modelGetter = _GetterCreate(self, _Get_integrationTime);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Item_Stat* stat = [self _createItemWithClass:[Item_Stat class]];
                stat->name = @"Analog Gain";
                stat->valueIndent = 115;
                stat->modelGetter = _GetterCreate(self, _Get_analogGain);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
                spacer->height = SpacerSize;
                spacer->darkBackground = true;
                section->items.push_back(spacer);
            }
            
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"White Balance";
            Item_SliderWithIcon* slider = [self _createItemWithClass:[Item_SliderWithIcon class]];
            slider->icon = @"Inspector-WhiteBalance";
            slider->modelGetter = _GetterCreate(self, _Get_whiteBalance);
            slider->modelSetter = _SetterCreate(self, _Set_whiteBalance);
            slider->section = section;
            slider->valueMin = -1;
            slider->valueMax = +1;
            slider->valueDefault = 0;
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Exposure";
            Item_SliderWithIcon* slider = [self _createItemWithClass:[Item_SliderWithIcon class]];
            slider->icon = @"Inspector-Exposure";
            slider->modelGetter = _GetterCreate(self, _Get_exposure);
            slider->modelSetter = _SetterCreate(self, _Set_exposure);
            slider->section = section;
            slider->valueMin = -1;
            slider->valueMax = +1;
            slider->valueDefault = 0;
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Saturation";
            Item_SliderWithIcon* slider = [self _createItemWithClass:[Item_SliderWithIcon class]];
            slider->icon = @"Inspector-Saturation";
            slider->modelGetter = _GetterCreate(self, _Get_saturation);
            slider->modelSetter = _SetterCreate(self, _Set_saturation);
            slider->section = section;
            slider->valueMin = -1;
            slider->valueMax = +1;
            slider->valueDefault = 0;
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Brightness";
            Item_SliderWithIcon* slider = [self _createItemWithClass:[Item_SliderWithIcon class]];
            slider->icon = @"Inspector-Brightness";
            slider->modelGetter = _GetterCreate(self, _Get_brightness);
            slider->modelSetter = _SetterCreate(self, _Set_brightness);
            slider->section = section;
            slider->valueMin = -1;
            slider->valueMax = +1;
            slider->valueDefault = 0;
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Contrast";
            Item_SliderWithIcon* slider = [self _createItemWithClass:[Item_SliderWithIcon class]];
            slider->icon = @"Inspector-Contrast";
            slider->modelGetter = _GetterCreate(self, _Get_contrast);
            slider->modelSetter = _SetterCreate(self, _Set_contrast);
            slider->section = section;
            slider->valueMin = -1;
            slider->valueMax = +1;
            slider->valueDefault = 0;
            section->items = { slider };
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize*2;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Local Contrast";
            
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize/3;
            section->items.push_back(spacer);
            
            Item_SliderWithLabel* slider1 = [self _createItemWithClass:[Item_SliderWithLabel class]];
            slider1->name = @"Amount";
            slider1->modelGetter = _GetterCreate(self, _Get_localContrastAmount);
            slider1->modelSetter = _SetterCreate(self, _Set_localContrastAmount);
            slider1->section = section;
            slider1->valueMin = -1;
            slider1->valueMax = +1;
            slider1->valueDefault = 0;
            section->items.push_back(slider1);
            
            Item_SliderWithLabel* slider2 = [self _createItemWithClass:[Item_SliderWithLabel class]];
            slider2->name = @"Radius";
            slider2->modelGetter = _GetterCreate(self, _Get_localContrastRadius);
            slider2->modelSetter = _SetterCreate(self, _Set_localContrastRadius);
            slider2->section = section;
            slider2->valueMin = -1;
            slider2->valueMax = +1;
            slider2->valueDefault = 0;
            section->items.push_back(slider2);
            
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Rotation";
            Item_Rotation* rotation = [self _createItemWithClass:[Item_Rotation class]];
            rotation->modelGetter = _GetterCreate(self, _Get_rotation);
            rotation->modelSetter = _SetterCreate(self, _Set_rotation);
            rotation->section = section;
            section->items = { rotation };
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
        
        {
            Item_Section* section = [self _createItemWithClass:[Item_Section class]];
            section->name = @"Other";
            
            {
                Item_Checkbox* checkbox = [self _createItemWithClass:[Item_Checkbox class]];
                checkbox->name = @"Defringe";
                checkbox->modelGetter = _GetterCreate(self, _Get_defringe);
                checkbox->modelSetter = _SetterCreate(self, _Set_defringe);
                checkbox->section = section;
                section->items.push_back(checkbox);
            }
            
            {
                Item_Checkbox* checkbox = [self _createItemWithClass:[Item_Checkbox class]];
                checkbox->name = @"Reconstruct highlights";
                checkbox->modelGetter = _GetterCreate(self, _Get_reconstructHighlights);
                checkbox->modelSetter = _SetterCreate(self, _Set_reconstructHighlights);
                checkbox->section = section;
                section->items.push_back(checkbox);
            }
            
            {
                Item_Timestamp* timestamp = [self _createItemWithClass:[Item_Timestamp class]];
                timestamp->name = @"Timestamp";
                timestamp->modelGetter = _GetterCreate(self, _Get_timestampShow);
                timestamp->modelSetter = _SetterCreate(self, _Set_timestampShow);
                timestamp->cornerModelGetter = _GetterCreate(self, _Get_timestampCorner);
                timestamp->cornerModelSetter = _SetterCreate(self, _Set_timestampCorner);
                timestamp->section = section;
                section->items.push_back(timestamp);
            }
            
            _rootItem->items.push_back(section);
        }
        
        {
            Item_Spacer* spacer = [self _createItemWithClass:[Item_Spacer class]];
            spacer->height = SpacerSize;
            _rootItem->items.push_back(spacer);
        }
    }
    
    [_outlineView reloadData];
    
    for (auto item : _rootItem->items) {
        [_outlineView expandItem:item];
    }
    
    [self setSelection:{}];
    return self;
}

using _ModelGetterFn = id(*)(const ImageRecord&);
using _ModelSetterFn = void(*)(ImageRecord&, id);

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

static _ModelGetter _GetterCreate(InspectorView* self, _ModelGetterFn fn) {
    __weak const auto selfWeak = self;
    return ^_ModelData(InspectorViewItem*) {
        const auto selfStrong = selfWeak;
        if (!selfStrong) return _ModelData{};
        return [selfStrong _get:fn];
    };
}

static _ModelSetter _SetterCreate(InspectorView* self, _ModelSetterFn fn) {
    __weak const auto selfWeak = self;
    return ^void(InspectorViewItem*, id data) {
        const auto selfStrong = selfWeak;
        if (!selfStrong) return;
        [selfStrong _set:fn data:data];
    };
}

// MARK: - Getters

static ImageOptions::Corner _Convert(ImageCornerButtonTypes::Corner x) {
    switch (x) {
    case ImageCornerButtonTypes::Corner::BottomRight:   return ImageOptions::Corner::BottomRight;
    case ImageCornerButtonTypes::Corner::BottomLeft:    return ImageOptions::Corner::BottomLeft;
    case ImageCornerButtonTypes::Corner::TopLeft:       return ImageOptions::Corner::TopLeft;
    case ImageCornerButtonTypes::Corner::TopRight:      return ImageOptions::Corner::TopRight;
    case ImageCornerButtonTypes::Corner::Mixed:         return ImageOptions::Corner::BottomRight;
    }
}

static ImageCornerButtonTypes::Corner _Convert(ImageOptions::Corner x) {
    switch (x) {
    case ImageOptions::Corner::BottomRight: return ImageCornerButtonTypes::Corner::BottomRight;
    case ImageOptions::Corner::BottomLeft:  return ImageCornerButtonTypes::Corner::BottomLeft;
    case ImageOptions::Corner::TopLeft:     return ImageCornerButtonTypes::Corner::TopLeft;
    case ImageOptions::Corner::TopRight:    return ImageCornerButtonTypes::Corner::TopRight;
    }
}


static NSDateFormatter* _DateFormatterCreate() {
    NSDateFormatter* x = [[NSDateFormatter alloc] init];
    [x setLocale:[NSLocale autoupdatingCurrentLocale]];
    [x setDateStyle:NSDateFormatterMediumStyle];
    [x setTimeStyle:NSDateFormatterMediumStyle];
    // Update date format to show milliseconds
    [x setDateFormat:[[x dateFormat] stringByReplacingOccurrencesOfString:@":ss" withString:@":ss.SSS"]];
    return x;
}

static NSDateFormatter* _DateFormatter() {
    static NSDateFormatter* x = _DateFormatterCreate();
    return x;
}



static id _Get_id(const ImageRecord& rec) {
    return @(rec.info.id);
}

static id _Get_timestamp(const ImageRecord& rec) {
    using namespace std::chrono;
    const Time::Instant t = rec.info.timestamp;
    if (Time::Absolute(t)) {
        auto timestamp = clock_cast<system_clock>(rec.info.timestamp);
        const milliseconds ms = duration_cast<milliseconds>(timestamp.time_since_epoch());
        return [_DateFormatter() stringFromDate:[NSDate dateWithTimeIntervalSince1970:(double)ms.count()/1000.]];
    
    } else {
        const seconds sec = Time::DurationRelative<seconds>(rec.info.timestamp);
        const std::string relTimeStr = Toastbox::DurationString(true, sec);
        return [NSString stringWithFormat:@"%s after boot", relTimeStr.c_str()];
    }
}

static id _Get_integrationTime(const ImageRecord& rec) {
    return @(rec.info.coarseIntTime);
}

static id _Get_analogGain(const ImageRecord& rec) {
    return @(rec.info.analogGain);
}

static id _Get_whiteBalance(const ImageRecord& rec) {
    // meowmix
    return @(0);
}

static id _Get_exposure(const ImageRecord& rec) {
    return @(rec.options.exposure);
}

static id _Get_saturation(const ImageRecord& rec) {
    return @(rec.options.saturation);
}

static id _Get_brightness(const ImageRecord& rec) {
    return @(rec.options.brightness);
}

static id _Get_contrast(const ImageRecord& rec) {
    return @(rec.options.contrast);
}

static id _Get_localContrastAmount(const ImageRecord& rec) {
    return @(rec.options.localContrast.amount);
}

static id _Get_localContrastRadius(const ImageRecord& rec) {
    return @(rec.options.localContrast.radius);
}

static id _Get_rotation(const ImageRecord& rec) {
    return @((int)rec.options.rotation);
}

static id _Get_defringe(const ImageRecord& rec) {
    return @(rec.options.defringe);
}

static id _Get_reconstructHighlights(const ImageRecord& rec) {
    return @(rec.options.reconstructHighlights);
}

static id _Get_timestampShow(const ImageRecord& rec) {
    return @(rec.options.timestamp.show);
}

static id _Get_timestampCorner(const ImageRecord& rec) {
    return @((int)_Convert(rec.options.timestamp.corner));
}

// MARK: - Setters

static void _Set_whiteBalance(ImageRecord& rec, id data) {
    // meowmix
}

static void _Set_exposure(ImageRecord& rec, id data) {
    rec.options.exposure = [data floatValue];
}

static void _Set_saturation(ImageRecord& rec, id data) {
    rec.options.saturation = [data floatValue];
}

static void _Set_brightness(ImageRecord& rec, id data) {
    rec.options.brightness = [data floatValue];
}

static void _Set_contrast(ImageRecord& rec, id data) {
    rec.options.contrast = [data floatValue];
}

static void _Set_localContrastAmount(ImageRecord& rec, id data) {
    rec.options.localContrast.amount = [data floatValue];
}

static void _Set_localContrastRadius(ImageRecord& rec, id data) {
    rec.options.localContrast.radius = [data floatValue];
}

static void _Set_rotation(ImageRecord& rec, id data) {
    rec.options.rotation = (ImageOptions::Rotation)[data intValue];
}

static void _Set_defringe(ImageRecord& rec, id data) {
    rec.options.defringe = [data boolValue];
}

static void _Set_reconstructHighlights(ImageRecord& rec, id data) {
    rec.options.reconstructHighlights = [data boolValue];
}

static void _Set_timestampShow(ImageRecord& rec, id data) {
    rec.options.timestamp.show = [data boolValue];
}

static void _Set_timestampCorner(ImageRecord& rec, id data) {
    const ImageOptions::Corner corner = _Convert((ImageCornerButtonTypes::Corner)[data intValue]);
    rec.options.timestamp.corner = corner;
}







// _handleImageLibraryEvent: called on whatever thread where the modification happened,
// and with the ImageLibraryPtr lock held!
- (void)_handleImageLibraryEvent:(const ImageLibrary::Event&)ev {
    switch (ev.type) {
    case ImageLibrary::Event::Type::Add:
        break;
    case ImageLibrary::Event::Type::Remove:
        break;
    case ImageLibrary::Event::Type::Change:
        if ([NSThread isMainThread]) {
            [self _handleImagesChanged:ev.records];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _handleImagesChanged:ev.records];
            });
        }
        break;
    }
}

- (void)_handleImagesChanged:(const ImageSet&)images {
    assert([NSThread isMainThread]);
    // Short-circuit if this notification is due to our own changes
    if (_notifying) return;
    if (ImageSetsOverlap(_selection, images)) {
        _Update(_rootItem);
    }
}

// MARK: - Methods

static void _Update(Item* it) {
    if (auto section = CastOrNil<Item_Section>(it)) {
        [section updateView];
    }
    
//    [it updateView];
//    if (auto section = CastOrNil<Item_Section>(it)) {
//        for (auto it : section->items) {
//            _UpdateView(it);
//        }
//    }
}

- (void)setSelection:(ImageSet)selection {
    _selection = std::move(selection);
    [_outlineContainerView setHidden:_selection.empty()];
    [_noSelectionLabel setHidden:!_selection.empty()];
    
    _Update(_rootItem);
}

// MARK: - Private Methods

- (id)_createItemWithClass:(Class)itemClass {
    NSParameterAssert(itemClass);
    Item* view = Cast<Item>([_outlineView makeViewWithIdentifier:NSStringFromClass(itemClass) owner:nil]);
    assert(view);
    return view;
}

- (_ModelData)_get:(_ModelGetterFn)fn {
    // first: holds the first non-nil value
    id first = nil;
    // mixed: tracks whether there are at least 2 differing values
    bool mixed = false;
    
    for (const ImageRecordPtr& rec : _selection) {
        const id obj = fn(*rec);
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

- (void)_set:(_ModelSetterFn)fn data:(id)data {
    for (const ImageRecordPtr& rec : _selection) {
        fn(*rec, data);
    }
    
    _notifying = true;
    {
        auto lock = std::unique_lock(*_imgLib);
        std::set<ImageLibrary::RecordStrongRef> records;
        for (const ImageRecordPtr& x : _selection) records.insert(x);
        _imgLib->notifyChange(std::move(records));
    }
    _notifying = false;
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
    
    } else if (auto it = CastOrNil<Item_Section>(item)) {
        return it->items.size();
    
    } else {
        abort();
    }
}

- (id)outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nullptr) {
        if (!_rootItem) return nil;
        return _rootItem->items[index];
    
    } else if (auto section = CastOrNil<Item_Section>(item)) {
        return section->items.at(index);
    
    } else {
        abort();
    }
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item {
    if (auto it = CastOrNil<Item_Section>(item)) {
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
        return [_outlineView makeViewWithIdentifier:NSStringFromClass([InspectorView_DarkRowView class]) owner:nil];
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

//- (BOOL)acceptsFirstResponder {
//    // Don't accept first responder status so that the center view of the 3-part-view
//    // remains the first responder when clicking on the inspector.
//    return false;
//}

- (BOOL)validateProposedFirstResponder:(NSResponder*)responder forEvent:(NSEvent*)event {
    // Allow labels in our outline view to be selected
    return true;
}

@end

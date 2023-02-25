#import "InspectorView.h"
#import <vector>
#import "Util.h"
#import "ImageCornerButton/ImageCornerButton.h"
#import "Code/Shared/Time.h"
#import "Code/Shared/TimeConvert.h"
#import "Toastbox/RelativeTimeString.h"
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

- (IBAction)updateModel:(id)sender {
    modelSetter(self, [_slider objectValue]);
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

- (IBAction)updateModel:(id)sender {
    modelSetter(self, [_slider objectValue]);
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

- (IBAction)updateModel:(id)sender {
    modelSetter(self, @([_checkbox state]!=NSControlStateValueOff));
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

- (IBAction)updateModel:(id)sender {
    modelSetter(self, @([_checkbox state]!=NSControlStateValueOff));
    cornerModelSetter(self, @((int)[_cornerButton corner]));
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

- (IBAction)updateModel:(id)sender {
    modelSetter(self, nil);
}

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


- (_ModelData)_get:(_ModelGetterFn)fn {
    // first: holds the first non-nil value
    id first = nil;
    // mixed: tracks whether there are at least 2 differing values
    bool mixed = false;
    
    auto lock = std::unique_lock(*_imgLib);
    for (const Img::Id imgId : _selection) {
        auto find = _imgLib->find(imgId);
        if (find == _imgLib->end()) continue;
        const id obj = fn(**find);
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
    auto lock = std::unique_lock(*_imgLib);
    for (const Img::Id imgId : _selection) {
        auto find = _imgLib->find(imgId);
        if (find == _imgLib->end()) continue;
        fn(**find, data);
    }
    _imgLib->notifyChange(_selection);
}

static _ModelGetter _GetterCreate(InspectorView* self, _ModelGetterFn fn) {
    __weak const auto selfWeak = self;
    return ^_ModelData(InspectorView_Item*) {
        const auto selfStrong = selfWeak;
        if (!selfStrong) return _ModelData{};
        return [selfStrong _get:fn];
    };
}

static _ModelSetter _SetterCreate(InspectorView* self, _ModelSetterFn fn) {
    __weak const auto selfWeak = self;
    return ^void(InspectorView_Item*, id data) {
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
        const seconds sec = Time::DurationSinceEpoch<seconds>(rec.info.timestamp);
        const std::string relTimeStr = Toastbox::RelativeTimeString(true, sec);
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
    // meowmix
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
                stat->modelGetter = _GetterCreate(self, _Get_id);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Timestamp";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, _Get_timestamp);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Integration Time";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, _Get_integrationTime);
                stat->darkBackground = true;
                section->items.push_back(stat);
            }
            
            {
                Stat* stat = [self _createItemWithClass:[Stat class]];
                stat->name = @"Analog Gain";
                stat->valueIndent = 110;
                stat->modelGetter = _GetterCreate(self, _Get_analogGain);
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
            slider->modelGetter = _GetterCreate(self, _Get_whiteBalance);
            slider->modelSetter = _SetterCreate(self, _Set_whiteBalance);
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
            slider->modelGetter = _GetterCreate(self, _Get_exposure);
            slider->modelSetter = _SetterCreate(self, _Set_exposure);
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
            slider->modelGetter = _GetterCreate(self, _Get_saturation);
            slider->modelSetter = _SetterCreate(self, _Set_saturation);
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
            slider->modelGetter = _GetterCreate(self, _Get_brightness);
            slider->modelSetter = _SetterCreate(self, _Set_brightness);
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
            slider->modelGetter = _GetterCreate(self, _Get_contrast);
            slider->modelSetter = _SetterCreate(self, _Set_contrast);
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
            slider1->modelGetter = _GetterCreate(self, _Get_localContrastAmount);
            slider1->modelSetter = _SetterCreate(self, _Set_localContrastAmount);
            
            SliderWithLabel* slider2 = [self _createItemWithClass:[SliderWithLabel class]];
            slider2->name = @"Radius";
            slider2->modelGetter = _GetterCreate(self, _Get_localContrastRadius);
            slider2->modelSetter = _SetterCreate(self, _Set_localContrastRadius);
            
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
            rotation->modelSetter = _SetterCreate(self, _Set_rotation);
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
                checkbox->modelGetter = _GetterCreate(self, _Get_defringe);
                checkbox->modelSetter = _SetterCreate(self, _Set_defringe);
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
                checkbox->modelGetter = _GetterCreate(self, _Get_reconstructHighlights);
                checkbox->modelSetter = _SetterCreate(self, _Set_reconstructHighlights);
                section->items.push_back(checkbox);
            }
            
//            {
//                Spacer* spacer = [self _createItemWithClass:[Spacer class]];
//                spacer->height = 4;
//                section->items.push_back(spacer);
//            }
            
            {
                Timestamp* timestamp = [self _createItemWithClass:[Timestamp class]];
                timestamp->modelGetter = _GetterCreate(self, _Get_timestampShow);
                timestamp->modelSetter = _SetterCreate(self, _Set_timestampShow);
                timestamp->cornerModelGetter = _GetterCreate(self, _Get_timestampCorner);
                timestamp->cornerModelSetter = _SetterCreate(self, _Set_timestampCorner);
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

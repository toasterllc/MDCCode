#import "BatteryLifeView.h"
#import "BatteryLifeSimulator.h"
#import "Prefs.h"
#import "BatteryLifePlotLayer.h"
#import "Code/Lib/Toastbox/Defer.h"
#import "Code/Lib/Toastbox/String.h"
#import "Code/Lib/Toastbox/NumForStr.h"
using namespace MDCStudio;
using namespace BatteryLifeViewTypes;

namespace T = BatteryLifeViewTypes;
namespace DS = DeviceSettings;

@implementation BatteryLifeView {
@public
    __weak id<BatteryLifeViewDelegate> _delegate;
    
    IBOutlet NSView* _nibView;
    IBOutlet NSView* _plotView;
    IBOutlet NSTextField* _motionIntervalField;
    IBOutlet NSPopUpButton* _motionIntervalMenu;
    IBOutlet NSTextField* _buttonIntervalField;
    IBOutlet NSPopUpButton* _buttonIntervalMenu;
    IBOutlet NSTextField* _batteryLifeMinLabel;
    IBOutlet NSTextField* _batteryLifeMaxLabel;
    
    bool _storeLoadUnderway;
    BatteryLifePlotLayer* _plotLayer;
    MSP::Triggers _triggers;
    std::optional<T::BatteryLifeEstimate> _estimate;
}

static DS::Duration _StimulusIntervalGet(std::string key, const DS::Duration& uninit) {
    namespace DS = DeviceSettings;
    using D = DS::Duration;
    using U = D::Unit;
    
//    constexpr DS::Duration Default = { 30, U::Seconds };
    
    DS::Duration dur = uninit;
    try {
        const auto str = PrefsGlobal().get(key, "");
        const auto parts = Toastbox::String::Split(str, " ");
        if (parts.size() != 2) throw Toastbox::RuntimeError("invalid duration: %s", str);
        
        dur.value = std::max(1.f, Toastbox::FloatForStr<float>(parts[0]));
        dur.unit = D::UnitFromString(parts[1]);
    } catch (std::exception& e) {
//        printf("failed to parse duration: %s\n", e.what());
        return uninit;
    }
    return dur;
}

static void _StimulusIntervalSet(std::string key, const DS::Duration& dur) {
    namespace DS = DeviceSettings;
    PrefsGlobal().set(key, std::to_string(dur.value) + " " + DS::Duration::StringFromUnit(dur.unit));
}

static DS::Duration _MotionStimulusInterval() {
    return _StimulusIntervalGet("MotionStimulusInterval", { 30, DeviceSettings::Duration::Unit::Seconds });
}

static void _MotionStimulusInterval(const DS::Duration& x) {
    _StimulusIntervalSet("MotionStimulusInterval", x);
}

static DS::Duration _ButtonStimulusInterval() {
    return _StimulusIntervalGet("ButtonStimulusInterval", { 6, DeviceSettings::Duration::Unit::Hours });
}

static void _ButtonStimulusInterval(const DS::Duration& x) {
    _StimulusIntervalSet("ButtonStimulusInterval", x);
}

// MARK: - Creation

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    
    // Load view from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        NSView* nibView = self->_nibView;
        [nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:nibView];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    }
    
    _plotLayer = [BatteryLifePlotLayer new];
    [_plotView setLayer:_plotLayer];
    [_plotView setWantsLayer:true];
    
    __weak auto selfWeak = self;
    PrefsGlobal().observerAdd([=] () {
        auto selfStrong = selfWeak;
        if (!selfStrong) return false;
        [selfStrong _prefsChanged];
        return true;
    });
    
    _Load(self);
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSLog(@"first responder: %@", [[self window] firstResponder]);
//    }];
    
    return self;
}

template<bool T_Forward>
static void _Copy(DS::Duration& x, NSTextField* field, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        [field setStringValue:@(DS::StringFromFloat(x.value).c_str())];
        [menu selectItemWithTitle:@(DS::Duration::StringFromUnit(x.unit).c_str())];
    } else {
        const std::string xstr = [[menu titleOfSelectedItem] UTF8String];
        try {
            x.value = std::max(0.f, DS::FloatFromString([[field stringValue] UTF8String]));
        } catch (...) {}
        x.unit = DS::Duration::UnitFromString([[menu titleOfSelectedItem] UTF8String]);
    }
}

static void _Store(BatteryLifeView* self) {
    {
        DS::Duration x;
        _Copy<false>(x, self->_motionIntervalField, self->_motionIntervalMenu);
        _MotionStimulusInterval(x);
    }
    
    {
        DS::Duration x;
        _Copy<false>(x, self->_buttonIntervalField, self->_buttonIntervalMenu);
        _ButtonStimulusInterval(x);
    }
}

static void _Load(BatteryLifeView* self) {
    {
        DS::Duration x = _MotionStimulusInterval();
        _Copy<true>(x, self->_motionIntervalField, self->_motionIntervalMenu);
    }
    {
        DS::Duration x = _ButtonStimulusInterval();
        _Copy<true>(x, self->_buttonIntervalField, self->_buttonIntervalMenu);
    }
}

static void _StoreLoad(BatteryLifeView* self) {
//    // Prevent re-entry, because our committing logic can trigger multiple calls
//    if (self->_actionViewChangedUnderway) return;
//    self->_actionViewChangedUnderway = true;
//    Defer( self->_actionViewChangedUnderway = false );
    
    // Prevent re-entry, because our committing logic can trigger multiple calls
    if (self->_storeLoadUnderway) return;
    self->_storeLoadUnderway = true;
    Defer( self->_storeLoadUnderway = false );
    
    _Store(self);
    _Load(self);
}

//- (BOOL)acceptsFirstResponder {
//    return true;
//}

- (IBAction)_actionViewChanged:(id)sender {
    _StoreLoad(self);
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

//- (void)cancelOperation:(id)sender {
//    [[self window] performClose:nil];
//}

- (void)setDelegate:(id<BatteryLifeViewDelegate>)delegate {
    _delegate = delegate;
}

- (void)setTriggers:(const MSP::Triggers&)triggers {
    _triggers = triggers;
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

- (T::BatteryLifeEstimate)batteryLifeEstimate {
    [self _updateIfNeeded];
    return *_estimate;
}

- (void)_prefsChanged {
    if (_storeLoadUnderway) return;
    NSLog(@"prefs changed");
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

- (void)_update {
    constexpr std::chrono::seconds BatteryLifeMin = date::days(1);
    constexpr std::chrono::seconds BatteryLifeMax = date::years(3);
    
    const MDCStudio::BatteryLifeSimulator::Parameters parameters = {
        .motionStimulusInterval = SecondsForDuration(_MotionStimulusInterval()),
        .buttonStimulusInterval = SecondsForDuration(_ButtonStimulusInterval()),
    };
    
    MDCStudio::BatteryLifeSimulator::Simulator simulatorMin(
        MDCStudio::BatteryLifeSimulator::WorstCase, parameters, _triggers);
    MDCStudio::BatteryLifeSimulator::Simulator simulatorMax(
        MDCStudio::BatteryLifeSimulator::BestCase, parameters, _triggers);
    
    const auto pointsMin = simulatorMin.estimate();
    const auto pointsMax = simulatorMax.estimate();
    assert(!pointsMin.empty());
    assert(!pointsMax.empty());
    
    // Update battery life estimate
    _estimate = {
        .min = std::clamp(pointsMin.back().time, BatteryLifeMin, BatteryLifeMax),
        .max = std::clamp(pointsMax.back().time, BatteryLifeMin, BatteryLifeMax),
    };
    
    // Update plot
    [_plotLayer setPoints:pointsMin];
    
    // Update labels
    [_batteryLifeMinLabel setStringValue:@(DeviceSettings::StringForDuration(_estimate->min).c_str())];
    [_batteryLifeMaxLabel setStringValue:@(DeviceSettings::StringForDuration(_estimate->max).c_str())];
}

- (void)_updateIfNeeded {
    if (_estimate) return;
    [self _update];
}

@end

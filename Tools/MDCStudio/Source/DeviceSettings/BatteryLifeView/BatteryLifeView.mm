#import "BatteryLifeView.h"
#import "BatteryLifeEstimate.h"
#import "Prefs.h"
using namespace MDCStudio;
using namespace BatteryLifeViewTypes;

namespace T = BatteryLifeViewTypes;
namespace DS = DeviceSettings;

@implementation BatteryLifeView {
@public
    __weak id<BatteryLifeViewDelegate> _delegate;
    
    IBOutlet NSView* _nibView;
    IBOutlet NSTextField* _motionIntervalField;
    IBOutlet NSPopUpButton* _motionIntervalMenu;
    IBOutlet NSTextField* _buttonIntervalField;
    IBOutlet NSPopUpButton* _buttonIntervalMenu;
    
    MSP::Triggers _triggers;
    std::optional<T::BatteryLifeEstimate> _estimate;
}

static DS::Duration _StimulusInterval(std::string key) {
    namespace DS = DeviceSettings;
    using U = DS::Duration::Unit;
    
    const float value = PrefsGlobal().get(key+".value", 30.f);
    const auto unit =
        PrefsGlobal().get(key+".unit", DS::Duration::StringFromUnit(U::Seconds));
    
    return DS::Duration{
        .value = std::max(1.f, value),
        .unit = DS::Duration::UnitFromString(unit),
    };
}

static void _StimulusInterval(std::string key, const DS::Duration& dur) {
    namespace DS = DeviceSettings;
    PrefsGlobal().set(key+".value", dur.value);
    PrefsGlobal().set(key+".unit", DS::Duration::StringFromUnit(dur.unit));
}

static DS::Duration _MotionStimulusInterval() {
    return _StimulusInterval("MotionStimulusInterval");
}

static void _MotionStimulusInterval(const DS::Duration& x) {
    _StimulusInterval("MotionStimulusInterval", x);
}

static DS::Duration _ButtonStimulusInterval() {
    return _StimulusInterval("ButtonStimulusInterval");
}

static void _ButtonStimulusInterval(const DS::Duration& x) {
    _StimulusInterval("ButtonStimulusInterval", x);
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
    
    __weak auto selfWeak = self;
    PrefsGlobal().observerAdd([=] () {
        auto selfStrong = selfWeak;
        if (!selfStrong) return false;
        [selfStrong _prefsChanged];
        return true;
    });
    
    _Load(self);
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
    
    _Store(self);
    _Load(self);
}

- (BOOL)acceptsFirstResponder {
    return true;
}

- (IBAction)_actionViewChanged:(id)sender {
    _StoreLoad(self);
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

- (void)cancelOperation:(id)sender {
    [[self window] performClose:nil];
}

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
    NSLog(@"prefs changed");
    [self _update];
    [_delegate batteryLifeViewChanged:self];
}

- (void)_update {
    const MDCStudio::BatteryLifeEstimate::Parameters parameters = {
        .motionStimulusInterval = SecondsForDuration(_MotionStimulusInterval()),
        .buttonStimulusInterval = SecondsForDuration(_ButtonStimulusInterval()),
    };
    MDCStudio::BatteryLifeEstimate::Estimator estimatorMin(
        MDCStudio::BatteryLifeEstimate::WorstCase, parameters, _triggers);
    MDCStudio::BatteryLifeEstimate::Estimator estimatorMax(
        MDCStudio::BatteryLifeEstimate::BestCase, parameters, _triggers);
    
    estimatorMin.estimate();
    estimatorMax.estimate();
}

- (void)_updateIfNeeded {
    if (_estimate) return;
    [self _update];
}

@end
